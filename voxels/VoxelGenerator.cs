using Godot;
using System;
using System.Linq;
using System.Collections.Generic;

public partial class VoxelGenerator : Node
{
    static float _adjust_val(float x, float n)
    {
        var s = Mathf.Sign(x);
        x = Mathf.Abs(x);
        x = 1.0f - x;
        x = Mathf.Pow(x, n);
        x = s * (1.0f - x);
        return x;
    }
    static (int, int, int) height_at_global(Noise noiser, float x, float z)
    {
        float pure_height = noiser.GetNoise2D(x, z);
        float height = pure_height;
        
        float steepness_freq = 0.5f;
        
        float steepness = noiser.GetNoise3D(x*steepness_freq, -z*steepness_freq + 100.0f, 50.0f)*0.5f + 0.5f;
        steepness = Mathf.Lerp(0.4f, 16.0f, steepness*steepness*steepness*steepness);
        height = _adjust_val(height, steepness);
        height += noiser.GetNoise2D(x*0.2f + 512.0f, z*0.2f + 11.0f) * 1.0f;
        
        float height_scale_freq = 0.5f;
        
        float height_scale = noiser.GetNoise2D(x*height_scale_freq, z*height_scale_freq + 154.0f)*0.5f + 0.5f;
        height = height * Mathf.Lerp(1.0f, 12.0f, height_scale);
        
        height += noiser.GetNoise2D(x*0.4f + 51.0f, z*0.4f + 1301.0f) * 5.0f;
                
        float rock_offset = noiser.GetNoise2D(z*2.6f + 151.0f, x*2.6f + 11.0f)*5.0f;
        
        pure_height = Mathf.Round(pure_height);
        height = Mathf.Round(height);
        rock_offset = Mathf.Round(rock_offset);
        
        return ((int)pure_height, (int)height, (int)rock_offset);
    }
    static int chunk_size = 16;
    static Aabb bounds = new Aabb(new Vector3(), Vector3.One*(chunk_size-1));
    static List<(Vector3, int, uint)> get_tree_coords(Vector3 chunk_position, Noise noiser)
    {
        var rng = new RandomNumberGenerator();
        rng.Seed = (ulong) GD.Hash(chunk_position * new Vector3(1.0f, 0.0f, 1.0f));
        var tree_count = rng.RandiRange(3, 6);
        
        var offset = -Vector3.One*chunk_size/2 + chunk_position;
        var offset_2d = new Vector2(offset.X, offset.Z);
        
        var trees = new List<(Vector3, int, uint)>();
        foreach (var _ in Enumerable.Range(0, tree_count))
        {
            var buffer = 2; // FIXME: remove
            var x = rng.RandiRange(buffer, chunk_size-1-buffer);
            var z = rng.RandiRange(buffer, chunk_size-1-buffer);
            
            var c_2d = new Vector2(x, z) + offset_2d;
            var (_, height, rock_part) = height_at_global(noiser, c_2d.X, c_2d.Y);
            var is_rock = rock_part > 1.0f;
            
            if (height >= 0 && !is_rock)
            {
                var c_3d = new Vector3(x, height+1 - chunk_position.Y + chunk_size/2, z);
                var tall = rng.RandiRange(4, 6);
                var grunge = rng.Randi();
                trees.Add((c_3d, tall, grunge));
            }
        }
        
        return trees;
    }
    static int coord_to_index(Vector3 coord)
    {
        return ((int)(coord.Y))*chunk_size*chunk_size + ((int)(coord.Z))*chunk_size + ((int)coord.X);
    }
    public byte[] _Generate(Noise noiser, Vector3 chunk_position, Vector3 offset, Vector2 offset_2d)
    {
        var voxels = new byte[chunk_size*chunk_size*chunk_size];
        foreach (var z in Enumerable.Range(0, chunk_size))
        {
            foreach (var x in Enumerable.Range(0, chunk_size))
            {
                var c_2d = new Vector2(x, z) + offset_2d;
                var (_, height, rock_offset) = height_at_global(noiser, c_2d.X, c_2d.Y);
                
                var h_i = coord_to_index(new Vector3(x, 0, z));
                
                foreach (var y in Enumerable.Range(0, chunk_size))
                {
                    var c = new Vector3(x, y, z) + offset;
                
                    var noise = height - c.Y;
                    var noise_above = height - c.Y - 1.0f;
                    
                    var rock_noise = noise + rock_offset;
                    
                    byte vox = 0;
                    if (noise < 0.0f)
                        vox = 0; // air
                    else if(noise_above < 0.0f && c.Y >= 0.0f)
                        vox = 1; // grass
                    else
                        vox = 2; // dirt
                    
                    if (vox != 0 && rock_noise > 1.0f)
                        vox = 3; // rock
                    
                    if (vox == 0 && c.Y <= 0.0f)
                        vox = 6; // water
                    
                    var i = h_i + y*chunk_size*chunk_size;
                    
                    voxels[i] = vox;
                }
            }
        }
        
        var tree_coords = get_tree_coords(chunk_position, noiser);
        foreach (var (coord, tall, grunge) in tree_coords)
        {
            var leaf_bottom = Math.Max(2, tall-3);
            
            foreach (var y in Enumerable.Range(leaf_bottom, (int)(tall+1+(grunge%3)/2)-leaf_bottom))
            {
                var range = 2;
                var evergreen = (grunge & 256) != 0;
                if (evergreen)
                {
                    range -= (y+tall-leaf_bottom)%2;
                }
                if (y+1 > tall)
                {
                    range -= 1;
                }
                foreach (var z in Enumerable.Range(-range, 2*range+1))
                {
                    foreach (var x in Enumerable.Range(-range, 2*range+1))
                    {
                        var limit = range*range+0.25f;
                        var fd = (grunge ^ GD.Hash(x) ^ GD.Hash(z) ^ GD.Hash(y));
                        if (fd%2 == 1)
                            limit += 1.0f;
                        if (x*x + z*z > limit)
                            continue;
                        var c2 = coord + new Vector3(x, y, z);
                        if (bounds.HasPoint(c2))
                        {
                            var index = coord_to_index(c2);
                            voxels[index] = 5;
                        }
                    }
                }
            }
            foreach (var y in Enumerable.Range(0, tall))
            {
                var c2 = coord + new Vector3(0, y, 0);
                if (bounds.HasPoint(c2))
                {
                    var index = coord_to_index(c2);
                    voxels[index] = 4;
                }
            }
        }
        return voxels;
    }
}

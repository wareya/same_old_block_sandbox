using Godot;
using System;
using System.Linq;
using System.Collections.Generic;

public partial class VoxelGenerator : RefCounted
{
    static float _adjust_val(float x, float n)
    {
        var s = Mathf.Sign(x);
        x = Mathf.Abs(x);
        x = Mathf.Abs(1.0f - x);
        x = Mathf.Pow(x, n);
        x = s * (1.0f - x);
        return x;
    }
    public static (int, int) height_at_global(Noise noiser, float x, float z)
    {
        float height = noiser.GetNoise2D(x, z);
        
        float steepness_preoffset_freq = 0.5f;
        
        float steepness_preoffset = noiser.GetNoise2D(x*steepness_preoffset_freq, -z*steepness_preoffset_freq - 1130.0f) * 0.75f;
        
        float steepness_freq = 0.5f;
        float steepness_min = 0.2f;
        float steepness_max = 64.0f;
        float steepness_exp = 1.0f;
        
        float steepness = noiser.GetNoise2D(x*steepness_freq, -z*steepness_freq + 100.0f)*0.5f + 0.5f;
        steepness = Mathf.Lerp(steepness_min, steepness_max, Mathf.Pow(steepness, steepness_exp));
        
        height = _adjust_val(height + steepness_preoffset, steepness) - steepness_preoffset;
        
        // extra grit
        float grit_freq = 0.4f;
        float grit_scale = 1.0f;
        
        height += noiser.GetNoise2D(x*grit_freq + 512.0f, z*grit_freq + 11.0f) * grit_scale;
        
        float height_scale_freq = 0.5f;
        float height_scale_min = 3.0f;
        float height_scale_max = 64.0f;
        float height_scale_exp = 5.0f;
        
        float height_scale = noiser.GetNoise2D(x*height_scale_freq, z*height_scale_freq + 154.0f)*0.5f + 0.5f;
        height = height * Mathf.Lerp(height_scale_min, height_scale_max, Mathf.Pow(height_scale, height_scale_exp));
        
        float height_noise_freq = 2.4f;
        float height_noise_scale = 5.0f;
        height += noiser.GetNoise2D(x*height_noise_freq + 51.0f, z*height_noise_freq + 1301.0f) * height_noise_scale;
        
        float rock_freq = 2.6f;
        float rock_scale = 5.0f;
        
        float rock_offset = noiser.GetNoise2D(z*rock_freq + 151.0f, x*rock_freq + 11.0f)*rock_scale - 2.0f;
        
        height = Mathf.Lerp(height, Mathf.Clamp(height, -32.0f, 32.0f), 0.5f);
        height = Mathf.Clamp(height, -63.0f, 63.0f);
        
        height = Mathf.Round(height);
        rock_offset = Mathf.Round(rock_offset);
        
        return ((int)height, (int)rock_offset);
    }
    public int pub_height_at_global(Noise noiser, Vector3 global_coord)
    {
        return height_at_global(noiser, global_coord.X, global_coord.Z).Item1;
    }
    static float erosion_strength_at_global(Noise noiser, Vector3 global_coord)
    {
        var erosion_info_freq = 0.1f;
        var min_strength = 0.0f;
        var max_strength = 96.0f;
        
        float f = noiser.GetNoise2D(global_coord.X*erosion_info_freq, -global_coord.Z*erosion_info_freq - 1100.0f)*0.5f + 0.5f;
        f *= f;
        return Mathf.Lerp(min_strength, max_strength, f);
    }
    static FastNoiseLite buh()
    {
        var r = new FastNoiseLite();
        r.NoiseType = FastNoiseLite.NoiseTypeEnum.Perlin; // or: value
        r.FractalType = FastNoiseLite.FractalTypeEnum.PingPong;
        r.FractalOctaves = 2;
        r.FractalPingPongStrength = 1.5f;
        r.Frequency = 0.02f; // or: 0.02f
        return r;
    }
    static FastNoiseLite erosion_noise = buh();
    static bool erosion_seed_set = false;
    static float get_erosion(Vector3 global_coord, float strength)
    {
        var out_scale = Mathf.Clamp(1.0f + global_coord.Y/16.0f, 0.0f, 1.0f);
        var ret = Mathf.Min(0.0f, erosion_noise.GetNoise3Dv(global_coord.Round()));
        return Mathf.Round(ret*Mathf.Abs(ret)*strength*out_scale);
    }
    // WARNING: for performance reasons, this does a coarse search.
    // its purpose is to find a y value that's solid but has air above it, and is close to the surface.
    // it is not 100% guaranteed to be exposed to the sky.
    public static (int, int) true_height_at_global(Noise noiser, Vector3 global_coord)
    {
        var erosion_strength = erosion_strength_at_global(noiser, global_coord);
        var (h, rock) = height_at_global(noiser, global_coord.X, global_coord.Z);
        var return_h = h;
        var erosion = 0.0f;
        int y = h;
        while (y-4 > -64)
        {
            y -= 4;
            return_h = y;
            erosion = get_erosion(new Vector3(global_coord.X, y, global_coord.Z), erosion_strength);
            if (h - y + erosion >= 0.0f)
                break;
        }
        var end = Math.Min(h, y + 4);
        while (y < end)
        {
            y += 1;
            var new_erosion = get_erosion(new Vector3(global_coord.X, y, global_coord.Z), erosion_strength);
            if (h - y + new_erosion < 0.0f)
                break;
            return_h = y;
            erosion = new_erosion;
        }
        rock = rock + (h - return_h) + (int)(erosion*0.9);
        return (return_h, rock);
    }
    public int pub_true_height_at_global(Noise noiser, Vector3 global_coord)
    {
        return true_height_at_global(noiser, global_coord).Item1;
    }
    public static int chunk_size = 16;
    public static Aabb bounds = new Aabb(new Vector3(), Vector3.One*(chunk_size-1));
    static List<(Vector3, int, uint)> get_tree_coords(Vector3 chunk_position, Noise noiser, int min, int max, int buffer, bool dirt_only = true)
    {
        var rng = new RandomNumberGenerator();
        rng.Seed = (ulong) GD.Hash(chunk_position * new Vector3(1.0f, 0.0f, 1.0f));
        var tree_count = rng.RandiRange(min, max);
        
        var offset = -Vector3.One*chunk_size/2 + chunk_position;
        
        var trees = new List<(Vector3, int, uint)>();
        foreach (var _ in Enumerable.Range(0, tree_count))
        {
            var x = rng.RandiRange(buffer, chunk_size-1-buffer);
            var z = rng.RandiRange(buffer, chunk_size-1-buffer);
            var tall = rng.RandiRange(4, 6);
            var grunge = rng.Randi();
            
            var (height, rock_part) = true_height_at_global(noiser, new Vector3(x, 0, z) + offset);
            var is_rock = rock_part > 1.0f;
            
            if (height >= 0 && !is_rock)
            {
                var c_3d = new Vector3(x, height+1 - chunk_position.Y + chunk_size/2, z);
                trees.Add((c_3d, tall, grunge));
            }
        }
        
        return trees;
    }
    static List<Vector3> get_grass_coords(Vector3 chunk_position, Noise noiser, int min, int max, bool dirt_only = true)
    {
        var rng = new RandomNumberGenerator();
        rng.Seed = (ulong) GD.Hash(chunk_position * new Vector3(1.0f, 0.0f, 1.0f));
        var item_count = rng.RandiRange(min, max);
        
        var offset = -Vector3.One*chunk_size/2 + chunk_position;
        
        var coords = new List<Vector3>();
        foreach (var _ in Enumerable.Range(0, item_count))
        {
            var x = rng.RandiRange(0, chunk_size-1);
            var z = rng.RandiRange(0, chunk_size-1);
            
            var (height, rock_part) = true_height_at_global(noiser, new Vector3(x, 0, z) + offset);
            var is_rock = rock_part > 1.0f;
            
            if (height >= 0 && !is_rock)
                coords.Add(new Vector3(x, height+1 - chunk_position.Y + chunk_size/2, z));
        }
        
        return coords;
    }
    static int coord_to_index(Vector3 coord)
    {
        return ((int)(coord.Y))*chunk_size*chunk_size + ((int)(coord.Z))*chunk_size + ((int)coord.X);
    }
    public byte[] _Generate(Noise noiser, Vector3 chunk_position, Vector3 offset, Vector2 offset_2d)
    {
        if (!erosion_seed_set)
        {
            erosion_noise.Seed = ((FastNoiseLite)noiser).Seed+2;
            erosion_seed_set = true;
        }
        
        var voxels = new byte[chunk_size*chunk_size*chunk_size];
        foreach (var z in Enumerable.Range(0, chunk_size))
        {
            foreach (var x in Enumerable.Range(0, chunk_size))
            {
                var c_2d = new Vector2(x, z) + offset_2d;
                var (height, rock_offset) = height_at_global(noiser, c_2d.X, c_2d.Y);
                
                var h_i = coord_to_index(new Vector3(x, 0, z));
                
                var erosion_strength = erosion_strength_at_global(noiser, new Vector3(x+offset.X, 0, z+offset.Z));
                var erosion = get_erosion(new Vector3(x, 0, z) + offset, erosion_strength);
                
                var max_y = Math.Clamp((int)(height - offset.Y) + 1, 0, chunk_size);
                if (offset.Y < 0)
                    max_y = chunk_size;
                
                foreach (var y in Enumerable.Range(0, max_y))
                {
                    var c = new Vector3(x, y, z) + offset;
        
                    var base_noise = height - c.Y;
                    var noise_above = height - c.Y - 1.0f;
                    
                    var noise = base_noise + erosion;
                    erosion = get_erosion(c + Vector3.Up, erosion_strength);
                    noise_above += erosion;
                    
                    var rock_noise = base_noise + rock_offset + (int)(erosion*0.9);
                    
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
        
        var tree_coords = get_tree_coords(chunk_position, noiser, 3, 6, 2);
        
        foreach (var (coord, tall, grunge) in tree_coords)
        {
            var leaf_bottom = Math.Max(2, tall-3);
            
            foreach (var y in Enumerable.Range(leaf_bottom, (int)(tall+1+(grunge%3)/2)-leaf_bottom))
            {
                var range = 2;
                var evergreen = (grunge & 256) != 0;
                
                if (evergreen)
                    range -= (y+tall-leaf_bottom)%2;
                if (y+1 > tall)
                    range -= 1;
                
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
        
        var grass = get_grass_coords(chunk_position, noiser, 48, 96);
        
        var rng = new RandomNumberGenerator();
        rng.Seed = (ulong) GD.Hash(chunk_position * new Vector3(1.0f, 0.0f, 1.0f));
        
        foreach (var coord in grass)
        {
            if (bounds.HasPoint(coord))
            {
                var index = coord_to_index(coord);
                var type = (byte)rng.RandiRange(7, 9);
                if (rng.RandiRange(0, 10) == 0)
                    type = 10;
                if (rng.RandiRange(0, 10) == 0)
                    type = 11;
                if (rng.RandiRange(0, 10) == 0)
                    type = 12;
                if (rng.RandiRange(0, 10) == 0)
                    type = 13;
                if (voxels[index] == 0)
                    voxels[index] = type;
            }
        }
        
        return voxels;
    }
}

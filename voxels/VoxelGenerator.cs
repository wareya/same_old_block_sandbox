using Godot;
using System;
using System.Linq;
using System.Collections.Generic;

using NoiseType = FastNoiseLite;

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
    
    const int blend_distance = 32;
    const long blend_max_value = int.MaxValue;
    const long blend_threshold = blend_max_value - blend_distance;
    const int blend_reflect_base = int.MinValue + blend_distance;
    
    static float noise_blend_wrapper(int x, int z, float freq, int x_offset, int z_offset, Func<double, double, float> f)
    {
        var x_over = x > blend_threshold;
        var z_over = z > blend_threshold;
        var noise_base = f(x*(double)freq + x_offset, z*(double)freq + z_offset);
        if (x_over && !z_over)
        {
            var x_over_amount = x - blend_threshold;
            long x2 = blend_reflect_base - x_over_amount + 1;
            var t = x_over_amount / (float)blend_distance;
            var noise_x_reflect = f(x2*(double)freq + x_offset, z*(double)freq + z_offset);
            noise_base = Lerp(noise_base, noise_x_reflect, t);
        }
        else if (z_over && !x_over)
        {
            var z_over_amount = z - blend_threshold;
            long z2 = blend_reflect_base - z_over_amount + 1;
            var t = z_over_amount / (float)blend_distance;
            var noise_z_reflect = f(x*(double)freq + x_offset, z2*(double)freq + z_offset);
            noise_base = Lerp(noise_base, noise_z_reflect, t);
        }
        else
        {
            var x_over_amount = x - blend_threshold;
            long x2 = blend_reflect_base - x_over_amount + 1;
            var tx = x_over_amount / (float)blend_distance;
            
            var z_over_amount = z - blend_threshold;
            long z2 = blend_reflect_base - z_over_amount + 1;
            var tz = z_over_amount / (float)blend_distance;
            
            var noise_x_reflect = f(x2*(double)freq + x_offset, z*(double)freq + z_offset);
            var noise_z_reflect = f(x*(double)freq + x_offset, z2*(double)freq + z_offset);
            var noise_xz_reflect = f(x2*(double)freq + x_offset, z2*(double)freq + z_offset);
            
            var a = Lerp(noise_base, noise_x_reflect, tx);
            var b = Lerp(noise_z_reflect, noise_xz_reflect, tx);
            noise_base = Lerp(a, b, tz);
        }
        
        return noise_base;
    }
    
    static float Lerp(float a, float b, float t) { return a + t * (b - a); }
    // gets 2d value noise
    public static float get_noise_2d_adjusted(int x, int z, float freq = 1.0f, int x_offset = 0, int z_offset = 0)
    {
        var x_over = x > blend_threshold;
        var z_over = z > blend_threshold;
        if (x_over || z_over)
            return noise_blend_wrapper(x, z, freq, x_offset, z_offset, (x, z) => {return custom_noise.GetNoise(x, z);});
        else
            return custom_noise.GetNoise(x*(double)freq + x_offset, z*(double)freq + z_offset);
    }
    // gets 3d perlin noise
    public static float get_noise_3d_adjusted(int x, int y, int z, float freq = 1.0f)
    {
        var x_over = x > blend_threshold;
        var z_over = z > blend_threshold;
        if (x_over || z_over)
            return noise_blend_wrapper(x, z, freq, 0, 0, (x, z) => {return erosion_noise.GetNoise(x, y, z);});
        else
            return erosion_noise.GetNoise(x*(double)freq, y*(double)freq, z*(double)freq);
    }
    public static (int, int) height_at_global(int x, int z)
    {
        x += chunk_size/2;
        z += chunk_size/2;
        
        float height = get_noise_2d_adjusted(x, z);
        
        float steepness_preoffset_freq = 0.5f;
        
        float steepness_preoffset = get_noise_2d_adjusted(x, -1-z, steepness_preoffset_freq, 0, -1130) * 0.75f;
        
        float steepness_freq = 0.5f;
        float steepness_min = 0.2f;
        float steepness_max = 64.0f;
        float steepness_exp = 1.0f;
        
        float steepness = get_noise_2d_adjusted(x, -1-z, steepness_freq, 100)*0.5f + 0.5f;
        steepness = Mathf.Lerp(steepness_min, steepness_max, Mathf.Pow(steepness, steepness_exp));
        
        height = _adjust_val(height + steepness_preoffset, steepness) - steepness_preoffset;
        
        // extra grit
        float grit_freq = 0.4f;
        float grit_scale = 1.0f;
        
        height += get_noise_2d_adjusted(x, z, grit_freq, 512, 11) * grit_scale;
        
        float height_scale_freq = 0.5f;
        float height_scale_min = 3.0f;
        float height_scale_max = 64.0f;
        float height_scale_exp = 5.0f;
        
        float height_scale = get_noise_2d_adjusted(x, z, height_scale_freq, 0, 154)*0.5f + 0.5f;
        height = height * Mathf.Lerp(height_scale_min, height_scale_max, Mathf.Pow(height_scale, height_scale_exp));
        
        float height_noise_freq = 2.4f;
        float height_noise_scale = 5.0f;
        height += get_noise_2d_adjusted(x, z, height_noise_freq, 51, 1301) * height_noise_scale;
        
        float rock_freq = 2.6f;
        float rock_scale = 5.0f;
        
        // x/z inversion is deliberate
        float rock_offset = get_noise_2d_adjusted(z, x, rock_freq, 151, 11)*rock_scale - 2.0f;
        
        height = Mathf.Lerp(height, Mathf.Clamp(height, -32.0f, 32.0f), 0.5f);
        height = Mathf.Clamp(height, -63.0f, 63.0f);
        
        height = Mathf.Round(height);
        rock_offset = Mathf.Round(rock_offset);
        
        return ((int)height, (int)rock_offset);
    }
    public int pub_height_at_global(Vector3I global_coord)
    {
        return height_at_global(global_coord.X, global_coord.Z).Item1;
    }
    static float erosion_strength_at_global(Vector3I global_coord)
    {
        global_coord.X += chunk_size/2;
        global_coord.Z += chunk_size/2;
        
        var erosion_info_freq = 0.1f;
        var min_strength = 0.0f;
        var max_strength = 96.0f;
        
        float f = get_noise_2d_adjusted(global_coord.X, -global_coord.Z, erosion_info_freq, 0, -1100)*0.5f + 0.5f;
        f *= f;
        return Mathf.Lerp(min_strength, max_strength, f);
    }
    //static FastNoiseLite buh()
    static NoiseType buh()
    {
        var r = new NoiseType();
        r.SetNoiseType(FastNoiseLite.NoiseType.Perlin);
        r.SetFractalType(FastNoiseLite.FractalType.PingPong);
        r.SetFractalOctaves(2);
        r.SetFractalPingPongStrength(1.5f);
        r.SetFrequency(0.02f);
        return r;
    }
    static NoiseType custom_noise = new NoiseType();
    static NoiseType erosion_noise = buh();
    static bool erosion_seed_set = false;
    static float get_erosion(Vector3I global_coord, float strength)
    {
        var out_scale = Mathf.Clamp(1.0f + global_coord.Y/16.0f, 0.0f, 1.0f);
        var ret = Mathf.Min(0.0f, get_noise_3d_adjusted(global_coord.X, global_coord.Y, global_coord.Z));
        return Mathf.Round(ret*Mathf.Abs(ret)*strength*out_scale);
    }
    // WARNING: for performance reasons, this does a coarse search.
    // its purpose is to find a y value that's solid but has air above it, and is close to the surface.
    // it is not 100% guaranteed to be exposed to the sky.
    public static (int, int) true_height_at_global(Noise noiser, Vector3I global_coord)
    {
        var erosion_strength = erosion_strength_at_global(global_coord);
        var (h, rock) = height_at_global(global_coord.X, global_coord.Z);
        var return_h = h;
        var erosion = 0.0f;
        int y = h;
        while (y-4 > -64)
        {
            y -= 4;
            return_h = y;
            erosion = get_erosion(new Vector3I(global_coord.X, y, global_coord.Z), erosion_strength);
            if (h - y + erosion >= 0.0f)
                break;
        }
        var end = Math.Min(h, y + 4);
        while (y < end)
        {
            y += 1;
            var new_erosion = get_erosion(new Vector3I(global_coord.X, y, global_coord.Z), erosion_strength);
            if (h - y + new_erosion < 0.0f)
                break;
            return_h = y;
            erosion = new_erosion;
        }
        rock = rock + (h - return_h) + (int)(erosion*0.9);
        return (return_h, rock);
    }
    public int pub_true_height_at_global(Noise noiser, Vector3I global_coord)
    {
        return true_height_at_global(noiser, global_coord).Item1;
    }
    public static int chunk_size = 16;
    public static Vector3I chunk_vec3i = new Vector3I(chunk_size, chunk_size, chunk_size);
    public static Aabb bounds = new Aabb(new Vector3(), Vector3.One*(chunk_size-1));
    static List<(Vector3I, int, uint)> get_tree_coords(Vector3I chunk_position, Noise noiser, int min, int max, int buffer, bool dirt_only = true)
    {
        var rng = new RandomNumberGenerator();
        rng.Seed = (ulong) GD.Hash(chunk_position * new Vector3I(1, 0, 1));
        var tree_count = rng.RandiRange(min, max);
        
        var offset = -Vector3I.One*chunk_size/2 + chunk_position;
        
        var trees = new List<(Vector3I, int, uint)>();
        foreach (var _ in Enumerable.Range(0, tree_count))
        {
            var x = rng.RandiRange(buffer, chunk_size-1-buffer);
            var z = rng.RandiRange(buffer, chunk_size-1-buffer);
            var tall = rng.RandiRange(4, 6);
            var grunge = rng.Randi();
            
            var (height, rock_part) = true_height_at_global(noiser, new Vector3I(x, 0, z) + offset);
            var is_rock = rock_part > 1.0f;
            
            if (height >= 0 && !is_rock)
            {
                var c_3d = new Vector3I(x, height+1 - chunk_position.Y + chunk_size/2, z);
                trees.Add((c_3d, tall, grunge));
            }
        }
        
        return trees;
    }
    static List<Vector3I> get_grass_coords(Vector3I chunk_position, Noise noiser, int min, int max, bool dirt_only = true)
    {
        var rng = new RandomNumberGenerator();
        rng.Seed = (ulong) GD.Hash(chunk_position * new Vector3I(1, 0, 1));
        var item_count = rng.RandiRange(min, max);
        
        var offset = -Vector3I.One*chunk_size/2 + chunk_position;
        
        var coords = new List<Vector3I>();
        foreach (var _ in Enumerable.Range(0, item_count))
        {
            var x = rng.RandiRange(0, chunk_size-1);
            var z = rng.RandiRange(0, chunk_size-1);
            
            var (height, rock_part) = true_height_at_global(noiser, new Vector3I(x, 0, z) + offset);
            var is_rock = rock_part > 1.0f;
            
            if (height >= 0 && !is_rock)
                coords.Add(new Vector3I(x, height+1 - chunk_position.Y + chunk_size/2, z));
        }
        
        return coords;
    }
    static int coord_to_index(Vector3I coord)
    {
        return coord.Y*chunk_size*chunk_size + coord.Z*chunk_size + coord.X;
    }
    public byte[] _Generate(Noise noiser, Vector3I chunk_position, Vector3I offset)
    {
        var offset_2d = new Vector2I(offset.X, offset.Z);
        
        if (!erosion_seed_set)
        {
            var n = (Godot.FastNoiseLite)noiser;
            custom_noise.SetSeed(n.Seed);
            custom_noise.SetFrequency(n.Frequency);
            custom_noise.SetNoiseType(FastNoiseLite.NoiseType.Value);

            custom_noise.SetFractalOctaves(n.FractalOctaves);
            custom_noise.SetFractalLacunarity(n.FractalLacunarity);
            custom_noise.SetFractalGain(n.FractalGain);
            
            erosion_noise.SetSeed(n.Seed+2);
            erosion_seed_set = true;
        }
        
        var voxels = new byte[chunk_size*chunk_size*chunk_size];
        foreach (var z in Enumerable.Range(0, chunk_size))
        {
            foreach (var x in Enumerable.Range(0, chunk_size))
            {
                var c_2d = new Vector2I(x, z) + offset_2d;
                var (height, rock_offset) = height_at_global(c_2d.X, c_2d.Y);
                
                var h_i = coord_to_index(new Vector3I(x, 0, z));
                
                var erosion_strength = erosion_strength_at_global(new Vector3I(x+offset.X, 0, z+offset.Z));
                var erosion = get_erosion(new Vector3I(x, 0, z) + offset, erosion_strength);
                
                var max_y = Math.Clamp((int)(height - offset.Y) + 1, 0, chunk_size);
                if (offset.Y < 0)
                    max_y = chunk_size;
                
                foreach (var y in Enumerable.Range(0, max_y))
                {
                    var c = new Vector3I(x, y, z) + offset;
        
                    var base_noise = height - c.Y;
                    var noise_above = height - c.Y - 1.0f;
                    
                    var noise = base_noise + erosion;
                    erosion = get_erosion(c + Vector3I.Up, erosion_strength);
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
                        var c2 = coord + new Vector3I(x, y, z);
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
                var c2 = coord + new Vector3I(0, y, 0);
                if (bounds.HasPoint(c2))
                {
                    var index = coord_to_index(c2);
                    voxels[index] = 4;
                }
            }
        }
        
        var grass = get_grass_coords(chunk_position, noiser, 48, 96);
        
        var rng = new RandomNumberGenerator();
        rng.Seed = (ulong) GD.Hash(chunk_position * new Vector3I(1, 0, 1));
        
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

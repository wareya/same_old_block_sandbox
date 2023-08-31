using Godot;
using System;
using System.Linq;
using System.Collections.Generic;

using NoiseType = FastNoiseLite;
//using NoiseType = GodotNoiseWrapper;

// used only when developing/debugging
// do not use for production, use FastNoiseLite.cs instead
class GodotNoiseWrapper
{
    Godot.FastNoiseLite noise = new();
    
    public float GetNoise(double x, double y)
    {
        return noise.GetNoise2D((float)x, (float)y);
    }
    public float GetNoise(double x, double y, double z)
    {
        return noise.GetNoise3D((float)x, (float)y, (float)z);
    }
    
    public void SetSeed(int seed)
    {
        noise.Seed = seed;
    }
    public void SetFrequency(float freq)
    {
        noise.Frequency = freq;
    }
    public void SetNoiseType(FastNoiseLite.NoiseType type)
    {
        noise.NoiseType = (Godot.FastNoiseLite.NoiseTypeEnum)type;
    }
    public void SetFractalType(FastNoiseLite.FractalType type)
    {
        noise.FractalType = (Godot.FastNoiseLite.FractalTypeEnum)type;
    }

    public void SetFractalOctaves(int octaves)
    {
        noise.FractalOctaves = octaves;
    }
    public void SetFractalLacunarity(float lacunarity)
    {
        noise.FractalLacunarity = lacunarity;
    }
    public void SetFractalPingPongStrength(float strength)
    {
        noise.FractalPingPongStrength = strength;
    }
    public void SetFractalGain(float gain)
    {
        noise.FractalGain = gain;
    }
}

public partial class VoxelGenerator : Node
{
    //public static int chunk_size = 16;
    public const int chunk_size_h = 16;
    public const int chunk_size_v = 64;
    public int _chunk_size_h = chunk_size_h; // for visibility from gdscript (can't be static/const)
    public int _chunk_size_v = chunk_size_v; // for visibility from gdscript (can't be static/const)
    public static Vector3I chunk_vec3i = new Vector3I(chunk_size_h, chunk_size_v, chunk_size_h);
    public static Aabb bounds = new Aabb(new Vector3(), new Vector3(chunk_vec3i.X, chunk_vec3i.Y, chunk_vec3i.Z) - Vector3.One);
    
    public const int height_offset = 2;
    public const int sea_level = 0;
    public int _height_offset = height_offset; // for visibility from gdscript (can't be static/const)
    public int _sea_level = height_offset; // for visibility from gdscript (can't be static/const)
    
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
        var x2 = (double)x;
        var z2 = (double)z;
        // add a small amount of jitter to x and z to make cliff faces less regular
        x2 += (uint)x*2654435761%256/512.0-0.25;
        z2 += (uint)z*2654435761%256/512.0-0.25;
        
        var x_over = x > blend_threshold;
        var z_over = z > blend_threshold;
        if (x_over || z_over)
            return noise_blend_wrapper(x, z, freq, x_offset, z_offset, (x, z) => {return custom_noise.GetNoise(x, z);});
        else
            return custom_noise.GetNoise(x2*(double)freq + x_offset, z2*(double)freq + z_offset);
    }
    // gets 3d perlin noise
    public static float get_noise_3d_adjusted(int x, int y, int z, float freq = 1.0f)
    {
        var x2 = (double)x;
        var z2 = (double)z;
        // add a small amount of jitter to x and z to make cliff faces less regular
        x2 += (uint)x*2654435761%256/512.0-0.25;
        z2 += (uint)z*2654435761%256/512.0-0.25;
        
        var x_over = x > blend_threshold;
        var z_over = z > blend_threshold;
        if (x_over || z_over)
            return noise_blend_wrapper(x, z, freq, 0, 0, (x, z) => {return erosion_noise.GetNoise(x, y, z);});
        else
            return erosion_noise.GetNoise(x2*(double)freq, y*(double)freq, z2*(double)freq);
    }
    public static (int, int, int) height_at_global(int x, int z)
    {
        x += chunk_size_h/2;
        z += chunk_size_h/2;
        
        var height_freq = 0.45f;
        
        float height = get_noise_2d_adjusted(x, z, height_freq);
        
        float steepness_preoffset_freq = 0.5f;
        float steepness_preoffset = get_noise_2d_adjusted(x, -1-z, steepness_preoffset_freq, 0, -1130) * 0.75f;
        
        float steepness_freq = 0.5f;
        float steepness_min = 0.2f;
        float steepness_max = 128.0f;
        float steepness_exp = 6.0f;
        
        float steepness = get_noise_2d_adjusted(x, -1-z, steepness_freq, 100)*0.5f + 0.5f;
        steepness = Mathf.Lerp(steepness_min, steepness_max, Mathf.Pow(steepness, steepness_exp));
        
        height = _adjust_val(height + steepness_preoffset, steepness) - steepness_preoffset;
        
        float height_scale_freq = 0.2f;
        float height_scale_min = 3.0f;
        //float height_scale_max = 64.0f;
        float height_scale_max = 192.0f;
        float height_scale_exp = 5.0f;
        
        float height_scale = get_noise_2d_adjusted(x, z, height_scale_freq, 0, 154)*0.5f + 0.5f;
        height *= Mathf.Lerp(height_scale_min, height_scale_max, Mathf.Pow(height_scale, height_scale_exp));
        
        float height_noise_freq = 5.4f;
        float height_noise_scale = 2.0f;
        height += get_noise_2d_adjusted(x, z, height_noise_freq, 51, 1301) * height_noise_scale;
        
        float height_continentize_freq = 0.11f;
        float height_continentize_scale = 5.0f;
        height += -blip(3.0f*get_noise_2d_adjusted(x-z, x+z, height_continentize_freq, 1561, 12246)) * height_continentize_scale - 1.0f;
        
        float rock_freq = 2.6f;
        float rock_scale = 4.0f;
        
        // x/z inversion is deliberate
        float rock = get_noise_2d_adjusted(z, x, rock_freq, 151, 11)*rock_scale - 3.0f;
        
        float sand_freq = 2.6f;
        float sand_scale = 3.0f;
        
        // x/z inversion is deliberate
        float sand = get_noise_2d_adjusted(z, x, sand_freq, 15, 61011)*sand_scale + 1.5f;
        
        var height_limit_soft = 128.0f;
        var height_limit_hard = 192.0f;
        
        var depth_limit_soft = -32.0f;
        var depth_limit_hard = -60.0f;
        
        height = Mathf.Lerp(height, Mathf.Clamp(height, depth_limit_soft, height_limit_soft), 0.5f);
        height = Mathf.Clamp(height, depth_limit_hard, height_limit_hard);
        
        rock = Mathf.Round(rock + height + height_offset);
        height = Mathf.Round(height + height_offset);
        sand = Mathf.Round(sand + height_offset);
        
        return ((int)height, (int)rock, (int)sand);
    }
    public int pub_height_at_global(Vector3I global_coord)
    {
        return height_at_global(global_coord.X, global_coord.Z).Item1;
    }
    static float erosion_min_strength = 0.0f;
    static float erosion_max_strength = 96.0f;
    static float erosion_strength_at_global(int x, int z)
    {
        return 0.0f;
        
        x += chunk_size_h/2;
        z += chunk_size_h/2;
        
        var erosion_info_freq = 0.2f;
        
        float f = get_noise_2d_adjusted(x, -1-z, erosion_info_freq, 0, -11100)*0.5f + 0.5f;
        f = Mathf.Clamp(Mathf.Lerp(-0.7f, 1.4f, f), 0.0f, 1.0f);
        f *= Math.Abs(f);
        f *= Math.Abs(f);
        return Mathf.Lerp(erosion_min_strength, erosion_max_strength, f);
    }
    //static FastNoiseLite buh()
    static NoiseType buh()
    {
        var r = new NoiseType();
        r.SetNoiseType(FastNoiseLite.NoiseType.Perlin);
        r.SetFractalType(FastNoiseLite.FractalType.FBm);
        r.SetFractalOctaves(3);
        r.SetFractalLacunarity(5.0f);
        r.SetFractalGain(0.15f);
        r.SetFrequency(0.004f);
        return r;
    }
    static NoiseType custom_noise = new NoiseType();
    static NoiseType erosion_noise = buh();
    static bool erosion_seed_set = false;
    static float funwrap(float x)
    {
        //x *= 0.5f;
        //x = Mathf.Clamp(x, -1.0f, 1.0f);
        //return Mathf.Max(-1-x, Mathf.Min(x, 1-x))*2.0f;
        x = Mathf.Clamp(x, -2.0f, 2.0f);
        const float _denom = 3.079201435678f;//Mathf.Sqrt(3.0f)*16.0f/9.0f;
        return (2+x)*x*(2-x)/_denom;
    }
    static float blip(float x)
    {
        x = Mathf.Clamp(x, -1.0f, 1.0f);
        return 1-x*x;
    }
    static int get_erosion(Vector3I global_coord, float strength)
    {
        if (strength == 0.0f)
            return 0;
        
        global_coord.Y -= height_offset;
        var out_scale = Mathf.Clamp(1.0f + global_coord.Y/16.0f, 0.0f, 1.0f);
        var center = get_noise_3d_adjusted(global_coord.X, global_coord.Y, global_coord.Z);
        if (center > 0)
            return 0;
        
        var ret = center;
        ret = funwrap(ret*8.0f - 0.4f);
        
        // weaken half-ish of lines
        //var next = get_noise_3d_adjusted(global_coord.X + 64, global_coord.Y, global_coord.Z);
        //if (center > next)
        //    ret /= (center-next)*100.0f + 1.0f;
        
        ret *= Math.Abs(ret);
        
        return (int)Mathf.Round(ret*strength*out_scale);
    }
    // WARNING: for performance reasons, this does a coarse search.
    // its purpose is to find a y value that's solid but has air above it, and is close to the surface.
    // it is not 100% guaranteed to be exposed to the sky.
    
    static int erode_height_at_global(int h, int x, int z)
    {
        var erosion_strength = erosion_strength_at_global(x, z);
        var return_h = h;
        int y = h;
        while (y-4 > -64)
        {
            y -= 4;
            return_h = y;
            var erosion = get_erosion(new Vector3I(x, y, z), erosion_strength);
            if (h - y + erosion >= 0.0f)
                break;
        }
        var end = Math.Min(h, y + 4);
        while (y < end)
        {
            y += 1;
            var erosion = get_erosion(new Vector3I(x, y, z), erosion_strength);
            if (h - y + erosion < 0.0f)
                break;
            return_h = y;
        }
        return return_h;
    }
    
    public static (int, int, int) true_height_at_global(int x, int z)
    {
        var (h, rock, sand) = height_at_global(x, z);
        var eroded_h = erode_height_at_global(h, x, z);
        var diff_h = h - eroded_h;
        rock -= diff_h;
        return (eroded_h, rock, sand);
    }
    public int pub_true_height_at_global(Vector3I global_coord)
    {
        return true_height_at_global(global_coord.X, global_coord.Z).Item1;
    }
    public int[] pub_true_height_at_global_3(Vector3I global_coord)
    {
        var r = true_height_at_global(global_coord.X, global_coord.Z);
        return new int[]{r.Item1, r.Item2, r.Item3};
    }
    
    public Image pub_generate_image(Vector2I vec, int subsampling)
    {
        var chunk_size_modifier = 1;
        
        var chunk_size = chunk_size_h * chunk_size_modifier;
        var chunk_size_2 = chunk_size * subsampling;
        Image image = null;
        var offset = -(chunk_size * subsampling)/2;
        
        image = Image.Create(chunk_size, chunk_size, true, Image.Format.Rgba8);
        
        foreach (var z in Enumerable.Range(0, chunk_size))
        {
            var z2 = z * chunk_size_2 / chunk_size;
            var z3 = z2 + vec.Y + offset;
            foreach (var x in Enumerable.Range(0, chunk_size))
            {
                var x2 = x * chunk_size_2 / chunk_size;
                var x3 = x2 + vec.X + offset;
                var (h, rock, sand) = true_height_at_global(x3, z3);
                
                Color c;
                if (h >= sea_level)
                {
                    c = new Color(0.2f, 0.7f, 0.2f);
                    if (subsampling > 3 && (x&1) == (z&1))
                    {
                        var biome_foliage = get_noise_2d_adjusted(x3, z3, 0.6f, -59234, 8143)*0.5f + 0.5f;
                        var biome_trees = Mathf.Clamp(Mathf.Lerp(-0.5f, 1.2f, biome_foliage), 0.0f, 1.0f);
                        var c2 = new Color(0.0f, 0.4f, 0.1f, biome_trees);
                        c = c.Blend(c2);
                    }
                }
                else
                    c = new Color(0.5f, 0.4f, 0.2f);
                
                if (rock > h)
                    c = new Color(0.5f, 0.55f, 0.6f);
                else if(sand > h)
                    c = new Color(0.95f, 0.9f, 0.7f);
                
                if (h < sea_level)
                    c = c.Blend(new Color(0.0f, 0.2f, 1.0f, 0.7f));
                
                var level = (h - sea_level)%4/4.0f;
                level = Mathf.Lerp(1.1f, 0.9f, level);
                c *= level;
                
                level = ((h - sea_level)%128 + 128)%128/128.0f;
                level = Mathf.Lerp(1.0f, 1.5f, level);
                c *= level;
                
                c.A = 1.0f;
                
                image.SetPixel(x, z, c);
                
                //var asdf = erosion_strength_at_global(x3, z3)/erosion_max_strength;
                //asdf = Mathf.Sqrt(asdf);
                
                //var asdf = erosion_strength_at_global(x3, z3);
                //var asdf2 = -get_erosion(new Vector3I(x3, 0, z3), asdf)/erosion_max_strength*8.0f;
                //
                //image.SetPixel(x, z, new Color(asdf2, asdf2, asdf2));
            }
        }
        
        var chunk_position = VoxelMesher.get_chunk_coord(new Vector3I(vec.X, 0, vec.Y));
        
        var all_tree_coords = new Dictionary<Vector2I, (int, int, uint)>();
        foreach (var z in Enumerable.Range(-1, 3))
        {
            foreach (var x in Enumerable.Range(-1, 3))
            {
                var g_coord = chunk_position + new Vector3I(x * chunk_size_h, 0, z*chunk_size_h);
                var coords =  get_tree_coords(g_coord);
                foreach (var (c, y, a, b) in coords)
                    all_tree_coords[c] = (y, a, b);
            }
        }
        
        all_tree_coords = filter_trees(all_tree_coords);
        
        foreach (var (_coord, (y, tall, grunge)) in all_tree_coords)
        {
            var (height, _, _) = true_height_at_global(_coord.X - chunk_size_h/2, _coord.Y - chunk_size_h/2);
            var coord = new Vector3I(_coord.X, y, _coord.Y) - chunk_position;
            coord.Y = height+1 - chunk_position.Y + chunk_size_v/2;
            
            coord /= subsampling;
            
            coord.X += (chunk_size_h - chunk_size_h/subsampling)/2;
            coord.Z += (chunk_size_h - chunk_size_h/subsampling)/2;
            
            var start = -2;
            var count = 5;
            start += subsampling-1;
            count = (int)MathF.Ceiling((float)count/subsampling);
            if (count <= 0)
                continue;
            
            foreach (var z in Enumerable.Range(start, count))
            {
                foreach (var x in Enumerable.Range(start, count))
                {
                    var limit = (count-1)*(count-1)/4.0f+0.25f;
                    var badhash = grunge ^ GD.Hash(x) ^ GD.Hash(z);
                    if (badhash%2 == 1)
                        limit += 1.0f/subsampling;
                    if (x*x + z*z > limit)
                        continue;
                    var x2 = x + coord.X;
                    var z2 = z + coord.Z;
                    if (x2 >= 0 && x2 < chunk_size_h && z2 >= 0 && z2 < chunk_size_h)
                    {
                        //image.GetPixel
                        var c = new Color(0.0f, 0.4f, 0.1f);
                        
                        var level = (height - sea_level + tall)%4/4.0f;
                        level = Mathf.Lerp(1.1f, 0.9f, level);
                        c *= level;
                        
                        level = (Math.Abs(height - sea_level + 1 + tall)%128 + 128)%128/128.0f;
                        level = Mathf.Lerp(1.0f, 1.5f, level);
                        c *= level;
                        
                        image.SetPixel(x2, z2, c);
                    }
                }
            }
        }
        
        return image;
    }
    
    static List<(Vector2I, int, int, uint)> get_tree_coords(Vector3I chunk_position)
    {
        var biome_foliage = get_noise_2d_adjusted(chunk_position.X, chunk_position.Z, 0.6f, -59234, 8143)*0.5f + 0.5f;
        
        var biome_trees = Mathf.Clamp(Mathf.Lerp(-0.5f, 1.2f, biome_foliage), 0.0f, 1.0f);
        var min = (int)(11*biome_trees);
        var max = (int)(16*biome_trees);
        
        var allow_supertall = max > 10;
        
        var rng = new RandomNumberGenerator();
        rng.Seed = (ulong) GD.Hash(chunk_position * new Vector3I(1, 0, 1));
        var tree_count = rng.RandiRange(min, max);
        tree_count *= chunk_size_h/16*chunk_size_h/16;
        
        var trees = new List<(Vector2I, int, int, uint)>();
        var coords = new HashSet<(int, int)>();
        foreach (var _ in Enumerable.Range(0, tree_count))
        {
            var x = rng.RandiRange(0, chunk_size_h-1);
            var z = rng.RandiRange(0, chunk_size_h-1);
            
            var tall = allow_supertall ? rng.RandiRange(4, 8) : rng.RandiRange(4, 6);
            var grunge = rng.Randi();
            
            var last_was_x = false;
            var bad_spot = (int x, int z) =>
            {
                int bwuh = 3;
                foreach (var (other_x, other_z) in coords)
                {
                    var _x = Math.Abs(x-other_x);
                    var _z = Math.Abs(z-other_z);
                    if (_x <= bwuh && _z <= bwuh)
                    {
                        if (last_was_x && _z > 0)
                            return (0, Math.Sign(z-other_z) * (bwuh-_z+1));
                        else if (_x >= _z)
                            return (Math.Sign(x-other_x) * (bwuh-_x+1), 0);
                        else if (_z > 0)
                            return (0, Math.Sign(z-other_z) * (bwuh-_z+1));
                        else
                            return (1, 0);
                    }
                }
                return (0, 0);
            };
            var retries = 5;
            for (var (x_dir, z_dir) = bad_spot(x, z); (x_dir != 0 || z_dir != 0) && retries > 0;)
            {
                x += x_dir;
                z += z_dir;
                retries -= 1;
                if (x < 0 || x >= chunk_size_h || z < 0 || z >= chunk_size_h)
                    retries = 0;
            }
            if (retries == 0)
                continue;
            
            var c_3d = new Vector3I(x, 0, z) + chunk_position;
            
            var c_3d2 = c_3d - new Vector3I(chunk_size_h/2, 0, chunk_size_h/2);
            
            var (height, rock, sand) = true_height_at_global(c_3d2.X, c_3d2.Z);
            if (rock >= height || sand >= height || height < sea_level)
                continue;
            if (true_height_at_global(c_3d2.X - 2, c_3d2.Z - 2).Item1-3 > height)
                continue;
            if (true_height_at_global(c_3d2.X + 2, c_3d2.Z - 2).Item1-3 > height)
                continue;
            if (true_height_at_global(c_3d2.X - 2, c_3d2.Z - 2).Item1-3 > height)
                continue;
            if (true_height_at_global(c_3d2.X + 2, c_3d2.Z + 2).Item1-3 > height)
                continue;
            
            coords.Add((x, z));
            trees.Add((new Vector2I(c_3d.X, c_3d.Z), c_3d.Y, tall, grunge));
        }
        
        return trees;
    }
    static List<Vector3I> get_grass_coords((int, byte)[] chunk_info, Vector3I chunk_position, int min, int max, bool dirt_only = true)
    {
        var rng = new RandomNumberGenerator();
        rng.Seed = (ulong) GD.Hash(chunk_position * new Vector3I(1, 0, 1));
        var item_count = rng.RandiRange(min, max);
        
        var offset = -chunk_vec3i/2 + chunk_position;
        
        var coords = new List<Vector3I>();
        foreach (var _ in Enumerable.Range(0, item_count))
        {
            var x = rng.RandiRange(0, chunk_size_h-1);
            var z = rng.RandiRange(0, chunk_size_h-1);
            
            var info_i = chunk_size_h*z + x;
            var (height, type) = chunk_info[info_i];
            
            if (height >= sea_level && type == 1) // 1 = grass
                coords.Add(new Vector3I(x, height+1 - chunk_position.Y + chunk_size_v/2, z));
        }
        
        return coords;
    }
    static int coord_to_index(Vector3I coord)
    {
        return coord.Y*chunk_size_h*chunk_size_h + coord.Z*chunk_size_h + coord.X;
    }
    public byte[] _voxels = new byte[chunk_size_h*chunk_size_h*chunk_size_v];
    public (int, byte)[] chunk_info = new (int, byte)[chunk_size_h*chunk_size_h];
    public byte get_voxel(Vector3I coord)
    {
        if (bounds.HasPoint(coord))
            return _voxels[coord_to_index(coord)];
        return 0;
    }
    public void set_voxel(Vector3I coord, byte type)
    {
        if (bounds.HasPoint(coord))
            _voxels[coord_to_index(coord)] = type;
    }
    public void _Set_Noiser(Noise noiser)
    {
        var n = (Godot.FastNoiseLite)noiser;
        custom_noise.SetSeed(n.Seed);
        custom_noise.SetFrequency(n.Frequency);
        custom_noise.SetNoiseType(FastNoiseLite.NoiseType.Value);

        custom_noise.SetFractalOctaves(n.FractalOctaves);
        custom_noise.SetFractalLacunarity(n.FractalLacunarity);
        custom_noise.SetFractalGain(n.FractalGain);
        
        erosion_noise.SetSeed(n.Seed+2);
    }
    static float terrain_time = 0.0f;
    float pub_get_terrain_time()
    {
        return terrain_time;
    }
    public void _Generate_Terrain_Only(Noise noiser, Vector3I chunk_position)
    {
        var start = Godot.Time.GetTicksUsec()/1000000.0f;
        
        if (!erosion_seed_set)
        {
            _Set_Noiser(noiser);
            erosion_seed_set = true;
        }
        
        var voxels = _voxels;
        
        var offset = -chunk_vec3i/2 + chunk_position;
        var offset_2d = new Vector2I(offset.X, offset.Z);
        
        var prev_height_x = new int[chunk_size_h];
        foreach (var x in Enumerable.Range(0, chunk_size_h))
        {
            prev_height_x[x] = true_height_at_global(offset_2d.X + x, offset_2d.Y - 1).Item1;
        }
        foreach (var z in Enumerable.Range(0, chunk_size_h))
        {
            var prev_height = true_height_at_global(offset_2d.X - 1, offset_2d.Y + z).Item1;
            foreach (var x in Enumerable.Range(0, chunk_size_h))
            {
                var info_i = chunk_size_h*z + x;
                
                var c_2d = new Vector2I(x, z) + offset_2d;
                var (height, rock_height, sand_height) = height_at_global(c_2d.X, c_2d.Y);
                
                var eroded_height = erode_height_at_global(height, c_2d.X, c_2d.Y);
                
                // figure out if this part of the map is steep
                var diff_north = Math.Abs(eroded_height - prev_height_x[x]);
                var diff_west  = Math.Abs(eroded_height - prev_height);
                prev_height_x[x] = eroded_height;
                prev_height = eroded_height;
                
                var steep_threshold = 4;//eroded_height - rock_height + 1;
                
                var extremely_steep = false;
                if (diff_north > steep_threshold)
                {
                    var diff_south = Math.Abs(eroded_height - true_height_at_global(c_2d.X, c_2d.Y + 1).Item1);
                    if (diff_south > steep_threshold)
                        extremely_steep = true;
                }
                if (!extremely_steep && diff_west > steep_threshold)
                {
                    var diff_east = Math.Abs(eroded_height - true_height_at_global(c_2d.X + 1, c_2d.Y).Item1);
                    if (diff_east > steep_threshold)
                        extremely_steep = true;
                }
                // done figuring out if it's steep
                
                var diff_h = height - eroded_height;
                rock_height -= diff_h;
                
                byte top_vox = 3; // stone
                if (!extremely_steep)
                {
                    if (rock_height > eroded_height || extremely_steep)
                        top_vox = 3; // rock
                    else if (sand_height > eroded_height)
                        top_vox = 14; // sand
                    else
                        top_vox = 1; // grass
                }
                
                chunk_info[info_i] = (eroded_height, top_vox);
                
                var erosion_strength = erosion_strength_at_global(c_2d.X, c_2d.Y);
                var erosion = get_erosion(new Vector3I(c_2d.X, offset.Y, c_2d.Y), erosion_strength);
                
                var max_y = Math.Clamp(height - offset.Y + 1, 0, chunk_size_v);
                if (offset.Y < 0)
                    max_y = chunk_size_v;
                
                var i = coord_to_index(new Vector3I(x, 0, z));
                var prev_skipped = false;
                foreach (var y in Enumerable.Range(0, max_y))
                {
                    if (height-1 - (y + offset.Y) > erosion_strength)
                    {
                        voxels[i] = 3; // rock
                        i += chunk_size_h*chunk_size_h;
                        prev_skipped = true;
                        continue;
                    }
                    var c = new Vector3I(x, y, z) + offset;
                    
                    if (prev_skipped)
                        erosion = get_erosion(c, erosion_strength);
                    prev_skipped = false;
        
                    var base_noise = height - c.Y;
                    var noise_above = base_noise - 1;
                    
                    var noise = base_noise + erosion;
                    erosion = get_erosion(c + Vector3I.Up, erosion_strength);
                    noise_above += erosion;
                    
                    byte vox = 0;
                    if (noise < 0)
                    {
                        if(c.Y <= sea_level)
                            vox = 6; // water
                        else
                            vox = 0; // air
                    }
                    else
                    {
                        if (rock_height > c.Y || extremely_steep)
                            vox = 3; // rock
                        else if (sand_height > c.Y)
                            vox = 14; // sand
                        else if(noise_above < 0 && c.Y >= sea_level)
                            vox = 1; // grass
                        else
                            vox = 2; // dirt
                    }
                    
                    voxels[i] = vox;
                    i += chunk_size_h*chunk_size_h;
                }
            }
        }
        var end = Godot.Time.GetTicksUsec()/1000000.0f;
        terrain_time += end-start;
    }
    static Dictionary<Vector2I, (int, int, uint)> filter_trees(Dictionary<Vector2I, (int, int, uint)> all_tree_coords)
    {
        Dictionary<Vector2I, (int, int, uint)> copy = new();
        foreach (var (_coord, (y, tall, grunge)) in all_tree_coords)
        {
            var bad = false;
            foreach (var z in Enumerable.Range(-2, 5))
            {
                var other_z = z + _coord.Y;
                foreach (var x in Enumerable.Range(-2, 5))
                {
                    var other_x = x + _coord.X;
                }
            }
            foreach (var (other_x, other_z) in all_tree_coords.Keys)
            {
                var diff_x = _coord.X - other_x;
                var diff_z = _coord.Y - other_z;
                if (diff_x < 0 || diff_z < 0)
                    continue;
                if (diff_x == 0 && diff_z == 0)
                    continue;
                if (diff_x < 3 && diff_z < 3)
                {
                    bad = true;
                    break;
                }
            }
            if (bad)
                continue;
            
            copy[_coord] = (y, tall, grunge);
        }
        return copy;
    }
    static float decorate_time = 0.0f;
    float pub_get_decorate_time()
    {
        return decorate_time;
    }
    public void _Generate(Vector3I chunk_position, Godot.Collections.Dictionary neighbor_chunks)
    {
        var start = Godot.Time.GetTicksUsec()/1000000.0f;
        
        var voxels = _voxels;
        
        System.Diagnostics.Debug.Assert(voxels.Length == chunk_size_h*chunk_size_h*chunk_size_v);
        
        Dictionary<Vector3I, VoxelGenerator> neighbors = new();
        foreach (var k in neighbor_chunks.Keys)
            neighbors[(Vector3I)k] = (VoxelGenerator)neighbor_chunks[k];
        
        var biome_foliage = get_noise_2d_adjusted(chunk_position.X, chunk_position.Z, 0.6f, -59234, 8143)*0.5f + 0.5f;
        
        var all_tree_coords = new Dictionary<Vector2I, (int, int, uint)>();
        foreach (var z in Enumerable.Range(-1, 3))
        {
            foreach (var x in Enumerable.Range(-1, 3))
            {
                var g_coord = chunk_position + new Vector3I(x * chunk_size_h, 0, z*chunk_size_h);
                var coords =  get_tree_coords(g_coord);
                foreach (var (c, y, a, b) in coords)
                {
                    all_tree_coords[c] = (y, a, b);
                }
            }
        }
        
        all_tree_coords = filter_trees(all_tree_coords);
        
        foreach (var (_coord, (_y, tall, grunge)) in all_tree_coords)
        {
            var (height, _, _) = true_height_at_global(_coord.X - chunk_size_h/2, _coord.Y - chunk_size_h/2);
            var coord = new Vector3I(_coord.X, _y, _coord.Y) - chunk_position;
            coord.Y = height+1 - chunk_position.Y + chunk_size_v/2;
            
            var leaf_bottom = Math.Max(2, tall-3);
            if (tall >= 7 && leaf_bottom > 2)
                leaf_bottom -= 1;
            
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
                        var badhash = grunge ^ GD.Hash(x) ^ GD.Hash(z) ^ GD.Hash(y);
                        if (badhash%2 == 1)
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
        
        var biome_grass = Mathf.Clamp(Mathf.Lerp(0.05f, 1.2f, biome_foliage), 0.0f, 1.0f);
        var grass_min_count = (int)(48*biome_grass);
        var grass_max_count = (int)(96*biome_grass);
        
        var grass = get_grass_coords(chunk_info, chunk_position, grass_min_count, grass_max_count);
        
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
        var end = Godot.Time.GetTicksUsec()/1000000.0f;
        decorate_time += end-start;
    }
    ~VoxelGenerator()
    {
        _voxels = null;
        chunk_info = null;
    }
}

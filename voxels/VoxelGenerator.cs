using Godot;
using System;
using System.Linq;
using System.Collections.Generic;

partial class CustomNoise
{
    // Ported from the FastNoiseLite project. https://github.com/Auburn/FastNoiseLite
    // FastNoiseLite license follows. Applies to this class. Ported from C++ to C#.
    
    /*
    MIT License

    Copyright(c) 2020 Jordan Peck (jordan.me2@gmail.com)
    Copyright(c) 2020 Contributors

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
    */
    
    public int mSeed = 0;
    public double mFrequency = 0.01;

    public int mOctaves = 5;
    public double mLacunarity = 2.0;
    public double mGain = 0.5;
    public double mPingPongStrength = 1.5;
    
    public double mFractalBounding = 1.0;

    public void CalculateFractalBounding()
    {
        double gain = FastAbs(mGain);
        double amp = gain;
        double ampFractal = 1.0f;
        for (int i = 1; i < mOctaves; i++)
        {
            ampFractal += amp;
            amp *= gain;
        }
        mFractalBounding = 1 / ampFractal;
    }
    
    static double FastAbs(double f) { return f < 0 ? -f : f; }
    static int FastFloor(double f) { return f >= 0 ? (int)f : (int)f - 1; }

    static float Lerp(float a, float b, float t) { return a + t * (b - a); }

    static float InterpHermite(float t) { return t * t * (3 - 2 * t); }
    static float InterpQuintic(float t) { return t * t * t * (t * (t * 6 - 15) + 10); }

    const int PrimeX = 501125321;
    const int PrimeY = 1136930381;
    const int PrimeZ = 1720413743;
    
    public float GenFractalFBm(double x, double y)
    {
        x *= mFrequency;
        y *= mFrequency;
        
        int seed = mSeed;
        double sum = 0.0;
        double amp = mFractalBounding;

        for (int i = 0; i < mOctaves; i++)
        {
            double noise = SingleValue(seed++, x, y);
            sum += noise * amp;

            x *= mLacunarity;
            y *= mLacunarity;
            amp *= mGain;
        }

        return (float)sum;
    }
    static float PingPong(float t)
    {
        t -= (int)(t * 0.5f) * 2;
        return t < 1 ? t : 2 - t;
    }
    public float GenFractalPingPong(double x, double y, double z)
    {
        x *= mFrequency;
        y *= mFrequency;
        z *= mFrequency;
        
        int seed = mSeed;
        double sum = 0;
        double amp = mFractalBounding;

        for (int i = 0; i < mOctaves; i++)
        {
            float noise = PingPong((float)((SinglePerlin(seed++, x, y, z) + 1) * mPingPongStrength));
            sum += (noise - 0.5f) * 2 * amp;

            x *= mLacunarity;
            y *= mLacunarity;
            z *= mLacunarity;
            amp *= mGain;
        }

        return (float)sum;
    }
    double SingleValue(int seed, double x, double y)
    {
        int x0 = FastFloor(x);
        int y0 = FastFloor(y);

        float xs = InterpHermite((float)(x - x0));
        float ys = InterpHermite((float)(y - y0));

        x0 *= PrimeX;
        y0 *= PrimeY;
        int x1 = x0 + PrimeX;
        int y1 = y0 + PrimeY;

        float xf0 = Lerp(ValCoord(seed, x0, y0), ValCoord(seed, x1, y0), xs);
        float xf1 = Lerp(ValCoord(seed, x0, y1), ValCoord(seed, x1, y1), xs);

        return Lerp(xf0, xf1, ys);
    }
    float SinglePerlin(int seed, double x, double y, double z)
    {
        int x0 = FastFloor(x);
        int y0 = FastFloor(y);
        int z0 = FastFloor(z);

        float xd0 = (float)(x - x0);
        float yd0 = (float)(y - y0);
        float zd0 = (float)(z - z0);
        float xd1 = xd0 - 1;
        float yd1 = yd0 - 1;
        float zd1 = zd0 - 1;

        float xs = InterpQuintic(xd0);
        float ys = InterpQuintic(yd0);
        float zs = InterpQuintic(zd0);

        x0 *= PrimeX;
        y0 *= PrimeY;
        z0 *= PrimeZ;
        int x1 = x0 + PrimeX;
        int y1 = y0 + PrimeY;
        int z1 = z0 + PrimeZ;

        float xf00 = Lerp(GradCoord(seed, x0, y0, z0, xd0, yd0, zd0), GradCoord(seed, x1, y0, z0, xd1, yd0, zd0), xs);
        float xf10 = Lerp(GradCoord(seed, x0, y1, z0, xd0, yd1, zd0), GradCoord(seed, x1, y1, z0, xd1, yd1, zd0), xs);
        float xf01 = Lerp(GradCoord(seed, x0, y0, z1, xd0, yd0, zd1), GradCoord(seed, x1, y0, z1, xd1, yd0, zd1), xs);
        float xf11 = Lerp(GradCoord(seed, x0, y1, z1, xd0, yd1, zd1), GradCoord(seed, x1, y1, z1, xd1, yd1, zd1), xs);

        float yf0 = Lerp(xf00, xf10, ys);
        float yf1 = Lerp(xf01, xf11, ys);

        return Lerp(yf0, yf1, zs) * 0.964921414852142333984375f;
    }
    float GradCoord(int seed, int xPrimed, int yPrimed, int zPrimed, float xd, float yd, float zd)
    {
        int hash = Hash(seed, xPrimed, yPrimed, zPrimed);
        hash ^= hash >> 15;
        hash &= 63 << 2;

        float xg = Gradients3D[hash];
        float yg = Gradients3D[hash | 1];
        float zg = Gradients3D[hash | 2];

        return xd * xg + yd * yg + zd * zg;
    }
    readonly float[] Gradients3D = new float[]
    {
        0, 1, 1, 0,  0,-1, 1, 0,  0, 1,-1, 0,  0,-1,-1, 0,
        1, 0, 1, 0, -1, 0, 1, 0,  1, 0,-1, 0, -1, 0,-1, 0,
        1, 1, 0, 0, -1, 1, 0, 0,  1,-1, 0, 0, -1,-1, 0, 0,
        0, 1, 1, 0,  0,-1, 1, 0,  0, 1,-1, 0,  0,-1,-1, 0,
        1, 0, 1, 0, -1, 0, 1, 0,  1, 0,-1, 0, -1, 0,-1, 0,
        1, 1, 0, 0, -1, 1, 0, 0,  1,-1, 0, 0, -1,-1, 0, 0,
        0, 1, 1, 0,  0,-1, 1, 0,  0, 1,-1, 0,  0,-1,-1, 0,
        1, 0, 1, 0, -1, 0, 1, 0,  1, 0,-1, 0, -1, 0,-1, 0,
        1, 1, 0, 0, -1, 1, 0, 0,  1,-1, 0, 0, -1,-1, 0, 0,
        0, 1, 1, 0,  0,-1, 1, 0,  0, 1,-1, 0,  0,-1,-1, 0,
        1, 0, 1, 0, -1, 0, 1, 0,  1, 0,-1, 0, -1, 0,-1, 0,
        1, 1, 0, 0, -1, 1, 0, 0,  1,-1, 0, 0, -1,-1, 0, 0,
        0, 1, 1, 0,  0,-1, 1, 0,  0, 1,-1, 0,  0,-1,-1, 0,
        1, 0, 1, 0, -1, 0, 1, 0,  1, 0,-1, 0, -1, 0,-1, 0,
        1, 1, 0, 0, -1, 1, 0, 0,  1,-1, 0, 0, -1,-1, 0, 0,
        1, 1, 0, 0,  0,-1, 1, 0, -1, 1, 0, 0,  0,-1,-1, 0
    };


    static float ValCoord(int seed, int xPrimed, int yPrimed)
    {
        int hash = Hash(seed, xPrimed, yPrimed);

        hash *= hash;
        hash ^= hash << 19;
        return hash * (1 / 2147483648.0f);
    }
    static int Hash(int seed, int xPrimed, int yPrimed)
    {
        int hash = seed ^ xPrimed ^ yPrimed;

        hash *= 0x27d4eb2d;
        return hash;
    }
    static int Hash(int seed, int xPrimed, int yPrimed, int zPrimed)
    {
        int hash = seed ^ xPrimed ^ yPrimed ^ zPrimed;

        hash *= 0x27d4eb2d;
        return hash;
    }
}

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
    
    static float noise_blend_wrapper(int x, int z, float freq, int x_offset, int z_offset, Func<double, double, float> f)
    {
        var x_over = x > blend_threshold;
        var z_over = z > blend_threshold;
        var noise_base = f(x*(double)freq + x_offset, z*(double)freq + z_offset);
        if (x_over && !z_over)
        {
            var x_over_amount = x - blend_threshold;
            long x2 = int.MinValue + blend_distance - x_over_amount + 1;
            var t = x_over_amount / (float)blend_distance;
            var noise_x_reflect = f(x2*(double)freq + x_offset, z*(double)freq + z_offset);
            noise_base = Lerp(noise_base, noise_x_reflect, t);
        }
        else if (z_over && !x_over)
        {
            var z_over_amount = z - blend_threshold;
            long z2 = int.MinValue + blend_distance - z_over_amount + 1;
            var t = z_over_amount / (float)blend_distance;
            var noise_z_reflect = f(x*(double)freq + x_offset, z2*(double)freq + z_offset);
            noise_base = Lerp(noise_base, noise_z_reflect, t);
        }
        else
        {
            var x_over_amount = x - blend_threshold;
            long x2 = int.MinValue + blend_distance - x_over_amount + 1;
            var tx = x_over_amount / (float)blend_distance;
            
            var z_over_amount = z - blend_threshold;
            long z2 = int.MinValue + blend_distance - z_over_amount + 1;
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

    const int blend_distance = 32;
    const long blend_max_value = int.MaxValue;
    const long blend_threshold = blend_max_value - blend_distance;
    
    static float Lerp(float a, float b, float t) { return a + t * (b - a); }
    // gets 2d value noise
    public static float get_noise_2d_adjusted(Noise noiser, int x, int z, float freq = 1.0f, int x_offset = 0, int z_offset = 0)
    {
        var x_over = x > blend_threshold;
        var z_over = z > blend_threshold;
        if (x_over || z_over)
            return noise_blend_wrapper(x, z, freq, x_offset, z_offset, custom_noise.GenFractalFBm);
        else
            return custom_noise.GenFractalFBm(x*(double)freq + x_offset, z*(double)freq + z_offset);
    }
    // gets 3d perlin noise
    public static float get_noise_3d_adjusted(Noise noiser, int x, int y, int z, float freq = 1.0f)
    {
        var x_over = x > blend_threshold;
        var z_over = z > blend_threshold;
        if (x_over || z_over)
            return noise_blend_wrapper(x, z, freq, 0, 0, (x, z) => {return erosion_noise.GenFractalPingPong(x, y, z);});
        else
            return erosion_noise.GenFractalPingPong(x*(double)freq, y*(double)freq, z*(double)freq);
    }
    public static (int, int) height_at_global(Noise noiser, int x, int z)
    {
        float height = get_noise_2d_adjusted(noiser, x, z);
        
        float steepness_preoffset_freq = 0.5f;
        
        float steepness_preoffset = get_noise_2d_adjusted(noiser, x, -1-z, steepness_preoffset_freq, 0, -1130) * 0.75f;
        
        float steepness_freq = 0.5f;
        float steepness_min = 0.2f;
        float steepness_max = 64.0f;
        float steepness_exp = 1.0f;
        
        float steepness = get_noise_2d_adjusted(noiser, x, -1-z, steepness_freq, 100)*0.5f + 0.5f;
        steepness = Mathf.Lerp(steepness_min, steepness_max, Mathf.Pow(steepness, steepness_exp));
        
        height = _adjust_val(height + steepness_preoffset, steepness) - steepness_preoffset;
        
        // extra grit
        float grit_freq = 0.4f;
        float grit_scale = 1.0f;
        
        height += get_noise_2d_adjusted(noiser, x, z, grit_freq, 512, 11) * grit_scale;
        
        float height_scale_freq = 0.5f;
        float height_scale_min = 3.0f;
        float height_scale_max = 64.0f;
        float height_scale_exp = 5.0f;
        
        float height_scale = get_noise_2d_adjusted(noiser, x, z, height_scale_freq, 0, 154)*0.5f + 0.5f;
        height = height * Mathf.Lerp(height_scale_min, height_scale_max, Mathf.Pow(height_scale, height_scale_exp));
        
        float height_noise_freq = 2.4f;
        float height_noise_scale = 5.0f;
        height += get_noise_2d_adjusted(noiser, x, z, height_noise_freq, 51, 1301) * height_noise_scale;
        
        float rock_freq = 2.6f;
        float rock_scale = 5.0f;
        
        // x/z inversion is deliberate
        float rock_offset = get_noise_2d_adjusted(noiser, z, x, rock_freq, 151, 11)*rock_scale - 2.0f;
        
        height = Mathf.Lerp(height, Mathf.Clamp(height, -32.0f, 32.0f), 0.5f);
        height = Mathf.Clamp(height, -63.0f, 63.0f);
        
        height = Mathf.Round(height);
        rock_offset = Mathf.Round(rock_offset);
        
        return ((int)height, (int)rock_offset);
    }
    public int pub_height_at_global(Noise noiser, Vector3I global_coord)
    {
        return height_at_global(noiser, global_coord.X, global_coord.Z).Item1;
    }
    static float erosion_strength_at_global(Noise noiser, Vector3I global_coord)
    {
        var erosion_info_freq = 0.1f;
        var min_strength = 0.0f;
        var max_strength = 96.0f;
        
        float f = get_noise_2d_adjusted(noiser, global_coord.X, -global_coord.Z, erosion_info_freq, 0, -1100)*0.5f + 0.5f;
        f *= f;
        return Mathf.Lerp(min_strength, max_strength, f);
    }
    //static FastNoiseLite buh()
    static CustomNoise buh()
    {
        /*
        var r = new FastNoiseLite();
        r.NoiseType = FastNoiseLite.NoiseTypeEnum.Perlin; // or: value
        r.FractalType = FastNoiseLite.FractalTypeEnum.PingPong;
        r.FractalOctaves = 2;
        r.FractalPingPongStrength = 1.5f;
        r.Frequency = 0.02f; // or: 0.02f
        */
        var r = new CustomNoise();
        r.mOctaves = 2;
        r.mFrequency = 0.02f;
        r.CalculateFractalBounding();
        return r;
    }
    static CustomNoise custom_noise = new CustomNoise();
    //static FastNoiseLite erosion_noise = buh();
    static CustomNoise erosion_noise = buh();
    static bool erosion_seed_set = false;
    static float get_erosion(Vector3I global_coord, float strength)
    {
        var out_scale = Mathf.Clamp(1.0f + global_coord.Y/16.0f, 0.0f, 1.0f);
        //var ret = Mathf.Min(0.0f, get_noise_3d_adjusted(erosion_noise, global_coord.X, global_coord.Y, global_coord.Z));
        var ret = Mathf.Min(0.0f, get_noise_3d_adjusted(null, global_coord.X, global_coord.Y, global_coord.Z));
        return Mathf.Round(ret*Mathf.Abs(ret)*strength*out_scale);
    }
    // WARNING: for performance reasons, this does a coarse search.
    // its purpose is to find a y value that's solid but has air above it, and is close to the surface.
    // it is not 100% guaranteed to be exposed to the sky.
    public static (int, int) true_height_at_global(Noise noiser, Vector3I global_coord)
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
            var n = ((FastNoiseLite)noiser);
            custom_noise.mSeed = n.Seed;
            custom_noise.mFrequency = n.Frequency;

            custom_noise.mOctaves = n.FractalOctaves;
            custom_noise.mLacunarity = n.FractalLacunarity;
            custom_noise.mGain = n.FractalGain;
            
            custom_noise.CalculateFractalBounding();
            
            erosion_noise.mSeed = n.Seed+2;
            erosion_seed_set = true;
        }
        
        var voxels = new byte[chunk_size*chunk_size*chunk_size];
        foreach (var z in Enumerable.Range(0, chunk_size))
        {
            foreach (var x in Enumerable.Range(0, chunk_size))
            {
                var c_2d = new Vector2I(x, z) + offset_2d;
                var (height, rock_offset) = height_at_global(noiser, c_2d.X, c_2d.Y);
                
                var h_i = coord_to_index(new Vector3I(x, 0, z));
                
                var erosion_strength = erosion_strength_at_global(noiser, new Vector3I(x+offset.X, 0, z+offset.Z));
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

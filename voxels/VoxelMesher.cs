using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using System.Runtime.CompilerServices;

public partial class VoxelMesher : Node
{
    static Vector3I posmodvi(Vector3I a, Vector3I b)
    {
        a.X = a.X%b.X;
        if (a.X < 0) a.X += b.X;
        a.Y = a.Y%b.Y;
        if (a.Y < 0) a.Y += b.Y;
        a.Z = a.Z%b.Z;
        if (a.Z < 0) a.Z += b.Z;
        return a;
    }
    public static Vector3I get_chunk_coord(Vector3I coord)
    {
        var leftover = posmodvi(coord + VoxelGenerator.chunk_vec3i/2, VoxelGenerator.chunk_vec3i);
        var chunk_coord = coord - leftover + VoxelGenerator.chunk_vec3i/2;
        return chunk_coord;
    }
    
    static Vector3I[] dirs = new Vector3I[6]{Vector3I.Up, Vector3I.Down, Vector3I.Forward, Vector3I.Back, Vector3I.Left, Vector3I.Right};
    static Vector3I[] right_dirs = new Vector3I[6]{Vector3I.Right, Vector3I.Left, Vector3I.Left, Vector3I.Right, Vector3I.Back, Vector3I.Forward};
    static Vector3I[] up_dirs  = new Vector3I[6]{Vector3I.Forward, Vector3I.Back, Vector3I.Up, Vector3I.Up, Vector3I.Up, Vector3I.Up};
    static Vector3[] face_verts = new Vector3[4]
    {
        new Vector3(0.5f, 0.5f, -0.5f),
        new Vector3(-0.5f, 0.5f, -0.5f),
        new Vector3(0.5f, -0.5f, -0.5f),
        new Vector3(-0.5f, -0.5f, -0.5f),
    };
    static Vector3[] generate_verts()
    {
        var verts = new Vector3[6*4];
        var j = 0;
        foreach (var dir in dirs)
        {
            var ref_dir = dir.Abs() == Vector3.Up ? Vector3.Left : Vector3.Up;
            var xform = Transform3D.Identity.LookingAt(dir, ref_dir);
            for (var i = 0; i < 4; i++)
            {
                var v = face_verts[i];
                v = xform * v;
                verts[j] = v;
                j += 1;
            }
        }
        return verts;
    }

    static Vector3[] vert_table = generate_verts();
    
    static (Vector3[], Vector3[]) generate_mesh_verts()
    {
        Vector3[] temp_verts = new Vector3[4]
        {
            new Vector3(0.5f, 0.5f, 0.5f),
            new Vector3(-0.5f, 0.5f, -0.5f),
            new Vector3(0.5f, -0.5f, 0.5f),
            new Vector3(-0.5f, -0.5f, -0.5f),
        };
        var verts = new Vector3[4*4];
        var normals = new Vector3[4*4];
        var j = 0;
        foreach (var step in Enumerable.Range(0, 4))
        {
            var angle = (float)step * Mathf.Pi * 0.5f;
            var xform = Transform3D.Identity.Rotated(Vector3.Up, angle);
            var n = xform * (new Vector3(-1.0f, 0.0f, 1.0f)).Normalized();
            for (var i = 0; i < 4; i++)
            {
                var v = temp_verts[i] * new Vector3(0.9f, 1.0f, 0.9f);
                v = xform * v;
                verts[j] = v;
                normals[j] = n;
                j += 1;
            }
        }
        return (verts, normals);
    }
    
    static (Vector3[], Vector3[]) mesh_vert_table = generate_mesh_verts();
    
    // top, bottom, side
    static int[][] voxel_info = new int[][]{
        new int[]{0, 0, 0}, // air
        new int[]{0, 10, 20}, // grass
        new int[]{10, 10, 10}, // dirt
        new int[]{30, 30, 30}, // rock
        new int[]{50, 50, 40}, // log
        // 5
        new int[]{60, 60, 60}, // leaf
        new int[]{70, 70, 70}, // water
        new int[]{110, 110, 110}, // grass a
        new int[]{111, 111, 111}, // grass b
        new int[]{112, 112, 112}, // grass c
        // 10
        new int[]{80, 80, 80}, // flower a
        new int[]{81, 81, 81}, // flower b
        new int[]{82, 82, 82}, // flower c
        new int[]{83, 83, 83}, // flower d
        new int[]{5, 5, 5}, // sand
    };
    int[] get_voxel_info(int myint)
    {
        return voxel_info[myint];
    }
    static HashSet<int> vox_alphatest = new HashSet<int>{
        5,
    };
    static HashSet<int> vox_transparent = new HashSet<int> {
        6,
    };
    static HashSet<int> vox_mesh = new HashSet<int> {
        7,
        8,
        9,
        10,
        11,
        12,
        13,
    };
    static HashSet<int> vox_bitmaskless = new HashSet<int> {
        5,
        6,
        7,
        8,
        9,
        10,
        11,
        12,
        13,
    };
    
    static int vox_get_type(int vox)
    {
        if (vox_alphatest.Contains(vox))
            return 1;
        else if(vox_transparent.Contains(vox))
            return 2;
        else if(vox_mesh.Contains(vox))
            return 3;
        return 0;
    }
    static bool type_is_solid(int type)
    {
        return type == 0 || type == 1;
    }
    public int vox_get_type_pub(int vox)
    {
        return vox_get_type(vox);
    }
    
    static bool vox_get_bitmaskless(int vox)
    {
        return vox_bitmaskless.Contains(vox);
    }
    bool pub_vox_get_bitmaskless(int vox)
    {
        return vox_get_bitmaskless(vox);
    }
    
    static bool vox_get_mesh(int vox)
    {
        return vox_mesh.Contains(vox);
    }
    
    byte[] bitmask_cache = new byte[VoxelGenerator.chunk_size_h*VoxelGenerator.chunk_size_h*VoxelGenerator.chunk_size_v*6];
    
    public byte[] side_cache;
    
    static int calc_index(Vector3I coord)
    {
        return (
            coord.Y*VoxelGenerator.chunk_size_h*VoxelGenerator.chunk_size_h +
            coord.Z*VoxelGenerator.chunk_size_h +
            coord.X );
    }
    
    class Arrays {
        public List<Vector3> ColVerts = new();
        public List<Vector3> Verts = new();
        public List<byte> FaceInfo = new();
        public List<int> Indexes = new();
    };
    
    static float meshing_time = 0.0f;
    float pub_get_meshing_time()
    {
        return meshing_time;
    }
    
    Godot.Collections.Array remesh_get_arrays(Vector3I chunk_position, Godot.Collections.Dictionary neighbor_chunks, int stride)
    {
        var start = Godot.Time.GetTicksUsec()/1000000.0f;
        
        var bounds = VoxelGenerator.bounds;
        
        var voxel_same_type = bool (int vox, int target_type) =>
        {
            if (vox == 0)
                return false;
            var type = vox_get_type(vox);
            return type == target_type;
        };
        
        Dictionary<Vector3I, byte[]> neighbors = new();
        foreach (var k in neighbor_chunks.Keys)
            neighbors[(Vector3I)k] = ((VoxelGenerator)neighbor_chunks[k])._voxels;
        
        byte[] voxels = neighbors[chunk_position];
        
        var get_voxel = int (Vector3I global_coord) =>
        {
            var local_coord = global_coord - chunk_position;
            if (local_coord.X >= 0 && local_coord.X < VoxelGenerator.chunk_size_h &&
                local_coord.Z >= 0 && local_coord.Z < VoxelGenerator.chunk_size_h &&
                local_coord.Y >= 0 && local_coord.Y < VoxelGenerator.chunk_size_v)
            {
                return voxels[calc_index(local_coord)];
            }
            var chunk_coord = get_chunk_coord(global_coord - VoxelGenerator.chunk_vec3i/2);
            if (neighbors.ContainsKey(chunk_coord))
            {
                var neighbor_voxels = neighbors[chunk_coord];
                var neighbor_coord = global_coord - chunk_coord;
                var index = calc_index(neighbor_coord);
                return neighbor_voxels[index];
            }
            return 0;
        };
        
        var info_max = 16;
        var static_water_height = 14;
        
        var calc_water_info = (byte, (int, int)[]) (Vector3I coord) =>
        {
            var vox = get_voxel(coord);
            var vox_type = vox_get_type(vox);
            
            var ret = ((byte) info_max, new (int, int)[]{(info_max, 0), (info_max, 0), (info_max, 0), (info_max, 0)});
            
            if (vox_type != 2)
                return ret;
            
            var vox2 = get_voxel(coord + Vector3I.Up);
            var vox2_type = vox_get_type(vox2);
            
            var vox_down = get_voxel(coord + Vector3I.Down);
            var vox_down_type = vox_get_type(vox_down);
            
            var core_height = info_max;
            if (vox2_type != 2)
                core_height = static_water_height;
            
            ret.Item1 = (byte)core_height;
            
            foreach (var d in Enumerable.Range(2, 4))
            {
                var dir = dirs[d];
                var beside_coord = coord + dir;
                var vox_side = get_voxel(beside_coord);
                var vox_side_type = vox_get_type(vox_side);
                
                var vox_side_down = get_voxel(beside_coord + Vector3I.Down);
                var vox_side_down_type = vox_get_type(vox_side_down);
                
                var vox_side_up = get_voxel(beside_coord + Vector3I.Up);
                var vox_side_up_type = vox_get_type(vox_side_up);
                
                int bottom = 0;
                int top = core_height;
                
                if (vox_side_type == 2)
                    bottom = static_water_height;
                else if (vox_down_type == 2 && vox_side_down_type == 2)
                {
                    if (vox_side_type == 0 && vox_side != 0)
                        top = 0;
                    bottom = static_water_height-info_max;
                }
                
                ret.Item2[d-2] = (top, bottom);
            }
            
            return ret;
        };
        
        var arrays = new Arrays[4]{new Arrays(), new Arrays(), new Arrays(), new Arrays()};
        
        var offs = (Vector3)VoxelGenerator.chunk_vec3i/2.0f;
        
        int chunk_size_h = VoxelGenerator.chunk_size_h;
        int chunk_size_v = VoxelGenerator.chunk_size_v;
        
        for (var y = 0; y < chunk_size_v; y += stride)
        {
            var prev_x = new (int, byte, int[], byte[], (int, int)[], bool, int[])[chunk_size_h];
            var prev_x_need_clear = new bool[chunk_size_h];
            foreach (var i in Enumerable.Range(0, chunk_size_h))
            {
                prev_x[i] = (-1, 0x00, new int[]{0, 0}, new byte[]{0, 0, 0, 0, 0, 0}, new (int, int)[]{(0,0), (0,0), (0,0), (0,0)}, false, new int[]{0, 0});
                prev_x_need_clear[i] = false;
            }
            
            var prev_i = new int[]{0, 0, 0, 0};
            var prev_col_i = new int[]{0, 0, 0, 0};
            
            for (var z = 0; z < chunk_size_h; z += stride)
            {
                var prev_solid = false;
                var prev_type = -1;
                var prev_cached = 0;
                var prev_bitmasks = new byte[]{0, 0, 0, 0, 0, 0};
                
                prev_i[0] = 0;
                prev_i[1] = 0;
                prev_i[2] = 0;
                prev_i[3] = 0;
                
                prev_col_i[0] = 0;
                prev_col_i[1] = 0;
                prev_col_i[2] = 0;
                prev_col_i[3] = 0;
                
                var prev_side_val = new (int, int)[]{(0,0), (0,0), (0,0), (0,0)};
                
                for (var x = 0; x < chunk_size_h; x += stride)
                {
                    var local_coord = new Vector3I(x, y, z);
                    var vox_index = calc_index(local_coord);
                    byte cached = side_cache[vox_index];
                    
                    var vox = voxels[vox_index];
                    var vox_type = vox_get_type(vox);
                    if (vox_type == 3 && stride > 1)
                    {
                        vox = 0;
                        vox_type = 0;
                    }
                    
                    var vox_atest = vox_type == 1;
                    var vox_xparent = vox_type != 0;
                    
                    var side_val = new (int, int)[]{(0,0), (0,0), (0,0), (0,0)};
                    
                    var top_val = 16;
                    if (vox_type == 2 && stride == 1)
                        (top_val, side_val) = calc_water_info(local_coord + chunk_position);
                    
                    // 0xFF = not calculated yet
                    if (cached == 0xFF)
                    {
                        cached = 0;
                        if (vox != 0)
                        {
                            foreach (var d in Enumerable.Range(0, 6))
                            {
                                var dir = dirs[d];
                                if (!vox_atest)
                                {
                                    var neighbor_coord = new Vector3I(x, y, z) + dir*stride;
                                    var neighbor = get_voxel(neighbor_coord + chunk_position);
                                    var neighbor_type = vox_get_type(neighbor);
                                    var neighbor_allows_xparent = neighbor == 0 || neighbor_type != 0;
                                    var xparent_condition = vox_xparent && !neighbor_allows_xparent && d != 0 && (d == 1 || (side_val[d-2].Item2 >= 0));
                                    if (voxel_same_type(neighbor, vox_type) || xparent_condition)
                                        continue;
                                }
                                
                                byte bitmask = 0;
                                byte bit = 0;
                                var right_dir = right_dirs[d];
                                var up_dir = up_dirs[d];
                                if (!vox_get_bitmaskless(vox))
                                {
                                    for (int _y = -1; _y <= 1; _y++)
                                    {
                                        for (int _x = -1; _x <= 1; _x++)
                                        {
                                            if (_y == 0 && _x == 0)
                                                continue;
                                            var next_coord = new Vector3I(x, y, z) + _y*up_dir*stride + _x*right_dir*stride;
                                            var occlude_coord = next_coord + dir*stride;
                                            var bit_is_same = 0;
                                            
                                            var next = get_voxel(next_coord + chunk_position);
                                            if (next == vox)
                                                bit_is_same = 1;
                                            
                                            if (bit_is_same == 1)
                                            {
                                                var occlude = get_voxel(occlude_coord + chunk_position);
                                                if (voxel_same_type(occlude, vox_type))
                                                    bit_is_same = 0;
                                            }
                                            bitmask |= (byte)(bit_is_same<<bit);
                                            bit += 1;
                                        }
                                    }
                                }
                                
                                bitmask_cache[vox_index*6 + d] = bitmask;
                                cached |= (byte)(1<<d);
                            }
                            side_cache[vox_index] = cached;
                        }
                    }
                    
                    if (cached == 0x00)
                    {
                        prev_solid = false;
                        prev_type = -1;
                        prev_cached = cached;
                        if (prev_x_need_clear[x])
                        {
                            prev_x[x].Item1 = -1;
                            prev_x[x].Item6 = false;
                            prev_x_need_clear[x] = false;
                        }
                    }
                    else
                    {
                        var coord = new Vector3(x, y, z) - offs;
                        var prev_x_i = prev_x[x].Item3;
                        
                        var prev_col_x_i = prev_x[x].Item7;
                        
                        if (vox_get_mesh(vox))
                        {
                            var array_index = voxel_info[vox][0];
                            var index_a = (byte)(array_index >> 8);
                            var index_b = (byte)(array_index & 0xFF);
                            
                            for (int j = 0; j < 4; j++)
                            {
                                var i_start = arrays[vox_type].Verts.Count;
                                
                                for (int i = 0; i < 4; i++)
                                {
                                    var v = mesh_vert_table.Item1[j*4 + i];
                                    
                                    arrays[vox_type].Verts.Add(coord + v);
                                    arrays[vox_type].FaceInfo.Add((byte)(6+j));
                                    arrays[vox_type].FaceInfo.Add(index_a);
                                    arrays[vox_type].FaceInfo.Add(index_b);
                                    arrays[vox_type].FaceInfo.Add(0xFF);
                                }
                                arrays[vox_type].Indexes.AddRange(new int[]{i_start+0, i_start+1, i_start+2, i_start+2, i_start+1, i_start+3});
                            }
                            
                            prev_solid = false;
                            prev_side_val = side_val;
                            prev_type = -1;
                            prev_cached = cached;
                            prev_x[x] = (-1, cached, prev_x_i, (byte[])prev_bitmasks.Clone(), side_val, false, prev_col_x_i);
                            prev_x_need_clear[x] = true;
                        }
                        else
                        {
                            var is_solid = type_is_solid(vox_type);
                            
                            foreach (var d in Enumerable.Range(0, 6))
                            {
                                var prev_bitmask = prev_bitmasks[d];
                                var prev_x_bitmask = prev_x[x].Item4[d];
                                var bitmask = bitmask_cache[vox_index*6 + d];
                                prev_bitmasks[d] = bitmask;
                                var dir = dirs[d];
                                if ((cached & (1<<d)) != 0)
                                {
                                    var extend_vert = (List<Vector3> slice, int d, int base_index, bool is_collision) =>
                                    {
                                        int[] f;
                                        if (!is_collision)
                                        {
                                            if (d == 0 || d == 1)
                                                f = new int[]{2, 3};
                                            else if (d == 3 || d == 4)
                                                f = new int[]{1, 3};
                                            else
                                                f = new int[]{0, 2};
                                        }
                                        // 0 1 2 2 1 3
                                        // 0 1 2 3 4 5
                                        // 0 -> 0
                                        // 1 -> 1, 4
                                        // 2 -> 2, 3
                                        // 3 -> 5
                                        else
                                        {
                                            if (d == 0 || d == 1)
                                                f = new int[]{2, 3, 5};
                                            else if (d == 3 || d == 4)
                                                f = new int[]{1, 4, 5};
                                            else
                                                f = new int[]{0, 2, 3};
                                        }
                                        
                                        var adder = d < 4 ? new Vector3(1.0f, 0.0f, 0.0f) : new Vector3(0.0f, 0.0f, 1.0f);
                                        
                                        foreach (var i in f)
                                            slice[base_index+i] += adder*stride;
                                    };
                                    
                                    var solid_extended = false;
                                    if (d < 4 && is_solid && prev_solid && (prev_cached & (1<<d)) != 0)
                                    {
                                        solid_extended = true;
                                        extend_vert(arrays[0].ColVerts, d, prev_col_i[d], true);
                                    }
                                    else if(d >= 4 && is_solid && prev_x[x].Item6 && (prev_x[x].Item2 & (1<<d)) != 0)
                                    {
                                        solid_extended = true;
                                        extend_vert(arrays[0].ColVerts, d, prev_col_x_i[d-4], true);
                                    }
                                    if (is_solid && !solid_extended)
                                    {
                                        var i_col_start = arrays[0].ColVerts.Count;
                                        if (d < 4)
                                            prev_col_i[d] = i_col_start;
                                        else
                                            prev_col_x_i[d-4] = i_col_start;
                                            
                                        foreach (var i in new int[]{0, 1, 2, 2, 1, 3})
                                        {
                                            var v = vert_table[d*4 + i];
                                            arrays[0].ColVerts.Add(coord + v);
                                        }
                                    }
                                    
                                    if (d < 4 &&
                                        (prev_cached & (1<<d)) != 0 &&
                                        prev_bitmask == bitmask &&
                                        prev_type == vox &&
                                        (d < 2 || (prev_side_val[d-2] == side_val[d-2])))
                                    {
                                        extend_vert(arrays[vox_type].Verts, d, prev_i[d], false);
                                    }
                                    else if(d >= 4 &&
                                        (prev_x[x].Item2 & (1<<d)) != 0 &&
                                        prev_x_bitmask == bitmask &&
                                        prev_x[x].Item1 == vox &&
                                        prev_x[x].Item5[d-2] == side_val[d-2])
                                    {
                                        extend_vert(arrays[vox_type].Verts, d, prev_x_i[d-4], false);
                                    }
                                    else
                                    {
                                        var dir_mat_index = Math.Min(d, 2);
                                        var array_index = voxel_info[vox][dir_mat_index];
                                        var index_a = (byte)(array_index >> 8);
                                        var index_b = (byte)(array_index & 0xFF);
                                        
                                        var side_top = (vox_type == 2 && d >= 2) ? side_val[d-2].Item1 : info_max;
                                        var side_bottom = (vox_type == 2 && d >= 2) ? side_val[d-2].Item2 : 0;
                                        
                                        prev_bitmasks[d] = bitmask;
                                        
                                        var i_start = arrays[vox_type].Verts.Count;
                                        if (d < 4)
                                            prev_i[d] = i_start;
                                        else
                                            prev_x_i[d-4] = i_start;
                                        
                                        for (int i = 0; i < 4; i++)
                                        {
                                            var v = vert_table[d*4 + i] * stride - new Vector3(stride-1,stride-1,stride-1)/2.0f;
                                            if (vox_xparent)
                                            {
                                                if (d == 0 && top_val != info_max)
                                                    v.Y -= 1.0f-((float)top_val)/(float)info_max;
                                                if (d >= 2 && i < 2 && side_top != info_max)
                                                    v.Y -= 1.0f-((float)side_top)/(float)info_max;
                                                if (d >= 2 && i >= 2 && side_bottom != 0)
                                                    v.Y += ((float)side_bottom)/(float)info_max;
                                            }
                                            
                                            arrays[vox_type].Verts.Add(coord + v);
                                            arrays[vox_type].FaceInfo.Add((byte)d);
                                            arrays[vox_type].FaceInfo.Add(index_a);
                                            arrays[vox_type].FaceInfo.Add(index_b);
                                            arrays[vox_type].FaceInfo.Add(bitmask);
                                        }
                                        arrays[vox_type].Indexes.AddRange(new int[]{i_start+0, i_start+1, i_start+2, i_start+2, i_start+1, i_start+3});
                                    }
                                }
                            }
                            
                            prev_solid = is_solid;
                            prev_side_val = side_val;
                            prev_type = vox;
                            prev_cached = cached;
                            prev_x[x] = (vox, cached, prev_x_i, (byte[])prev_bitmasks.Clone(), side_val, is_solid, prev_col_x_i);
                            prev_x_need_clear[x] = true;
                        }
                    }
                }
            }
        }
        
        var end = Godot.Time.GetTicksUsec()/1000000.0f;
        meshing_time += end-start;
        
        var arraysets = new Godot.Collections.Array();
        
        foreach (var array in arrays)
        {
            var mesharrays = new Godot.Collections.Array();
            mesharrays.Resize((int)Mesh.ArrayType.Max);
            mesharrays[(int)Mesh.ArrayType.Vertex] = array.Verts.ToArray();
            mesharrays[(int)Mesh.ArrayType.Custom0] = array.FaceInfo.ToArray();
            mesharrays[(int)Mesh.ArrayType.Index] = array.Indexes.ToArray();
            arraysets.Add(mesharrays);
        }
        arraysets.Add(arrays[0].ColVerts.ToArray());
        
        return arraysets;
    }
    ~VoxelMesher()
    {
        bitmask_cache = null;
        side_cache = null;
    }
}


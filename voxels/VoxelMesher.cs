using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using System.Runtime.CompilerServices;

public partial class VoxelMesher : RefCounted
{
    static HashSet<int> vox_alphatest = new HashSet<int>{
        5,
    };
    static HashSet<int> vox_transparent = new HashSet<int> {
        6,
    };

    static int vox_get_type(int vox)
    {
        if (vox_alphatest.Contains(vox))
            return 1;
        else if(vox_transparent.Contains(vox))
            return 2;
        return 0;
    }
    static Vector3 get_chunk_coord(Vector3 coord)
    {
        var chunk_coord = ((coord + Vector3.One*0.5f) / VoxelGenerator.chunk_size).Round() * VoxelGenerator.chunk_size;
        return chunk_coord;
    }
    
    static Vector3[] dirs = new Vector3[6]{Vector3.Up, Vector3.Down, Vector3.Forward, Vector3.Back, Vector3.Left, Vector3.Right};
    static Vector3[] right_dirs = new Vector3[6]{Vector3.Right, Vector3.Left, Vector3.Left, Vector3.Right, Vector3.Back, Vector3.Forward};
    static Vector3[] up_dirs  = new Vector3[6]{Vector3.Forward, Vector3.Back, Vector3.Up, Vector3.Up, Vector3.Up, Vector3.Up};
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
    };
    
    byte[] bitmask_cache = new byte[VoxelGenerator.chunk_size*VoxelGenerator.chunk_size*VoxelGenerator.chunk_size*6];
    
    public byte[] side_cache;
    
    static int calc_index(Vector3 coord)
    {
        return (int)(
            coord.Y*VoxelGenerator.chunk_size*VoxelGenerator.chunk_size +
            coord.Z*VoxelGenerator.chunk_size +
            coord.X );
    }
    
    Godot.Collections.Array remesh_get_arrays(int target_type, Vector3 chunk_position, Godot.Collections.Dictionary neighbor_chunks)
    {
        int chunk_size = VoxelGenerator.chunk_size;
        var bounds = VoxelGenerator.bounds;
        
        var voxel_is_target = bool (int vox, int target_type) =>
        {
            if (vox == 0)
                return false;
            var type = vox_get_type(vox);
            return type == target_type;
        };
        
        Dictionary<Vector3, byte[]> neighbors = new Dictionary<Vector3, byte[]>();
        foreach (var k in neighbor_chunks.Keys)
            neighbors[(Vector3)k] = (byte[])neighbor_chunks[k];
        
        byte[] voxels = neighbors[chunk_position];
        
        var get_voxel = int (Vector3 global_coord) =>
        {
            var local_coord = global_coord - chunk_position;
            if (bounds.HasPoint(local_coord))
            {
                var neighbor_index = calc_index(local_coord);
                return voxels[neighbor_index];
            }
            var chunk_coord = get_chunk_coord(global_coord - Vector3.One*chunk_size/2);
            if (neighbors.ContainsKey(chunk_coord))
            {
                var neighbor_voxels = neighbors[chunk_coord];
                var neighbor_coord = global_coord - chunk_coord;
                var index = calc_index(neighbor_coord);
                return neighbor_voxels[index];
            }
            return 0;
        };
        
        var water_info_max = new List<byte>();
        var water_info_min = new List<(int, int)>();
        
        var info_max = 16;
        var static_water_height = 14;
        
        if (target_type == 2)
        {
            foreach (var y in Enumerable.Range(0, chunk_size))
            {
                foreach (var z in Enumerable.Range(0, chunk_size))
                {
                    foreach (var x in Enumerable.Range(0, chunk_size))
                    {
                        var coord = new Vector3(x, y, z) + chunk_position;
                        var vox = get_voxel(coord);
                        var vox_type = vox_get_type(vox);
                        
                        if (vox_type != 2)
                        {
                            water_info_max.Add((byte)info_max);
                            foreach (var d in Enumerable.Range(0, 4))
                                water_info_min.Add((info_max, 0));
                            continue;
                        }
                        
                        var vox2 = get_voxel(coord + Vector3.Up);
                        var vox2_type = vox_get_type(vox2);
                        
                        var vox_down = get_voxel(coord + Vector3.Down);
                        var vox_down_type = vox_get_type(vox_down);
                        
                        var core_height = info_max;
                        if (vox2_type != 2)
                            core_height = static_water_height;
                        
                        water_info_max.Add((byte)core_height);
                        
                        foreach (var d in Enumerable.Range(2, 4))
                        {
                            var dir = dirs[d];
                            var beside_coord = coord + dir;
                            var vox_side = get_voxel(beside_coord);
                            var vox_side_type = vox_get_type(vox_side);
                            
                            var vox_side_down = get_voxel(beside_coord + Vector3.Down);
                            var vox_side_down_type = vox_get_type(vox_side_down);
                            
                            var vox_side_up = get_voxel(beside_coord + Vector3.Up);
                            var vox_side_up_type = vox_get_type(vox_side_up);
                            
                            int bottom = 0;
                            int top = core_height;
                            
                            //if (vox_side_up_type == 2)
                            //    top = info_max;
                            
                            if (vox_side_type == 2)
                                bottom = static_water_height;
                            else if (vox_down_type == 2 && vox_side_down_type == 2)
                            {
                                if (vox_side_type == 0 && vox_side != 0)
                                    top = 0;
                                bottom = static_water_height-info_max;
                            }
                            
                            //if (vox_side_down_type == 2)
                            
                            water_info_min.Add((top, bottom));
                        }
                    }
                }
            }
        }
        
        var verts = new List<Vector3>();
        var face_info = new List<byte>();
        var indexes = new List<int>();
        
        var start = Time.GetTicksUsec();
        
        var offs = Vector3.One*chunk_size/2.0f;
        
        foreach (var y in Enumerable.Range(0, chunk_size))
        {
            var prev_x = new (int, byte, int, int, byte[], (int, int)[])[chunk_size];
            var prev_x_need_clear = new bool[chunk_size];
            foreach (var i in Enumerable.Range(0, chunk_size))
            {
                prev_x[i] = ((-1, 0x00, 0, 0, new byte[]{0, 0, 0, 0, 0, 0}, new (int, int)[]{(0,0), (0,0), (0,0), (0,0)}));
                prev_x_need_clear[i] = false;
            }
            
            foreach (var z in Enumerable.Range(0, chunk_size))
            {
                var prev_type = -1;
                var prev_cached = 0;
                var prev_bitmasks = new byte[]{0, 0, 0, 0, 0, 0};
                var prev_i_0 = 0;
                var prev_i_1 = 0;
                var prev_i_2 = 0;
                var prev_i_3 = 0;
                
                var prev_side_val = new (int, int)[]{(0,0), (0,0), (0,0), (0,0)};
                
                foreach (var x in Enumerable.Range(0, chunk_size))
                {
                    var vox_index = calc_index(new Vector3(x, y, z));
                    byte cached = 0xFF;//side_cache[vox_index];
                    
                    var vox = voxels[vox_index];
                    var vox_type = vox_get_type(vox);
                    var vox_atest = vox_type == 1;
                    var vox_xparent = vox_type != 0;
                    
                    var side_val = new (int, int)[]{(0,0), (0,0), (0,0), (0,0)};
                    
                    var top_val = 16;
                    if (target_type == 2 && vox_type == 2)
                        top_val = water_info_max[vox_index];
                    
                    // 0x7F == special (always recalculate)
                    if (cached == 0xFF || cached == 0x7F)
                    {
                        var force_recalculate = false;
                        cached = 0;
                        if (voxel_is_target(vox, vox_type))
                        {
                            foreach (var d in Enumerable.Range(0, 6))
                            {
                                var current_side_val = (0,0);
                                if (target_type == 2 && vox_type == 2 && d >= 2)
                                {
                                    current_side_val = water_info_min[vox_index*4 + (d-2)];
                                    side_val[d-2] = current_side_val;
                                    //if (side_val[d-2] != 16)
                                    {
                                        //force_recalculate = true;
                                        //if (side_val[d-2] != top_val)
                                        //    cached |= (byte)(1<<d);
                                        //continue;
                                    }
                                }
                                var dir = dirs[d];
                                if (!vox_atest)
                                {
                                    var neighbor_coord = new Vector3(x, y, z) + dir;
                                    var neighbor = get_voxel(neighbor_coord + chunk_position);
                                    var xparent_condition = vox_xparent && neighbor != 0 && d != 0 && current_side_val.Item2 >= 0;
                                    if (voxel_is_target(neighbor, vox_type) || xparent_condition)
                                        continue;
                                }
                                
                                byte bitmask = 0;
                                byte bit = 0;
                                var right_dir = right_dirs[d];
                                var up_dir = up_dirs[d];
                                for (int _y = -1; _y <= 1; _y++)
                                {
                                    for (int _x = -1; _x <= 1; _x++)
                                    {
                                        if (_y == 0 && _x == 0)
                                            continue;
                                        var next_coord = new Vector3(x, y, z) + _y*up_dir + _x*right_dir;
                                        var occlude_coord = next_coord + dir;
                                        var bit_is_same = 0;
                                        
                                        var next = get_voxel(next_coord + chunk_position);
                                        if (next == vox)
                                            bit_is_same = 1;
                                        
                                        if (bit_is_same == 1)
                                        {
                                            var occlude = get_voxel(occlude_coord + chunk_position);
                                            if (voxel_is_target(occlude, vox_type))
                                                bit_is_same = 0;
                                        }
                                        bitmask |= (byte)(bit_is_same<<bit);
                                        bit += 1;
                                    }
                                }
                                
                                bitmask_cache[vox_index*6 + d] = bitmask;
                                cached |= (byte)(1<<d);
                            }
                        }
                        side_cache[vox_index] = force_recalculate ? (byte)0x7F : cached;
                    }
                    
                    if (cached == 0x00 || !voxel_is_target(vox, target_type))
                    {
                        prev_type = -1;
                        prev_cached = cached;
                        if (prev_x_need_clear[x])
                        {
                            prev_x[x].Item1 = -1;
                            prev_x_need_clear[x] = false;
                        }
                    }
                    else
                    {
                        var coord = new Vector3(x, y, z) - offs;
                        var prev_i_4 = prev_x[x].Item3;
                        var prev_i_5 = prev_x[x].Item4;
                        
                        foreach (var d in Enumerable.Range(0, 6))
                        {
                            var prev_bitmask = prev_bitmasks[d];
                            var prev_x_bitmask = prev_x[x].Item5[d];
                            var bitmask = bitmask_cache[vox_index*6 + d];
                            prev_bitmasks[d] = bitmask;
                            var dir = dirs[d];
                            if ((cached & (1<<d)) != 0)
                            {
                                if (d < 4 && (prev_cached & (1<<d)) != 0 && prev_bitmask == bitmask && prev_type == vox && ((d >= 2) ? (prev_side_val[d-2] == side_val[d-2]) : true))
                                {
                                    if (d == 0)
                                    {
                                        verts[prev_i_0+2] += new Vector3(1.0f, 0.0f, 0.0f);
                                        verts[prev_i_0+3] += new Vector3(1.0f, 0.0f, 0.0f);
                                    }
                                    else if(d == 1)
                                    {
                                        verts[prev_i_1+2] += new Vector3(1.0f, 0.0f, 0.0f);
                                        verts[prev_i_1+3] += new Vector3(1.0f, 0.0f, 0.0f);
                                    }
                                    else if(d == 2)
                                    {
                                        verts[prev_i_2+0] += new Vector3(1.0f, 0.0f, 0.0f);
                                        verts[prev_i_2+2] += new Vector3(1.0f, 0.0f, 0.0f);
                                    }
                                    else if(d == 3)
                                    {
                                        verts[prev_i_3+1] += new Vector3(1.0f, 0.0f, 0.0f);
                                        verts[prev_i_3+3] += new Vector3(1.0f, 0.0f, 0.0f);
                                    }
                                }
                                else if(d >= 4 && (prev_x[x].Item2 & (1<<d)) != 0 && prev_x_bitmask == bitmask && prev_x[x].Item1 == vox && prev_x[x].Item6[d-2] == side_val[d-2])
                                {
                                    if (d == 4)
                                    {
                                        verts[prev_i_4+1] += new Vector3(0.0f, 0.0f, 1.0f);
                                        verts[prev_i_4+3] += new Vector3(0.0f, 0.0f, 1.0f);
                                    }
                                    else if (d == 5)
                                    {
                                        verts[prev_i_5+0] += new Vector3(0.0f, 0.0f, 1.0f);
                                        verts[prev_i_5+2] += new Vector3(0.0f, 0.0f, 1.0f);
                                    }
                                }
                                else
                                {
                                    var dir_mat_index = Math.Min(d, 2);
                                    var array_index = voxel_info[vox][dir_mat_index];
                                    
                                    var side_top = (vox_type == 2 && d >= 2) ? side_val[d-2].Item1 : info_max;
                                    var side_bottom = (vox_type == 2 && d >= 2) ? side_val[d-2].Item2 : 0;
                                    
                                    prev_bitmasks[d] = bitmask;
                                    var i_start = verts.Count();
                                    if (d == 0)
                                        prev_i_0 = i_start;
                                    else if(d == 1)
                                        prev_i_1 = i_start;
                                    else if(d == 2)
                                        prev_i_2 = i_start;
                                    else if(d == 3)
                                        prev_i_3 = i_start;
                                    else if(d == 4)
                                        prev_i_4 = i_start;
                                    else if(d == 5)
                                        prev_i_5 = i_start;
                                    
                                    for (int i = 0; i < 4; i++)
                                    {
                                        var v = vert_table[d*4 + i];
                                        if (d == 0 && top_val != info_max)
                                            v.Y -= 1.0f-((float)top_val)/(float)info_max;
                                        if (d >= 2 && i < 2 && side_top != info_max)
                                            v.Y -= 1.0f-((float)side_top)/(float)info_max;
                                        if (d >= 2 && i >= 2 && side_bottom != 0)
                                            v.Y += ((float)side_bottom)/(float)info_max;
                                        
                                        verts.Add(coord + v);
                                        
                                        var index_a = (byte)(array_index >> 8);
                                        var index_b = (byte)(array_index & 0xFF);
                                        face_info.Add((byte)d);
                                        face_info.Add(index_a);
                                        face_info.Add(index_b);
                                        face_info.Add(bitmask);
                                    }
                                    foreach (var i in new int[]{0, 1, 2, 2, 1, 3})
                                        indexes.Add(i_start + i);
                                }
                            }
                        }
                        
                        prev_side_val = side_val;
                        prev_type = vox;
                        prev_cached = cached;
                        prev_x[x] = (vox, cached, prev_i_4, prev_i_5, (byte[])prev_bitmasks.Clone(), side_val);
                        prev_x_need_clear[x] = true;
                    }
                }
            }
        }
        
        var arrays = new Godot.Collections.Array();
        arrays.Resize((int)Mesh.ArrayType.Max);
        arrays[(int)Mesh.ArrayType.Vertex] = verts.ToArray();
        arrays[(int)Mesh.ArrayType.Custom0] = face_info.ToArray();
        arrays[(int)Mesh.ArrayType.Index] = indexes.ToArray();
        return arrays;
    }
}


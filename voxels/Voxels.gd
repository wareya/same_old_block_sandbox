extends Node3D
class_name Voxels

#static var chunk_size = 16
static var chunk_size = 16
static var bounds : AABB = AABB(Vector3(), Vector3.ONE*(chunk_size-1))

# top, bottom, side
static var voxel_info = [
    # 0
    [0, 0, 0], # air
    [0, 10, 20], # grass
    [10, 10, 10], # dirt
    [30, 30, 30], # rock
    [50, 50, 40], # log
    # 5
    [60, 60, 60], # leaf
    [70, 70, 70], # water
]

static var vox_alphatest = {
    5 : null, # leaf
}
static var vox_transparent = {
    6 : null, # water
}

static func vox_get_type(vox : int):
    if vox in vox_alphatest:
        return 1
    elif vox in vox_transparent:
        return 2
    return 0
    

# 0xFF - not cached. other: cached, "on" bits are drawn sides.
var side_cache = PackedByteArray()
# bitmask - which neighbors are "connected" to the given voxel face
var bitmask_cache = PackedByteArray()

var voxels = PackedByteArray()

static func _adjust_val(x : float, n : float) -> float:
    var s = sign(x)
    x = abs(x)
    x = 1.0 - x
    x = pow(x, n)
    x = s * (1.0 - x)
    return x

static func height_at_global(noiser : Noise, x : float, z : float):
    var pure_height = noiser.get_noise_2d(x, z)
    var height = pure_height
    
    var steepness_freq = 0.5
    
    var steepness = noiser.get_noise_3d(x*steepness_freq, -z*steepness_freq + 100.0, 50.0)*0.5 + 0.5
    steepness = lerp(0.4, 16.0, steepness*steepness*steepness*steepness)
    height = _adjust_val(height, steepness)
    height += noiser.get_noise_2d(x*0.2 + 512.0, z*0.2 + 11.0) * 1.0
    
    var height_scale_freq = 0.5
    
    var height_scale = noiser.get_noise_2d(x*height_scale_freq, z*height_scale_freq + 154.0)*0.5 + 0.5
    height = height * lerp(1.0, 12.0, height_scale)
    
    height += noiser.get_noise_2d(x*0.4 + 51.0, z*0.4 + 1301.0) * 5.0
            
    var rock_offset = noiser.get_noise_2d(z*2.6 + 151.0, x*2.6 + 11.0)*5.0
    
    pure_height = round(pure_height)
    height = round(height)
    rock_offset = round(rock_offset)
    
    return [pure_height, height, rock_offset]

static func get_tree_coords(_chunk_position : Vector3, noiser : Noise):
    var rng = RandomNumberGenerator.new()
    rng.seed = hash(_chunk_position * Vector3(1.0, 0.0, 1.0))
    var tree_count = rng.randi_range(3, 6)
    
    var offset = -Vector3.ONE*chunk_size/2 + _chunk_position
    var offset_2d = Vector2(offset.x, offset.z)
    
    var trees = []
    for i in tree_count:
        var buffer = 2 # FIXME: remove
        var x = rng.randi_range(buffer, chunk_size-1-buffer)
        var z = rng.randi_range(buffer, chunk_size-1-buffer)
        
        var c_2d = Vector2(x, z) + offset_2d
        var info = Voxels.height_at_global(noiser, c_2d.x, c_2d.y)
        var height = info[1]
        var rock_part = info[2]
        var is_rock = rock_part > 1.0
        
        if height >= 0 and !is_rock:
            var c_3d = Vector3(x, height+1 - _chunk_position.y + chunk_size/2, z)
            var tall = rng.randi_range(4, 6)
            var grunge = rng.randi()
            trees.push_back([c_3d, tall, grunge])
    
    return trees

static func _generate_internal(
    noiser : Noise,
    _voxels : PackedByteArray,
    _chunk_position : Vector3,
    offset : Vector3,
    offset_2d : Vector2):
    
    for z in chunk_size:
        for x in chunk_size:
            var c_2d = Vector2(x, z) + offset_2d
            var info = Voxels.height_at_global(noiser, c_2d.x, c_2d.y)
            
            #var pure_height = info[0]
            var height = info[1]
            var rock_offset = info[2]
            
            var h_i = Voxels.coord_to_index(Vector3(x, 0, z))
            
            for y in chunk_size:
                var c = Vector3(x, y, z) + offset
            
                #var pure_noise = pure_height - c.y
                
                var noise = height - c.y
                var noise_above = height - c.y - 1.0
                
                var rock_noise = noise + rock_offset
                
                var vox = 0
                if noise < 0.0:
                    vox = 0 # air
                elif noise_above < 0.0 and c.y >= 0.0:
                    vox = 1 # grass
                else:
                    vox = 2 # dirt
                
                if vox != 0 and rock_noise > 1.0:
                    vox = 3 # rock
                
                if vox == 0 and c.y <= 0:
                    vox = 6 # water
                
                var i = h_i + y*chunk_size*chunk_size
                
                _voxels[i] = vox
    
    var tree_coords = get_tree_coords(_chunk_position, noiser)
    for tree in tree_coords:
        var coord = tree[0]
        var tall = tree[1]
        var grunge = tree[2]
        
        var leaf_bottom = max(2, tall-3)
        
        for y in range(leaf_bottom, tall+1+(grunge%3)/2):
            var _range = 2
            var evergreen = grunge & 256 != 0
            if evergreen:
                _range -= (y+tall-leaf_bottom)%2
            if y+1 > tall:
                _range -= 1
            for z in range(-_range, _range+1):
                for x in range(-_range, _range+1):
                    var limit = _range*_range+0.25
                    var fd = (grunge ^ hash(x) ^ hash(z) ^ hash(y))
                    if fd%2 == 1:
                        limit += 1.0
                    if x*x + z*z > limit:
                        continue
                    var c2 = coord + Vector3(x, y, z)
                    if bounds.has_point(c2):
                        var index = Voxels.coord_to_index(c2)
                        _voxels[index] = 5
        
        for y in tall:
            var c2 = coord + Vector3(0, y, 0)
            if bounds.has_point(c2):
                var index = Voxels.coord_to_index(c2)
                _voxels[index] = 4

static var VoxelGenerator = preload("res://voxels/VoxelGenerator.cs").new()
var VoxelMesher = preload("res://voxels/VoxelMesher.cs").new()

func generate():
    var start = Time.get_ticks_usec()
    side_cache.resize(chunk_size*chunk_size*chunk_size)
    side_cache.fill(0xFF)
    bitmask_cache.resize(chunk_size*chunk_size*chunk_size*6)
    bitmask_cache.fill(0x0)
    
    var offset = -Vector3.ONE*chunk_size/2 + chunk_position
    var offset_2d = Vector2(offset.x, offset.z)
    var noiser = world.base_noise
    
    #voxels.resize(chunk_size*chunk_size*chunk_size)
    #Voxels._generate_internal(noiser, voxels, chunk_position, offset, offset_2d)
    
    voxels = VoxelGenerator._Generate(noiser, chunk_position, offset, offset_2d)
    
    #print("gen time: ", (Time.get_ticks_usec() - start)/1000.0)


var meshinst_child = MeshInstance3D.new()
var body_child = StaticBody3D.new()
func _ready() -> void:
    #print("voxels ready!")
    
    add_child(meshinst_child)
    add_child(body_child)

var chunk_position = Vector3()
func do_generation(pos : Vector3):
    set_global_position.call_deferred(pos)
    chunk_position = pos
    generate()

func initial_remesh(_force_wait : bool = false):
    force_wait = _force_wait
    alive = true
    process_and_remesh()
    accept_remesh.call_deferred()

static var dirs = [Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]
static var right_dirs = [Vector3.RIGHT, Vector3.LEFT, Vector3.LEFT, Vector3.RIGHT, Vector3.BACK, Vector3.FORWARD]
static var up_dirs = [Vector3.FORWARD, Vector3.BACK, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP]
static var face_verts = [Vector3(0.5, 0.5, -0.5), Vector3(-0.5, 0.5, -0.5), Vector3(0.5, -0.5, -0.5), Vector3(-0.5, -0.5, -0.5)]

static func coord_to_index(coord : Vector3) -> float:
    return coord.y*chunk_size*chunk_size + coord.z*chunk_size + coord.x


static func generate_verts():
    var verts = PackedVector3Array()
    for dir in dirs:
        var ref_dir = Vector3.UP if not dir.abs() == Vector3.UP else Vector3.LEFT
        var xform = Transform3D.IDENTITY.looking_at(dir, ref_dir)
        for i in [0, 1, 2, 3]:
            var v = face_verts[i]
            v = xform * v
            verts.push_back(v)
    return verts

static var vert_table = generate_verts()

var remesh_output_mutex = Mutex.new()
var remesh_output = []

var world : World = DummySingleton.get_tree().get_first_node_in_group("World")

func remesh_get_arrays(target_type : int):
    var voxel_is_target = func(vox : int, target_type : int) -> bool:
        if vox == 0:
            return false
        var type = Voxels.vox_get_type(vox)
        return type == target_type
    
    var get_voxel = func(global_coord : Vector3):
        var chunk_coord = World.get_chunk_coord(global_coord - Vector3.ONE*chunk_size/2)
        if chunk_coord in neighbor_chunks:
            var neighbor_voxels = neighbor_chunks[chunk_coord]
            var local_coord = global_coord - chunk_coord
            var index = (
                local_coord.y*chunk_size*chunk_size +
                local_coord.z*chunk_size +
                local_coord.x )
            return neighbor_voxels[index]
        return 0
    
    var verts = PackedVector3Array()
    var normals = PackedVector3Array()
    var tex_indexes = PackedVector2Array()
    var indexes = PackedInt32Array()
    
    var start = Time.get_ticks_usec()
    
    var offs = Vector3.ONE*chunk_size/2.0
    
    #print("starting loop in remesh()")
    for y in chunk_size:
        var prev_x = []
        var prev_x_need_clear = []
        for _i in chunk_size:
            prev_x.push_back([-1, 0x00, 0, 0, [0x00, 0x00, 0x00, 0x00, 0x00, 0x00]])
            prev_x_need_clear.push_back(false)
        
        for z in chunk_size:
            var prev_type = -1
            var prev_cached = 0x00
            var prev_bitmasks = [0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
            var prev_i_0 = 0
            var prev_i_1 = 0
            var prev_i_2 = 0
            var prev_i_3 = 0
            for x in chunk_size:
                #var vox_index = Voxels.coord_to_index(Vector3(x, y, z))
                var vox_index = y*chunk_size*chunk_size + z*chunk_size + x
                var cached = side_cache[vox_index]
                
                var vox = voxels[vox_index]
                var vox_type = Voxels.vox_get_type(vox)
                var vox_atest = vox_type == 1
                var vox_xparent = vox_type != 0
                
                if cached == 0xFF:
                    cached = 0x00
                    if voxel_is_target.call(vox, vox_type):
                        for d in 6:
                            var dir : Vector3 = dirs[d]
                            if !vox_atest:
                                var neighbor_coord : Vector3 = Vector3(x, y, z) + dir
                                if bounds.has_point(neighbor_coord):
                                    var neighbor_index = (
                                        neighbor_coord.y*chunk_size*chunk_size +
                                        neighbor_coord.z*chunk_size +
                                        neighbor_coord.x )
                                    var v = voxels[neighbor_index]
                                    if voxel_is_target.call(v, vox_type) or (vox_xparent and v != 0):
                                        continue
                                else:
                                    var neighbor = get_voxel.call(neighbor_coord + chunk_position)
                                    if voxel_is_target.call(neighbor, vox_type) or (vox_xparent and neighbor != 0):
                                        continue
                            
                            var bitmask : int = 0
                            var bit : int = 0
                            var right_dir : Vector3 = right_dirs[d]
                            var up_dir : Vector3 = up_dirs[d]
                            for _y in range(-1, 2):
                                for _x in range(-1, 2):
                                    if _y == 0 and _x == 0:
                                        continue
                                    var next_coord : Vector3 = Vector3(x, y, z) + _y*up_dir + _x*right_dir
                                    var occlude_coord : Vector3 = next_coord + dir
                                    var bit_is_same = 0
                                    
                                    if bounds.has_point(next_coord):
                                        var next_index = (
                                            next_coord.y*chunk_size*chunk_size +
                                            next_coord.z*chunk_size +
                                            next_coord.x )
                                        if voxels[next_index] == vox:
                                            bit_is_same = 1
                                    else:
                                        var next = get_voxel.call(next_coord + chunk_position)
                                        if next == vox:
                                            bit_is_same = 1
                                    
                                    if bit_is_same == 1:
                                        if bounds.has_point(occlude_coord):
                                            var occlude_index = (
                                                occlude_coord.y*chunk_size*chunk_size +
                                                occlude_coord.z*chunk_size +
                                                occlude_coord.x )
                                            if voxel_is_target.call(voxels[occlude_index], vox_type):
                                                bit_is_same = 0
                                        else:
                                            var occlude = get_voxel.call(occlude_coord + chunk_position)
                                            if voxel_is_target.call(occlude, vox_type):
                                                bit_is_same = 0
                                    
                                    bitmask |= bit_is_same<<bit
                                    bit += 1
                            
                            bitmask_cache[vox_index*6 + d] = bitmask
                            cached |= 1<<d
                    side_cache[vox_index] = cached
                
                if cached == 0x00 or !voxel_is_target.call(vox, target_type):
                    prev_type = -1
                    prev_cached = cached
                    if prev_x_need_clear[x]:
                        prev_x[x][0] = -1
                        prev_x_need_clear[x] = false
                else:
                    var coord = Vector3(x, y, z) - offs
                    var prev_i_4 = prev_x[x][2]
                    var prev_i_5 = prev_x[x][3]
                    for d in 6:
                        var prev_bitmask = prev_bitmasks[d]
                        var prev_x_bitmask = prev_x[x][4][d]
                        var bitmask = bitmask_cache[vox_index*6 + d]
                        prev_bitmasks[d] = bitmask
                        var dir : Vector3 = dirs[d]
                        if cached & (1<<d):
                            if d < 4 and (prev_cached & (1<<d)) and prev_bitmask == bitmask and prev_type == vox:
                                if d == 0:
                                    verts[prev_i_0+2].x += 1.0
                                    verts[prev_i_0+3].x += 1.0
                                elif d == 1:
                                    verts[prev_i_1+2].x += 1.0
                                    verts[prev_i_1+3].x += 1.0
                                elif d == 2:
                                    verts[prev_i_2+0].x += 1.0
                                    verts[prev_i_2+2].x += 1.0
                                elif d == 3:
                                    verts[prev_i_3+1].x += 1.0
                                    verts[prev_i_3+3].x += 1.0
                            elif d >= 4 and (prev_x[x][1] & (1<<d)) and prev_x_bitmask == bitmask and prev_x[x][0] == vox:
                                if d == 4:
                                    verts[prev_i_4+1].z += 1.0
                                    verts[prev_i_4+3].z += 1.0
                                elif d == 5:
                                    verts[prev_i_5+0].z += 1.0
                                    verts[prev_i_5+2].z += 1.0
                            else:
                                var dir_mat_index = min(d, 2)
                                var array_index = voxel_info[vox][dir_mat_index]
                                
                                prev_bitmasks[d] = bitmask
                                var i_start = verts.size()
                                if d == 0:
                                    prev_i_0 = i_start
                                elif d == 1:
                                    prev_i_1 = i_start
                                elif d == 2:
                                    prev_i_2 = i_start
                                elif d == 3:
                                    prev_i_3 = i_start
                                elif d == 4:
                                    prev_i_4 = i_start
                                elif d == 5:
                                    prev_i_5 = i_start
                                
                                for i in 4:
                                    var v = vert_table[d*4 + i]
                                    verts.push_back(coord + v)
                                    normals.push_back(dir)
                                    tex_indexes.push_back(Vector2(float(array_index), float(bitmask)))
                                for i in [0, 1, 2, 2, 1, 3]:
                                    indexes.push_back(i_start + i)
                    
                    prev_type = vox
                    prev_cached = cached
                    prev_x[x] = [vox, cached, prev_i_4, prev_i_5, prev_bitmasks.duplicate()]
                    prev_x_need_clear[x] = true
    
    #print((Time.get_ticks_usec() - start)/1000.0, "msec to build buffers")
    #print("verts size: ", verts.size())
    #print("----")
    
    start = Time.get_ticks_usec()
    var arrays = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = verts
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_TEX_UV2] = tex_indexes
    arrays[Mesh.ARRAY_INDEX] = indexes
    return arrays

var neighbor_chunks = {}
var remeshed = false
func remesh():
    var start = Time.get_ticks_usec()
    
    #print("in remesh()")
    neighbor_chunks = {}
    world.chunk_table_mutex.lock()
    for y in range(-1, 2):
        for z in range(-1, 2):
            for x in range(-1, 2):
                var c = Vector3(x, y, z)*chunk_size + chunk_position
                if c in world.all_chunks:
                    neighbor_chunks[c] = world.all_chunks[c].voxels
    world.chunk_table_mutex.unlock()
    
    dirty_command_mutex.lock()
    for cmd in dirty_commands:
        print("dirty command...", cmd)
        if cmd == null:
            _dirty_sides()
        else:
            _dirty_block(cmd)
    dirty_commands = []
    dirty_command_mutex.unlock()
    
    var solid_arrays = VoxelMesher.remesh_get_arrays(voxels, 0, chunk_position, neighbor_chunks)
    var atest_arrays = VoxelMesher.remesh_get_arrays(voxels, 1, chunk_position, neighbor_chunks)
    var trans_arrays = VoxelMesher.remesh_get_arrays(voxels, 2, chunk_position, neighbor_chunks)
    #var solid_arrays = remesh_get_arrays(0)
    #var atest_arrays = remesh_get_arrays(1)
    #var trans_arrays = remesh_get_arrays(2)
    
    # wrong way, have to do it to avoid crashes
    remesh_output_mutex.lock()
    remesh_output = [solid_arrays, atest_arrays, trans_arrays]
    #print([solid_arrays.size(), atest_arrays.size(), trans_arrays.size()])
    #print([remesh_output[0].size(), remesh_output[1].size(), remesh_output[2].size()])
    remesh_output_mutex.unlock()
    
    #print("remesh time: ", (Time.get_ticks_usec() - start)/1000.0)

var block_command_mutex = Mutex.new()
var block_commands = []

func get_block(coord : Vector3) -> int:
    coord += Vector3.ONE*chunk_size/2
    coord -= chunk_position
    coord = coord.round()
    if bounds.has_point(coord):
        var index = Voxels.coord_to_index(coord)
        return voxels[index]
    
    return 0

func set_block(coord : Vector3, id : int):
    coord += Vector3.ONE*chunk_size/2
    coord -= chunk_position
    coord = coord.round()
    
    # if the id is real, change the voxel
    if bounds.has_point(coord) and id >= 0:
        # FIXME: thread-unsafe but... the remesh thread only ever *reads* this, and will
        # reread it again next cycle if it ever reads a half-stale version
        var index = Voxels.coord_to_index(coord)
        voxels[index] = id
    
    block_command_mutex.lock()
    block_commands.push_back([coord, id])
    block_command_mutex.unlock()

var dirty_command_mutex = Mutex.new()
var dirty_commands = []

func dirty_block(coord : Vector3):
    dirty_command_mutex.lock()
    dirty_commands.push_back(coord)
    dirty_command_mutex.unlock()

func _dirty_block(coord : Vector3):
    for y in range(-1, 2):
        for z in range(-1, 2):
            for x in range(-1, 2):
                var c = coord + Vector3(x, y, z)
                if bounds.has_point(c):
                    side_cache[Voxels.coord_to_index(c)] = 0xFF

func dirty_sides():
    dirty_command_mutex.lock()
    dirty_commands.push_back(null)
    dirty_command_mutex.unlock()
    
func _dirty_sides():
    for y in chunk_size:
        for z in chunk_size:
            side_cache[Voxels.coord_to_index(Vector3(0, y, z))] = 0xFF
            side_cache[Voxels.coord_to_index(Vector3(chunk_size-1, y, z))] = 0xFF
    for y in chunk_size:
        for x in chunk_size:
            side_cache[Voxels.coord_to_index(Vector3(x, y, 0))] = 0xFF
            side_cache[Voxels.coord_to_index(Vector3(x, y, chunk_size-1))] = 0xFF
    for z in chunk_size:
        for x in chunk_size:
            side_cache[Voxels.coord_to_index(Vector3(x, 0, z))] = 0xFF
            side_cache[Voxels.coord_to_index(Vector3(x, chunk_size-1, z))] = 0xFF

var remesh_semaphore = Semaphore.new()
var remesh_thread = Thread.new()
var remesh_work_mutex = Mutex.new()
func process_and_remesh():
    remesh_work_mutex.lock()
    block_command_mutex.lock()
    for data in block_commands:
        dirty_block(data[0])
    block_commands = []
    block_command_mutex.unlock()
    remesh()
    remesh_work_mutex.unlock()

var force_wait : bool = false
var alive = false

func accept_remesh():
    remesh_output_mutex.lock()
    if remesh_output != []:
        var start = Time.get_ticks_usec()
        
        var mesh_collision = []
        
        var mesh_child = ArrayMesh.new()
        
        var add_arrays = func(arrays, mat, solid):
            if arrays and arrays.size() > 0 and arrays[0].size() > 0:
                mesh_child.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
                var id = mesh_child.get_surface_count() - 1
                mesh_child.surface_set_material(id, mat)
                if solid:
                    mesh_collision.push_back(mesh_child.create_trimesh_shape())
            return mesh_child
        
        #print("array sizes:")
        #for array in remesh_output:
        #    print(array[0].size())
        
        add_arrays.call(remesh_output[0], preload("res://voxels/VoxMat.tres"), true)
        add_arrays.call(remesh_output[1], preload("res://voxels/VoxMatATest.tres"), true)
        add_arrays.call(remesh_output[2], preload("res://voxels/VoxMatTrans.tres"), false)
        remesh_output = []
        
        remesh_output_mutex.unlock()
        
        meshinst_child.mesh = mesh_child
        
        if body_child.get_shape_owners().size() == 0:
            body_child.create_shape_owner(body_child)
        while body_child.shape_owner_get_shape_count(0) > 0:
            body_child.shape_owner_remove_shape(0, 0)
        
        for mesh in mesh_collision:
            body_child.shape_owner_add_shape(0, mesh)
        
        #print("accept time: ", (Time.get_ticks_usec() - start)/1000.0)
        
        remeshed = true
    else:
        remesh_output_mutex.unlock()
    
    

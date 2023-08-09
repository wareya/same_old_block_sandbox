extends Node3D
class_name Voxels

static var chunk_size = 16
static var bounds : AABB = AABB(Vector3(), Vector3.ONE*(chunk_size-1))

const threaded_remesh = true

class Voxel:
    # [top, bottom, side]
    static var type_info = [
        [0, 0, 0],
        [0, 10, 20],
        [10, 10, 10],
    ]
    var type : int = 0

# 0xFF - not cached. other: cached, "on" bits are drawn sides.
var side_cache = PackedByteArray()
# bitmask - which neighbors are "connected" to the given voxel face
var bitmask_cache = PackedByteArray()

var voxels : Array[Voxel] = []

func generate(_global_coord : Vector3):
    for y in chunk_size:
        for z in chunk_size:
            for x in chunk_size:
                var vox = Voxel.new()
                if y >= chunk_size/2:
                    vox.type = 0
                elif y+1 == chunk_size/2:
                    vox.type = 1
                else:
                    vox.type = 2
                voxels.push_back(vox)
                side_cache.push_back(0xFF)
                for i in 6:
                    bitmask_cache.push_back(0x0)


var meshinst_child = MeshInstance3D.new()
var mesh_child = ArrayMesh.new()
var body_child = StaticBody3D.new()
func _ready() -> void:
    print("voxels ready!")
    
    add_child(meshinst_child)
    add_child(body_child)

func do_generation(pos : Vector3):
    global_position = pos
    generate(global_position)
    remesh()
    
    if threaded_remesh:
        remesh_thread.start(async_remesh)

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

func remesh():
    var verts = PackedVector3Array()
    var normals = PackedVector3Array()
    var tex_indexes = PackedVector2Array()
    var indexes = PackedInt32Array()
    
    var start = Time.get_ticks_usec()
    
    var offs = Vector3.ONE*chunk_size/2.0
    
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
                
                if cached == 0xFF:
                    var vox : Voxel = voxels[vox_index]
                    cached = 0x00
                    if vox.type != 0:
                        for d in 6:
                            var dir : Vector3 = dirs[d]
                            var neighbor_coord : Vector3 = Vector3(x, y, z) + dir
                            if bounds.has_point(neighbor_coord):
                                var neighbor_index = (
                                    neighbor_coord.y*chunk_size*chunk_size +
                                    neighbor_coord.z*chunk_size +
                                    neighbor_coord.x )
                                if voxels[neighbor_index].type != 0:
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
                                        if voxels[next_index].type == vox.type:
                                            bit_is_same = 1
                                    if bit_is_same == 1 and bounds.has_point(occlude_coord):
                                        var occlude_index = (
                                            occlude_coord.y*chunk_size*chunk_size +
                                            occlude_coord.z*chunk_size +
                                            occlude_coord.x )
                                        if voxels[occlude_index].type != 0:
                                            bit_is_same = 0
                                    
                                    bitmask |= bit_is_same<<bit
                                    bit += 1
                            
                            bitmask_cache[vox_index*6 + d] = bitmask
                            cached |= 1<<d
                    side_cache[vox_index] = cached
                
                if cached == 0x00:
                    prev_type = -1
                    prev_cached = cached
                    if prev_x_need_clear[x]:
                        prev_x[x][0] = -1
                        prev_x_need_clear[x] = false
                else:
                    var vox = voxels[vox_index]
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
                            if d < 4 and (prev_cached & (1<<d)) and prev_bitmask == bitmask and prev_type == vox.type:
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
                            elif d >= 4 and (prev_x[x][1] & (1<<d)) and prev_x_bitmask == bitmask and prev_x[x][0] == vox.type:
                                if d == 4:
                                    verts[prev_i_4+1].z += 1.0
                                    verts[prev_i_4+3].z += 1.0
                                elif d == 5:
                                    verts[prev_i_5+0].z += 1.0
                                    verts[prev_i_5+2].z += 1.0
                            else:
                                var dir_mat_index = min(d, 2)
                                var array_index = Voxel.type_info[vox.type][dir_mat_index]
                                
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
                    
                    prev_type = vox.type
                    prev_cached = cached
                    prev_x[x] = [vox.type, cached, prev_i_4, prev_i_5, prev_bitmasks.duplicate()]
                    prev_x_need_clear[x] = true
                
                
    print((Time.get_ticks_usec() - start)/1000.0, "msec to build buffers")
    
    if verts.size() == 0:
        return
    
    start = Time.get_ticks_usec()
    var arrays = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = verts
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_TEX_UV2] = tex_indexes
    arrays[Mesh.ARRAY_INDEX] = indexes
    
    var new_mesh_child = ArrayMesh.new()
    new_mesh_child.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    new_mesh_child.surface_set_material(0, preload("res://voxels/VoxMat.tres"))
    print((Time.get_ticks_usec() - start)/1000.0, "msec to commit mesh")
    
    start = Time.get_ticks_usec()
    var mesh_collision = new_mesh_child.create_trimesh_shape()
    print((Time.get_ticks_usec() - start)/1000.0, "msec to rebuild collision (", verts.size(), " verts)")
    
    remesh_output_mutex.lock()
    remesh_output = [new_mesh_child, mesh_collision]
    remesh_output_mutex.unlock()

var block_command_mutex = Mutex.new()
var block_commands = []

func set_block(coord : Vector3, id : int):
    coord += Vector3.ONE*chunk_size/2
    coord -= global_position
    coord = coord.round()
    if !bounds.has_point(coord):
        return
    
    # FIXME: thread-unsafe but... the remesh thread only ever *reads* this, and will
    # reread it again next cycle if it ever reads a half-stale version
    var index = Voxels.coord_to_index(coord)
    voxels[index] = Voxel.new()
    voxels[index].type = id
    
    block_command_mutex.lock()
    block_commands.push_back([coord, id])
    block_command_mutex.unlock()
    dirty = true

func process_block(coord : Vector3):
    for y in range(-1, 2):
        for z in range(-1, 2):
            for x in range(-1, 2):
                var i = Voxels.coord_to_index(coord + Vector3(x, y, z))
                side_cache[i] = 0xFF

var remesh_semaphore = Semaphore.new()
var remesh_thread = Thread.new()
var remesh_exit : bool = false

func async_remesh():
    while true:
        remesh_semaphore.wait()
        print("in async")
        if remesh_exit:
            return
        
        block_command_mutex.lock()
        for data in block_commands:
            process_block(data[0])
        block_commands = []
        block_command_mutex.unlock()
        
        remesh()

func sync_remesh():
    for data in block_commands:
        process_block(data[0])
    block_commands = []
    remesh()

var _script = get_script().source_code
var dirty : bool = false
func _process(_delta: float) -> void:
    # hot reloading watchdog
    if _script != get_script().source_code:
        _script = get_script().source_code
        # the previous thread is attached to a now-invalid script instance
        # so we can't use it AT ALL, or risk crashing
        remesh_semaphore = Semaphore.new()
        remesh_thread = Thread.new()
    
    if !remesh_thread.is_alive():
        if remesh_thread.is_started():
            remesh_thread.wait_to_finish()
        remesh_thread.start(async_remesh)
    
    if dirty: 
        dirty = false 
        if threaded_remesh:
            remesh_semaphore.post()
            print("posting to async")
        else:
            sync_remesh()
    
    remesh_output_mutex.lock()
    if remesh_output != []:
        mesh_child = remesh_output[0]
        var mesh_collision = remesh_output[1]
        remesh_output = []
        remesh_output_mutex.unlock()
        
        meshinst_child.mesh = mesh_child
        
        if body_child.get_shape_owners().size() == 0:
            body_child.create_shape_owner(body_child)
        while body_child.shape_owner_get_shape_count(0) > 0:
            body_child.shape_owner_remove_shape(0, 0)
        body_child.shape_owner_add_shape(0, mesh_collision)
    else:
        remesh_output_mutex.unlock()
    
    

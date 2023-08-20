extends Node3D
class_name Voxels

#static var chunk_size = 16
static var chunk_size : int = 16
static var chunk_vec3i : Vector3i = Vector3i(chunk_size, chunk_size, chunk_size)
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

static var VoxelGenerator = preload("res://voxels/VoxelGenerator.cs").new()
var VoxelMesher = preload("res://voxels/VoxelMesher.cs").new()

func generate():
    var _start = Time.get_ticks_usec()
    side_cache.resize(chunk_size*chunk_size*chunk_size)
    side_cache.fill(0xFF)
    bitmask_cache.resize(chunk_size*chunk_size*chunk_size*6)
    bitmask_cache.fill(0x0)
    
    var offset = -Vector3i.ONE*chunk_size/2 + chunk_position
    var offset_2d = Vector2i(offset.x, offset.z)
    var noiser = world.base_noise
    
    voxels = VoxelGenerator._Generate(noiser, chunk_position, offset)


var meshinst_child = MeshInstance3D.new()
var meshinst_childed : bool = false
var body_child = StaticBody3D.new()
var body_childed : bool = false

func _ready() -> void:
    pass

func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        if meshinst_child and is_instance_valid(meshinst_child):
            meshinst_child.free()
            meshinst_child = null
        if body_child and is_instance_valid(body_child):
            body_child.free()
            body_child = null

var chunk_position : Vector3i = Vector3i()
func do_generation(pos : Vector3):
    chunk_position = pos
    generate()

func load_generation(pos : Vector3, _voxels : PackedByteArray):
    side_cache.resize(chunk_size*chunk_size*chunk_size)
    side_cache.fill(0xFF)
    bitmask_cache.resize(chunk_size*chunk_size*chunk_size*6)
    bitmask_cache.fill(0x0)
    
    chunk_position = pos
    voxels = _voxels

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

var remeshed = false
func remesh():
    var _start = Time.get_ticks_usec()
    
    #print("in remesh()")
    var neighbor_chunks = {}
    world.chunk_table_mutex.lock()
    for y in range(-1, 2):
        for z in range(-1, 2):
            for x in range(-1, 2):
                var c = Vector3i(x, y, z)*chunk_size + chunk_position
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
    
    VoxelMesher.side_cache = side_cache
    var arrays = VoxelMesher.remesh_get_arrays(chunk_position, neighbor_chunks)
    side_cache = VoxelMesher.side_cache
    
    # wrong way, have to do it to avoid crashes
    remesh_output_mutex.lock()
    remesh_output = arrays
    #print([solid_arrays.size(), atest_arrays.size(), trans_arrays.size()])
    #print([remesh_output[0].size(), remesh_output[1].size(), remesh_output[2].size()])
    remesh_output_mutex.unlock()
    
    #print("remesh time: ", (Time.get_ticks_usec() - _start)/1000.0)

var block_command_mutex = Mutex.new()
var block_commands = []

func get_block_with_origin(coord : Vector3) -> int:
    return get_block(Vector3i(coord.round()) + world.world_origin)

func get_block(coord : Vector3i) -> int:
    coord += Vector3i.ONE*chunk_size/2
    coord -= Vector3i(chunk_position)
    if bounds.has_point(coord):
        var index = Voxels.coord_to_index(coord)
        return voxels[index]
    
    return 0

func set_block_with_origin(coord : Vector3, id : int):
    set_block(Vector3i(coord.round()) + world.world_origin, id)

func set_block(coord : Vector3i, id : int):
    coord += Vector3i.ONE*chunk_size/2
    coord -= Vector3i(chunk_position)
    
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

func accept_remesh():
    remesh_output_mutex.lock()
    if remesh_output != []:
        var _start = Time.get_ticks_usec()
        
        var mesh_child = ArrayMesh.new()
        var mesh2_child = ArrayMesh.new()
        
        var add_arrays = func(mesh, arrays, mat):
            if arrays and arrays.size() > 0 and arrays[0].size() > 0:
                var flags = (Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
                mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
                var id = mesh.get_surface_count() - 1
                mesh.surface_set_material(id, mat)
            return mesh
        
        #print("array sizes:")
        #for array in remesh_output:
        #    print(array[0].size())
        
        add_arrays.call(mesh_child, remesh_output[0], preload("res://voxels/VoxMat.tres"))
        add_arrays.call(mesh_child, remesh_output[1], preload("res://voxels/VoxMatATest.tres"))
        add_arrays.call(mesh_child, remesh_output[2], preload("res://voxels/VoxMatTransOuter.tres"))
        add_arrays.call(mesh_child, remesh_output[3], preload("res://voxels/VoxMatATest.tres"))
        var solids = remesh_output.back()
        #print(solids)
        remesh_output = []
        
        remesh_output_mutex.unlock()
        
        if mesh_child.get_surface_count() > 0:
            meshinst_child.set_layer_mask_value(20, false)
            meshinst_child.mesh = mesh_child
            if !meshinst_childed:
                add_child(meshinst_child)
                meshinst_child.force_update_transform()
                meshinst_childed = true
        else:
            meshinst_child.mesh = null
            if meshinst_childed:
                remove_child(meshinst_child)
                meshinst_childed = false
        
        if body_child.get_shape_owners().size() == 0:
            body_child.create_shape_owner(body_child)
        while body_child.shape_owner_get_shape_count(0) > 0:
            body_child.shape_owner_remove_shape(0, 0)
        
        var collision_added = false
        if solids and solids.size() > 0:
            var shape = ConcavePolygonShape3D.new()
            shape.set_faces(solids)
            body_child.shape_owner_add_shape(0, shape)
            collision_added = true
        
        if collision_added:
            if !body_childed:
                add_child(body_child)
                body_child.force_update_transform()
                body_childed = true
        else:
            if body_childed:
                remove_child(body_child)
                body_childed = false
        
        
        #print("accept time: ", (Time.get_ticks_usec() - _start)/1000.0)
        
        remeshed = true
    else:
        remesh_output_mutex.unlock()
    
func inform_moved():
    if body_childed:
        body_child.force_update_transform()

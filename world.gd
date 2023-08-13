extends Node3D
class_name World

var chunk_table_mutex = Mutex.new()
var chunks_unloaded = {}
var chunks_loaded = {}
var all_chunks = {}

var backing_file : FileAccess = null
func _init():
    var fname = "user://classicbox_world0.bin"
    backing_file = FileAccess.open(fname, FileAccess.READ_WRITE)
    if !backing_file:
        backing_file = FileAccess.open(fname, FileAccess.WRITE)
    print(backing_file)

var f_access_mutex = Mutex.new()
func trigger_save(chunks_to_save : Array):
    if chunks_to_save.size() == 0:
        return
    
    f_access_mutex.lock()
    var chunk_bytes = Voxels.chunk_size*Voxels.chunk_size*Voxels.chunk_size
    var chunk_storage_size = chunk_bytes + 8*4 # three signed i64s for position plus a padding/metadata i64
    
    var dirty_coords = {}
    for chunk in chunks_to_save:
        dirty_coords[chunk.chunk_position] = chunk
    
    # loop over dirty chunks
    backing_file.seek(0)
    while backing_file.get_position() < backing_file.get_length() and chunks_to_save.size() > 0:
        var x = backing_file.get_64()
        var y = backing_file.get_64()
        var z = backing_file.get_64()
        var _unused = backing_file.get_64()
        var c = Vector3(x, y, z)
        if c in dirty_coords:
            var chunk = dirty_coords[c]
            backing_file.store_buffer(chunk.voxels)
            dirty_coords.erase(c)
            chunks_to_save.erase(chunk)
        else:
            backing_file.seek(backing_file.get_position() + chunk_bytes)
    
    for chunk in chunks_to_save:
        var c = chunk.chunk_position
        backing_file.store_64(c.x)
        backing_file.store_64(c.y)
        backing_file.store_64(c.z)
        backing_file.store_64(0)
        backing_file.store_buffer(chunk.voxels)
    
    backing_file.flush()
    
    f_access_mutex.unlock()

func load_chunk_if_in_file(coord : Vector3):
    f_access_mutex.lock()
    var chunk_bytes = Voxels.chunk_size*Voxels.chunk_size*Voxels.chunk_size
    
    # loop over dirty chunks
    backing_file.seek(0)
    var found_chunk = null
    while backing_file.get_position() < backing_file.get_length():
        var x = backing_file.get_64()
        var y = backing_file.get_64()
        var z = backing_file.get_64()
        var _unused = backing_file.get_64()
        var c = Vector3(x, y, z)
        var data = backing_file.get_buffer(chunk_bytes)
        if c == coord:
            found_chunk = Voxels.new()
            found_chunk.load_generation(coord, data)
            break
    
    f_access_mutex.unlock()
    
    return found_chunk

func load_chunk(coord : Vector3):
    var vox = load_chunk_if_in_file(coord)
    if !vox:
        vox = Voxels.new()
        vox.do_generation(coord)
    return vox

var chunks_meshed = 0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
    var _range = 1
    for y in range(-1, 2):
        for z in range(-_range, _range+1):
            for x in range(-_range, _range+1):
                var c = Vector3(x, y, z)*Voxels.chunk_size
                
                var vox = load_chunk(c)
                all_chunks[c] = vox
    
    var c = Vector3()
    var vox = all_chunks[c]
    vox.process_and_remesh()
    vox.accept_remesh()
    chunks_meshed += 1
    add_child(vox)
    vox.global_position = c
    
    chunks_loaded[c] = vox
                

static func get_chunk_coord(coord):
    var chunk_coord = ((coord + Vector3.ONE*0.5) / Voxels.chunk_size).round() * Voxels.chunk_size
    return chunk_coord

var dirty_chunk_mutex = Mutex.new()
var dirty_chunks = []

func set_block(coord : Vector3, id : int):
    var chunk_coord = World.get_chunk_coord(coord)
    if chunk_coord in chunks_loaded:
        var chunk = chunks_loaded[chunk_coord]
        chunk.set_block(coord, id)
        
        dirty_chunk_mutex.lock()
        print("dirtying chunk...")
        dirty_chunks.push_back(chunk)
        dirty_chunk_mutex.unlock()
            
        var c = coord.round() - chunk_coord + Vector3.ONE*Voxels.chunk_size/2
        if (c.x == 0 or c.y == 0 or c.z == 0
            or c.x+1 == Voxels.chunk_size or c.y+1 == Voxels.chunk_size or c.z+1 == Voxels.chunk_size):
            var neighbor_chunk_coords = {}
            for y in range(-1, 2):
                for z in range(-1, 2):
                    for x in range(-1, 2):
                        var c2 = Vector3(x, y, z) + coord
                        var chunk2_coord = World.get_chunk_coord(c2)
                        chunk_table_mutex.lock()
                        if chunk2_coord in all_chunks:
                            neighbor_chunk_coords[chunk2_coord] = all_chunks[chunk2_coord]
                        chunk_table_mutex.unlock()
            
            if chunk_coord in neighbor_chunk_coords:
                neighbor_chunk_coords.erase(chunk_coord)
            
            
            dirty_chunk_mutex.lock()
            for neighbor_chunk in neighbor_chunk_coords.values():
                neighbor_chunk.set_block(coord, -1)
                dirty_chunks.push_back(neighbor_chunk)
            dirty_chunk_mutex.unlock()
            
            
        print(c)
    else:
        print("no chunk")

@export var base_noise : Noise = null

var time_alive = 0.0
func _process(delta : float) -> void:
    $FPS.text = (
        "FPS: %s\nchunks to load: %s\nchunks loaded: %s\nchunks generated: %s\nchunks meshed: %s" %
        [Engine.get_frames_per_second(),
        world_work_num_unloaded,
        chunks_loaded.size(),
        all_chunks.size(),
        chunks_meshed,
        ]
    )
    
    if !world_work_thread.is_started():
        world_work_thread.start(dynamic_world_loop)
    
    if !remesh_work_thread.is_started():
        remesh_work_thread.start(remesh_work_loop)
    
    time_alive += delta
    if world_work_num_unloaded == 0 and time_alive >= 0.0:
        print("fully loaded!", time_alive)
        time_alive = -100.0
    
    
var remesh_work_thread = Thread.new()
var remesh_work_wait_signal = Mutex.new()

func trigger_remesh_acceptance(dirty_chunk_list):
    for chunk in dirty_chunk_list:
        chunk.accept_remesh()

func __print(d): print(d)

signal _trigger_remesh
func remesh_work_loop():
    var semaphore = Semaphore.new()
    while true:
        dirty_chunk_mutex.lock()
        var dirty_list_copy = dirty_chunks.duplicate()
        dirty_chunks = []
        dirty_chunk_mutex.unlock()
        
        if dirty_list_copy.size() > 0:
            for chunk in dirty_list_copy:
                chunk.process_and_remesh()
            
            var dc = dirty_list_copy.duplicate()
            
            trigger_save(dc)
            
            trigger_remesh_acceptance.bind(dirty_list_copy).call_deferred()
        
        semaphore.post.call_deferred()
        semaphore.wait()


var world_work_thread = Thread.new()
var world_work_wait_signal = Mutex.new()
var world_work_num_unloaded = -1

signal _trigger_world_work
func dynamic_world_loop():
    var semaphore = Semaphore.new()
    var work_frame = Engine.get_process_frames()
    var chunks_to_add_and_load = []
    var _start = Time.get_ticks_usec()
    while true:
        var player_chunk = get_player_chunk_coord()
        var facing_dir = get_player_facing_dir()
        
        dynamically_unload_world(player_chunk)
        
        var loaded_info = dynamically_load_world(player_chunk, facing_dir)
        
        if !loaded_info:
            if chunks_to_add_and_load.size() > 0:
                add_and_load_all.call_deferred(chunks_to_add_and_load)
                chunks_to_add_and_load = []
            
            semaphore.post.call_deferred()
            semaphore.wait()
            work_frame = Engine.get_process_frames()
            continue
        
        chunks_to_add_and_load.push_back(loaded_info)
        
        var current_frame = Engine.get_process_frames()
        if current_frame != work_frame:
            if chunks_to_add_and_load.size() > 0:
                add_and_load_all.call_deferred(chunks_to_add_and_load)
                chunks_to_add_and_load = []
            #semaphore.post.call_deferred()
            #semaphore.wait()
            work_frame = current_frame
        

# 128 = 4 chunk distance
# 256 = 8 chunk distance
# 512 = 16 chunk distance
# 1024 = 32 chunk distance

var range_h = 512/Voxels.chunk_size/2
var range_v = 64/Voxels.chunk_size/2

var _found_unloadable_chunks = []
var _find_chunks_prev_player_chunk_2 = Vector3()
var unload_threshold = 1.5 * Voxels.chunk_size
func dynamically_unload_world(player_chunk):
    if _find_chunks_prev_player_chunk_2 != player_chunk:
        _find_chunks_prev_player_chunk_2 = player_chunk
        
        _found_unloadable_chunks = []
        for coord in chunks_loaded:
            var c_local = coord - player_chunk
            if Vector2(c_local.x, c_local.z).length() > (range_h-0.5)*Voxels.chunk_size + unload_threshold:
                _found_unloadable_chunks.push_back(coord)
            elif abs(c_local.y) > range_v*Voxels.chunk_size + unload_threshold:
                _found_unloadable_chunks.push_back(coord)
        
        var unload_list = []
        chunk_table_mutex.lock()
        for coord in _found_unloadable_chunks:
            var chunk = chunks_loaded[coord]
            chunks_loaded.erase(coord)
            chunks_unloaded[coord] = chunk
            unload_list.push_back(chunk)
        chunk_table_mutex.unlock()
        
        do_unload.call_deferred(unload_list)

func do_unload(chunk_list : Array):
    for chunk in chunk_list:
        if chunk.is_inside_tree() and chunk.get_parent() == self:
            remove_child(chunk)

var _find_chunks_prev_player_chunk = Vector3()
var _find_chunks_prev_facing_dir = Vector3.FORWARD
var _find_chunks_unloaded_coords = []
func find_chunk_load_queue(player_chunk : Vector3, facing_dir : Vector3):
    var dot = facing_dir.dot(_find_chunks_prev_facing_dir)
    if _find_chunks_prev_player_chunk != player_chunk or dot < 0.8:
        _find_chunks_prev_player_chunk = player_chunk
        _find_chunks_prev_facing_dir = facing_dir
        print(facing_dir)
        
        _find_chunks_unloaded_coords = []
        for y in range(-range_v, range_v+1):
            for z in range(-range_h, range_h+1):
                for x in range(-range_h, range_h+1):
                    if Vector2(x, z).length() > range_h-0.5:
                        continue
                    var c = Vector3(x, y, z) * Voxels.chunk_size
                    
                    var c_global = c + player_chunk
                    
                    # FIXME: wait... I need to use a mutex here...
                    if c_global in chunks_loaded:
                        continue
                    
                    var score = c.length()
                    if score > 30.0:
                        # cos(60deg) = 0.5; roughly 120 horiz fov
                        var cn = c/score
                        if cn.dot(facing_dir) < 0.2:
                            score += 200.0
                        elif cn.dot(facing_dir) < 0.5:
                            score += 20.0
                    
                    _find_chunks_unloaded_coords.push_back([-score, c])
    
        world_work_num_unloaded = _find_chunks_unloaded_coords.size()
        _find_chunks_unloaded_coords.sort()
    
    return _find_chunks_unloaded_coords

func get_player_chunk_coord(no_y : bool = false):
    var player = DummySingleton.get_tree().get_first_node_in_group("Player")
    var player_chunk = World.get_chunk_coord(player.cached_position)
    if no_y:
        player_chunk.y = 0.0
    return player_chunk

func get_player_facing_dir():
    var player = DummySingleton.get_tree().get_first_node_in_group("Player")
    return player.cached_facing_dir

        
func dynamically_load_world(player_chunk, facing_dir):
    var unloaded_coords = find_chunk_load_queue(player_chunk, facing_dir)
    if unloaded_coords.size() > 0:
        var c_coord = unloaded_coords.pop_back()[1] + player_chunk
        world_work_num_unloaded = unloaded_coords.size()
        
        if c_coord in chunks_unloaded:
            var chunk = chunks_unloaded[c_coord]
            chunk_table_mutex.lock()
            chunks_loaded[c_coord] = chunk
            chunks_unloaded.erase(c_coord)
            chunk_table_mutex.unlock()
            return [chunk]
        else:
            chunk_table_mutex.lock()
            
            var vox
            if not c_coord in all_chunks:
                vox = load_chunk(c_coord)
                all_chunks[c_coord] = vox
            else:
                vox = all_chunks[c_coord]
            
            for y in range(-1, 2):
                for z in range(-1, 2):
                    for x in range(-1, 2):
                        var c2_coord = Vector3(x, y, z) * Voxels.chunk_size + c_coord
                        if not c2_coord in all_chunks:
                            var vox2 = load_chunk(c2_coord)
                            all_chunks[c2_coord] = vox2
            chunk_table_mutex.unlock()
            
            vox.process_and_remesh()
            chunks_meshed += 1
            
            chunks_loaded[c_coord] = vox
            return [vox, c_coord]
    return null

func add_and_load_all(chunks):
    var _start = Time.get_ticks_usec()
    var just_chunks = []
    for chunk in chunks:
        if chunk.size() == 2:
            initial_add_vox(chunk[0], chunk[1])
        else:
            add_child(chunk[0])
        just_chunks.push_back(chunk[0])
    trigger_save(just_chunks)
    #print("add time: ", (Time.get_ticks_usec() - _start)/1000.0)

func initial_add_vox(vox : Node, coord : Vector3):
    add_child(vox)
    vox.global_position = coord
    vox.accept_remesh()

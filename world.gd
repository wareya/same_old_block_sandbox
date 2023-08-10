extends Node3D
class_name World

var chunk_table_mutex = Mutex.new()
var chunks_unloaded = {}
var chunks_loaded = {}
var all_chunks = {}

func load_chunk(coord = Vector3()):
    var vox = Voxels.new()
    add_child.call_deferred(vox)
    vox.do_generation(coord)
    return vox

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
    var range = 1
    for y in range(-1, 2):
        for z in range(-range, range+1):
            for x in range(-range, range+1):
                var c = Vector3(x, y, z)*Voxels.chunk_size
                
                var vox = load_chunk(c)
                all_chunks[c] = vox
    
    var c = Vector3()
    var vox = all_chunks[c]
    vox.initial_remesh(true)
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
        "FPS: %s\nchunks to load: %s\nchunks loaded: %s\nchunks generated: %s" %
        [Engine.get_frames_per_second(),
        world_work_num_unloaded,
        chunks_loaded.size(),
        all_chunks.size(),
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

signal _trigger_remesh
func remesh_work_loop():
    var semaphore = Semaphore.new()
    while true:
        dirty_chunk_mutex.lock()
        var dirty_list_copy = dirty_chunks.duplicate()
        dirty_chunks = []
        dirty_chunk_mutex.unlock()
        
        for chunk in dirty_list_copy:
            chunk.process_and_remesh()
        trigger_remesh_acceptance.bind(dirty_list_copy).call_deferred()
        
        semaphore.post.call_deferred()
        semaphore.wait()


var world_work_thread = Thread.new()
var world_work_wait_signal = Mutex.new()
var world_work_num_unloaded = -1

signal _trigger_world_work
func dynamic_world_loop():
    var semaphore = Semaphore.new()
    while true:
        dynamically_load_world()
        if world_work_num_unloaded == 0:
            semaphore.post.call_deferred()
            semaphore.wait()

func find_chunk_load_queue(player_chunk, facing_dir):
    # 128 = 8 chunk distance
    # 256 = 16 chunk distance
    # 512 = 32 chunk distance
    var range_h = 256/Voxels.chunk_size/2
    var range_v = 64/Voxels.chunk_size/2
    
    var unloaded_coords = []
    for y in range(-range_v, range_v+1):
        for z in range(-range_h, range_h+1):
            for x in range(-range_h, range_h+1):
                if Vector2(x, z).length() > range_h-0.5:
                    continue
                var c = Vector3(x, y, z) * Voxels.chunk_size
                
                var c_global = c + player_chunk
                
                # wait... I need to use a mutex here...
                if c_global in chunks_loaded:
                    continue
                
                unloaded_coords.push_back(c)
    
    world_work_num_unloaded = unloaded_coords.size()
    unloaded_coords.sort_custom(func (a, b):
        var a_score = a.length()
        var b_score = b.length()
        # cos(60deg) = 0.5; roughly 120 horiz fov
        if a_score > 30.0:
            if (a/a_score).dot(facing_dir) < 0.2:
                a_score += 200.0
            elif (a/a_score).dot(facing_dir) < 0.5:
                a_score += 20.0
        if b_score > 30.0 and (b/b_score).dot(facing_dir) < 0.2:
            if (b/b_score).dot(facing_dir) < 0.2:
                b_score += 200.0
            elif (b/b_score).dot(facing_dir) < 0.5:
                b_score += 20.0
        return a_score < b_score
    )
    
    return unloaded_coords

func get_player_chunk_coord(no_y : bool = false):
    var player = DummySingleton.get_tree().get_first_node_in_group("Player")
    var player_chunk = get_chunk_coord(player.cached_position)
    if no_y:
        player_chunk.y = 0.0
    return player_chunk

func get_player_facing_dir():
    var player = DummySingleton.get_tree().get_first_node_in_group("Player")
    return player.cached_facing_dir

func dynamically_load_world():
    var player_chunk = get_player_chunk_coord()
    var facing_dir = get_player_facing_dir()
    var unloaded_coords = find_chunk_load_queue(player_chunk, facing_dir)
    
    if unloaded_coords.size() > 0:
        var c_coord = unloaded_coords[0] + player_chunk
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
        
        vox.initial_remesh()
        
        chunks_loaded[c_coord] = vox
    

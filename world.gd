extends Node3D
class_name World

var do_threading = true

# actual world limit: 32-bit signed integer overflow
var chunk_table_mutex = Mutex.new()
var chunk_loaded_table_mutex = Mutex.new()
var chunks_unloaded = {}
var chunks_loaded = {}
var all_chunks = {}
var generated_chunks = {}

var save_disabled = true
var backing_file : FileAccess = null

func _init():
    randomize()
    world_seed = randi()
    world_seed = 124
    #world_seed = 6143
    #world_seed = 733
    #world_seed = 578
    #world_seed = 613
    print(world_seed)
    open_save()

var f_access_mutex = Mutex.new()
var f_index_table = {}

static var f_chunk_bytes = Voxels.chunk_size_h*Voxels.chunk_size_h*Voxels.chunk_size_v
static var f_chunk_header_bytes = 8*4 # three signed i64s for position plus a padding/metadata i64

var world_seed = 16

func open_save():
    if save_disabled:
        return
    f_access_mutex.lock()
    
    var fname = "user://classicbox_world0.bin"
    backing_file = FileAccess.open(fname, FileAccess.READ_WRITE)
    if !backing_file:
        backing_file = FileAccess.open(fname, FileAccess.WRITE)
    
    # build index table
    backing_file.seek(0)
    
    if backing_file.get_position() < backing_file.get_length():
        world_seed = backing_file.get_64()
    
    while backing_file.get_position() < backing_file.get_length():
        var x = backing_file.get_64()
        var y = backing_file.get_64()
        var z = backing_file.get_64()
        var _unused = backing_file.get_64()
        var c = Vector3i(x, y, z)
        f_index_table[c] = backing_file.get_position() - f_chunk_header_bytes
        backing_file.seek(backing_file.get_position() + f_chunk_bytes)
    
    f_access_mutex.unlock()

func trigger_save(chunks_to_save : Array):
    if save_disabled:
        return
    if chunks_to_save.size() == 0:
        return
    
    f_access_mutex.lock()
    
    backing_file.seek(0)
    backing_file.store_64(world_seed)
    
    for chunk in chunks_to_save:
        var c = chunk.chunk_position
        if c in f_index_table:
            backing_file.seek(f_index_table[c] + f_chunk_header_bytes)
            backing_file.store_buffer(chunk.voxels)
            chunks_to_save.erase(chunk)
    
    backing_file.seek(backing_file.get_length())
    for chunk in chunks_to_save:
        var c = chunk.chunk_position
        f_index_table[c] = backing_file.get_position()
        backing_file.store_64(c.x)
        backing_file.store_64(c.y)
        backing_file.store_64(c.z)
        backing_file.store_64(0)
        backing_file.store_buffer(chunk.voxels)
    
    backing_file.flush()
    
    f_access_mutex.unlock()

func load_chunk_if_in_file(coord : Vector3i):
    if save_disabled:
        return null
    f_access_mutex.lock()
    
    if coord in f_index_table:
        backing_file.seek(f_index_table[coord] + f_chunk_header_bytes)
        var data = backing_file.get_buffer(f_chunk_bytes)
        f_access_mutex.unlock()
        var chunk = Voxels.new()
        chunk.load_generation(coord, data)
        return chunk
    else:
        f_access_mutex.unlock()
        return null

func load_chunk(coord : Vector3i):
    var terrain_load_buffer = 1
    var neighbor_chunks = {}
    
    var start = Time.get_ticks_usec()/1000000.0
    
    for z in range(-terrain_load_buffer, terrain_load_buffer+1):
        for x in range(-terrain_load_buffer, terrain_load_buffer+1):
            var c = coord + Vector3i(x, 0, z)*Voxels.chunk_vec3i
            var new_vox
            if c in all_chunks:
                new_vox = all_chunks[c]
            else:
                new_vox = load_chunk_if_in_file(c)
                if !new_vox:
                    new_vox = Voxels.new()
                all_chunks[c] = new_vox
            neighbor_chunks[c] = all_chunks[c]
    
    var end = Time.get_ticks_usec()/1000000.0
    setup_time += end-start
    
    for c in neighbor_chunks:
        neighbor_chunks[c].generate_terrain(c)
        neighbor_chunks[c] = neighbor_chunks[c].voxels
    
    var vox = null
    if coord in all_chunks:
        vox = all_chunks[coord]
    else:
        vox = load_chunk_if_in_file(coord)
        if !vox:
            vox = Voxels.new()
        all_chunks[coord] = vox
    
    vox.generate_terrain(coord)
    vox.generate(coord, neighbor_chunks)
    
    generated_chunks[coord] = vox
    
    return vox

var chunks_meshed = 0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
    base_noise.seed = world_seed
    print(world_seed)
    print(base_noise.seed)
    
    for y in range(-range_v_down, range_v_up+1):
        for z in range(-_spawn_range, _spawn_range+1):
            for x in range(-_spawn_range, _spawn_range+1):
                var c = Vector3i(x, y, z)*Voxels.chunk_vec3i
                
                load_chunk(c)
    
    place_player()
    
    var c = get_player_chunk_coord()
    print(c)
    var vox = all_chunks[c]
    add_child(vox)
    vox.global_position = c
    
    vox.process_and_remesh()
    vox.accept_remesh()
    chunks_meshed += 1
    
    chunks_loaded[c] = vox
    
    start_music_playlist()

func start_music_playlist():
    var playlist = [
        preload("res://bgm/main theme.ogg"),
        preload("res://bgm/cold theme.ogg"),
        preload("res://bgm/hot theme.ogg"),
    ]
    while true:
        await get_tree().create_timer(30.0).timeout
        var next = playlist.pop_front()
        playlist.push_back(next)
        $BGMPlayer.stream = next
        if !$BGMPlayer.playing:
            $BGMPlayer.playing = true
        await $BGMPlayer.finished
    
var VoxelMesher = preload("res://voxels/VoxelMesher.cs").new()

func place_player():
    var attempts = 2000
    seed(world_seed)
    
    var land_height = -1
    var good_x = 0
    var good_z = 0
    var _range = _spawn_range + 0.5
    for _i in attempts:
        var z = randi_range(-Voxels.chunk_size_h*_range, Voxels.chunk_size_h*_range)
        var x = randi_range(-Voxels.chunk_size_h*_range, Voxels.chunk_size_h*_range)
        
        land_height = -1000
        #var found_air = false
        
        var world_top = (range_v_up+0.5)*Voxels.chunk_size_v
        var start_h = Voxels.GlobalGenerator.pub_height_at_global(Vector3i(x, 0, z))
        
        if start_h < Voxels.GlobalGenerator._sea_level:
            continue
        
        for y in range(start_h-1, world_top):
            var vox = get_block(Vector3i(x, y, z))
            #var type = VoxelMesher.vox_get_type_pub(vox)
            if vox == 0:
                good_x = x
                good_z = z
                #found_air = true
                land_height = y-1
                break
        
    
    if land_height == -1000:
        print("failed to position player")
        land_height = 24
    
    var player = preload("res://player/player.tscn").instantiate()
    add_child(player)
    player.force_update_transform()
    player.global_position = Vector3(good_x, land_height + 0.5, good_z)
    player.cached_position = player.global_position
    print("added player at ", player.global_position)

static func posmodvi(a : Vector3i, b : Vector3i):
    a.x = posmod(a.x, b.x)
    a.y = posmod(a.y, b.y)
    a.z = posmod(a.z, b.z)
    return a

static func get_chunk_coord(coord) -> Vector3i:
    if coord is Vector3:
        coord = Vector3i((coord).round())
    var leftover = posmodvi(coord + Voxels.chunk_vec3i/2, Voxels.chunk_vec3i)
    var chunk_coord = coord - leftover + Voxels.chunk_vec3i/2
    return chunk_coord

var dirty_chunk_mutex = Mutex.new()
var dirty_chunks = []

var new_chunk_mutex = Mutex.new()
var new_chunks = []

func dirtify_world():
    var player = DummySingleton.get_tree().get_first_node_in_group("Player")
    if player:
        player.refresh_probe()

func get_block_with_origin(coord : Vector3) -> int:
    return get_block(Vector3i(coord.round()) + world_origin)

func get_block(coord : Vector3i) -> int:
    var chunk_coord = World.get_chunk_coord(coord)
    if chunk_coord in all_chunks:
        var chunk = all_chunks[chunk_coord]
        return chunk.get_block(coord)
    return 0

func set_block_with_origin(coord : Vector3, id : int):
    set_block(Vector3i(coord.round()) + world_origin, id)

func set_block(coord : Vector3i, id : int):
    var chunk_coord = World.get_chunk_coord(coord)
    if chunk_coord in chunks_loaded:
        var chunk = chunks_loaded[chunk_coord]
        chunk.set_block(coord, id)
        
        dirty_chunk_mutex.lock()
        print("dirtying chunk...")
        dirty_chunks.push_back(chunk)
        dirty_chunk_mutex.unlock()
            
        var c = coord - chunk_coord + Voxels.chunk_vec3i/2
        if (c.x == 0 or c.y == 0 or c.z == 0
            or c.x+1 == Voxels.chunk_size_h or c.y+1 == Voxels.chunk_size_v or c.z+1 == Voxels.chunk_size_h):
            var neighbor_chunk_coords = {}
            chunk_table_mutex.lock()
            for y in range(-1, 2):
                for z in range(-1, 2):
                    for x in range(-1, 2):
                        var c2 = Vector3i(x, y, z) + coord
                        var chunk2_coord = World.get_chunk_coord(c2)
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

@export var base_noise : Noise = null

static var setup_time = 0.0

var time_alive = 0.0
func _process(delta : float) -> void:
    $FPS.text = (
        "FPS: %s\nchunks to load: %s\nchunks loaded: %s\nchunks generated: %s\nchunks at least partly generated: %s\nchunks meshed: %s\ntime spent meshing: %s\ntime spent generating terrain: %s\ntime spent decorating world: %s\ntime spent accepting meshes: %s\nload and setup time: %s" %
        [Engine.get_frames_per_second(),
        world_work_num_unloaded,
        chunks_loaded.size(),
        generated_chunks.size(),
        all_chunks.size(),
        chunks_meshed,
        snapped(VoxelMesher.pub_get_meshing_time(), 0.01),
        snapped(Voxels.GlobalGenerator.pub_get_terrain_time(), 0.01),
        snapped(Voxels.GlobalGenerator.pub_get_decorate_time(), 0.01),
        snapped(Voxels.accept_time, 0.01),
        snapped(setup_time, 0.01),
        ]
    )
    
    if do_threading:
        if !world_work_thread.is_started():
            print("starting world work thread")
            world_work_thread.start(dynamic_world_loop)
        
        if !remesh_work_thread.is_started():
            print("starting remesh work thread")
            remesh_work_thread.start(remesh_work_loop)
        
        if !first_time_mesh_work_thread.is_started():
            print("starting remesh work thread")
            first_time_mesh_work_thread.start(first_time_mesh_work_loop)
    else:
        dynamic_world_oneshot()
        remesh_work_oneshot()
    
    if time_alive >= 0:
        time_alive += delta
        if world_work_num_unloaded == 0 and dirty_chunks.size() == 0:
            print("fully loaded!", time_alive)
            time_alive = -100.0
    
    apply_chunks_offset()
    
    
var remesh_work_thread = Thread.new()

var first_time_mesh_work_thread = Thread.new()

func __print(d): print(d)

func trigger_remesh_accept(chunks):
    for chunk in chunks:
        chunk.accept_remesh()

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
            trigger_save(dirty_list_copy.duplicate())
            trigger_remesh_accept.call_deferred(dirty_list_copy)
            dirtify_world.call_deferred()
        
        semaphore.post.call_deferred()
        semaphore.wait()

var first_time_mesh_semaphore = Semaphore.new()
func first_time_mesh_work_loop():
    while true:
        var chunk_count = 0
        var start_time = Time.get_ticks_usec()/1000000.0
        
        new_chunk_mutex.lock()
        if new_chunks.size() > 0:
            var chunk = new_chunks.pop_front()
            new_chunk_mutex.unlock()
            chunk.process_and_remesh()
            chunk.accept_remesh.call_deferred()
            chunk_count += 1
        else:
            new_chunk_mutex.unlock()
        
        var end_time = Time.get_ticks_usec()/1000000.0
        var time = end_time - start_time
        if chunk_count > 0:
            chunks_per_second_estimate = max(10, chunk_count/float(time))
        
        first_time_mesh_semaphore.wait()

func remesh_work_oneshot():
    var dirty_list_copy = dirty_chunks.duplicate()
    dirty_chunks = []
    
    if new_chunks.size() > 0:
        for chunk in new_chunks:
            chunk.process_and_remesh()
            chunk.accept_remesh()
        new_chunks = []
        dirtify_world()
    
    if dirty_list_copy.size() > 0:
        for chunk in dirty_list_copy:
            chunk.process_and_remesh()
            chunk.accept_remesh()
        trigger_save(dirty_list_copy)
        dirtify_world()

var world_work_thread = Thread.new()
var world_work_wait_signal = Mutex.new()
var world_work_num_unloaded = -1

func dynamic_world_oneshot():
    var player_chunk = get_player_chunk_coord()
    var facing_dir = get_player_facing_dir()
    
    dynamically_unload_world(player_chunk)
    
    var loaded_info = dynamically_load_world(player_chunk, facing_dir)
    if loaded_info:
        add_all([loaded_info])

var chunks_per_second_estimate = 50

func dynamic_world_loop():
    var semaphore = Semaphore.new()
    var work_frame = Engine.get_process_frames()
    var chunks_to_add_and_load = []
    var first_wait = false
    while true:
        new_chunk_mutex.lock()
        var new_chunk_count = new_chunks.size()
        new_chunk_mutex.unlock()
        
        # wait until next frame if there are too many unmeshed chunks loaded ahead of time (one 20fps frame worth)
        if new_chunk_count > chunks_per_second_estimate*0.05:
            #if !first_wait:
            #    print("waiting till next frame... (estimate ", chunks_per_second_estimate, ")")
            first_wait = true
            semaphore.post.call_deferred()
            semaphore.wait()
            continue
        first_wait = false
        
        var player_chunk = get_player_chunk_coord()
        var facing_dir = get_player_facing_dir()
        
        dynamically_unload_world(player_chunk)
        
        var loaded_info = dynamically_load_world(player_chunk, facing_dir)
        
        if loaded_info:
            chunks_to_add_and_load.push_back(loaded_info)
            inform_new_chunks([loaded_info])
        
        var current_frame = Engine.get_process_frames()
        if !loaded_info or current_frame != work_frame:
            if chunks_to_add_and_load.size() > 0:
                add_all.call_deferred(chunks_to_add_and_load)
                chunks_to_add_and_load = []
            else:
                semaphore.post.call_deferred()
                semaphore.wait()
            work_frame = current_frame
        

# 128 = 4 chunk distance
# 256 = 8 chunk distance
# 512 = 16 chunk distance
# 768 = 24 chunk distance
# 1024 = 32 chunk distance

static var _DummyGen = preload("res://voxels/VoxelGenerator.cs").new()
#static var range_h = 96/Voxels.chunk_size_h/2
static var range_h = 512/_DummyGen._chunk_size_h/2
#static var range_h = 256/Voxels.chunk_size_h/2
static var range_v_down = 64/_DummyGen._chunk_size_v
#static var range_v_down = 64/Voxels.chunk_size
static var range_v_up = 256/_DummyGen._chunk_size_v
#static var range_v_up = 64/Voxels.chunk_size

static var _spawn_range = min(range_h, 3)

var _find_chunks_prev_player_chunk_2 = null
const unload_threshold = 3.5 # do not lower below 3.5. FIXME: make this based on terrain_load_buffer somehow
func dynamically_unload_world(player_chunk):
    #print("range: ", range_v_down, " ", range_v_up)
    var force_unload = Input.is_action_just_pressed("force_unload")
    if _find_chunks_prev_player_chunk_2 != player_chunk or force_unload:
        _find_chunks_prev_player_chunk_2 = player_chunk
        
        # FIXME move the loaded, meshed neighbors of unloaded chunks into "unmeshed" state
        chunk_table_mutex.lock()
        chunk_loaded_table_mutex.lock()
        
        var _found_unloadable_chunks = []
        for coord in all_chunks:
            var c_local = coord - player_chunk
            if Vector2(c_local.x, c_local.z).length() > (range_h+0.5 + unload_threshold)*Voxels.chunk_size_h:
                _found_unloadable_chunks.push_back(coord)
            elif force_unload and (c_local.x != 0 or c_local.z != 0):
                _found_unloadable_chunks.push_back(coord)
        
        var unload_list = []
        for coord in _found_unloadable_chunks:
            var chunk = all_chunks[coord]
            all_chunks.erase(coord)
            if coord in chunks_loaded:
                chunks_loaded.erase(coord)
            if coord in generated_chunks:
                generated_chunks.erase(coord)
            
            unload_list.push_back(chunk)
        
        chunk_loaded_table_mutex.unlock()
        chunk_table_mutex.unlock()
        
        do_unload.call_deferred(unload_list)

func do_unload(chunk_list : Array):
    chunk_table_mutex.lock()
    for chunk in chunk_list:
        if chunk.is_inside_tree():
            chunk.get_parent().remove_child(chunk)
        chunk.queue_free()
    chunk_table_mutex.unlock()

var _find_chunks_prev_player_chunk = null
var _find_chunks_prev_facing_dir = Vector3.FORWARD
var _find_chunks_unloaded_coords = []
func find_chunk_load_queue(player_chunk : Vector3i, facing_dir : Vector3):
    var dot = facing_dir.dot(_find_chunks_prev_facing_dir)
    var force_unload = Input.is_action_just_pressed("force_unload")
    if _find_chunks_prev_player_chunk != player_chunk or dot < 0.95 or force_unload:
        #print("finding chunk load")
        _find_chunks_prev_player_chunk = player_chunk
        _find_chunks_prev_facing_dir = facing_dir
        
        _find_chunks_unloaded_coords = []
        chunk_loaded_table_mutex.lock()
        for y in range(-range_v_down, range_v_up+1):
            for z in range(-range_h, range_h+1):
                for x in range(-range_h, range_h+1):
                    if Vector2i(x, z).length() > range_h+0.5:
                        continue
                    var c = Vector3i(x, y, z) * Voxels.chunk_vec3i
                    
                    var c2 = c - player_chunk*Vector3i(0, 1, 0)
                    var c2_aux = c2/Voxels.chunk_vec3i
                    
                    var c_global = c + player_chunk*Vector3i(1, 0, 1)
                    
                    if c_global in chunks_loaded:
                        continue
                    
                    var h_delta_immediate = abs(c2_aux.y) + abs(c2_aux.z) + abs(c2_aux.x)
                    var h_delta_box = max(max(abs(c2_aux.y), abs(c2_aux.z)), abs(c2_aux.x))
                    
                    var h_dist = (c*Vector3i(1, 0, 1)).length()
                    var score = c2.length()
                    
                    if h_delta_immediate <= 1:
                        score -= 2000.0
                    elif h_delta_box <= 1:
                        score -= 1000.0
                    
                    if score > 30.0 and h_dist > 30.0:
                        var cn = c2/score
                        if cn.dot(facing_dir) < -0.5:
                            score += 200.0
                        if cn.dot(facing_dir) < 0.0:
                            score += 100.0
                        elif cn.dot(facing_dir) < 0.5:
                            score += 20.0
                    
                    _find_chunks_unloaded_coords.push_back([-score, c_global])
    
        chunk_loaded_table_mutex.unlock()
        
        world_work_num_unloaded = _find_chunks_unloaded_coords.size()
        _find_chunks_unloaded_coords.sort()
    
    return _find_chunks_unloaded_coords

var world_origin = Vector3i()

func apply_chunks_offset():
    var player_chunk_coord = get_player_chunk_coord() * Vector3i(1, 0, 1)
    # FIXME: add some kind of hysterisis, and also make it less granular, so it only changes every dozen or hundred chunks or w/e
    # BUT: for now, leave it as-is, so that world origin bugs are easier to identify early
    if player_chunk_coord != world_origin:
        var diff = player_chunk_coord - world_origin
        world_origin = player_chunk_coord
        RenderingServer.global_shader_parameter_set("world_origin", world_origin)
        print("new world offset: ", world_origin)
        var player = DummySingleton.get_tree().get_first_node_in_group("Player")
        player.global_position -= Vector3(diff)
        player.cached_position -= Vector3(diff)
        player.force_update_transform()
        
        chunk_loaded_table_mutex.lock()
        for chunk_coord in chunks_loaded:
            var chunk = chunks_loaded[chunk_coord]
            if chunk.is_inside_tree():
                chunk.global_position = chunk.chunk_position - world_origin
                chunk.inform_moved()
        chunk_loaded_table_mutex.unlock()

func get_player_chunk_coord(no_y : bool = false):
    var player = DummySingleton.get_tree().get_first_node_in_group("Player")
    var player_chunk = World.get_chunk_coord(player.cached_position)
    player_chunk += world_origin
    if no_y:
        player_chunk.y = 0
    return player_chunk

func get_player_facing_dir():
    var player = DummySingleton.get_tree().get_first_node_in_group("Player")
    return player.cached_facing_dir

func dynamically_load_world(player_chunk, facing_dir):
    var unloaded_coords = find_chunk_load_queue(player_chunk, facing_dir)
    if unloaded_coords.size() > 0:
        var c_coord = unloaded_coords.pop_back()[1]
        world_work_num_unloaded = unloaded_coords.size()
        
        if c_coord in chunks_unloaded:
            var chunk = chunks_unloaded[c_coord]
            chunk_loaded_table_mutex.lock()
            chunks_loaded[c_coord] = chunk
            chunks_unloaded.erase(c_coord)
            chunk_loaded_table_mutex.unlock()
            return [chunk]
        else:
            var chunk = load_chunk(c_coord)
            
            chunk_table_mutex.lock()
            
            for y in range(-1, 2):
                if c_coord.y/Voxels.chunk_size_v + y < -range_v_down or c_coord.y/Voxels.chunk_size_v + y > range_v_up:
                    continue
                for z in range(-1, 2):
                    for x in range(-1, 2):
                        var c2_coord = Vector3i(x, y, z) * Voxels.chunk_vec3i + c_coord
                        load_chunk(c2_coord)
            
            chunk_table_mutex.unlock()
            #chunk.process_and_remesh()
            
            chunk_loaded_table_mutex.lock()
            chunks_loaded[c_coord] = chunk
            chunk_loaded_table_mutex.unlock()
            
            return [chunk, c_coord]
    return null

func inform_new_chunks(chunks):
    var just_chunks = []
    for chunk in chunks:
        if is_instance_valid(chunk[0]):
            var coord = chunk[0].chunk_position
            if not coord in f_index_table:
                just_chunks.push_back(chunk[0])
    
    new_chunk_mutex.lock()
    new_chunks.append_array(just_chunks)
    chunks_meshed += just_chunks.size()
    new_chunk_mutex.unlock()
    first_time_mesh_semaphore.post()
    
    trigger_save(just_chunks)

func add_all(chunks):
    if chunks.size() == 0:
        return
    for chunk in chunks:
        if is_instance_valid(chunk[0]):
            if chunk.size() == 2:
                initial_add_vox(chunk[0], chunk[1])
            else:
                add_child(chunk[0])
                chunk[0].global_position = chunk[0].chunk_position - world_origin
                chunk[0].inform_moved()
    
    dirtify_world()

func initial_add_vox(vox : Node3D, coord : Vector3i):
    add_child(vox)
    vox.global_position = coord - world_origin
    
    vox.force_update_transform()
    vox.accept_remesh()

extends Node3D
class_name World

var chunk_table_mutex = Mutex.new()
var chunks_unloaded = {}
var chunks_loaded = {}
var all_chunks = {}

func load_chunk(coord = Vector3()):
    var vox = Voxels.new()
    add_child(vox)
    vox.do_generation(coord)
    return vox

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
    var range = 0
    for y in range(-1, 2):
        for z in range(-range, range+1):
            for x in range(-range, range+1):
                var c = Vector3(x, y, z)*Voxels.chunk_size
                
                var vox = load_chunk(c)
                
                chunk_table_mutex.lock()
                all_chunks[c] = vox
                chunk_table_mutex.unlock()
                
                vox.initial_remesh(c == Vector3())
                chunks_loaded[c] = vox
                

static func get_chunk_coord(coord):
    var chunk_coord = ((coord + Vector3.ONE*0.5) / Voxels.chunk_size).round() * Voxels.chunk_size
    return chunk_coord

func set_block(coord : Vector3, id : int):
    var chunk_coord = World.get_chunk_coord(coord)
    if chunk_coord in chunks_loaded:
        chunks_loaded[chunk_coord].set_block(coord, id)
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
            for neighbor_chunk in neighbor_chunk_coords.values():
                neighbor_chunk.set_block(coord, -1)
            
        print(c)
    else:
        print("no chunk")

@export var base_noise : Noise = null

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta : float) -> void:
    $FPS.text = str(Engine.get_frames_per_second())
    
    dynamically_load_world()

func dynamically_load_world():
    var range_h = 128/Voxels.chunk_size/2
    var range_v = 64/Voxels.chunk_size/2
    
    var player = get_tree().get_first_node_in_group("Player")
    var player_chunk = get_chunk_coord(player.global_position)
    player_chunk.y = 0.0
    
    var unloaded_coords = []
    for y in range(-range_v, range_v+1):
        for z in range(-range_h, range_h+1):
            for x in range(-range_h, range_h+1):
                if Vector2(x, z).length() > range_h-0.5:
                    continue
                var c = Vector3(x, y, z) * Voxels.chunk_size
                
                var c_global = c + player_chunk
                
                if c_global in chunks_loaded:
                    continue
                
                unloaded_coords.push_back(c)
    
    unloaded_coords.sort_custom(func (a, b): return a.length() < b.length())
    
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
    
    pass

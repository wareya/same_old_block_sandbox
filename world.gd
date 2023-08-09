extends Node3D
class_name World

static var chunk_size = 16

var chunks_unloaded = {}
var chunks_loaded = {}
var all_chunks = {}

func load_chunk(coord = Vector3()):
    var vox = Voxels.new()
    add_child(vox)
    vox.do_generation(coord)
    chunks_loaded[vox.global_position] = vox
    all_chunks[vox.global_position] = vox

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
    load_chunk(Vector3())
    load_chunk(Vector3(chunk_size, 0.0, 0.0))
    load_chunk(Vector3(0.0, 0.0, chunk_size))
    pass # Replace with function body.

static func get_chunk_coord(coord):
    var chunk_coord = ((coord + Vector3.ONE*0.5) / chunk_size).round() * chunk_size
    return chunk_coord

func set_block(coord : Vector3, id : int):
    var chunk_coord = World.get_chunk_coord(coord)
    if chunk_coord in chunks_loaded:
        chunks_loaded[chunk_coord].set_block(coord, id)
    else:
        print("no chunk")

@export var base_noise : Noise = null

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta : float) -> void:
    $FPS.text = str(Engine.get_frames_per_second())
    pass

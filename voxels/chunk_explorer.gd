extends Control

var gen = Voxels.GlobalGenerator
static var noise = preload("res://voxels/Noise.tres")

var chunk_size_modifier = 1
func build_chunk_texrect(vec : Vector2i):
    #var image = Image.create(chunk_size, chunk_size, true, Image.FORMAT_RGBA8)
    #
    #var sea_level = gen._sea_level
    #
    #for z in Voxels.chunk_size_h:
    #    var z2 = z * chunk_size if is_fast_mode() else z
    #    for x in Voxels.chunk_size_h:
    #        var x2 = x * chunk_size if is_fast_mode() else x
    #        var data = gen.pub_true_height_at_global_3(Vector3i(x2 + vec.x + offset, 0, z2 + vec.y + offset))
    #        var h = data[0]
    #        var c : Color
    #        
    #        if h >= sea_level:
    #            c = Color.LIME_GREEN*0.7
    #        else:
    #            c = Color.SADDLE_BROWN
    #        
    #        if data[1] > h:
    #            c = Color.DIM_GRAY
    #        elif data[2] > h:
    #            c = Color.TAN
    #        if h < sea_level:
    #            c = c.blend(Color(0.2, 0.7, 1.0, 0.5))
    #        
    #        var level = float(h%8)/8.0
    #        level = lerp(1.0, 0.8, level)
    #        c = c * level
    #        c.a = 1.0
    #        image.set_pixel(x, z, c)
    
    var image = gen.pub_generate_image(vec, get_subsampling())
    
    var chunk_size = Voxels.chunk_size_h * chunk_size_modifier * get_subsampling()
    var tex = ImageTexture.create_from_image(image)
    var rect = TextureRect.new()
    rect.texture = tex
    rect.stretch_mode = TextureRect.STRETCH_SCALE
    add_child(rect)
    var offset = -chunk_size/2 - (int(get_subsampling())-1)/2
    rect.position.x = vec.x + offset
    rect.position.y = vec.y + offset
    rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    rect.size.x = chunk_size
    rect.size.y = chunk_size
    
    return rect

func _ready() -> void:
    noise.seed = $CanvasLayer/Seed.value
    gen._Set_Noiser(noise)
    get_loading()

var loaded_chunks = {}


var loading_chunks = []
var last_xform = null
func get_loading():
    var xform = get_viewport_transform().affine_inverse()
    if xform == last_xform:
        return
    last_xform = xform
    var rect = get_viewport_rect()
    
    var start = xform * rect.position
    var end = xform * rect.end
    
    var chunk_size = Voxels.chunk_size_h * chunk_size_modifier * get_subsampling()
    
    start = (start/chunk_size).floor()
    end = (end/chunk_size).ceil()
    
    var c = (start+end)/2
    
    var limit = 100
    if end.x - start.x > limit:
        start.x = c.x-limit/2
        end.x = start.x + limit
    if end.y - start.y > limit:
        start.y = c.y-limit/2
        end.y = start.y + limit
    
    loading_chunks = []
    for z in range(start.y, end.y + 1):
        for x in range(start.x, end.x + 1):
            var coord = Vector2i(x, z)
            var len2 = (coord - Vector2i(c)).length_squared()
            
            coord *= chunk_size
            if coord in loaded_chunks:
                continue
            
            loading_chunks.push_back([-len2, coord])
    
    loading_chunks.sort()

var dragging = false
func _input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.is_released() && event.button_index == 4:
            $Camera2D.zoom *= pow(2.0, 0.25)
        if event.is_released() && event.button_index == 5:
            $Camera2D.zoom /= pow(2.0, 0.25)
        if event.button_index == 3:
            dragging = event.is_pressed()
    elif event is InputEventMouseMotion:
        if dragging:
            $Camera2D.position -= event.relative / $Camera2D.zoom

func get_subsampling():
    return $CanvasLayer/Subsample.value

var last_subsample = 1
var last_seed = 0
func _process(delta : float) -> void:
    noise.seed = $CanvasLayer/Seed.value
    if noise.seed != last_seed:
        gen._Set_Noiser(noise)
        last_seed = noise.seed
        
        for coord in loaded_chunks:
            var texrect = loaded_chunks[coord]
            remove_child(texrect)
        loaded_chunks = {}
        loading_chunks = []
        last_xform = null
    
    if get_subsampling() != last_subsample:
        for coord in loaded_chunks:
            var texrect = loaded_chunks[coord]
            remove_child(texrect)
        loaded_chunks = {}
        loading_chunks = []
        
        last_xform = null
        last_subsample = get_subsampling()
    get_loading()
    
    var start_time = Time.get_ticks_usec()
    while loading_chunks.size() > 0:
        var coord = loading_chunks.pop_back()[1]
        var texrect = build_chunk_texrect(coord)
        loaded_chunks[coord] = texrect
        var time = Time.get_ticks_usec()
        if (time - start_time)/1000000.0 > 0.016:
            break
    pass

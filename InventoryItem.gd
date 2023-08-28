@tool
extends NinePatchRect
class_name InventoryItem

var icon : Icon = null
func _ready():
    texture = preload("res://art/ui_a.png")
    patch_margin_top = 12
    patch_margin_left = 12
    patch_margin_right = 12
    patch_margin_bottom = 12
    
    icon = Icon.new()
    add_child(icon)
    icon.anchor_right = 1
    icon.anchor_bottom = 1

func set_id(id : int):
    icon.id = id

func set_active(is_active : bool):
    if is_active:
        texture = preload("res://art/ui_b.png")
    else:
        texture = preload("res://art/ui_a.png")

@export var count : int = 1
@export var max_count : int = 1

class Icon extends Control:
    var id : int = 1

    static var mesher = preload("res://voxels/VoxelMesher.cs").new()

    func make_mesh(vox : int) -> ArrayMesh:
        var _mesh = ArrayMesh.new()
        var tool = SurfaceTool.new()
        tool.begin(Mesh.PRIMITIVE_TRIANGLES)
        var verts = [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.0, 1.0), Vector2(1.0, 1.0)]
        var colors = [Color.BLUE, Color.RED, Color.GREEN, Color.YELLOW]
        
        var cos30 = sqrt(0.75) # (yes)
        var mats = [
            Transform2D(Vector2(-cos30,  0.5), Vector2(cos30, 0.5), Vector2(0.0, -0.5)),
            Transform2D(Vector2(cos30,  0.5), Vector2(0.0, 1), Vector2(-cos30/2.0, 0.25)),
            Transform2D(Vector2(cos30, -0.5), Vector2(0.0, 1), Vector2( cos30/2.0, 0.25)),
        ]
        var brightness = [1.0, 0.75, 0.5]
        
        var render_mode = 0
        if mesher.vox_get_type_pub(vox) == 3:
            render_mode = 1
        
        if render_mode == 0:
            for d in [0, 1, 2]:
                var index = mesher.get_voxel_info(vox)[0 if d == 0 else 2]
                if !mesher.pub_vox_get_bitmaskless(vox):
                    index += 1
                
                for i in [0, 1, 2, 2, 1, 3]:
                    tool.set_uv(verts[i])
                    tool.set_color(Color((index >> 8)/255.0, (index&0xFF)/255.0, 0, brightness[d]))
                    var vert : Vector2 = Vector2(verts[i].x, verts[i].y)
                    var mat : Transform2D = mats[d]
                    vert -= Vector2(0.5, 0.5)
                    vert = mat * vert
                    vert *= 0.401
                    vert += Vector2(0.5, 0.5)
                    tool.add_vertex(Vector3(vert.x, vert.y, 0.0))
        else:
            var index = mesher.get_voxel_info(vox)[0]
            if !mesher.pub_vox_get_bitmaskless(vox):
                index += 1
            
            for i in [0, 1, 2, 2, 1, 3]:
                tool.set_uv(verts[i])
                tool.set_color(Color((index >> 8)/255.0, (index&0xFF)/255.0, 0, 1.0))
                var vert : Vector2 = Vector2(verts[i].x, verts[i].y)
                vert -= Vector2(0.5, 0.5)
                vert *= 0.7
                vert += Vector2(0.5, 0.5)
                tool.add_vertex(Vector3(vert.x, vert.y, 0.0))
        
        tool.commit(_mesh)
        return _mesh

    var mesh : ArrayMesh = null

    func _ready():
        material = preload("res://voxels/VoxMatPreview.tres")
    
    var prev_id = -1
    func _process(_delta : float):
        if id != prev_id:
            prev_id = id
        mesh = make_mesh(id)
        queue_redraw()

    func _draw() -> void:
        if mesh == null:
            return
        var rid = get_canvas_item()
        var mesh_rid = mesh.get_rid()
        RenderingServer.canvas_item_add_mesh(rid, mesh_rid, Transform2D.IDENTITY.scaled(get_rect().size))

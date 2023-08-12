@tool
extends NinePatchRect

@export var render_mode : int = 0 # 0: voxel, 1: just the sprite
@export var id : int = 1
@export var count : int = 1
@export var max_count : int = 1

static func make_mesh() -> ArrayMesh:
    var _mesh = ArrayMesh.new()
    var tool = SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
    tool.set_color(Color.BLUE)
    tool.add_vertex(Vector3(0.0, 0.0, 0.0))
    tool.set_color(Color.RED)
    tool.add_vertex(Vector3(1.0, 0.0, 0.0))
    tool.set_color(Color.GREEN)
    tool.add_vertex(Vector3(0.0, 1.0, 0.0))
    tool.set_color(Color.YELLOW)
    tool.add_vertex(Vector3(1.0, 1.0, 0.0))
    tool.commit(_mesh)
    return _mesh

static var mesh : ArrayMesh = make_mesh()
static var tex : Texture = preload("res://art/tilemap.png")

func _process(delta: float) -> void:
    pass

func _draw() -> void:
    var rid = get_canvas_item()
    var mesh_rid = mesh.get_rid()
    RenderingServer.canvas_item_add_mesh(rid, mesh_rid, Transform2D.IDENTITY.scaled(get_rect().size))

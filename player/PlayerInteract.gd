extends RayCast3D

# Called when the node enters the scene tree for the first time.
var mesh_child = ArrayMesh.new()
var mesh_instance_child = MeshInstance3D.new()

static var dirs = [Vector3.LEFT, Vector3.RIGHT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]
static var face_verts = [Vector3(0.5, 0.5, -0.5), Vector3(-0.5, 0.5, -0.5), Vector3(0.5, -0.5, -0.5), Vector3(-0.5, -0.5, -0.5)]

func _ready() -> void:
    var verts = PackedVector3Array()
    
    for dir in dirs:
        var ref_dir = Vector3.UP if not dir.abs() == Vector3.UP else Vector3.LEFT
        var xform = Transform3D.IDENTITY.looking_at(dir, ref_dir)
        
        var asdf = 1.0/32.0
        
        for info in [[0.0, 1.0, 0.0, asdf], [0.0, 1.0, 1.0-asdf, 1.0], [0.0, asdf, asdf, 1.0-asdf], [1.0-asdf, 1.0, asdf, 1.0-asdf]]:
            var mini_verts = []
            for i in 4:
                var x = lerp(face_verts[0].x, face_verts[3].x, info[i%2])
                var y = lerp(face_verts[0].y, face_verts[3].y, info[i/2+2])
                mini_verts.push_back(xform * Vector3(x, y, -0.5))
        
            for i in [0, 1, 2, 2, 1, 3]:
                verts.push_back(mini_verts[i])
    
    var arrays = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = verts
    mesh_child.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    
    mesh_instance_child.mesh = mesh_child
    
    add_child(mesh_instance_child)
    mesh_instance_child.visible = false
    
    var mat = StandardMaterial3D.new()
    #mat.albedo_color = Color(0.5, 0.5, 0.5, 2.0)
    mat.albedo_color = Color(0.0, 0.0, 0.0, 0.5)
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
    mesh_instance_child.material_override = mat

@onready var world : World = DummySingleton.get_tree().get_first_node_in_group("World")

func _input(event: InputEvent) -> void:
    if event is InputEventKey:
        if event.pressed and event.keycode == KEY_P:
            print_orphan_nodes()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta : float) -> void:
    force_raycast_update()
    
    if is_colliding():
        var delete_point = (get_collision_point() - get_collision_normal()*0.01).round()
        var build_point = delete_point + get_collision_normal()
        mesh_instance_child.visible = true
        mesh_instance_child.global_position = delete_point
        mesh_instance_child.global_rotation = Vector3()
        mesh_instance_child.scale = Vector3.ONE * 1.01
        
        if Input.is_action_just_pressed("m1"):
            world.set_block_with_origin(delete_point, 0)
        if Input.is_action_just_pressed("m2"):
            world.set_block_with_origin(build_point, 1)
    else:
        mesh_instance_child.visible = false
    #if Input.is_action_just_pressed("m1"):
    #    
    pass

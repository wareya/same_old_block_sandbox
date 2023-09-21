extends Control
func _ready() -> void:
    $CenterContainer/VBoxContainer/Button.pressed.connect(func():
        $CenterContainer.hide()
        $Loading.show()
        await get_tree().process_frame
        await get_tree().process_frame
        get_tree().change_scene_to_file("res://world.tscn")
    )
    $CenterContainer/VBoxContainer/Button2.pressed.connect(func():
        $CenterContainer.hide()
        $Loading.show()
        await get_tree().process_frame
        await get_tree().process_frame
        get_tree().change_scene_to_file("res://voxels/chunk_explorer.tscn")
    )

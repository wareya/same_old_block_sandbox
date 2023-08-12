@tool
extends EditorPlugin

func _enter_tree():
    add_custom_type("ScrollListContainer", "Container", preload("ScrollListContainer.gd"), preload("icon.png"))
    add_custom_type("ScrollGridContainer", "Container", preload("ScrollGridContainer.gd"), preload("icongrid.png"))

func _exit_tree():
    remove_custom_type("ScrollListContainer")
    remove_custom_type("ScrollGridContainer")

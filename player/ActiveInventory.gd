extends ScrollGridContainer

var inventory = [1, 2, 3, 4, 5, 6, 14, 9, 10, 11]
var current_item = 0

var mode = 0 # creative
func use_selected_block():
    if mode == 0:
        return inventory[current_item]
    else:
        # TODO check and reduce count etc
        return inventory[current_item]

func pick_block(vox : int):
    var found = inventory.find(vox)
    if found >= 0:
        current_item = found
    else:
        inventory[current_item] = vox

var icons = []
func _ready() -> void:
    for child in get_children():
        child.queue_free()
    
    for item in inventory:
        var icon = InventoryItem.new()
        add_child(icon)
        icon.set_id(item)
        icons.push_back(icon)
    super._ready()

func _process(delta : float) -> void:
    if Input.is_action_just_released("scroll_up"):
        current_item = (current_item - 1 + inventory.size()) % inventory.size()
    if Input.is_action_just_released("scroll_down"):
        current_item = (current_item + 1) % inventory.size()
    
    var i = 0
    for item in inventory:
        icons[i].set_id(item)
        icons[i].set_active(i == current_item)
        i += 1

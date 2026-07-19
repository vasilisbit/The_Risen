extends Label
## T-0011 inventory readout: shows how many items are in
## SaveManager.owned_weapons, refreshed whenever the save changes.

func _ready() -> void:
	var sm := get_node_or_null("/root/SaveManager")
	if sm:
		sm.game_saved.connect(_refresh)
		sm.game_loaded.connect(_refresh)
	_refresh()


func _refresh() -> void:
	var sm := get_node_or_null("/root/SaveManager")
	var n := 0
	if sm:
		n = (sm.data.get("owned_weapons", []) as Array).size()
	text = "Inventory: %d" % n

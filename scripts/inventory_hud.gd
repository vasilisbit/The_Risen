extends Label
## Corner readout: Flux balance and item count, plus the key that opens the
## full inventory. Flux is shown here because it is now earned during a mission
## (per kill) rather than only spent at the vendor, so it has to be visible
## while you are earning it.

func _ready() -> void:
	var sm := get_node_or_null("/root/SaveManager")
	if sm:
		sm.game_saved.connect(_refresh)
		sm.game_loaded.connect(_refresh)
		if sm.has_signal("flux_changed"):
			sm.flux_changed.connect(_on_flux_changed)
	_refresh()


func _on_flux_changed(_total: int) -> void:
	_refresh()


func _refresh() -> void:
	var sm := get_node_or_null("/root/SaveManager")
	var items := 0
	var flux := 0
	if sm:
		items = (sm.data.get("owned_weapons", []) as Array).size() \
			+ (sm.data.get("owned_armor", []) as Array).size()
		flux = int(sm.data.get("flux_currency", 0))
	text = "Flux: %d      Items: %d   [I]" % [flux, items]

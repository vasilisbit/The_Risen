extends RayCast3D
## Debug interactor: casts forward from the camera crosshair. On the "interact"
## action it acts on whatever is under the crosshair:
##   - a body in group "vendor"        -> opens the vendor shop UI (T-0005)
##   - a body in group "mission_sphere" -> prints "Mission Selected: <planet>"
##                                         and emits mission_selected (T-0003)
## No mission level loading yet (that arrives with the GameState autoload).

signal mission_selected(mission: String)


func _unhandled_input(event: InputEvent) -> void:
	# is_action_pressed() on the event is true only on the press edge (not
	# on hold/echo), so rapid clicking fires once per click.
	if event.is_action_pressed("interact"):
		try_interact()


## Force-update the ray and act on the target under the crosshair.
func try_interact() -> void:
	force_raycast_update()
	if not is_colliding():
		return
	var target := get_collider()
	if target == null:
		return
	if target.is_in_group("vendor"):
		var shop := get_tree().get_first_node_in_group("vendor_shop")
		if shop and shop.has_method("open"):
			shop.open()
		return
	if target.is_in_group("mission_sphere"):
		var mission := String(target.name).trim_suffix("Sphere")
		print("Mission Selected: %s" % mission)
		mission_selected.emit(mission)

extends RayCast3D
## T-0003 debug interactor: casts forward from the camera crosshair. On the
## "interact" action, selects the mission sphere under the crosshair, prints it,
## and emits `mission_selected`. No level loading yet — that arrives with the
## mission-transition system (GameState autoload, later milestone).
##
## A valid target is any body in the "mission_sphere" group; the mission name is
## the node name with the "Sphere" suffix stripped (EarthSphere -> "Earth").

signal mission_selected(mission: String)


func _unhandled_input(event: InputEvent) -> void:
	# is_action_pressed() on the event is true only on the press edge (not
	# on hold/echo), so rapid clicking fires once per click — no double-fire.
	if event.is_action_pressed("interact"):
		try_select()


## Force-update the ray; if a mission sphere is under the crosshair, print +
## emit its mission name. Returns the mission name, or "" when nothing valid
## is targeted.
func try_select() -> String:
	force_raycast_update()
	if not is_colliding():
		return ""
	var target := get_collider()
	if target == null or not target.is_in_group("mission_sphere"):
		return ""
	var mission := String(target.name).trim_suffix("Sphere")
	print("Mission Selected: %s" % mission)
	mission_selected.emit(mission)
	return mission

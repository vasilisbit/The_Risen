extends RayCast3D
## Debug interactor: casts forward from the camera crosshair. On the "interact"
## action it acts on whatever is under the crosshair:
##   - a body in group "vendor"        -> opens the vendor shop UI (T-0005)
##   - a body in group "mission_sphere" -> selects the mission and, if a level
##                                         scene exists and is unlocked, loads it.

signal mission_selected(mission: String)

## Mission planet -> level scene. Only Earth is built so far; others fall through
## to a debug print until their levels exist.
const MISSION_SCENES := {
	"Earth": "res://scenes/missions/earth/earth.tscn",
}


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
		_launch_mission(mission)


## Load the mission's level scene if it exists and the mission is unlocked.
func _launch_mission(mission: String) -> void:
	var sm := get_node_or_null("/root/SaveManager")
	if sm and sm.has_method("is_mission_unlocked") and not sm.is_mission_unlocked(mission):
		print("Mission locked: %s (complete the previous mission first)" % mission)
		return
	if MISSION_SCENES.has(mission):
		var gs := get_node_or_null("/root/GameState")
		if gs and gs.has_method("transition_to"):
			gs.transition_to(MISSION_SCENES[mission])   # fade to black
		else:
			get_tree().change_scene_to_file(MISSION_SCENES[mission])
	else:
		print("Mission not implemented yet: %s" % mission)

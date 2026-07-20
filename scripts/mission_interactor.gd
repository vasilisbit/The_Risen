extends RayCast3D
## Debug interactor: casts forward from the camera crosshair. On the "interact"
## action it acts on whatever is under the crosshair:
##   - a body in group "vendor"        -> opens the vendor shop UI (T-0005)
##   - a body in group "mission_sphere" -> selects the mission and, if a level
##                                         scene exists and is unlocked, loads it.

signal mission_selected(mission: String)

## Mission planet -> level scene. All three are built; anything not listed falls
## through to a debug print. Unlock gating is handled by SaveManager.
const MISSION_SCENES := {
	"Earth": "res://scenes/missions/earth/earth.tscn",
	"Mars": "res://scenes/missions/mars/mars.tscn",
	"Venus": "res://scenes/missions/venus/venus.tscn",
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


## Selecting a planet opens the difficulty prompt (T-0027) rather than dropping
## straight into the mission; the prompt calls back here on confirm.
func _launch_mission(mission: String) -> void:
	var sm := get_node_or_null("/root/SaveManager")
	if sm and sm.has_method("is_mission_unlocked") and not sm.is_mission_unlocked(mission):
		_notify("%s is locked — complete %s first." % [mission, _previous_mission(mission)])
		return
	if not MISSION_SCENES.has(mission):
		print("Mission not implemented yet: %s" % mission)
		return
	var prompt := get_tree().get_first_node_in_group("difficulty_select")
	if prompt and prompt.has_method("open"):
		if not prompt.launch_confirmed.is_connected(_start_mission):
			prompt.launch_confirmed.connect(_start_mission)
		prompt.open(mission)
	else:
		_start_mission(mission)          # no prompt in the scene: go directly


## Bottom-left notice in the hub. Falls back to a print if the hub has no
## notice node, so this stays usable from a bare test scene.
func _notify(message: String) -> void:
	var notice := get_tree().get_first_node_in_group("hub_notice")
	if notice and notice.has_method("notify"):
		notice.notify(message)
	else:
		print(message)
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.play_sfx("ui_hover")


## The mission that gates `mission`, for the locked message.
func _previous_mission(mission: String) -> String:
	var sm := get_node_or_null("/root/SaveManager")
	if sm == null or not ("MISSION_ORDER" in sm):
		return "the previous mission"
	var order: Array = sm.MISSION_ORDER
	var idx := order.find(mission)
	return String(order[idx - 1]) if idx > 0 else "the previous mission"


func _start_mission(mission: String) -> void:
	if MISSION_SCENES.has(mission):
		var gs := get_node_or_null("/root/GameState")
		if gs and gs.has_method("transition_to"):
			gs.transition_to(MISSION_SCENES[mission])   # fade to black
		else:
			get_tree().change_scene_to_file(MISSION_SCENES[mission])
	else:
		print("Mission not implemented yet: %s" % mission)

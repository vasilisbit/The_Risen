class_name ExtractionCountdown
extends CanvasLayer

## Post-objective extraction, reframed as BOARDING your landed ship (reference: on the
## surface the controls become "E board / L lift-off"). When the last objective (or final
## wave) completes the mission is already banked; this drops the hero ship nearby and lets
## the player loot, then walk to it and press [E] to board - or [L] to lift off from
## anywhere - to return to the hub. A generous auto-timer still fires as a safety fallback
## so an idle player is never stranded, and if the ship asset is missing the [L]/auto path
## still works (so extraction can never soft-lock).

const RETURN_FALLBACK := "res://scenes/hub/hub.tscn"
const SHIP_GLB := "res://assets/generated/ship/hero_ship.glb"
## The landed ship reads as a boardable ~10 m craft (the GLB mesh is only ~1.4 m across).
const SHIP_SCALE := 7.0
const LAND_AHEAD := 8.0            # metres in front of the player it sets down
const BOARD_RANGE := 6.5           # how close you must be to press [E] board

var _left: float = 0.0
var _return_scene: String = RETURN_FALLBACK
var _label: Label
var _going: bool = false

var _ship: Node3D
var _ship_pos: Vector3 = Vector3.ZERO
var _has_ship: bool = false
var _boarding: bool = false


## Show the window and start. Add this to the running scene first.
func begin(seconds: float, return_scene: String) -> void:
	# The board/lift-off action is the primary exit; the timer is a generous fallback.
	_left = maxf(seconds, 30.0)
	_return_scene = return_scene
	layer = 30
	# Keep counting (and able to return home) even if a menu pauses the tree.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_land_ship()
	set_process(true)


func _build_ui() -> void:
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_label.position = Vector2(-320, 54)
	_label.custom_minimum_size = Vector2(640, 0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 24)
	_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.34))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(_label)


## Pick the boarding point. Preferred: the mission's PERMANENT parked ship (group
## "extraction_ship", placed behind the spawn by the level) - the one that's been sitting
## there the whole mission. Only if a level has none do we set a temporary ship down ahead
## of the player as a fallback. Grounded fallback if the asset/surface is missing too, so
## the [L]/auto exit can never soft-lock.
func _land_ship() -> void:
	var parked := get_tree().get_first_node_in_group("extraction_ship") as Node3D
	if parked and is_instance_valid(parked):
		_ship = parked
		_ship_pos = parked.global_position
		_has_ship = true
		return

	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var origin := player.global_position
	var fwd := -player.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var spot := origin + fwd * LAND_AHEAD
	var ground_y := origin.y
	var world := player.get_world_3d()
	if world:
		var space := world.direct_space_state
		var q := PhysicsRayQueryParameters3D.create(spot + Vector3(0, 8, 0), spot + Vector3(0, -40, 0))
		q.exclude = [player]
		var hit := space.intersect_ray(q)
		if hit:
			ground_y = hit["position"].y
	_ship_pos = Vector3(spot.x, ground_y, spot.z)

	if not ResourceLoader.exists(SHIP_GLB):
		return
	var packed := load(SHIP_GLB)
	if not (packed is PackedScene):
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	_ship = (packed as PackedScene).instantiate() as Node3D
	scene.add_child(_ship)
	_ship.scale = Vector3.ONE * SHIP_SCALE
	_ship.global_position = _ship_pos + Vector3(0, 0.3, 0)
	if origin.distance_to(_ship_pos) > 0.2:
		_ship.look_at(Vector3(origin.x, _ship.global_position.y, origin.z), Vector3.UP)
	_has_ship = true


func _process(delta: float) -> void:
	if _going:
		return
	_left -= delta
	if _left <= 0.0:
		_extract()
		return
	# The parked ship shows its own "[E] Board ship" prompt and runs the board/lift-off
	# cinematic; this just nudges the player + auto-lifts if they idle.
	_label.text = "AREA SECURED  -  loot up!\nBoard your ship to extract   (auto-lift in %d s)" % int(ceil(_left))


## Timed out: leave. Prefer the parked ship's lift-off cinematic (it flies up and returns
## home itself); if there's no cinematic ship, just fade home directly.
func _extract() -> void:
	if _going:
		return
	if _ship and is_instance_valid(_ship) and _ship.has_method("begin_boarding"):
		_going = true
		if _label:
			_label.visible = false
		_ship.begin_boarding(true)      # no-op if the player is already boarding; true = real extraction (mission cleared)
	else:
		_return_to_ship()


func _return_to_ship() -> void:
	if _going:
		return
	_going = true
	set_process(false)
	set_process_unhandled_input(false)
	# Auto-collect everything still on the floor as the player extracts, so no drops
	# are lost by leaving - they're added to the inventory they'll see on the ship.
	_collect_all_loot()
	# Clear any pause left on by an open menu, so the hub isn't frozen on arrival.
	get_tree().paused = false
	var gs := get_node_or_null("/root/GameState")
	if gs and gs.has_method("transition_to"):
		gs.transition_to(_return_scene)
	else:
		get_tree().change_scene_to_file(_return_scene)
	# Belt-and-suspenders: if the faded transition somehow hasn't swapped the scene
	# shortly after (a stuck fade, a missing GameState), force it. The timer is owned by
	# the tree, so it still fires under a menu pause; if the swap DID happen this node is
	# already freed and the callback is a safe no-op.
	var guard := get_tree().create_timer(2.0)
	guard.timeout.connect(_force_return)


## Grab every uncollected loot drop still lying in the mission and bank it to the player's
## inventory (each drop's own pickup() adds to SaveManager + saves). Called as we leave.
func _collect_all_loot() -> void:
	for l in get_tree().get_nodes_in_group("loot"):
		if is_instance_valid(l) and l.has_method("pickup"):
			l.pickup()


## Last-resort scene swap. Runs only if we are still in the finished mission.
func _force_return() -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.scene_file_path == _return_scene:
		return                                  # already home, nothing to do
	get_tree().paused = false
	get_tree().change_scene_to_file(_return_scene)

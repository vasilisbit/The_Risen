extends Node3D
## P0 pilot-helm (reference: the "sit at the chair and point the ship at a world"
## beat). Coexists with the hologram table - both are ways to pick a world and both
## funnel into the SAME launch path (unlock gate -> difficulty prompt -> fade), so
## there is one source of truth for actually starting a mission.
##
## Walk to the pilot chair and press [E] to take the helm: the view snaps to a
## seated camera looking out the canopy, where Earth / Mars / Venus float as
## aim-able markers in space. Aim at one (mouse) and HOLD [F] to "Fold" - a hold
## meter fills, then the world launches. [E] or [Esc] leaves the helm.
##
## No new art: the seat camera, the world markers and the helm HUD are all built
## in code here, matching hub_structure.gd / hologram_table.gd's build-in-_ready
## convention. The cinematic fly-to-planet cutscene is a later phase (P1); for now
## Fold reuses the existing fade-to-black, so the verb is proven end to end.

## Same map the hologram table's interactor uses. Kept local so the helm works in a
## bare test scene; if these ever diverge, centralise into one autoload/const.
const MISSION_SCENES := {
	"Earth": "res://scenes/missions/earth/earth.tscn",
	"Mars": "res://scenes/missions/mars/mars.tscn",
	"Venus": "res://scenes/missions/venus/venus.tscn",
}

## Where the pilot chair is (for the "in range to sit" test) and where the seated
## eye sits and looks. The cockpit window is 5x3 at z=-5 (x[-2.5,2.5], y[1,4]); the
## seat looks out through it, slightly up, toward the worlds.
const SEAT_ANCHOR := Vector3(0.0, 0.0, -3.0)
const SEAT_EYE := Vector3(0.0, 1.55, -2.6)
const SEAT_LOOK := Vector3(0.0, 2.4, -18.0)
const SIT_RANGE := 2.8

## How far the seated look can swing off the forward canopy view, so you always
## stay looking out the window and can't spin round to the back of the room.
const YAW_LIMIT := deg_to_rad(40.0)
const PITCH_LIMIT := deg_to_rad(26.0)
const LOOK_SENS := 0.0022

## Hold [F] this long, with a world under the reticle, to Fold to it. The reticle
## locks the nearest marker within PICK_RADIUS screen pixels of centre.
const HOLD_TIME := 1.2
const PICK_RADIUS := 150.0

## The worlds drawn out the canopy. `pos` is a world-space point in "space" beyond
## the window (in front of the HubPlanet backdrop at z=-24), `tint` colours its
## label. Locked worlds render dim and can't be Folded to, mirroring the table.
const WORLDS := [
	{"mission": "Earth", "pos": Vector3(-4.2, 4.2, -15.0), "tint": Color(0.45, 0.75, 1.0)},
	{"mission": "Mars", "pos": Vector3(0.2, 5.2, -16.0), "tint": Color(1.0, 0.45, 0.32)},
	{"mission": "Venus", "pos": Vector3(4.2, 3.7, -15.0), "tint": Color(1.0, 0.85, 0.45)},
]

var _seated: bool = false
var _yaw: float = 0.0
var _pitch: float = 0.0
var _hold: float = 0.0
var _target: String = ""             # mission under the reticle this frame, or ""

var _player: Node3D
var _player_cam: Camera3D
var _seat_cam: Camera3D
var _labels: Dictionary = {}         # mission -> Label3D

# HUD
var _hud: CanvasLayer
var _reticle: Label
var _target_label: Label
var _fold_bar: ProgressBar
var _hint: Label
var _sit_prompt: Label


func _ready() -> void:
	_build_seat_camera()
	_build_markers()
	_build_hud()
	set_process(true)


func _build_seat_camera() -> void:
	_seat_cam = Camera3D.new()
	_seat_cam.name = "SeatCamera"
	_seat_cam.top_level = true         # we drive it in world space each frame
	_seat_cam.fov = 68.0
	add_child(_seat_cam)               # in-tree before we touch its global transform
	_seat_cam.global_position = SEAT_EYE
	_seat_cam.look_at(SEAT_LOOK, Vector3.UP)


## One billboarded label per world, floating out the canopy. no_depth_test so it
## reads over the planet backdrop; dimmed and marked when locked.
func _build_markers() -> void:
	var sm := get_node_or_null("/root/SaveManager")
	for w in WORLDS:
		var mission: String = w["mission"]
		var unlocked := true
		if sm and sm.has_method("is_mission_unlocked"):
			unlocked = sm.is_mission_unlocked(mission)
		var label := Label3D.new()
		label.name = "%sMarker" % mission
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.shaded = false
		label.double_sided = true
		label.pixel_size = 0.01
		label.font_size = 48
		label.outline_size = 12
		label.outline_modulate = Color(0, 0, 0, 0.8)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var tint: Color = w["tint"]
		label.modulate = tint if unlocked else tint.darkened(0.55)
		label.text = ("◈ %s" % mission.to_upper()) if unlocked else "◈ %s\nLOCKED" % mission.to_upper()
		add_child(label)                # in-tree before setting the world position
		label.global_position = w["pos"]
		_labels[mission] = label


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "HelmHUD"
	_hud.layer = 10
	add_child(_hud)

	_reticle = _mk_label("+", 34, HORIZONTAL_ALIGNMENT_CENTER)
	_reticle.set_anchors_preset(Control.PRESET_CENTER)
	_reticle.position = Vector2(-10, -22)
	_hud.add_child(_reticle)

	_target_label = _mk_label("", 22, HORIZONTAL_ALIGNMENT_CENTER)
	_target_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_target_label.anchor_left = 0.5
	_target_label.anchor_right = 0.5
	_target_label.position = Vector2(-260, 70)
	_target_label.custom_minimum_size = Vector2(520, 0)
	_hud.add_child(_target_label)

	_fold_bar = ProgressBar.new()
	_fold_bar.min_value = 0.0
	_fold_bar.max_value = 1.0
	_fold_bar.show_percentage = false
	_fold_bar.set_anchors_preset(Control.PRESET_CENTER)
	_fold_bar.position = Vector2(-140, 40)
	_fold_bar.custom_minimum_size = Vector2(280, 10)
	var fg := StyleBoxFlat.new()
	fg.bg_color = Color(0.35, 0.8, 1.0)
	_fold_bar.add_theme_stylebox_override("fill", fg)
	_hud.add_child(_fold_bar)

	_hint = _mk_label("[E] leave helm      hold [F] to Fold", 18, HORIZONTAL_ALIGNMENT_CENTER)
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.anchor_left = 0.5
	_hint.anchor_right = 0.5
	_hint.position = Vector2(-220, -60)
	_hint.custom_minimum_size = Vector2(440, 0)
	_hud.add_child(_hint)

	_sit_prompt = _mk_label("[E]  Take the helm", 22, HORIZONTAL_ALIGNMENT_CENTER)
	_sit_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_sit_prompt.anchor_left = 0.5
	_sit_prompt.anchor_right = 0.5
	_sit_prompt.position = Vector2(-160, -110)
	_sit_prompt.custom_minimum_size = Vector2(320, 0)
	_hud.add_child(_sit_prompt)

	_set_seated_hud(false)


func _mk_label(text: String, size: int, align: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.85, 0.93, 1.0))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _process(delta: float) -> void:
	if _seated:
		_update_seated(delta)
	else:
		_update_prompt()


## Not seated: show the "take the helm" prompt when the player is close enough.
func _update_prompt() -> void:
	var p := _find_player()
	var near := p != null and p.global_position.distance_to(SEAT_ANCHOR) <= SIT_RANGE
	_sit_prompt.visible = near


func _find_player() -> Node3D:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	return _player


func _update_seated(delta: float) -> void:
	# Re-aim the seat camera from the base canopy view by the accumulated look.
	_seat_cam.global_position = SEAT_EYE
	_seat_cam.look_at(SEAT_LOOK, Vector3.UP)
	_seat_cam.rotate_object_local(Vector3.UP, _yaw)
	_seat_cam.rotate_object_local(Vector3.RIGHT, _pitch)

	_target = _pick_target()
	var sm := get_node_or_null("/root/SaveManager")
	var locked := false
	if _target != "" and sm and sm.has_method("is_mission_unlocked"):
		locked = not sm.is_mission_unlocked(_target)

	# Hold-to-Fold only counts on an unlocked, targeted world.
	if _target != "" and not locked and Input.is_key_pressed(KEY_F):
		_hold += delta
		if _hold >= HOLD_TIME:
			_fold_to(_target)
			return
	else:
		_hold = 0.0

	_fold_bar.value = _hold / HOLD_TIME
	_fold_bar.visible = _target != "" and not locked
	if _target == "":
		_target_label.text = "AIM AT A WORLD"
	elif locked:
		_target_label.text = "%s  —  LOCKED" % _target.to_upper()
	else:
		_target_label.text = "%s  —  HOLD [F] TO FOLD" % _target.to_upper()


## The world nearest the screen centre within PICK_RADIUS, or "".
func _pick_target() -> String:
	var centre := get_viewport().get_visible_rect().size * 0.5
	var best := ""
	var best_d := PICK_RADIUS
	for mission in _labels:
		var pos: Vector3 = (_labels[mission] as Label3D).global_position
		if _seat_cam.is_position_behind(pos):
			continue
		var screen := _seat_cam.unproject_position(pos)
		var d := screen.distance_to(centre)
		if d < best_d:
			best_d = d
			best = mission
	return best


func _unhandled_input(event: InputEvent) -> void:
	if _seated:
		if event is InputEventMouseMotion:
			var m := event as InputEventMouseMotion
			_yaw = clampf(_yaw - m.relative.x * LOOK_SENS, -YAW_LIMIT, YAW_LIMIT)
			_pitch = clampf(_pitch - m.relative.y * LOOK_SENS, -PITCH_LIMIT, PITCH_LIMIT)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel"):
			_leave_helm()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("interact"):
		var p := _find_player()
		if p != null and p.global_position.distance_to(SEAT_ANCHOR) <= SIT_RANGE:
			_take_helm()
			get_viewport().set_input_as_handled()


func _take_helm() -> void:
	var p := _find_player()
	if p == null:
		return
	_player = p
	_player_cam = p.get_node_or_null("SpringArm3D/Camera3D") as Camera3D
	# Freeze the whole player subtree (movement, look, its crosshair raycast) in one
	# move; the seat camera lives under Helm, so it is untouched.
	p.process_mode = Node.PROCESS_MODE_DISABLED
	var crosshair := p.get_node_or_null("DebugHUD") as CanvasLayer
	if crosshair:
		crosshair.visible = false
	_seat_cam.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_yaw = 0.0
	_pitch = 0.0
	_hold = 0.0
	_seated = true
	_set_seated_hud(true)


func _leave_helm() -> void:
	_seated = false
	_hold = 0.0
	_set_seated_hud(false)
	if _player and is_instance_valid(_player):
		_player.process_mode = Node.PROCESS_MODE_INHERIT
		var crosshair := _player.get_node_or_null("DebugHUD") as CanvasLayer
		if crosshair:
			crosshair.visible = true
	if _player_cam and is_instance_valid(_player_cam):
		_player_cam.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _set_seated_hud(on: bool) -> void:
	_reticle.visible = on
	_target_label.visible = on
	_hint.visible = on
	_fold_bar.visible = false
	_sit_prompt.visible = false        # the "take the helm" prompt is a not-seated cue


## Fold confirmed: leave the helm (so a cancelled difficulty prompt returns you to a
## normal walkable hub), then run the exact table launch path.
func _fold_to(mission: String) -> void:
	_leave_helm()
	var sm := get_node_or_null("/root/SaveManager")
	if sm and sm.has_method("is_mission_unlocked") and not sm.is_mission_unlocked(mission):
		_notify("%s is locked." % mission)
		return
	if not MISSION_SCENES.has(mission):
		return
	var prompt := get_tree().get_first_node_in_group("difficulty_select")
	if prompt and prompt.has_method("open"):
		if not prompt.launch_confirmed.is_connected(_start_mission):
			prompt.launch_confirmed.connect(_start_mission)
		prompt.open(mission)
	else:
		_start_mission(mission)


func _start_mission(mission: String) -> void:
	if not MISSION_SCENES.has(mission):
		return
	var gs := get_node_or_null("/root/GameState")
	if gs and gs.has_method("transition_to"):
		gs.transition_to(MISSION_SCENES[mission])
	else:
		get_tree().change_scene_to_file(MISSION_SCENES[mission])


func _notify(message: String) -> void:
	var notice := get_tree().get_first_node_in_group("hub_notice")
	if notice and notice.has_method("notify"):
		notice.notify(message)
	else:
		print(message)

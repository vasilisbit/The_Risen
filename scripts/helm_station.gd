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
## Base view is aimed at the planet row so the reticle starts among the worlds.
const SEAT_LOOK := Vector3(0.5, 5.5, -49.0)
const SIT_RANGE := 2.8

## How far the seated look can swing off the forward canopy view. Kept tight - just
## enough to put the reticle on the outermost world (~16 deg) - so the view stays
## framed on the window and never swings into the cramped, hard-edged interior
## corners behind the seat, which was the source of the look-around visual glitches.
const YAW_LIMIT := deg_to_rad(22.0)
const PITCH_LIMIT := deg_to_rad(15.0)
const LOOK_SENS := 0.0022

## Hold [F] this long, with a world under the reticle, to Fold to it. The reticle
## locks the nearest marker within PICK_RADIUS screen pixels of centre.
const HOLD_TIME := 1.2
const PICK_RADIUS := 150.0

## The worlds are real planets floating far out the canopy (each a sphere on the
## project's planet shader, per-world tinted like hub_planet.gd), with a name
## marker pinned just above it. `pos` is the planet centre in "space"; `radius`
## its size; the colour block feeds the shader. They sit well beyond the window so
## they read as distant destinations you point the ship at. Locked worlds still
## show but can't be Folded to, mirroring the table.
const PLANET_SHADER := "res://shaders/planet.gdshader"
const WORLDS := [
	{
		"mission": "Earth", "tint": Color(0.55, 0.8, 1.0),
		"pos": Vector3(-12.0, 5.0, -46.0), "radius": 4.0,
		"ocean": Color(0.05, 0.22, 0.55), "land": Color(0.16, 0.42, 0.18),
		"atmo": Color(0.40, 0.65, 1.00), "threshold": 0.52, "bands": 0.05, "clouds": 0.42,
	},
	{
		"mission": "Mars", "tint": Color(1.0, 0.5, 0.36),
		"pos": Vector3(1.5, 8.0, -54.0), "radius": 3.4,
		"ocean": Color(0.42, 0.16, 0.09), "land": Color(0.66, 0.34, 0.17),
		"atmo": Color(1.00, 0.52, 0.30), "threshold": 0.46, "bands": 0.28, "clouds": 0.08,
	},
	{
		"mission": "Venus", "tint": Color(1.0, 0.85, 0.5),
		"pos": Vector3(13.0, 5.0, -47.0), "radius": 4.0,
		"ocean": Color(0.62, 0.36, 0.12), "land": Color(0.94, 0.72, 0.32),
		"atmo": Color(1.00, 0.74, 0.34), "threshold": 0.40, "bands": 0.55, "clouds": 0.70,
	},
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
var _planets: Dictionary = {}        # mission -> planet-centre world position (aim point)

# HUD
var _hud: CanvasLayer
var _reticle: Label
var _target_label: Label
var _fold_bar: ProgressBar
var _hint: Label
var _sit_prompt: Label


func _ready() -> void:
	# The single big "last-deployed" planet is replaced here by the three distant
	# selectable worlds, so hide it to avoid a giant sphere dominating the canopy.
	var hub_planet := get_parent().get_node_or_null("HubPlanet") as Node3D
	if hub_planet:
		hub_planet.visible = false
	_build_seat_camera()
	_build_worlds()
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


## Per world: a distant planet sphere on the planet shader, plus a name marker
## pinned just above it. The marker respects depth (no_depth_test off) so the ship
## walls occlude it as you swing the view away - no labels bleeding through the
## hull - and is fixed_size so it stays readable however far the planet sits.
func _build_worlds() -> void:
	var sm := get_node_or_null("/root/SaveManager")
	var shader := load(PLANET_SHADER)
	for w in WORLDS:
		var mission: String = w["mission"]
		var unlocked := true
		if sm and sm.has_method("is_mission_unlocked"):
			unlocked = sm.is_mission_unlocked(mission)

		var planet := MeshInstance3D.new()
		planet.name = "%sPlanet" % mission
		var sphere := SphereMesh.new()
		sphere.radius = w["radius"]
		sphere.height = float(w["radius"]) * 2.0
		sphere.radial_segments = 48
		sphere.rings = 24
		planet.mesh = sphere
		# Sits outside the room, so it must not be culled by the interior geometry.
		planet.extra_cull_margin = float(w["radius"]) * 3.0
		if shader:
			var mat := ShaderMaterial.new()
			mat.shader = shader
			mat.set_shader_parameter("rot_speed", 1.0 / 60.0)
			mat.set_shader_parameter("ocean_color", w["ocean"])
			mat.set_shader_parameter("land_color", w["land"])
			mat.set_shader_parameter("atmo_color", w["atmo"])
			mat.set_shader_parameter("land_threshold", w["threshold"])
			mat.set_shader_parameter("band_strength", w["bands"])
			mat.set_shader_parameter("cloud_amount", w["clouds"])
			planet.material_override = mat
		add_child(planet)
		planet.global_position = w["pos"]
		_planets[mission] = w["pos"]     # aim at the planet itself, not its label

		var label := Label3D.new()
		label.name = "%sMarker" % mission
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.fixed_size = true
		label.no_depth_test = false
		label.shaded = false
		label.double_sided = true
		label.pixel_size = 0.0007
		label.font_size = 64
		label.outline_size = 16
		label.outline_modulate = Color(0, 0, 0, 0.85)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var tint: Color = w["tint"]
		label.modulate = tint if unlocked else tint.darkened(0.5)
		label.text = ("◈ %s" % mission.to_upper()) if unlocked else "◈ %s\nLOCKED" % mission.to_upper()
		add_child(label)                # in-tree before setting the world position
		label.global_position = w["pos"] + Vector3(0.0, float(w["radius"]) + 1.8, 0.0)
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

	_hint = _mk_label("[E] Leave Helm", 18, HORIZONTAL_ALIGNMENT_CENTER)
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.anchor_left = 0.5
	_hint.anchor_right = 0.5
	_hint.position = Vector2(-220, -60)
	_hint.custom_minimum_size = Vector2(440, 0)
	_hud.add_child(_hint)

	_sit_prompt = _mk_label("[E]  Take the Helm", 22, HORIZONTAL_ALIGNMENT_CENTER)
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
	# Re-aim the seat camera from the base canopy view by the accumulated look. Yaw
	# is applied about WORLD up (a level pan) and pitch about the camera's own right,
	# so panning left/right doesn't dip the aim - the earlier local-up yaw did, which
	# dragged the reticle below the worlds as you looked across them.
	_seat_cam.global_position = SEAT_EYE
	_seat_cam.look_at(SEAT_LOOK, Vector3.UP)
	var base := _seat_cam.global_transform.basis
	_seat_cam.global_transform.basis = Basis(Vector3.UP, _yaw) * base * Basis(Vector3.RIGHT, _pitch)

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
		_target_label.text = "%s  -  LOCKED" % _target.to_upper()
	else:
		_target_label.text = "%s  -  HOLD [F] TO FOLD" % _target.to_upper()


## The world whose planet is nearest the screen centre within PICK_RADIUS, or "".
func _pick_target() -> String:
	var centre := get_viewport().get_visible_rect().size * 0.5
	var best := ""
	var best_d := PICK_RADIUS
	for mission in _planets:
		var pos: Vector3 = _planets[mission]
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

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
## Base view frames the solar-system spread (near hero world + far background ones).
const SEAT_LOOK := Vector3(0.0, 3.6, -45.0)
const SIT_RANGE := 2.8

## How far the seated look can swing off the forward canopy view. Kept tight - just
## enough to put the reticle on the outermost world (~16 deg) - so the view stays
## framed on the window and never swings into the cramped, hard-edged interior
## corners behind the seat, which was the source of the look-around visual glitches.
const YAW_LIMIT := deg_to_rad(22.0)
const PITCH_LIMIT := deg_to_rad(15.0)
const LOOK_SENS := 0.0022

## To take the helm you must be near the chair AND looking at it (crosshair on the
## seat), not merely standing beside it. This is the cosine of the aim cone half-
## angle: the angle between the camera forward and the direction to the seat must
## be under ~21 deg. Resolution-independent (an angle, not a pixel radius).
const AIM_DOT := 0.93

## Hold [F] this long, with a world under the reticle, to Fold to it. The reticle
## locks the nearest marker within PICK_RADIUS screen pixels of centre.
const HOLD_TIME := 1.2
const PICK_RADIUS := 150.0

## The worlds are real planets out the canopy (each a sphere on the project's planet
## shader, per-world tinted like hub_planet.gd) with a name marker pinned above it.
## Positions aren't fixed per planet - they're assigned to SLOTS at build time so the
## LAST-VISITED world sits close + large in the foreground and the rest hang far in
## the background at different heights/depths, reading as a solar system rather than
## a flat row. The colour block feeds the shader. Locked worlds show but can't Fold.
const PLANET_SHADER := "res://shaders/planet.gdshader"
const SCREEN_SHADER := "res://shaders/cockpit_screen.gdshader"
## Realistic full-disc planet renders (fal.ai) shown as billboards out the canopy.
const PLANET_TEX := {
	"Earth": "res://assets/generated/interior/planet_earth.png",
	"Mars": "res://assets/generated/interior/planet_mars.png",
	"Venus": "res://assets/generated/interior/planet_venus.png",
}
const ORDER := ["Earth", "Mars", "Venus"]
## Slot 0 = the near/foreground hero world (last visited); slots 1-2 = far background.
## Spread so the three discs never overlap on screen (the near hero world is
## centre-low; the far two sit up in opposite corners), each clearly aim-able.
const SLOTS := [
	{"pos": Vector3(0.5, 2.8, -32.0), "radius": 4.6, "near": true},
	{"pos": Vector3(15.5, 8.5, -72.0), "radius": 3.0, "near": false},
	{"pos": Vector3(-15.5, 7.5, -76.0), "radius": 2.8, "near": false},
]
const WORLDS := [
	{
		"mission": "Earth", "tint": Color(0.55, 0.8, 1.0),
		"ocean": Color(0.05, 0.22, 0.55), "land": Color(0.16, 0.42, 0.18),
		"atmo": Color(0.40, 0.65, 1.00), "threshold": 0.52, "bands": 0.05, "clouds": 0.42,
	},
	{
		"mission": "Mars", "tint": Color(1.0, 0.5, 0.36),
		"ocean": Color(0.42, 0.16, 0.09), "land": Color(0.66, 0.34, 0.17),
		"atmo": Color(1.00, 0.52, 0.30), "threshold": 0.46, "bands": 0.28, "clouds": 0.08,
	},
	{
		"mission": "Venus", "tint": Color(1.0, 0.85, 0.5),
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
var _planet_radius: Dictionary = {}  # mission -> world radius (for crosshair hit-testing)

# Cockpit console (always present); its screens light up while seated.
var _console: Node3D
var _screens: Array = []

var _seat: Node3D
var _seat_rest_yaw: float = 0.0
var _seat_known: bool = false
var _seat_tween: Tween
## The pilot seat is placed at its rest yaw by hub_structure; on sit it swivels to
## face the canopy, on leave it swivels back (reference: the chair turns to the window).
const SEAT_FACE_YAW := PI * 0.5

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
	_build_console()
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
	# Assign slots: the last-visited world takes the near/foreground slot, the others
	# the far background slots (in ORDER) - so the canopy reads as a solar system.
	var cfg := {}
	for w in WORLDS:
		cfg[w["mission"]] = w
	var last := _last_visited()
	var seq := [last]
	for m in ORDER:
		if m != last:
			seq.append(m)

	for i in seq.size():
		var mission: String = seq[i]
		var w: Dictionary = cfg[mission]
		var slot: Dictionary = SLOTS[mini(i, SLOTS.size() - 1)]
		var pos: Vector3 = slot["pos"]
		var radius: float = slot["radius"]
		var near: bool = slot["near"]
		var unlocked := true
		if sm and sm.has_method("is_mission_unlocked"):
			unlocked = sm.is_mission_unlocked(mission)

		# The world out the canopy is now a real 3D fal.ai planet (photographic detail,
		# slowly spinning, self-lit so it reads in the dim cockpit); falls back to the
		# flat billboard render if the GLB is missing. The near/current world turns a
		# touch faster so it draws the eye.
		var pb: Node3D = preload("res://scripts/planet_body.gd").new()
		pb.name = "%sPlanet" % mission
		add_child(pb)
		pb.global_position = pos
		if not pb.setup(mission, radius, 0.06 if near else 0.035):
			pb.queue_free()
			var bb := _billboard_planet(mission, unlocked, radius)
			add_child(bb)
			bb.global_position = pos
		_planets[mission] = pos          # aim at the planet itself, not its label
		_planet_radius[mission] = radius

		var label := Label3D.new()
		label.name = "%sMarker" % mission
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.fixed_size = true
		label.no_depth_test = false
		label.shaded = false
		label.double_sided = true
		# The near/current world's marker reads a little larger.
		label.pixel_size = 0.0009 if near else 0.00055
		label.font_size = 64
		label.outline_size = 16
		label.outline_modulate = Color(0, 0, 0, 0.85)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var tint: Color = w["tint"]
		label.modulate = tint if unlocked else tint.darkened(0.5)
		label.text = ("◈ %s" % mission.to_upper()) if unlocked else "◈ %s\nLOCKED" % mission.to_upper()
		# Markers are the seated targeting UI, NOT ambient space labels: hidden by
		# default (so the planets read as plain worlds through the canopy while you
		# walk the hub) and shown one-at-a-time only for the world you point at while
		# seated (see _update_marker_visibility).
		label.visible = false
		add_child(label)                # in-tree before setting the world position
		label.global_position = pos + Vector3(0.0, radius + 2.5, 0.0)
		_labels[mission] = label


## Fallback flat-billboard planet (the fal.ai full-disc render), additively blended so
## the image's black background reads as empty space. Used only if the 3D GLB is missing.
func _billboard_planet(mission: String, unlocked: bool, radius: float) -> MeshInstance3D:
	var planet := MeshInstance3D.new()
	planet.name = "%sPlanet" % mission
	var quad := QuadMesh.new()
	var qs := radius * 2.0 / 0.9      # the disc fills ~0.9 of the square image
	quad.size = Vector2(qs, qs)
	planet.mesh = quad
	planet.extra_cull_margin = qs
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	pm.billboard_keep_scale = true
	pm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var tex := load(String(PLANET_TEX.get(mission, ""))) as Texture2D
	if tex:
		pm.albedo_texture = tex
	pm.albedo_color = Color(0.95, 0.95, 0.95) if unlocked else Color(0.45, 0.45, 0.45)
	planet.material_override = pm
	return planet


## The mission most recently deployed to (the near/foreground world). Default Earth.
func _last_visited() -> String:
	var sm := get_node_or_null("/root/SaveManager")
	if sm and "data" in sm:
		var last := String(sm.data.get("last_mission", "Earth"))
		if ORDER.has(last):
			return last
	return "Earth"


## The pilot's console: the fal.ai cockpit console asset with subtle live readouts
## laid into its recessed screens, seated in front of the chair. Built stowed +
## hidden; _deploy_console rises it when you take the helm, _retract hides it. Falls
## back to a plain dark box if the asset is missing. Transforms were tuned in-engine.
const CONSOLE_GLB := "res://assets/generated/interior/cockpit_console.glb"
const CONSOLE_POS := Vector3(0.0, 1.12, -3.52)
const CONSOLE_YAW := -90.0
const CONSOLE_SCALE := 2.65
const SCREEN_SLOTS := [
	Vector3(-0.73, 1.27, -3.52), Vector3(0.0, 1.29, -3.55), Vector3(0.73, 1.27, -3.52),
]
const SCREEN_SIZE := Vector2(0.47, 0.28)
const SCREEN_TILT := -30.0    # deg: x-tilt of the recessed screen glass (center screen)
## The console is curved, so the side screens also roll about z (and turn about y) to
## sit flush on their angled panels. Left rolls +, right rolls - (mirror).
const SCREEN_SIDE_ROLL := 2.3
const SCREEN_SIDE_YAW := 18.0

func _build_console() -> void:
	_console = Node3D.new()
	_console.name = "Console"
	add_child(_console)

	var glb := load(CONSOLE_GLB)
	if glb is PackedScene:
		var body := (glb as PackedScene).instantiate() as Node3D
		_console.add_child(body)
		body.position = CONSOLE_POS
		body.rotation.y = deg_to_rad(CONSOLE_YAW)
		body.scale = Vector3.ONE * CONSOLE_SCALE
	else:
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(2.6, 0.5, 0.7)
		box.mesh = bm
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color(0.06, 0.07, 0.09)
		bmat.metallic = 0.7
		bmat.roughness = 0.4
		box.material_override = bmat
		box.position = Vector3(0.0, 1.0, -3.7)
		_console.add_child(box)

	# Subtle live readouts lying flat in the console's recessed screens - stored so
	# they can be switched on only while you're seated.
	var shader := load(SCREEN_SHADER)
	for i in SCREEN_SLOTS.size():
		var scr := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = SCREEN_SIZE
		scr.mesh = qm
		if shader:
			var mat := ShaderMaterial.new()
			mat.shader = shader
			scr.material_override = mat
		_console.add_child(scr)
		scr.position = SCREEN_SLOTS[i]
		# Center screen: pure x-tilt. Side screens also roll/turn onto their angled
		# panels (left +, right - mirror).
		var roll := 0.0
		var yaw := 0.0
		if i == 0:
			roll = SCREEN_SIDE_ROLL
			yaw = SCREEN_SIDE_YAW
		elif i == SCREEN_SLOTS.size() - 1:
			roll = -SCREEN_SIDE_ROLL
			yaw = -SCREEN_SIDE_YAW
		scr.rotation = Vector3(deg_to_rad(SCREEN_TILT), deg_to_rad(yaw), deg_to_rad(roll))
		_screens.append(scr)

	# The console is a permanent fixture of the cockpit; only its screens turn on
	# when you take the helm. Offset sits it ON the console table (top ~y0.5, built
	# by hub_structure._build_console_table) in front of the seated pilot, clear of
	# the front bulkhead (was on the floor and buried in the wall).
	_console.position = Vector3(0.0, -0.22, -0.35)
	_console.visible = true
	_set_screens(false)


## Swivel the pilot seat: to the canopy when you sit, back to its rest angle when
## you leave. The rest angle is whatever hub_structure placed it at (read once).
func _swivel_seat(to_window: bool) -> void:
	if _seat == null or not is_instance_valid(_seat):
		_seat = get_tree().get_first_node_in_group("pilot_seat") as Node3D
	if _seat == null:
		return
	if not _seat_known:
		_seat_rest_yaw = _seat.rotation.y
		_seat_known = true
	var target := SEAT_FACE_YAW if to_window else _seat_rest_yaw
	if _seat_tween and _seat_tween.is_valid():
		_seat_tween.kill()
	_seat_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_seat_tween.tween_property(_seat, "rotation:y", target, 0.5)


## Turn the console screens on/off (the console itself is always present).
func _set_screens(on: bool) -> void:
	for scr in _screens:
		if is_instance_valid(scr):
			scr.visible = on


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "HelmHUD"
	_hud.layer = 10
	add_child(_hud)

	_reticle = _mk_label("+", 34, HORIZONTAL_ALIGNMENT_CENTER, Color(0.9, 0.95, 1.0))
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

	_hint = _mk_label("[E] Leave Helm", 22, HORIZONTAL_ALIGNMENT_CENTER)
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


## Shared gold interaction-prompt colour — identical to the hub interact/deploy
## prompt (debug_hud) and the landed-ship board prompt, so every "point at
## something" text reads the same. The aiming reticle passes a neutral colour.
const PROMPT_GOLD := Color(1.0, 0.82, 0.34)

func _mk_label(text: String, size: int, align: int, color := PROMPT_GOLD) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _process(delta: float) -> void:
	if _seated:
		_update_seated(delta)
	else:
		_update_prompt()


## Not seated: show the "take the helm" prompt only when the player is close AND
## pointing at the chair (see _can_sit) - so it isn't a stray prompt whenever you
## happen to walk past the seat.
func _update_prompt() -> void:
	_sit_prompt.visible = _can_sit()


## True only when the player is within reach of the chair AND aiming at it.
func _can_sit() -> bool:
	var p := _find_player()
	if p == null or p.global_position.distance_to(SEAT_ANCHOR) > SIT_RANGE:
		return false
	return _aiming_at_seat()


## Is the crosshair on the chair? The angle between the player camera's forward and
## the direction from the camera to the seat must fall inside the AIM_DOT cone.
func _aiming_at_seat() -> bool:
	var cam := _player_camera()
	if cam == null:
		return false
	var aim := Vector3(SEAT_ANCHOR.x, 1.0, SEAT_ANCHOR.z)   # the seat body, not the floor
	var to_seat := aim - cam.global_position
	if to_seat.length() < 0.05:
		return true
	var fwd := -cam.global_transform.basis.z
	return fwd.normalized().dot(to_seat.normalized()) >= AIM_DOT


func _player_camera() -> Camera3D:
	var p := _find_player()
	if p == null:
		return null
	return p.get_node_or_null("SpringArm3D/Camera3D") as Camera3D


func _find_player() -> Node3D:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	return _player


func _update_seated(delta: float) -> void:
	# Restore the aiming HUD (it is hidden while the difficulty prompt is open; the tree
	# is paused then, so reaching here means the prompt just closed - e.g. a cancel).
	_reticle.visible = true
	_target_label.visible = true
	# Re-aim the seat camera from the base canopy view by the accumulated look. Yaw
	# is applied about WORLD up (a level pan) and pitch about the camera's own right,
	# so panning left/right doesn't dip the aim - the earlier local-up yaw did, which
	# dragged the reticle below the worlds as you looked across them.
	_seat_cam.global_position = SEAT_EYE
	_seat_cam.look_at(SEAT_LOOK, Vector3.UP)
	var base := _seat_cam.global_transform.basis
	_seat_cam.global_transform.basis = Basis(Vector3.UP, _yaw) * base * Basis(Vector3.RIGHT, _pitch)

	_target = _pick_target()
	_update_marker_visibility(_target)
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
	# The hold meter only shows while you are actually holding Fold - otherwise it
	# sat as a stray empty bar under the crosshair.
	_fold_bar.visible = _hold > 0.0
	if _target == "":
		_target_label.text = "AIM AT A WORLD"
	elif locked:
		_target_label.text = "%s  -  LOCKED" % _target.to_upper()
	else:
		_target_label.text = "%s  -  HOLD [F] TO FOLD" % _target.to_upper()


## The world the crosshair is actually on. First preference: a planet whose
## on-screen disc contains the crosshair (nearest such planet wins, so the big near
## world takes priority over a far one behind it) - this stops the readout naming a
## different planet than the one under the reticle. Otherwise the nearest disc edge
## within PICK_RADIUS, so you can still lock a tiny far world by pointing near it.
func _pick_target() -> String:
	var centre := get_viewport().get_visible_rect().size * 0.5
	var inside := ""
	var inside_z := INF
	var edge := ""
	var edge_d := PICK_RADIUS
	for mission in _planets:
		var pos: Vector3 = _planets[mission]
		if _seat_cam.is_position_behind(pos):
			continue
		var screen := _seat_cam.unproject_position(pos)
		var d := screen.distance_to(centre)
		# Projected on-screen radius: unproject a point one world-radius to the side.
		var radius: float = _planet_radius.get(mission, 3.0)
		var edge_world: Vector3 = pos + _seat_cam.global_transform.basis.x * radius
		var r_px := _seat_cam.unproject_position(edge_world).distance_to(screen)
		var depth := _seat_cam.global_position.distance_to(pos)
		if d <= r_px and depth < inside_z:      # crosshair sits on this disc
			inside_z = depth
			inside = mission
		if d - r_px < edge_d:                    # distance from the disc edge
			edge_d = d - r_px
			edge = mission
	return inside if inside != "" else edge


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
		if _can_sit():
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
	_set_screens(true)
	_swivel_seat(true)
	# Hide the pilot's own body so you don't see a figure sitting beside you when you
	# look around from the seat.
	p.visible = false


func _leave_helm() -> void:
	_seated = false
	_hold = 0.0
	_set_seated_hud(false)
	_set_screens(false)
	_swivel_seat(false)
	if _player and is_instance_valid(_player):
		_player.visible = true
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
	if not on:
		_update_marker_visibility("")  # leaving the helm clears every world marker


## Show only the pointed-at world's rhombus name marker, and only while seated -
## the other planets stay unlabelled so the canopy reads as plain outer space.
func _update_marker_visibility(active: String) -> void:
	for mission in _labels:
		(_labels[mission] as Label3D).visible = _seated and mission == active


## Fold confirmed: open the difficulty prompt WHILE STILL SEATED at the helm (you pick
## the difficulty from the chair, looking out the canopy), then run the launch path. A
## cancelled prompt leaves you seated to pick again; a confirm hands off to the cutscene.
func _fold_to(mission: String) -> void:
	var sm := get_node_or_null("/root/SaveManager")
	if sm and sm.has_method("is_mission_unlocked") and not sm.is_mission_unlocked(mission):
		_notify("%s is locked." % mission)
		return                       # stay seated
	if not MISSION_SCENES.has(mission):
		return
	var prompt := get_tree().get_first_node_in_group("difficulty_select")
	if prompt and prompt.has_method("open"):
		if not prompt.launch_confirmed.is_connected(_start_mission):
			prompt.launch_confirmed.connect(_start_mission)
		# Hide the aiming HUD behind the prompt; _update_seated restores it if cancelled.
		_hold = 0.0
		_reticle.visible = false
		_target_label.visible = false
		_fold_bar.visible = false
		prompt.open(mission)
	else:
		_start_mission(mission)


## Difficulty confirmed: run the Fold cinematic (fly to the world & land), then it
## swaps to the mission. Falls back to the plain fade if ShipTravel can't run (missing
## ship asset / cutscene scene), so the launch never dead-ends.
func _start_mission(mission: String) -> void:
	if not MISSION_SCENES.has(mission):
		return
	# The cutscene (or the fallback fade) owns the camera from here, so tear down the
	# seated helm view without restoring the walking player - the scene swaps away.
	_seated = false
	if _hud:
		_hud.visible = false
	var st := get_node_or_null("/root/ShipTravel")
	if st and st.has_method("begin"):
		var planet_hint := _labels.get(mission) as Node3D   # aimed world, hint only
		if st.begin(mission, planet_hint):
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

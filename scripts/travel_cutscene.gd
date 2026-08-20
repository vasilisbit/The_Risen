extends Node3D
## The Fold cinematic (P1) - the "fly to the planet and land" beat the reference clip
## is loved for. Instanced by ShipTravel into the live hub scene and driven entirely
## in code (repo convention: helm_station / hub_structure build in _ready), so there
## is no fragile hand-keyed AnimationPlayer to maintain.
##
## A self-contained little pocket of space is built FAR from the hub (see ORIGIN) so
## the hub's interior never intrudes on frame - only the hero ship, the destination
## planet and the WorldEnvironment star-sky are visible. The beats:
##   FOLD     - warp streaks fill the screen (hides the cut), engines light
##   APPROACH - streaks clear, the ship coasts in banking toward the world,
##              letterbox bars slide in + the lower-left title card fades up
##   DESCENT  - the ship noses over and dives at the planet, which swells to fill frame
##   HANDOFF  - emit `handoff(mission)`; ShipTravel does the white flash + scene swap
##
## Skippable with [E]/[Esc]. If the ship asset is missing ShipTravel never instances
## this (it falls back to the plain fade), so here we assume the GLB loads.

signal state_changed(state: int)
signal handoff(mission: String)     # descent done -> ShipTravel flashes white + swaps

enum State { IDLE, FOLD, APPROACH, DESCENT, HANDOFF }

const SHIP_GLB := "res://assets/generated/ship/hero_ship.glb"
const PLANET_SHADER := "res://shaders/planet.gdshader"
const WARP_SHADER := "res://shaders/warp_fx.gdshader"

## A pocket of space well above the hub so no interior geometry is ever in shot.
const ORIGIN := Vector3(0.0, 1200.0, 0.0)

## Beat durations (seconds). Tuned so the whole thing is a brisk ~6 s.
const T_FOLD := 1.3
const T_APPROACH := 2.6
const T_DESCENT := 2.2

## The hero ship's nose axis after import. hero_ship.glb reads nose along +Z, so we
## yaw it 180 deg to fly forward (-Z travel). Tunable if a future ship asset differs.
## The GLB mesh is only ~1.4 units across, so it is scaled up to read as a hero ship.
const SHIP_YAW := PI
const SHIP_SCALE := 14.0

## Per-world planet look (mirrors hub_planet.PLANETS) + a title-card lore line in the
## reference's "star - descriptor - world count" style.
const WORLDS := {
	"Earth": {
		"ocean": Color(0.05, 0.22, 0.55), "land": Color(0.16, 0.42, 0.18),
		"atmo": Color(0.40, 0.65, 1.00), "threshold": 0.52, "bands": 0.05, "clouds": 0.42,
		"lore": "SOL - BLUE-WHITE DWARF - 8 WORLDS",
	},
	"Mars": {
		"ocean": Color(0.42, 0.16, 0.09), "land": Color(0.66, 0.34, 0.17),
		"atmo": Color(1.00, 0.52, 0.30), "threshold": 0.46, "bands": 0.28, "clouds": 0.08,
		"lore": "SOL - RED DESERT WORLD - 8 WORLDS",
	},
	"Venus": {
		"ocean": Color(0.62, 0.36, 0.12), "land": Color(0.94, 0.72, 0.32),
		"atmo": Color(1.00, 0.74, 0.34), "threshold": 0.40, "bands": 0.55, "clouds": 0.70,
		"lore": "SOL - SULFUR-VEILED WORLD - 8 WORLDS",
	},
}

## Ship flight path (local to the rig). Starts up-and-right and curves in toward the
## planet, ending just above its limb where the descent takes over.
const PATH_PTS := [
	Vector3(30.0, 22.0, 40.0),
	Vector3(12.0, 6.0, -60.0),
	Vector3(-6.0, -10.0, -160.0),
	Vector3(0.0, -20.0, -250.0),
]
## Planet sits dead ahead and low so the ship dives down onto it (radius clears p3).
const PLANET_POS := Vector3(0.0, -52.0, -300.0)
const PLANET_RADIUS := 50.0

## The camera chases the ship at a fixed offset (see _process), tweened per beat, so
## the hero ship stays a consistent size no matter where it is on the path while the
## planet fills the background behind it.
const CAM_OFF_FOLD := Vector3(16.0, 9.0, 40.0)
const CAM_OFF_APPROACH := Vector3(20.0, 7.0, 34.0)
## Descent frames the ship from the upper-RIGHT side (not behind), so we look down onto
## the TOP of the hull and its travel direction (-Z) reads left-to-right: the nose points
## right, toward the planet that sits in the lower-right of frame.
const CAM_OFF_DESCENT := Vector3(32.0, 24.0, 8.0)
## How far the camera's look-at is biased from the ship toward the planet (0 = the ship,
## 1 = the planet). Small on descent - looking mostly at the ship keeps the side-top
## framing (a strong planet bias would swing back to a behind-the-ship rear view).
const FOCUS_APPROACH := 0.22
const FOCUS_DESCENT := 0.16

var _state: int = State.IDLE
var _mission: String = ""
var _done: bool = false

## Live camera framing, tweened per beat and applied in _process (chase rig).
var _cam_offset: Vector3 = CAM_OFF_FOLD
var _focus_bias: float = FOCUS_APPROACH

var _rig: Node3D
var _cam: Camera3D
var _ship_follow: PathFollow3D
var _ship_model: Node3D
var _planet: Node3D
var _engine_glow: OmniLight3D
var _engine_player: AudioStreamPlayer

# Overlay UI (freed with this scene on the swap; the white flash lives on ShipTravel).
var _ui: CanvasLayer
var _warp_rect: ColorRect
var _warp_mat: ShaderMaterial
var _bar_top: ColorRect
var _bar_bottom: ColorRect
var _title: Label
var _subtitle: Label
var _skip_hint: Label


## Kick off the cinematic for `mission`. Called by ShipTravel right after it adds
## this node to the live scene.
func play(mission: String) -> void:
	_mission = mission if WORLDS.has(mission) else "Earth"
	_build_rig()
	_build_ui()
	_cam.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	set_process(true)
	set_process_unhandled_input(true)
	_start_audio()
	_run()


func _build_rig() -> void:
	_rig = Node3D.new()
	_rig.name = "Rig"
	_rig.position = ORIGIN
	add_child(_rig)

	# A dedicated sun so the PBR hero ship reads out here, away from the hub lights.
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.5
	sun.rotation = Vector3(deg_to_rad(-35.0), deg_to_rad(35.0), 0.0)
	_rig.add_child(sun)

	# Destination planet: the fal.ai 3D planet (photographic detail, slowly spinning,
	# self-lit); falls back to the procedural planet shader if the GLB is missing.
	var pb: Node3D = preload("res://scripts/planet_body.gd").new()
	pb.name = "Planet"
	_rig.add_child(pb)
	pb.position = PLANET_POS
	if pb.setup(_mission, PLANET_RADIUS, 0.05):
		_planet = pb
	else:
		pb.queue_free()
		_planet = _build_procedural_planet()

	# The flight path + the ship mounted on a PathFollow3D (position along the curve is
	# tweened; the model's heading is corrected by SHIP_YAW).
	var path := Path3D.new()
	path.name = "Path"
	var curve := Curve3D.new()
	for p in PATH_PTS:
		curve.add_point(p)
	path.curve = curve
	_rig.add_child(path)

	_ship_follow = PathFollow3D.new()
	_ship_follow.rotation_mode = PathFollow3D.ROTATION_ORIENTED
	_ship_follow.loop = false
	path.add_child(_ship_follow)         # in-tree before touching progress_ratio
	_ship_follow.progress_ratio = 0.0

	# Wrapper carries the axis fix + banking/pitch; the GLB rides inside it.
	_ship_model = Node3D.new()
	_ship_model.name = "ShipModel"
	_ship_follow.add_child(_ship_model)
	var glb := load(SHIP_GLB)
	if glb is PackedScene:
		var body := (glb as PackedScene).instantiate() as Node3D
		body.rotation.y = SHIP_YAW
		body.scale = Vector3.ONE * SHIP_SCALE
		_ship_model.add_child(body)

	# A warm engine glow trailing the ship, brightened on the Fold.
	_engine_glow = OmniLight3D.new()
	_engine_glow.light_color = Color(0.5, 0.75, 1.0)
	_engine_glow.light_energy = 2.0
	_engine_glow.omni_range = 14.0
	_engine_glow.position = Vector3(0.0, 0.0, 6.0)   # behind the nose (nose is -Z)
	_ship_model.add_child(_engine_glow)

	_cam = Camera3D.new()
	_cam.name = "CineCam"
	_cam.fov = 60.0
	_cam.far = 4000.0
	_rig.add_child(_cam)
	_cam_offset = CAM_OFF_FOLD
	_cam.global_position = _ship_model.global_position + _cam_offset


## Fallback destination planet on the procedural shader (used only if the fal.ai GLB
## is missing), tinted per world to match the one out the cockpit window.
func _build_procedural_planet() -> Node3D:
	var planet := MeshInstance3D.new()
	planet.name = "Planet"
	var sphere := SphereMesh.new()
	sphere.radius = PLANET_RADIUS
	sphere.height = PLANET_RADIUS * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	planet.mesh = sphere
	planet.extra_cull_margin = PLANET_RADIUS * 2.0
	var pshader := load(PLANET_SHADER)
	if pshader:
		var pmat := ShaderMaterial.new()
		pmat.shader = pshader
		var w: Dictionary = WORLDS[_mission]
		pmat.set_shader_parameter("ocean_color", w["ocean"])
		pmat.set_shader_parameter("land_color", w["land"])
		pmat.set_shader_parameter("atmo_color", w["atmo"])
		pmat.set_shader_parameter("land_threshold", w["threshold"])
		pmat.set_shader_parameter("band_strength", w["bands"])
		pmat.set_shader_parameter("cloud_amount", w["clouds"])
		pmat.set_shader_parameter("rot_speed", 0.03)
		planet.material_override = pmat
	_rig.add_child(planet)
	planet.position = PLANET_POS
	return planet


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "CutsceneUI"
	_ui.layer = 40
	add_child(_ui)

	# Full-screen warp streaks (starts opaque during FOLD, clears on APPROACH).
	_warp_rect = ColorRect.new()
	_warp_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_warp_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wshader := load(WARP_SHADER)
	if wshader:
		_warp_mat = ShaderMaterial.new()
		_warp_mat.shader = wshader
		_warp_mat.set_shader_parameter("warp", 0.0)
		var vp := get_viewport().get_visible_rect().size
		if vp.y > 0.0:
			_warp_mat.set_shader_parameter("aspect", vp.x / vp.y)
		_warp_rect.material = _warp_mat
	_ui.add_child(_warp_rect)

	# Cinematic letterbox bars (slide in from off-screen during APPROACH).
	_bar_top = _mk_bar()
	_bar_top.anchor_left = 0.0
	_bar_top.anchor_right = 1.0
	_bar_top.offset_bottom = 0.0
	_bar_top.offset_top = -120.0            # parked above the screen
	_ui.add_child(_bar_top)

	_bar_bottom = _mk_bar()
	_bar_bottom.anchor_left = 0.0
	_bar_bottom.anchor_right = 1.0
	_bar_bottom.anchor_top = 1.0
	_bar_bottom.anchor_bottom = 1.0
	_bar_bottom.offset_top = 0.0
	_bar_bottom.offset_bottom = 120.0       # parked below the screen
	_ui.add_child(_bar_bottom)

	# Lower-left title card, reference styling: thin wide-tracked caps. Text is the shared,
	# realistic fold card (named landing site + planet designation + environmental readout).
	var ft := _fold_text()
	_title = Label.new()
	_title.text = ft["site"]
	_title.add_theme_font_size_override("font_size", 30)
	_title.add_theme_color_override("font_color", Color(0.88, 0.95, 1.0))
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_title.add_theme_constant_override("outline_size", 6)
	_title.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_title.position = Vector2(56, -132)
	_title.modulate.a = 0.0
	_ui.add_child(_title)

	_subtitle = Label.new()
	_subtitle.text = "%s      %s" % [ft["designation"], ft["readout"]]
	_subtitle.add_theme_font_size_override("font_size", 15)
	_subtitle.add_theme_color_override("font_color", Color(0.55, 0.78, 0.95))
	_subtitle.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_subtitle.add_theme_constant_override("outline_size", 4)
	_subtitle.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_subtitle.position = Vector2(58, -96)
	_subtitle.modulate.a = 0.0
	_ui.add_child(_subtitle)

	_skip_hint = Label.new()
	_skip_hint.text = "[E] SKIP"
	_skip_hint.add_theme_font_size_override("font_size", 14)
	_skip_hint.add_theme_color_override("font_color", Color(0.7, 0.75, 0.82))
	_skip_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_skip_hint.add_theme_constant_override("outline_size", 4)
	_skip_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip_hint.position = Vector2(-96, -40)
	_ui.add_child(_skip_hint)


## The shared realistic fold card for this mission (named landing site + planet designation +
## environmental readout), read from ShipTravel.FOLD_TEXT so there is one source of truth.
## Falls back to a plain planet name if the mission is unknown.
func _fold_text() -> Dictionary:
	var st = get_node_or_null("/root/ShipTravel")
	if st != null:
		var ft = st.FOLD_TEXT
		if ft is Dictionary and ft.has(_mission):
			return ft[_mission]
	return {"site": "%s - DESCENT" % _mission.to_upper(), "designation": _mission.to_upper(), "readout": ""}


func _mk_bar() -> ColorRect:
	var bar := ColorRect.new()
	bar.color = Color(0, 0, 0, 1)
	bar.custom_minimum_size = Vector2(0, 120)
	bar.offset_left = 0.0
	bar.offset_right = 0.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bar


## Drive the beats with a single chained tween. Node stays alive until ShipTravel
## frees it on the scene swap, so the tween completing is fine.
func _run() -> void:
	_set_state(State.FOLD)
	var tw := create_tween()

	# FOLD: warp ramps up fast and holds; engines flare.
	_warp_mat.set_shader_parameter("warp", 0.0) if _warp_mat else null
	tw.tween_method(_set_warp, 0.0, 1.0, T_FOLD * 0.55)
	tw.parallel().tween_property(_engine_glow, "light_energy", 6.0, T_FOLD * 0.55)
	tw.tween_interval(T_FOLD * 0.45)

	# APPROACH: reveal the cinematic (warp clears), fly + bank in, bars + title in.
	tw.tween_callback(func() -> void: _set_state(State.APPROACH))
	tw.parallel().tween_method(_set_warp, 1.0, 0.0, 0.7)
	tw.parallel().tween_property(_ship_follow, "progress_ratio", 0.62, T_APPROACH) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(self, "_cam_offset", CAM_OFF_APPROACH, T_APPROACH) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_ship_model, "rotation:z", deg_to_rad(28.0), T_APPROACH * 0.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(_bar_top, "offset_top", 0.0, 0.6).set_delay(0.2)
	tw.parallel().tween_property(_bar_bottom, "offset_bottom", 0.0, 0.6).set_delay(0.2)
	tw.parallel().tween_property(_title, "modulate:a", 1.0, 0.5).set_delay(0.6)
	tw.parallel().tween_property(_subtitle, "modulate:a", 1.0, 0.5).set_delay(0.8)

	# DESCENT: level the bank, pitch the nose down, dive at the planet; the look-at
	# biases toward the world so it swells to fill the frame.
	tw.tween_callback(func() -> void: _set_state(State.DESCENT))
	tw.parallel().tween_property(_ship_follow, "progress_ratio", 1.0, T_DESCENT) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_ship_model, "rotation:z", 0.0, T_DESCENT * 0.4)
	tw.parallel().tween_property(_ship_model, "rotation:x", deg_to_rad(-26.0), T_DESCENT * 0.7) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(self, "_cam_offset", CAM_OFF_DESCENT, T_DESCENT) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(self, "_focus_bias", FOCUS_DESCENT, T_DESCENT) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	tw.tween_callback(_finish)


func _set_warp(v: float) -> void:
	if _warp_mat:
		_warp_mat.set_shader_parameter("warp", v)


func _set_state(s: int) -> void:
	_state = s
	state_changed.emit(s)


func _finish() -> void:
	if _done:
		return
	_done = true
	_stop_audio()
	_set_state(State.HANDOFF)
	handoff.emit(_mission)


## Fold audio: the warp boom on the jump, a looping engine bed during the flight, and the
## travel-music stinger. All generated on fal.ai; if a clip is missing these are silent
## no-ops (AudioManager falls back / returns null).
func _start_audio() -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am == null:
		return
	if am.has_method("play_sfx"):
		am.play_sfx("warp")
	if am.has_method("play_music"):
		am.play_music("travel")
	if am.has_method("_sfx"):
		var eng: AudioStream = am._sfx("engine")
		if eng:
			_engine_player = AudioStreamPlayer.new()
			_engine_player.bus = "SFX"
			_engine_player.stream = eng
			_engine_player.volume_db = -6.0
			add_child(_engine_player)
			_engine_player.play()


func _stop_audio() -> void:
	if _engine_player and is_instance_valid(_engine_player):
		_engine_player.stop()


## Chase-cam: every frame the camera sits at a fixed (tweened) offset from the ship and
## looks at a point biased from the ship toward the planet - so the hero ship holds a
## consistent size and the world stays composed behind it, no hand-keyed look-at needed.
func _process(_delta: float) -> void:
	if _cam == null or _ship_model == null or not is_instance_valid(_ship_model):
		return
	var ship_pos := _ship_model.global_position
	var planet_pos := _planet.global_position
	_cam.global_position = ship_pos + _cam_offset
	var focus := ship_pos.lerp(planet_pos, _focus_bias)
	if _cam.global_position.distance_to(focus) > 0.01:
		_cam.look_at(focus, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if _done:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_finish()

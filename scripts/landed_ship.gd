extends Node3D
## The player's parked ship - a large hero_ship.glb sitting on a landing pad BEHIND the
## spawn, as a permanent landmark and the mission's extraction point. It is always there
## ("waiting for extraction"); ExtractionCountdown finds it (group "extraction_ship") and
## uses it as the board point instead of spawning a throwaway ship. The pad under it
## guarantees a flat footprint clear of props so the big hull always fits.
##
## It also plays two in-mission cinematics from a 3rd-person camera on the same scene:
## `start_landing()` (the ship descends onto the pad on arrival, then hands control back)
## and `begin_boarding()` -> `[L]` -> lift-off (the ship climbs into the sky, then emits
## `lifted_off` so the extraction returns to the hub).

signal lifted_off

const SHIP_GLB := "res://assets/generated/ship/hero_ship.glb"
const PAD_GLB := "res://assets/generated/ship/landing_pad.glb"

## Cinematics: how high the ship starts (landing) / ends (lift-off) above the pad, the
## durations, and the 3rd-person camera offset from the pad (local: right / up / back).
## CAM_OFFSET is the default; a level can pass its own to configure() when its clear
## framing is on a different side (e.g. Venus frames the ship against its open bay, not
## the narrow ascent gorge behind the nose).
const SKY_HEIGHT := 95.0
const LAND_TIME := 3.4
const LIFT_TIME := 3.0
const CAM_OFFSET := Vector3(16.0, 9.0, 24.0)
## How close the player must be to the ship to board it, and where to go on lift-off.
const BOARD_RANGE := 8.0
const HUB_SCENE := "res://scenes/hub/hub.tscn"
const CREDITS_SCENE := "res://ui/credits.tscn"

var _parked_y: float = 0.0
var _busy: bool = false
var _boardable: bool = false        # true once landed - the player may board to leave
var _prompt_shown: bool = false
var _await_liftoff: bool = false
var _completed_run: bool = false        # true when boarding via the extraction (mission cleared), not a manual early [E] board
var _cine_cam: Camera3D
var _player: Node3D
var _player_cam: Camera3D
var _hud: CanvasLayer
var _prompt: Label
var _engine_player: AudioStreamPlayer3D
## hero_ship.glb is a wide, low-profile craft (~0.98 m mesh -> ~8.8 x 8.3 x 1.3 m at x9).
## x13 makes it a ~13 m-wide landed ship - clearly large next to the ~1.8 m Guardian
## (about half a realistic ship-to-human ratio, as asked). Per-map overridable via
## configure() where a level's clear space is tighter (Mars).
const SHIP_SCALE := 13.0

var _scale: float = SHIP_SCALE
var _height_scale: float = 1.0          # extra VERTICAL scale so the flat hull reads as a real ship
var _ship: Node3D
var _footprint: float = 6.0
var _cam_offset: Vector3 = CAM_OFFSET   # 3rd-person cine offset (level-overridable)


func _ready() -> void:
	add_to_group("extraction_ship")


## Place the parked ship. `pad_center` is the ground point the pad sits on; the ship is
## turned so its nose faces `look_target` (the spawn), so it reads as "landed facing you".
func configure(pad_center: Vector3, look_target: Vector3, ship_scale := SHIP_SCALE, cam_offset := CAM_OFFSET, height_scale := 1.0) -> void:
	_scale = ship_scale
	_cam_offset = cam_offset
	_height_scale = height_scale
	global_position = pad_center
	_build()
	var to := look_target - global_position
	to.y = 0.0
	if to.length() > 0.5:
		look_at(global_position + to, Vector3.UP)
	# Boardable by default; start_landing() suppresses the prompt (via _busy) until the
	# arrival touchdown finishes, and re-affirms it in _end_landing.
	_boardable = true


## The radius of clear ground the parked ship needs (pad radius); callers use it to carve
## space / move hazards back so the hull never sits inside props.
func clearance() -> float:
	return _footprint * 0.62 + 3.5


func _build() -> void:
	if not ResourceLoader.exists(SHIP_GLB):
		_fallback(); return
	var packed := load(SHIP_GLB)
	if not (packed is PackedScene):
		_fallback(); return
	_ship = (packed as PackedScene).instantiate() as Node3D
	add_child(_ship)
	# Non-uniform: extra vertical scale gives the wide, flat hull real height so it reads as a
	# ship next to a ~1.8 m human (height_scale 1.0 = uniform, unchanged for Earth/Mars).
	_ship.scale = Vector3(_scale, _scale * _height_scale, _scale)
	var ab := _aabb(_ship)
	_footprint = maxf(ab.size.x, ab.size.z)
	# Seat the hull's base just above the pad top (pad top sits at PAD_TOP).
	_ship.position.y = -ab.position.y + PAD_TOP + 0.05
	_parked_y = _ship.position.y
	_build_pad(clearance())
	_build_hull_collision()
	_build_beacons(clearance())


# --- cinematics -------------------------------------------------------------

## Arrival: the ship drops out of the sky onto its pad, framed 3rd-person, then hands
## control back to the player. Called by the mission once the level is built.
func start_landing() -> void:
	if _ship == null or _busy:
		return
	_busy = true
	_freeze_player(true)
	_make_cine_cam()
	_engine(true)
	_ship.position.y = _parked_y + SKY_HEIGHT
	var tw := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_ship, "position:y", _parked_y, LAND_TIME)
	tw.tween_callback(_end_landing)


func _end_landing() -> void:
	_engine(false)
	_release_cine_cam()
	_freeze_player(false)
	_busy = false
	_boardable = true        # from now on, walking up to the ship lets you board + leave


## Boarding: swap to a 3rd-person view of the ship and wait for the player to press [L]
## to lift off. Reached by walking up to the ship ([E]) any time during a mission, or from
## ExtractionCountdown at mission end. On lift-off the ship flies up and returns to the hub.
func begin_boarding(from_extraction := false) -> void:
	if _ship == null or _busy:
		return
	_completed_run = from_extraction
	_busy = true
	_boardable = false
	_hide_prompt()
	_freeze_player(true)
	_make_cine_cam()
	_show_prompt("[L]  Lift off")
	_await_liftoff = true
	set_process_unhandled_input(true)


func _liftoff() -> void:
	_await_liftoff = false
	_hide_prompt()
	_engine(true)
	var tw := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_ship, "position:y", _parked_y + SKY_HEIGHT, LIFT_TIME)
	tw.tween_callback(_return_home)


## Lift-off complete: sweep up any loot the player left, notify listeners, and fly home to
## the hub (the ship interior in orbit).
func _return_home() -> void:
	_engine(false)
	lifted_off.emit()
	for l in get_tree().get_nodes_in_group("loot"):
		if is_instance_valid(l) and l.has_method("pickup"):
			l.pickup()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# After the in-engine climb, play the LIFT-OFF cinematic (the ship leaves the atmosphere
	# and docks into the mothership where it rests); it then dissolves to the destination. Falls
	# back to the plain transition if the clip / ShipTravel is missing, so extraction never stalls.
	# Clearing Venus on the hardest tier (Legendary) rolls the credits between the orbit
	# cinematic and the hub; the roll then continues into the hub itself.
	var dest := HUB_SCENE
	if _completed_run and _venus_legendary_cleared():
		Credits.next_scene = HUB_SCENE
		dest = CREDITS_SCENE
	var st := get_node_or_null("/root/ShipTravel")
	if st and st.has_method("play_liftoff") and st.play_liftoff(dest):
		return
	var gs := get_node_or_null("/root/GameState")
	if gs and gs.has_method("transition_to"):
		gs.transition_to(dest)
	else:
		get_tree().change_scene_to_file(dest)


## True when the run just finished IS the Venus mission played on Legendary (the hardest
## tier). Read from the Difficulty autoload, which resolves the mission from the scene and
## the effective tier from the save; safe (returns false) if the autoload is absent.
func _venus_legendary_cleared() -> bool:
	var diff := get_node_or_null("/root/Difficulty")
	if diff == null:
		return false
	var mid := String(diff.current_mission()) if diff.has_method("current_mission") else ""
	if mid != "Venus":
		return false
	return diff.has_method("current") and String(diff.current(mid)) == "Legendary"


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		if _await_liftoff and event is InputEventKey and event.pressed and not event.echo \
				and event.keycode == KEY_L:
			get_viewport().set_input_as_handled()
			_liftoff()
		return
	# [E] near the parked ship boards it (and lets you leave the mission).
	if _boardable and event.is_action_pressed("interact") and _player_near():
		get_viewport().set_input_as_handled()
		begin_boarding()


## True when the player is close enough to board the parked ship - and alive.
## A dead/respawning Guardian must not board (they can die on the pad; boarding
## then would strand them in the leave-mission cinematic mid-death).
func _player_near() -> bool:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null or ("is_dead" in p and p.is_dead):
		return false
	return p.global_position.distance_to(global_position) <= BOARD_RANGE


## Keep the 3rd-person camera aimed at the ship during a cinematic; otherwise show the
## "[E] Board ship" prompt whenever the player is standing by the parked ship.
func _process(_delta: float) -> void:
	if _cine_cam and _ship and is_instance_valid(_ship):
		var to := _ship.global_position
		if _cine_cam.global_position.distance_to(to) > 0.1:
			_cine_cam.look_at(to, Vector3.UP)
		return
	if _boardable and not _busy:
		var near := _player_near()
		if near and not _prompt_shown:
			_show_prompt("[E]  Board ship  -  leave the mission")
			_prompt_shown = true
		elif not near and _prompt_shown:
			_hide_prompt()
			_prompt_shown = false


func _make_cine_cam() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player:
		_player_cam = _player.get_node_or_null("SpringArm3D/Camera3D") as Camera3D
	_cine_cam = Camera3D.new()
	_cine_cam.fov = 58.0
	_cine_cam.far = 3000.0
	add_child(_cine_cam)
	_cine_cam.global_position = to_global(_cam_offset)   # fixed ground spot by the pad
	_cine_cam.look_at(_ship.global_position, Vector3.UP)
	_cine_cam.make_current()


func _release_cine_cam() -> void:
	if _player_cam and is_instance_valid(_player_cam):
		_player_cam.make_current()
	if _cine_cam and is_instance_valid(_cine_cam):
		_cine_cam.queue_free()
	_cine_cam = null


func _freeze_player(frozen: bool) -> void:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p:
		p.process_mode = Node.PROCESS_MODE_DISABLED if frozen else Node.PROCESS_MODE_INHERIT
		var hud := p.get_node_or_null("DebugHUD") as CanvasLayer
		if hud:
			hud.visible = not frozen
		# Hide the first-person weapon viewmodel (the composited arms+gun overlay) so the gun
		# doesn't hang in the corner of the 3rd-person cinematic.
		var vm = p.get("_fp_viewmodel")
		if vm and is_instance_valid(vm) and vm.has_method("set_shown"):
			vm.set_shown(not frozen)
	# Hide the mission HUD (objectives panel etc.) during the cinematic.
	for h in get_tree().get_nodes_in_group("mission_hud"):
		if h is CanvasLayer:
			(h as CanvasLayer).visible = not frozen
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if frozen else Input.MOUSE_MODE_CAPTURED


## A looping engine bed during the cinematics (uses the generated engine SFX if present).
func _engine(on: bool) -> void:
	if on:
		var am := get_node_or_null("/root/AudioManager")
		if am == null or not am.has_method("_sfx"):
			return
		var stream: AudioStream = am._sfx("engine")
		if stream == null:
			return
		_engine_player = AudioStreamPlayer3D.new()
		_engine_player.bus = "SFX"
		_engine_player.stream = stream
		add_child(_engine_player)
		_engine_player.global_position = global_position
		_engine_player.play()
	elif _engine_player and is_instance_valid(_engine_player):
		_engine_player.stop()
		_engine_player.queue_free()
		_engine_player = null


func _show_prompt(text: String) -> void:
	if _hud == null:
		_hud = CanvasLayer.new()
		_hud.layer = 25
		add_child(_hud)
		_prompt = Label.new()
		_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		_prompt.anchor_left = 0.5
		_prompt.anchor_right = 0.5
		_prompt.position = Vector2(-160, -120)
		_prompt.custom_minimum_size = Vector2(320, 0)
		_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_prompt.add_theme_font_size_override("font_size", 22)
		_prompt.add_theme_color_override("font_color", Color(1.0, 0.82, 0.34))
		_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		_prompt.add_theme_constant_override("outline_size", 6)
		_hud.add_child(_prompt)
	_prompt.text = text
	_prompt.visible = true


func _hide_prompt() -> void:
	if _prompt:
		_prompt.visible = false


## Pad COLLISION top height (local). FLUSH with the surrounding ground (which sits at the
## ship's y) so there is NO step/lip to jump over - you just walk on. The visual pad is
## lifted PAD_VISUAL_LIFT above it so the two meshes never z-fight.
const PAD_TOP := 0.0
const PAD_VISUAL_LIFT := 0.06


## A landing pad the player can walk straight onto: a solid collision disc FLUSH with the
## ground (no lip) topped with the generated pad asset (or a plain disc if it is missing),
## lifted a few cm so it never z-fights the ground.
func _build_pad(radius: float) -> void:
	var pad := StaticBody3D.new()
	pad.name = "Pad"
	add_child(pad)
	# Solid collision cylinder, its TOP flush at PAD_TOP (= ground level -> walkable, no jump).
	var col := CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = radius
	cs.height = 1.2
	col.shape = cs
	col.position.y = PAD_TOP - 0.6
	pad.add_child(col)

	# Visual: the generated fal.ai landing pad asset, scaled to the pad radius and seated with
	# its top just above the ground; falls back to a simple bevelled disc if the GLB is missing.
	if ResourceLoader.exists(PAD_GLB):
		var packed := load(PAD_GLB)
		if packed is PackedScene:
			var m := (packed as PackedScene).instantiate() as Node3D
			pad.add_child(m)
			var raw := _child_aabb(m)
			var d: float = maxf(raw.size.x, raw.size.z)
			if d > 0.01:
				m.scale = Vector3.ONE * (radius * 2.0 / d)
			var fit := _child_aabb(m)
			m.position = Vector3(-fit.get_center().x, PAD_TOP + PAD_VISUAL_LIFT - (fit.position.y + fit.size.y), -fit.get_center().z)
			return
	var mesh := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius + 1.2
	cm.height = 1.0
	cm.radial_segments = 32
	mesh.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.13, 0.14, 0.16)
	mat.metallic = 0.7
	mat.roughness = 0.5
	mesh.material_override = mat
	mesh.position.y = PAD_TOP + PAD_VISUAL_LIFT - 0.5
	pad.add_child(mesh)


## A solid box collider around the hull so the player can't walk through the parked ship.
func _build_hull_collision() -> void:
	var ab := _aabb(_ship)
	var body := StaticBody3D.new()
	body.name = "HullBody"
	add_child(body)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(ab.size.x * 0.9, maxf(ab.size.y, 2.0), ab.size.z * 0.9)
	col.shape = box
	col.position = ab.position + ab.size * 0.5
	body.add_child(col)


## A ring of warm marker lights + a soft beacon, so the parked ship reads at a distance.
func _build_beacons(radius: float) -> void:
	var beacon := OmniLight3D.new()
	beacon.light_color = Color(0.45, 0.7, 1.0)
	beacon.light_energy = 1.0
	beacon.omni_range = radius * 2.2
	beacon.position = Vector3(0, 6.0, 0)
	add_child(beacon)
	for i in 8:
		var a := TAU * float(i) / 8.0
		var e := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.2, 1.2, 0.2)              # slim marker post
		e.mesh = bm
		var em := StandardMaterial3D.new()
		em.emission_enabled = true
		em.emission = Color(1.0, 0.62, 0.24)
		em.emission_energy_multiplier = 1.4
		em.albedo_color = Color(0.4, 0.28, 0.16)
		e.material_override = em
		e.position = Vector3(cos(a) * radius, 0.6, sin(a) * radius)
		add_child(e)


func _fallback() -> void:
	# No GLB: a simple box so the extraction point still exists visibly.
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(8, 4, 12)
	box.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.22, 0.26)
	mat.metallic = 0.6
	box.mesh = bm
	box.material_override = mat
	box.position.y = 2.0
	add_child(box)
	_footprint = 12.0


func _aabb(root: Node) -> AABB:
	var acc := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var world: AABB = mi.global_transform * mi.get_aabb()
		if first:
			acc = world
			first = false
		else:
			acc = acc.merge(world)
	# express relative to this node so callers get a local footprint
	acc.position -= global_position
	return acc


## AABB of `m`'s meshes expressed in its PARENT's local frame (for seating a pad GLB).
func _child_aabb(m: Node3D) -> AABB:
	var acc := AABB()
	var first := true
	for node in m.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var world: AABB = mi.global_transform * mi.get_aabb()
		if first:
			acc = world
			first = false
		else:
			acc = acc.merge(world)
	if not first and m.get_parent() is Node3D:
		acc = (m.get_parent() as Node3D).global_transform.affine_inverse() * acc
	return acc

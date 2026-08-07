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
const SKY_HEIGHT := 95.0
const LAND_TIME := 3.4
const LIFT_TIME := 3.0
const CAM_OFFSET := Vector3(16.0, 9.0, 24.0)

var _parked_y: float = 0.0
var _busy: bool = false
var _await_liftoff: bool = false
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
var _ship: Node3D
var _footprint: float = 6.0


func _ready() -> void:
	add_to_group("extraction_ship")


## Place the parked ship. `pad_center` is the ground point the pad sits on; the ship is
## turned so its nose faces `look_target` (the spawn), so it reads as "landed facing you".
func configure(pad_center: Vector3, look_target: Vector3, ship_scale := SHIP_SCALE) -> void:
	_scale = ship_scale
	global_position = pad_center
	_build()
	var to := look_target - global_position
	to.y = 0.0
	if to.length() > 0.5:
		look_at(global_position + to, Vector3.UP)


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
	_ship.scale = Vector3.ONE * _scale
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


## Boarding: swap to a 3rd-person view of the ship and wait for the player to press [L]
## to lift off. Called by ExtractionCountdown when the player boards at the ship.
func begin_boarding() -> void:
	if _ship == null or _busy:
		return
	_busy = true
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
	tw.tween_callback(func() -> void:
		_engine(false)
		lifted_off.emit())


func _unhandled_input(event: InputEvent) -> void:
	if _await_liftoff and event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_L:
		get_viewport().set_input_as_handled()
		_liftoff()


## Keep the 3rd-person camera aimed at the ship as it moves through a cinematic.
func _process(_delta: float) -> void:
	if _cine_cam and _ship and is_instance_valid(_ship):
		var to := _ship.global_position
		if _cine_cam.global_position.distance_to(to) > 0.1:
			_cine_cam.look_at(to, Vector3.UP)


func _make_cine_cam() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player:
		_player_cam = _player.get_node_or_null("SpringArm3D/Camera3D") as Camera3D
	_cine_cam = Camera3D.new()
	_cine_cam.fov = 58.0
	_cine_cam.far = 3000.0
	add_child(_cine_cam)
	_cine_cam.global_position = to_global(CAM_OFFSET)   # fixed ground spot by the pad
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
		# Hide the first-person weapon viewmodel (its own CanvasLayer overlay) so the gun
		# doesn't hang in the corner of the 3rd-person cinematic.
		var vm := p.get_node_or_null("SpringArm3D/Camera3D/WeaponViewmodel")
		if vm:
			for c in vm.get_children():
				if c is CanvasLayer:
					(c as CanvasLayer).visible = not frozen
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
		_prompt.add_theme_font_size_override("font_size", 26)
		_prompt.add_theme_color_override("font_color", Color(1.0, 0.82, 0.34))
		_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		_prompt.add_theme_constant_override("outline_size", 6)
		_hud.add_child(_prompt)
	_prompt.text = text
	_prompt.visible = true


func _hide_prompt() -> void:
	if _prompt:
		_prompt.visible = false


## Pad surface height (local). Kept a touch above 0 so the pad + ship never z-fight with
## the ground/apron they rest on (the coplanar cylinder was the source of the flicker).
const PAD_TOP := 0.15


## A landing pad the player can stand on: a solid collision disc (so you never fall
## through it) topped with the generated pad asset (or a plain disc if it is missing).
func _build_pad(radius: float) -> void:
	var pad := StaticBody3D.new()
	pad.name = "Pad"
	add_child(pad)
	# Solid collision cylinder, its TOP at PAD_TOP.
	var col := CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = radius
	cs.height = 1.2
	col.shape = cs
	col.position.y = PAD_TOP - 0.6
	pad.add_child(col)

	# Visual: the generated fal.ai landing pad asset, scaled to the pad radius and seated
	# with its top at PAD_TOP; falls back to a simple bevelled disc if the GLB is missing.
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
			m.position = Vector3(-fit.get_center().x, PAD_TOP - (fit.position.y + fit.size.y), -fit.get_center().z)
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
	mesh.position.y = PAD_TOP - 0.5
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

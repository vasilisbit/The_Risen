extends Node3D
## The player's parked ship - a large hero_ship.glb sitting on a landing pad BEHIND the
## spawn, as a permanent landmark and the mission's extraction point. It is always there
## ("waiting for extraction"); ExtractionCountdown finds it (group "extraction_ship") and
## uses it as the board point instead of spawning a throwaway ship. The pad under it
## guarantees a flat footprint clear of props so the big hull always fits.

const SHIP_GLB := "res://assets/generated/ship/hero_ship.glb"
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
	# Seat the hull's base on the pad top (local y = 0).
	_ship.position.y = -ab.position.y + 0.1
	_build_pad(clearance())
	_build_beacons(clearance())


## A low metal landing pad with collision, so the ship stands on flat ground the player
## can walk onto, regardless of the terrain under it.
func _build_pad(radius: float) -> void:
	var pad := StaticBody3D.new()
	pad.name = "Pad"
	add_child(pad)
	var mesh := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius + 1.2
	cm.height = 1.0
	cm.radial_segments = 24
	mesh.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.13, 0.14, 0.16)
	mat.metallic = 0.7
	mat.roughness = 0.5
	mesh.material_override = mat
	mesh.position.y = -0.5
	pad.add_child(mesh)
	var col := CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = radius
	cs.height = 1.0
	col.shape = cs
	col.position.y = -0.5
	pad.add_child(col)


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

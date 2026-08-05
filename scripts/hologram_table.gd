extends Node3D

## Dresses the three mission spheres as holographic projections of the planets
## themselves, using the same fbm surface as the hub viewport planet so a world
## reads as the same place on the table and out the window.
##
## Locked missions project dimmer and desaturated, so the table shows at a
## glance how far you have got without needing a separate label.

const SHADER := "res://shaders/hologram_planet.gdshader"

## Per-planet look. `base`/`land` are the two tones the surface mixes between;
## `bands` is the latitude banding that Earth barely has and Venus is made of.
const PLANETS := {
	"Earth": {
		"node": "EarthSphere", "base": Color(0.10, 0.45, 1.00),
		"land": Color(0.45, 0.95, 0.85), "threshold": 0.52, "bands": 0.05,
	},
	"Mars": {
		"node": "MarsSphere", "base": Color(1.00, 0.30, 0.15),
		"land": Color(1.00, 0.65, 0.35), "threshold": 0.46, "bands": 0.28,
	},
	"Venus": {
		"node": "VenusSphere", "base": Color(1.00, 0.55, 0.12),
		"land": Color(1.00, 0.85, 0.45), "threshold": 0.40, "bands": 0.55,
	},
}

const LOCKED_BRIGHTNESS := 0.35
const UNLOCKED_BRIGHTNESS := 1.0

## Realistic planet renders (fal.ai) projected as teal-tinted holograms over the table.
const PLANET_TEX := {
	"Earth": "res://assets/generated/interior/planet_earth.png",
	"Mars": "res://assets/generated/interior/planet_mars.png",
	"Venus": "res://assets/generated/interior/planet_venus.png",
}
const HOLO_TINT := Color(0.55, 0.85, 1.05)

## Label sits just above each floating planet (radius 0.35 at y = 2.2).
const LABEL_HEIGHT := 0.6
const LABEL_SIZE := 0.11
## Table top surface height and each planet's world height. The holo-table asset is
## scaled so its top lands at TABLE_TOP_Y; the worlds float well above it.
const TABLE_TOP_Y := 0.95
const PLANET_Y := 1.95           # about eye level, floating above the table
const PLANET_RADIUS := 0.35

var _materials: Dictionary = {}          # mission -> StandardMaterial3D (holo billboard)
var _tints: Dictionary = {}              # mission -> base tint (for locked dimming)
var _labels: Dictionary = {}             # mission -> Label3D
var _projectors: Dictionary = {}         # mission -> StandardMaterial3D (beam)
var _flicker: float = 0.0

## Projector-beam tint per planet: Earth blue, Mars red, Venus yellow, so each
## cone reads as its own world at a glance.
const BEAM_TINT := Color(0.35, 0.75, 1.0)
const BEAM_TINTS := {
	"Earth": Color(0.35, 0.75, 1.0),
	"Mars": Color(1.0, 0.32, 0.22),
	"Venus": Color(1.0, 0.82, 0.30),
}


func _ready() -> void:
	_build()
	refresh()


## Labels flicker in sympathy with the projections they name, so the text reads
## as part of the hologram rather than as UI floating in the room.
func _process(delta: float) -> void:
	_flicker += delta
	var wobble := 0.88 + 0.12 * sin(_flicker * 9.0)
	for mission in _labels:
		var label: Label3D = _labels[mission]
		var base: float = float(label.get_meta("base_alpha"))
		label.modulate.a = base * wobble


## Repaint from save progress. The hub reloads on return from a mission, so
## _ready covers the normal path; this exists for tests and future in-place use.
func refresh() -> void:
	var sm := get_node_or_null("/root/SaveManager")
	for mission in _materials:
		var unlocked := true
		if sm and sm.has_method("is_mission_unlocked"):
			unlocked = sm.is_mission_unlocked(mission)
		var mat: StandardMaterial3D = _materials[mission]
		var tint: Color = _tints.get(mission, HOLO_TINT)
		mat.albedo_color = tint * (UNLOCKED_BRIGHTNESS if unlocked else LOCKED_BRIGHTNESS)
		if _labels.has(mission):
			var label: Label3D = _labels[mission]
			# A locked world still names itself, but says so. The suffix goes on
			# its own line - inline, the three labels ran into each other.
			label.text = mission.to_upper() if unlocked else "%s\nLOCKED" % mission.to_upper()
			label.set_meta("base_alpha", 0.95 if unlocked else 0.45)
		if _projectors.has(mission):
			var beam: StandardMaterial3D = _projectors[mission]
			beam.emission_energy_multiplier = 1.3 if unlocked else 0.4
			beam.albedo_color.a = 0.10 if unlocked else 0.04


func _build() -> void:
	_build_console()
	for mission in PLANETS:
		var info: Dictionary = PLANETS[mission]
		var mesh := get_node_or_null("%s/Mesh" % info["node"]) as MeshInstance3D
		if mesh == null:
			continue
		# Hide the old stylised fbm sphere; project the realistic planet render as a
		# teal-tinted holographic billboard instead (blend-add so black reads as clear).
		mesh.visible = false
		var anchor := mesh.get_parent() as Node3D
		var bb := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(PLANET_RADIUS * 2.4, PLANET_RADIUS * 2.4)
		bb.mesh = qm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.billboard_keep_scale = true
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var tex := load(String(PLANET_TEX.get(mission, ""))) as Texture2D
		if tex:
			mat.albedo_texture = tex
		mat.albedo_color = HOLO_TINT
		bb.material_override = mat
		anchor.add_child(bb)
		_materials[mission] = mat
		_tints[mission] = HOLO_TINT
		_labels[mission] = _build_label(anchor, info["base"])
		_projectors[mission] = _build_projector(anchor, BEAM_TINTS.get(mission, BEAM_TINT))


## A projector beam under each planet: a glowing emitter on the table surface and
## a translucent cone of light widening up toward the planet, which floats just
## ABOVE the beam's tip (not inside it). Built as children of the planet anchor,
## whose origin is the planet centre at world y = PLANET_Y. Returns the beam
## material so refresh() can dim it for locked worlds.
func _build_projector(anchor: Node3D, tint: Color) -> StandardMaterial3D:
	# Local heights (anchor origin is the planet centre). The cone's mouth sits a
	# little BELOW the planet's equator and is slightly narrower than the planet,
	# so the sphere seats down into the cone like a ball in a cup - its widest
	# point rests on the rim rather than the whole sphere perching on top.
	# The worlds are now flat billboards (radius ~PLANET_RADIUS*1.2); the beam mouth
	# reaches up to just below the disc and matches its width, so it reads as the
	# projection of THAT planet rather than a thin thread beside it.
	var top_y := -PLANET_RADIUS * 0.9           # cone mouth just under the disc
	var bot_y := TABLE_TOP_Y - PLANET_Y         # beam base sits on the table top
	var beam_h: float = top_y - bot_y

	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = PLANET_RADIUS * 1.2         # match the billboard disc width
	cm.bottom_radius = 0.05                     # narrow at the emitter
	cm.height = beam_h
	cm.radial_segments = 28
	cone.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.05)
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 0.6
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cone.material_override = mat
	cone.position = Vector3(0.0, (top_y + bot_y) * 0.5, 0.0)
	anchor.add_child(cone)

	# The emitter puck on the table surface.
	var emitter := MeshInstance3D.new()
	var em := CylinderMesh.new()
	em.top_radius = 0.13
	em.bottom_radius = 0.16
	em.height = 0.05
	emitter.mesh = em
	var emat := StandardMaterial3D.new()
	emat.albedo_color = Color(tint.r * 0.2, tint.g * 0.2, tint.b * 0.2)
	emat.emission_enabled = true
	emat.emission = tint
	emat.emission_energy_multiplier = 2.4
	emitter.material_override = emat
	emitter.position = Vector3(0.0, bot_y + 0.02, 0.0)
	anchor.add_child(emitter)
	return mat


## The spaceship operation table. Prefer the fal.ai holo-table asset (a real modelled
## command table); if it's missing, fall back to the procedural glowing ring + disc.
func _build_console() -> void:
	# Hide the old procedural cylinder base from the .tscn (the tall black cone that
	# sat under the new table).
	var old_base := get_node_or_null("Base") as Node3D
	if old_base:
		old_base.visible = false

	var scene := load("res://assets/generated/interior/holo_table.glb")
	if scene is PackedScene:
		var t := (scene as PackedScene).instantiate() as Node3D
		add_child(t)
		# Non-uniform: WIDE enough that the three projector beams land on the surface,
		# but SHORT (top at TABLE_TOP_Y) so the planets float clearly above it.
		var a := _asset_aabb(t)
		if a.size.x > 0.01 and a.size.y > 0.01 and a.size.z > 0.01:
			t.scale = Vector3(3.0 / a.size.x, TABLE_TOP_Y / a.size.y, 3.0 / a.size.z)
		a = _asset_aabb(t)
		t.position = Vector3(0.0, -a.position.y, 0.0)
		return
	_build_console_procedural()


## Global-space AABB of a node's visuals.
func _asset_aabb(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for vi in node.find_children("*", "VisualInstance3D", true, false):
		var a: AABB = (vi as VisualInstance3D).global_transform * (vi as VisualInstance3D).get_aabb()
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	return out


func _build_console_procedural() -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.32
	tm.outer_radius = 1.42
	tm.rings = 48
	tm.ring_segments = 12
	ring.mesh = tm
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.1, 0.3, 0.5)
	rmat.emission_enabled = true
	rmat.emission = BEAM_TINT
	rmat.emission_energy_multiplier = 2.8
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = rmat
	ring.position = Vector3(0.0, TABLE_TOP_Y + 0.01, 0.0)
	add_child(ring)

	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 1.3
	dm.bottom_radius = 1.3
	dm.height = 0.02
	disc.mesh = dm
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(BEAM_TINT.r, BEAM_TINT.g, BEAM_TINT.b, 0.14)
	dmat.emission_enabled = true
	dmat.emission = BEAM_TINT
	dmat.emission_energy_multiplier = 0.8
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material_override = dmat
	disc.position = Vector3(0.0, TABLE_TOP_Y + 0.02, 0.0)
	add_child(disc)


## Floating name above a projection. Billboarded and depth-test-free so it is
## readable from anywhere around the table, and tinted to match its planet.
func _build_label(anchor: Node3D, tint: Color) -> Label3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.shaded = false
	label.double_sided = true
	label.pixel_size = 0.0012
	label.font_size = 64
	label.outline_size = 0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.line_spacing = -8.0
	label.modulate = Color(tint.lightened(0.45), 0.95)
	label.position = Vector3(0, LABEL_HEIGHT, 0)
	label.scale = Vector3.ONE * LABEL_SIZE * 10.0
	label.set_meta("base_alpha", 0.95)
	anchor.add_child(label)
	return label

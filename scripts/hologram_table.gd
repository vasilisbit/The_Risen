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

## Label sits just above each sphere (spheres are radius 0.25 at y = 1.5).
const LABEL_HEIGHT := 0.42
const LABEL_SIZE := 0.10

var _materials: Dictionary = {}          # mission -> ShaderMaterial
var _labels: Dictionary = {}             # mission -> Label3D
var _flicker: float = 0.0


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
		var mat: ShaderMaterial = _materials[mission]
		mat.set_shader_parameter("brightness",
			UNLOCKED_BRIGHTNESS if unlocked else LOCKED_BRIGHTNESS)
		if _labels.has(mission):
			var label: Label3D = _labels[mission]
			# A locked world still names itself, but says so. The suffix goes on
			# its own line — inline, the three labels ran into each other.
			label.text = mission.to_upper() if unlocked else "%s\nLOCKED" % mission.to_upper()
			label.set_meta("base_alpha", 0.95 if unlocked else 0.45)


func _build() -> void:
	var shader := load(SHADER)
	if shader == null:
		push_warning("HologramTable: %s missing" % SHADER)
		return
	for mission in PLANETS:
		var info: Dictionary = PLANETS[mission]
		var mesh := get_node_or_null("%s/Mesh" % info["node"]) as MeshInstance3D
		if mesh == null:
			continue
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("base_color", info["base"])
		mat.set_shader_parameter("land_color", info["land"])
		mat.set_shader_parameter("land_threshold", info["threshold"])
		mat.set_shader_parameter("band_strength", info["bands"])
		# Each planet turns at its own rate so the table doesn't look synced.
		mat.set_shader_parameter("rot_speed", 0.045 + 0.015 * float(_materials.size()))
		mesh.material_override = mat
		_materials[mission] = mat
		_labels[mission] = _build_label(mesh.get_parent() as Node3D, info["base"])


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

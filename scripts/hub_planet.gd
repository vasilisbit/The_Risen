extends Node3D

## Planet seen through the hub's cockpit window (T-0028, Phase 5). Uses the
## project's own procedural planet shader - continents, latitude banding,
## drifting clouds, a soft terminator and an atmospheric rim, all self-lit so it
## reads clearly out the window with no stray specular hot-spots. Shows the world
## you were LAST DEPLOYED TO (the ship is parked in its orbit) - Earth before the
## first mission.
##
## Rotation lives in the shader against TIME, so it is frame-rate independent and
## there is no per-frame script work to stutter.
##
## (An earlier pass tried the naejimer 3D planet generator addon here, but its
## ported clouds shader rendered as a flat wash with specular artifacts at this
## scale, so the custom shader - which was purpose-built for this window - wins.)

const SHADER := "res://shaders/planet.gdshader"
const RADIUS := 6.0
## Out through the cockpit window (opening is 5x3 at z = -5, centred x = 0).
const OFFSET := Vector3(0.0, 3.0, -24.0)
const ROT_SPEED := 1.0 / 60.0          # revolutions per second (card: 1/60 s)

## Look per planet. `band_strength` is the latitude banding that reads as
## dust/cloud belts, which Earth barely has and Venus is made of.
const PLANETS := {
	"Earth": {
		"ocean": Color(0.05, 0.22, 0.55), "land": Color(0.16, 0.42, 0.18),
		"atmo": Color(0.40, 0.65, 1.00), "threshold": 0.52,
		"bands": 0.05, "clouds": 0.42,
	},
	"Mars": {
		"ocean": Color(0.42, 0.16, 0.09), "land": Color(0.66, 0.34, 0.17),
		"atmo": Color(1.00, 0.52, 0.30), "threshold": 0.46,
		"bands": 0.28, "clouds": 0.08,
	},
	"Venus": {
		"ocean": Color(0.62, 0.36, 0.12), "land": Color(0.94, 0.72, 0.32),
		"atmo": Color(1.00, 0.74, 0.34), "threshold": 0.40,
		"bands": 0.55, "clouds": 0.70,
	},
}

## Which planet is currently shown - exposed for tests.
var shown: String = "Earth"

var _mesh: MeshInstance3D
var _mat: ShaderMaterial


func _ready() -> void:
	_build()
	refresh()


## Re-read progress and repaint. The hub is reloaded on return from a mission
## so _ready covers the normal path; this exists for tests and for any future
## in-place refresh.
func refresh() -> void:
	shown = _last_visited()
	var look: Dictionary = PLANETS.get(shown, PLANETS["Earth"])
	if _mat == null:
		return
	_mat.set_shader_parameter("ocean_color", look["ocean"])
	_mat.set_shader_parameter("land_color", look["land"])
	_mat.set_shader_parameter("atmo_color", look["atmo"])
	_mat.set_shader_parameter("land_threshold", look["threshold"])
	_mat.set_shader_parameter("band_strength", look["bands"])
	_mat.set_shader_parameter("cloud_amount", look["clouds"])


## The mission most recently deployed to, defaulting to Earth before the first.
func _last_visited() -> String:
	var sm := get_node_or_null("/root/SaveManager")
	if sm == null:
		return "Earth"
	var last := String(sm.data.get("last_mission", "Earth"))
	return last if PLANETS.has(last) else "Earth"


func _build() -> void:
	_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = RADIUS
	sphere.height = RADIUS * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	_mesh.mesh = sphere
	_mesh.position = OFFSET
	# Far outside the room, so it must not be culled by the interior geometry.
	_mesh.extra_cull_margin = RADIUS * 2.0

	var shader := load(SHADER)
	if shader == null:
		push_warning("HubPlanet: %s missing" % SHADER)
		return
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_mat.set_shader_parameter("rot_speed", ROT_SPEED)
	_mesh.material_override = _mat
	add_child(_mesh)

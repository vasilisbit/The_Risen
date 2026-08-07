extends Node3D
## A spinning textured-sphere planet. It wears a generated equirectangular surface MAP
## (nano-banana-pro, assets/generated/planets/<world>_map.png) plus PATINA normal/roughness,
## wrapped on a SphereMesh - so the worlds read with real photographic detail and turn
## slowly like a real planet (replacing the mushy image-to-3d GLBs).
##
## A mild emission from the albedo keeps it clearly visible in dark contexts (the hub
## canopy, the black main-menu backdrop); where scene light exists (the cutscene sun, the
## menu's own sun) the normal map + terminator add surface relief.
##
## Instantiate dynamically (no class_name, to avoid a global-class scan dependency):
##     var p = preload("res://scripts/planet_body.gd").new()
##     add_child(p); p.setup("Venus", 46.0, 0.08)
## Returns false from setup() if the map is missing, so callers can fall back.

const MAP := {
	"Earth": "res://assets/generated/planets/earth_map.png",
	"Mars": "res://assets/generated/planets/mars_map.png",
	"Venus": "res://assets/generated/planets/venus_map.png",
}
const NORMAL := {
	"Earth": "res://assets/generated/planets/earth_map_normal.png",
	"Mars": "res://assets/generated/planets/mars_map_normal.png",
	"Venus": "res://assets/generated/planets/venus_map_normal.png",
}
const ROUGH := {
	"Earth": "res://assets/generated/planets/earth_map_roughness.png",
	"Mars": "res://assets/generated/planets/mars_map_roughness.png",
	"Venus": "res://assets/generated/planets/venus_map_roughness.png",
}

var _mission := "Earth"
var _radius := 1.0
var _spin := 0.12          # radians / second
var _spinner: Node3D


## Build the planet. radius is the desired world radius; spin in rad/s. Returns false (so
## callers can fall back) if the surface map is missing.
func setup(mission: String, radius: float, spin := 0.12) -> bool:
	_mission = mission
	_radius = radius
	_spin = spin
	return _build()


func _build() -> bool:
	var map_path: String = MAP.get(_mission, "")
	if map_path == "" or not ResourceLoader.exists(map_path):
		return false

	_spinner = Node3D.new()
	add_child(_spinner)

	var mesh := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = _radius
	sph.height = _radius * 2.0
	sph.radial_segments = 48
	sph.rings = 24
	mesh.mesh = sph
	mesh.extra_cull_margin = _radius * 2.0

	# UNSHADED: show the surface map's true colours exactly, in any lighting, with no
	# terminator and - crucially - no double-brightening blowout that washed the planet
	# white when scene ambient + emission stacked on the albedo. The silhouette + rotation
	# carry the 3D read (this is how the project's own procedural planet reads, too).
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = load(map_path)
	mesh.material_override = mat

	_spinner.add_child(mesh)
	set_process(true)
	return true


func _process(delta: float) -> void:
	if _spinner and is_instance_valid(_spinner):
		_spinner.rotate_y(_spin * delta)

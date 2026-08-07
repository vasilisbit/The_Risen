extends Node3D
## A spinning 3D planet built from a fal.ai image-to-3d GLB (Tripo H3.1, generated from
## the nano-banana full-disc renders in assets/generated/interior/planet_*.png). Replaces
## the flat billboard / procedural-shader planets so the worlds read with real photographic
## detail and turn slowly like a real planet.
##
## Self-lit: each surface is made UNSHADED so the planet shows its full photographic
## texture brightly and identically in any context - the dim hub canopy, the black
## main-menu backdrop, the travel cutscene - without depending on scene lighting (the
## same trick the old procedural planet shader used). The silhouette + rotation carry
## the 3D read.
##
## Instantiate dynamically (no class_name, to avoid a global-class scan dependency):
##     var p = preload("res://scripts/planet_body.gd").new()
##     add_child(p); p.setup("Venus", 46.0, 0.08)
## Returns false from setup() if the GLB is missing, so callers can fall back.

const GLB := {
	"Earth": "res://assets/generated/planets/planet_earth.glb",
	"Mars": "res://assets/generated/planets/planet_mars.glb",
	"Venus": "res://assets/generated/planets/planet_venus.glb",
}

var _mission := "Earth"
var _radius := 1.0
var _spin := 0.12          # radians / second
var _spinner: Node3D


## Build the planet. MUST be called after this node is inside the scene tree (the fit /
## recentre measures global AABBs). radius is the desired world radius; spin in rad/s.
func setup(mission: String, radius: float, spin := 0.12) -> bool:
	_mission = mission
	_radius = radius
	_spin = spin
	return _build()


func _build() -> bool:
	var path: String = GLB.get(_mission, "")
	if path == "" or not ResourceLoader.exists(path):
		return false
	var packed := load(path)
	if not (packed is PackedScene):
		return false
	_spinner = Node3D.new()
	add_child(_spinner)
	var model := (packed as PackedScene).instantiate() as Node3D
	_spinner.add_child(model)
	# Scale the ~1 m Tripo sphere to the requested radius, then recentre it on the spin
	# axis so it turns in place rather than orbiting an off-origin pivot.
	var raw := _global_aabb(model)
	var d: float = maxf(raw.size.x, maxf(raw.size.y, raw.size.z))
	if d > 0.0001:
		model.scale = Vector3.ONE * (_radius * 2.0 / d)
	var fit := _global_aabb(model)
	model.position -= _spinner.to_local(fit.get_center())
	_self_light(model)
	set_process(true)
	return true


func _process(delta: float) -> void:
	if _spinner and is_instance_valid(_spinner):
		_spinner.rotate_y(_spin * delta)


## Make every surface unshaded so the planet's own texture reads fully and clearly in
## any lighting (self-lit, like the old procedural planet).
func _self_light(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m = mi.get_active_material(i)
			if m is BaseMaterial3D:
				var dup := (m as BaseMaterial3D).duplicate()
				dup.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mi.set_surface_override_material(i, dup)


## Combined world-space AABB of every mesh under `root` (root must be in the tree).
func _global_aabb(root: Node) -> AABB:
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
	if root is MeshInstance3D:
		var rw: AABB = (root as MeshInstance3D).global_transform * (root as MeshInstance3D).get_aabb()
		acc = rw if first else acc.merge(rw)
	return acc

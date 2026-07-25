extends Node3D
## A full-length mirror. Renders the world from a camera placed at this mirror's
## reflected eye point onto the mirror surface, so the Guardian sees himself.
##
## Practical purpose beyond flavour: it is the only way to actually LOOK at the
## player character in a first-person game (including from a screenshot), which
## is how the body and the weapon hold get checked.

const WIDTH := 1.6
const HEIGHT := 2.4
const RES := Vector2i(512, 768)

var _viewport: SubViewport
var _camera: Camera3D
var _surface: MeshInstance3D


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = RES
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Share the real world so the mirror shows the actual scene, not a copy.
	_viewport.world_3d = get_viewport().world_3d
	add_child(_viewport)

	_camera = Camera3D.new()
	_camera.fov = 60.0
	_viewport.add_child(_camera)

	# Frame + glass.
	var frame := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(WIDTH + 0.12, HEIGHT + 0.12, 0.06)
	frame.mesh = fb
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.16, 0.17, 0.21)
	fm.metallic = 0.8
	fm.roughness = 0.35
	frame.material_override = fm
	frame.position = Vector3(0, HEIGHT * 0.5, -0.04)
	add_child(frame)

	_surface = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(WIDTH, HEIGHT)
	_surface.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = _viewport.get_texture()
	_surface.material_override = mat
	_surface.position = Vector3(0, HEIGHT * 0.5, 0.0)
	add_child(_surface)


func _process(_delta: float) -> void:
	if _camera == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	# A true mirror would reflect the eye through the glass plane, but that puts
	# the camera behind the wall the mirror hangs on and it renders black. So the
	# camera sits just in FRONT of the glass and looks back at the player - what
	# you see is yourself, framed as a reflection, which is what this is for.
	var eye := player.global_position + Vector3(0, 1.2, 0)
	_camera.global_position = to_global(Vector3(0.0, HEIGHT * 0.5, 0.06))
	if _camera.global_position.distance_to(eye) > 0.05:
		_camera.look_at(eye, Vector3.UP)

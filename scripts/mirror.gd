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
	# A real mirror shows you at TWICE your distance to the glass. This camera
	# sits at the glass (a truly reflected camera would be buried in the wall
	# behind it and render black), so it is only one distance away and the
	# reflection came out twice life size. Doubling the FOV tangent shrinks
	# everything by half and restores the correct apparent size at any range.
	_camera.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(60.0) * 0.5) * 2.0))
	_camera.near = 0.25             # don't slice into anything standing at the glass
	_viewport.add_child(_camera)
	_aim_camera()

	# A chunky metal frame that stands proud of the glass on all four sides, so
	# the mirror reads as a fitted object rather than a floating rectangle.
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.20, 0.21, 0.26)
	fm.metallic = 0.9
	fm.roughness = 0.3
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.85, 0.62, 0.30)      # gold trim, matching the UI
	trim.metallic = 0.85
	trim.roughness = 0.35
	var bar := 0.09
	var half_w := WIDTH * 0.5 + bar * 0.5
	var half_h := HEIGHT * 0.5 + bar * 0.5
	var cy := HEIGHT * 0.5
	# left / right / top / bottom
	_frame_bar(Vector3(-half_w, cy, 0.01), Vector3(bar, HEIGHT + bar * 2.0, 0.10), fm)
	_frame_bar(Vector3(half_w, cy, 0.01), Vector3(bar, HEIGHT + bar * 2.0, 0.10), fm)
	_frame_bar(Vector3(0, cy + half_h, 0.01), Vector3(WIDTH, bar, 0.10), fm)
	_frame_bar(Vector3(0, cy - half_h, 0.01), Vector3(WIDTH, bar, 0.10), fm)
	# thin gold inner lip
	_frame_bar(Vector3(0, cy + HEIGHT * 0.5, 0.035), Vector3(WIDTH, 0.02, 0.02), trim)
	_frame_bar(Vector3(0, cy - HEIGHT * 0.5, 0.035), Vector3(WIDTH, 0.02, 0.02), trim)
	# backing panel so you never see through the mirror into the void
	var back := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(WIDTH + bar * 2.0, HEIGHT + bar * 2.0, 0.04)
	back.mesh = bb
	back.material_override = fm
	back.position = Vector3(0, cy, -0.03)
	add_child(back)

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


func _frame_bar(pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)


## The camera is parented to the mirror and aimed straight out of the glass, so
## it never moves. An earlier version re-aimed it at the player every frame,
## which made the whole reflection swing and shear as you walked - the artifacts.
## A flat mirror's view direction is fixed anyway; only what falls inside it
## changes, which a static camera reproduces without any jitter.
func _aim_camera() -> void:
	if _camera == null:
		return
	# The camera hangs under the SubViewport, which is not a spatial node, so it
	# has to be placed in world space. A camera looks down its own -Z, and the
	# glass faces the mirror's +Z, so the mirror's basis is turned 180 degrees.
	var t := global_transform
	t.origin = to_global(Vector3(0.0, HEIGHT * 0.5, 0.06))
	t.basis = global_transform.basis.rotated(global_transform.basis.y.normalized(), PI)
	_camera.global_transform = t

extends Node3D
## A full-length mirror. Renders the world from a camera placed at this mirror's
## reflected eye point onto the mirror surface, so the Guardian sees himself.
##
## Practical purpose beyond flavour: it is the only way to actually LOOK at the
## player character in a first-person game (including from a screenshot), which
## is how the body and the weapon hold get checked.

const WIDTH := 1.6
const HEIGHT := 2.4
const RES := Vector2i(720, 1080)   # high enough that shadow edges don't stair-step

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
	# FOV is set per frame from the viewer's distance - see _update_fov().
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
	# A camera looking back at you renders you like ANOTHER PERSON facing you, so
	# stepping right moved the image left. A mirror does not do that, so the quad
	# is flipped horizontally to put the reflection back on the correct side.
	_surface.scale.x = -1.0
	add_child(_surface)


## The reflection only reads at the right size if the camera's field of view
## tracks how far the viewer is standing from the glass.
##
## Viewer at distance d sees the quad (height H) filling an angle H/d, and should
## see a reflection that looks like it is 2d away - i.e. the person must cover
## h/(2H) of the quad. The camera sits at the glass, so the person at distance d
## covers h / (2*d*tan(fov/2)) of the frame. Equating the two gives
## tan(fov/2) = H/d. A fixed FOV can therefore never be right at every range,
## which is why the reflection was first too big and then too small.
func _update_fov() -> void:
	if _camera == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	# Distance from the viewer to the mirror PLANE (its local Z axis).
	var d: float = absf(to_local(player.global_position).z)
	d = maxf(d, 0.4)
	_camera.fov = clampf(rad_to_deg(2.0 * atan(HEIGHT / d)), 30.0, 130.0)


func _process(_delta: float) -> void:
	_update_fov()


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
	# Sit clear of the frame bars (they span to z = 0.06); parked inside them the
	# frame occluded the view and the mirror looked blank/empty.
	var t := global_transform
	t.origin = to_global(Vector3(0.0, HEIGHT * 0.5, 0.14))
	t.basis = global_transform.basis.rotated(global_transform.basis.y.normalized(), PI)
	_camera.global_transform = t

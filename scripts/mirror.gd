extends Node3D
## Planar mirror (technique per the Norodix GodotMirror plugin + the user's
## reference): a SubViewport renders the scene from a camera reflected across the
## mirror plane, and the glass samples that render in SCREEN space. Reflecting the
## real camera - rather than aiming a hand-placed one - is what gets the scale,
## handedness and parallax right at every position and angle, which the earlier
## fixed-camera version could not.
##
## Practical purpose: it is the only way to actually look at the player character
## in a first-person game, including from a screenshot.

const WIDTH := 1.6
const HEIGHT := 2.4
## The mirror's own frame and glass go on this render layer, and the reflection
## camera is told to skip it. The main camera still draws them (its cull mask
## keeps every layer), but the reflection never sees the glass - which would
## otherwise sample its own texture into a hall-of-mirrors - or the backing.
const NO_REFLECT_LAYER := 1 << 19                    # render layer 20

var _viewport: SubViewport
var _camera: Camera3D


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.world_3d = get_viewport().world_3d      # show the real scene
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_2X
	add_child(_viewport)

	_camera = Camera3D.new()
	_camera.cull_mask = 0xFFFFF & ~NO_REFLECT_LAYER   # skip the mirror's own parts
	_viewport.add_child(_camera)

	_build_frame()
	_build_glass()


## Metal frame proud of the glass on all four sides, gold inner lip, and a
## backing panel so you never see past the mirror into the void.
func _build_frame() -> void:
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.20, 0.21, 0.26)
	fm.metallic = 0.9
	fm.roughness = 0.3
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.85, 0.62, 0.30)
	trim.metallic = 0.85
	trim.roughness = 0.35
	var bar := 0.09
	var half_w := WIDTH * 0.5 + bar * 0.5
	var half_h := HEIGHT * 0.5 + bar * 0.5
	var cy := HEIGHT * 0.5
	_bar(Vector3(-half_w, cy, 0.0), Vector3(bar, HEIGHT + bar * 2.0, 0.10), fm)
	_bar(Vector3(half_w, cy, 0.0), Vector3(bar, HEIGHT + bar * 2.0, 0.10), fm)
	_bar(Vector3(0, cy + half_h, 0.0), Vector3(WIDTH, bar, 0.10), fm)
	_bar(Vector3(0, cy - half_h, 0.0), Vector3(WIDTH, bar, 0.10), fm)
	_bar(Vector3(0, cy + HEIGHT * 0.5, 0.03), Vector3(WIDTH, 0.02, 0.02), trim)
	_bar(Vector3(0, cy - HEIGHT * 0.5, 0.03), Vector3(WIDTH, 0.02, 0.02), trim)
	var back := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(WIDTH + bar * 2.0, HEIGHT + bar * 2.0, 0.04)
	back.mesh = bb
	back.material_override = fm
	back.position = Vector3(0, cy, -0.04)
	back.layers = NO_REFLECT_LAYER
	add_child(back)


func _bar(pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.layers = NO_REFLECT_LAYER
	add_child(mi)


## The glass samples the reflection render at the matching SCREEN position.
func _build_glass() -> void:
	var surface := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(WIDTH, HEIGHT)
	surface.mesh = quad
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D reflection : filter_linear;
void fragment() {
	ALBEDO = texture(reflection, SCREEN_UV).rgb;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("reflection", _viewport.get_texture())
	surface.material_override = mat
	surface.position = Vector3(0, HEIGHT * 0.5, 0.0)
	surface.layers = NO_REFLECT_LAYER
	add_child(surface)


func _process(_delta: float) -> void:
	var main := get_viewport().get_camera_3d()
	if main == null or _camera == null:
		return
	# Match the render size so SCREEN_UV lines up with the main viewport.
	var vp := get_viewport().get_visible_rect().size
	if _viewport.size != Vector2i(vp):
		_viewport.size = Vector2i(vp)

	# Reflect the player camera across the mirror plane (origin = this node,
	# normal = its +Z, the way the glass faces). Reflecting position AND each
	# basis axis gives a genuine mirrored viewpoint.
	var n := global_transform.basis.z.normalized()
	var o := global_transform.origin
	var t := main.global_transform
	var refl_origin := t.origin - 2.0 * (t.origin - o).dot(n) * n
	var bx := t.basis.x - 2.0 * t.basis.x.dot(n) * n
	var by := t.basis.y - 2.0 * t.basis.y.dot(n) * n
	var bz := t.basis.z - 2.0 * t.basis.z.dot(n) * n
	_camera.global_transform = Transform3D(Basis(bx, by, bz), refl_origin)
	_camera.fov = main.fov
	_camera.keep_aspect = main.keep_aspect
	# The reflected camera sits behind the mirror, with the wall it hangs on
	# between it and the mirror plane. Put the near plane in that gap: past the
	# wall (so it is culled) but short of the mirror plane (so the whole reflected
	# room, floor and legs included, is kept). The mirror stands ~0.6 m off the
	# wall for exactly this margin; the glass itself is handled by the layer cull.
	var d := absf((t.origin - o).dot(n))
	_camera.near = clampf(d - 0.3, 0.05, maxf(0.05, d))

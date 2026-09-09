extends Node3D
## Trailer/IGF frame capture harness.
## Renders clean 1920x1080 hero frames of the real game actors (Guardian, Forge
## Master, the 6 enemies/bosses) into assets/generated/trailer/frames/ so they can
## be fed to fal.ai image-to-video (minimax/h3-max) for the trailer, and used as the
## IGF screenshots. Runs in the editor via project_run (custom scene). Offscreen
## SubViewport => exact 1920x1080 regardless of monitor size. Quits when done.

const OUT_DIR := "res://assets/generated/trailer/frames/"
const W := 1920
const H := 1080

# name, glb, yaw_deg (spin to face camera), key_hex (rim light tint)
var SHOTS := [
	{"name": "guardian",       "glb": "res://assets/generated/guardian/guardian.glb", "yaw": 0.0,   "rim": Color(0.2, 0.9, 0.9)},
	{"name": "forge_master",   "glb": "res://assets/generated/hub/forge_master.glb",  "yaw": 0.0,   "rim": Color(1.0, 0.55, 0.2)},
	{"name": "rusher",         "glb": "res://assets/generated/enemies/rusher.glb",         "yaw": 0.0, "rim": Color(0.2, 0.95, 0.9)},
	{"name": "shooter",        "glb": "res://assets/generated/enemies/shooter.glb",        "yaw": 0.0, "rim": Color(0.2, 0.95, 0.9)},
	{"name": "exploder",       "glb": "res://assets/generated/enemies/exploder.glb",       "yaw": 0.0, "rim": Color(0.2, 0.95, 0.9)},
	{"name": "shielded_brute", "glb": "res://assets/generated/enemies/shielded_brute.glb", "yaw": 0.0, "rim": Color(0.2, 0.95, 0.9)},
	{"name": "phantom",        "glb": "res://assets/generated/enemies/phantom.glb",        "yaw": 0.0, "rim": Color(0.35, 0.85, 1.0)},
	{"name": "ember_tyrant",   "glb": "res://assets/generated/enemies/ember_tyrant.glb",   "yaw": 0.0, "rim": Color(1.0, 0.45, 0.15)},
]

var _vp: SubViewport
var _cam: Camera3D
var _mount: Node3D

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_build_studio()
	await get_tree().process_frame
	for shot in SHOTS:
		await _capture(shot)
	print("TRAILER_CAPTURE_DONE")
	await get_tree().create_timer(0.3).timeout
	get_tree().quit()

func _build_studio() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(W, H)
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_3d = Viewport.MSAA_4X
	add_child(_vp)

	# Environment: dark cinematic backdrop + subtle glow (matches game grade).
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.025, 0.035)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.10, 0.13, 0.16)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.15
	env.ssao_enabled = true
	we.environment = env
	_vp.add_child(we)

	# Ground: dark reflective floor so actors are grounded, not floating.
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor.mesh = pm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.03, 0.035, 0.045)
	fmat.metallic = 0.5
	fmat.roughness = 0.45
	floor.material_override = fmat
	_vp.add_child(floor)

	_mount = Node3D.new()
	_vp.add_child(_mount)

	_cam = Camera3D.new()
	_cam.current = true
	_cam.fov = 38.0
	_vp.add_child(_cam)

func _add_lights(rim: Color, center: Vector3, radius: float) -> Array:
	var nodes := []
	var r: float = maxf(radius, 0.6)
	var key := DirectionalLight3D.new()
	key.light_energy = 2.2
	key.light_color = Color(1.0, 0.96, 0.9)
	key.rotation_degrees = Vector3(-38, -35, 0)
	key.shadow_enabled = true
	_vp.add_child(key); nodes.append(key)

	var fill := OmniLight3D.new()
	fill.light_energy = 4.0
	fill.omni_range = r * 12.0
	fill.light_color = Color(0.6, 0.7, 0.9)
	fill.position = center + Vector3(-1.4, 0.8, 1.6) * r
	_vp.add_child(fill); nodes.append(fill)

	var rimL := OmniLight3D.new()
	rimL.light_energy = 8.0
	rimL.omni_range = r * 12.0
	rimL.light_color = rim
	rimL.position = center + Vector3(1.4, 1.2, -1.6) * r
	_vp.add_child(rimL); nodes.append(rimL)
	return nodes

func _capture(shot: Dictionary) -> void:
	var res: Resource = load(shot["glb"])
	if res == null:
		push_warning("missing glb: %s" % shot["glb"])
		return
	var inst: Node3D = res.instantiate()
	inst.rotation.y = deg_to_rad(shot["yaw"])
	_mount.add_child(inst)

	# Let the rig settle + play an idle pose if the GLB ships one.
	_play_idle(inst)
	await get_tree().process_frame
	await get_tree().process_frame

	# Skinned Meshy rigs have a ~0.0117 bind-pose scale, so MeshInstance.get_aabb()
	# is centimetre-sized garbage. Frame from the POSED skeleton bones instead.
	var aabb := _skel_bounds(inst)
	if aabb.size == Vector3.ZERO:
		aabb = _world_aabb(inst)
	if aabb.size == Vector3.ZERO:
		aabb = AABB(Vector3(-0.5, 0, -0.5), Vector3(1, 2, 1))
	# Drop actor so its feet sit on the floor (y=0).
	inst.position.y -= aabb.position.y
	aabb.position.y = 0.0

	var center := aabb.get_center()
	var radius: float = maxf(maxf(aabb.size.x, aabb.size.y), aabb.size.z) * 0.5
	var lights := _add_lights(shot["rim"], center, radius)
	var dist: float = radius / tan(deg_to_rad(_cam.fov * 0.5)) * 2.15
	var dir := Vector3(0.5, 0.16, 1.0).normalized()
	_cam.position = center + dir * dist
	_cam.look_at(center, Vector3.UP)

	# Settle the animation pose + render, then read pixels.
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	var out := ProjectSettings.globalize_path(OUT_DIR + str(shot["name"]) + ".png")
	img.save_png(out)
	print("SHOT ", shot["name"], " ", aabb.size, " -> ", out)

	inst.queue_free()
	for l in lights:
		l.queue_free()
	await get_tree().process_frame

func _play_idle(root: Node) -> void:
	var ap := _find_anim_player(root)
	if ap == null:
		return
	var names := ap.get_animation_list()
	if names.is_empty():
		return
	var pick := names[0]
	for n in names:
		if String(n).to_lower().contains("idle"):
			pick = n
			break
	ap.play(pick)
	ap.seek(0.35, true)

func _skel_bounds(root: Node) -> AABB:
	var skel := _find_skel(root)
	if skel == null:
		return AABB()
	var have := false
	var out := AABB()
	for i in range(skel.get_bone_count()):
		var wp: Vector3 = skel.global_transform * skel.get_bone_global_pose(i).origin
		if not have:
			out = AABB(wp, Vector3.ZERO)
			have = true
		else:
			out = out.expand(wp)
	if not have:
		return AABB()
	# Pad for mesh thickness around the joints (esp. head/shoulders/feet).
	var pad := Vector3(0.18, 0.22, 0.18)
	out.position -= pad
	out.size += pad * 2.0
	return out

func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r != null:
			return r
	return null

func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim_player(c)
		if r != null:
			return r
	return null

func _world_aabb(n: Node) -> AABB:
	var out := AABB()
	var have := false
	for vi in _all_visuals(n):
		var a: AABB = vi.get_aabb()
		var gt: Transform3D = vi.global_transform
		var pts := []
		for i in range(8):
			pts.append(gt * (a.position + Vector3(
				a.size.x * float(i & 1),
				a.size.y * float((i >> 1) & 1),
				a.size.z * float((i >> 2) & 1))))
		for p in pts:
			if not have:
				out = AABB(p, Vector3.ZERO)
				have = true
			else:
				out = out.expand(p)
	return out

func _all_visuals(n: Node) -> Array:
	var r := []
	if n is VisualInstance3D and not (n is GPUParticles3D):
		r.append(n)
	for c in n.get_children():
		r += _all_visuals(c)
	return r

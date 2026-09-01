extends Node
## First-person weapon viewmodel. Renders a dedicated ARMS+GUN mesh (two armoured
## gauntlets modelled already gripping the weapon - T-0042, tools/gen_viewmodel.py)
## in its own isolated SubViewport, composited on top of the main view.
##
## Why a bespoke mesh and not the player body rig: the Meshy-rigged Guardian can't
## hold a gun two-handed - the arms are too short to reach the handguard and the
## auto-rig hands are a single fingerless bone, so a support hand only splays open.
## Real FPS viewmodels are purpose-built arm+gun meshes, which is what this shows.
## The world/inventory keep the T-0041 gun models (separate view vs world models).

const VM_DIR := "res://assets/generated/viewmodels/"
## Fallback: the bare world gun (no arms) if a weapon has no viewmodel mesh yet.
const WEAPON_DIR := "res://assets/generated/weapons/"

## Where the viewmodel camera sits and looks (fixed; the mesh is placed in front of
## it, lower-right, barrel forward). The mesh transform per weapon does the framing.
@export var cam_position: Vector3 = Vector3(0, 0, 0)
@export var cam_look_at: Vector3 = Vector3(0, 0, -1)
@export var cam_fov: float = 55.0
## The viewmodel dips/rises a touch with the look pitch.
@export var pitch_follow: float = 0.04

## Per-weapon viewmodel placement in the holder's space: position (m), rotation
## (deg) and uniform scale, so the gun sits lower-right with the barrel pointing
## forward (-Z), arms coming up from the bottom - the reference viewmodel look.
## Tuned in-engine; the auto rifle is the baseline (others reuse it until tuned).
const VM_BASE := {"pos": Vector3(0.14, -0.24, -0.60), "rot": Vector3(2, 6, -8), "scale": 0.47}
## NOTE on per-weapon rotation: each Tripo mesh keeps its own native barrel axis.
## Auto Rifle / Shotgun / Sniper already model the barrel along -Z, so their rot is
## a small cosmetic cant. The Hand Cannon mesh models the barrel along +X, so it
## needs a ~+90 deg Y turn (barrel +X -> -Z) or it points back at the player.
const VM_XFORM := {
	"Auto Rifle": {"pos": Vector3(0.14, -0.2, -0.50), "rot": Vector3(0, -22, -5), "scale": 0.6},
	"Shotgun": {"pos": Vector3(0.14, -0.18, -0.35), "rot": Vector3(5, 50, -7), "scale": 0.6},
	"Sniper": {"pos": Vector3(0.14, -0.21, -0.62), "rot": Vector3(2, -20, -7), "scale": 0.85},
	"Hand Cannon": {"pos": Vector3(0.14, -0.25, -0.53), "rot": Vector3(2, 170, 6), "scale": 0.6},
}
const VM_FILE := {
	"Auto Rifle": "auto_rifle_vm.glb", "Shotgun": "shotgun_vm.glb",
	"Sniper": "sniper_vm.glb", "Hand Cannon": "hand_cannon_vm.glb",
}

## Per-weapon recoil impulse (metres back/up + radians of muzzle rise).
const KICK := {
	"Auto Rifle": {"back": 0.03, "up": 0.018, "rot": 0.05},
	"Shotgun": {"back": 0.075, "up": 0.045, "rot": 0.11},
	"Sniper": {"back": 0.065, "up": 0.04, "rot": 0.10},
	"Hand Cannon": {"back": 0.05, "up": 0.03, "rot": 0.08},
}
const RECOIL_RECOVER := 12.0

## Muzzle-flash placement (holder space, at each gun's barrel tip) + size (billboarded
## quad, m). Per gun type so each reads differently: the shotgun flares wide, the sniper
## is longer/narrower, the auto rifle is small and quick. Tuned in-engine.
const MUZZLE_POS := {
	"Auto Rifle": Vector3(0.15, -0.17, -0.92),
	"Shotgun": Vector3(0.15, -0.15, -0.78),
	"Sniper": Vector3(0.15, -0.18, -1.15),
	"Hand Cannon": Vector3(0.16, -0.20, -0.86),
}
const MUZZLE_SIZE := {
	"Auto Rifle": Vector2(0.26, 0.26),
	"Shotgun": Vector2(0.46, 0.36),
	"Sniper": Vector2(0.28, 0.40),
	"Hand Cannon": Vector2(0.38, 0.34),
}
const MUZZLE_TEX := "res://assets/generated/vfx/tex/"

var _viewport: SubViewport
var _cam: Camera3D
var _holder: Node3D           # recoil/dip move this; the VM mesh hangs under it
var _model: Node3D
var _layer: CanvasLayer
var _tex: TextureRect
var _pitch: float = 0.0
var _recoil: Vector3 = Vector3.ZERO
var _recoil_rot: float = 0.0
var _reload_left: float = 0.0
var _reload_dur: float = 1.0
var _base_pos: Vector3 = Vector3.ZERO      # current weapon's rest holder position
var _muzzle_local: Vector3 = Vector3.ZERO  # cached barrel-tip in holder space (per weapon)


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_2X
	add_child(_viewport)

	_build_lighting()

	_cam = Camera3D.new()
	_cam.fov = cam_fov
	_cam.near = 0.02
	_viewport.add_child(_cam)
	_aim_camera()

	_holder = Node3D.new()
	_viewport.add_child(_holder)

	_build_overlay()


## Key + fill so the dark gauntlets read, plus a little ambient. The isolated world
## is otherwise pitch black.
func _build_lighting() -> void:
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-45), deg_to_rad(30), 0)
	key.light_energy = 1.2
	_viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-10), deg_to_rad(-140), 0)
	fill.light_energy = 0.5
	fill.light_color = Color(0.75, 0.82, 1.0)
	_viewport.add_child(fill)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.46, 0.55)
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)


func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 1
	add_child(_layer)
	_tex = TextureRect.new()
	_tex.texture = _viewport.get_texture()
	_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_tex)


func _process(delta: float) -> void:
	# Size the viewmodel viewport to the 2D CONTENT rect (the window-stretch base,
	# aspect-matched under canvas_items), NOT the raw OS window size. The overlay
	# TextureRect is a full-rect Control that lives in that base space, so matching the
	# viewport to it keeps the composite 1:1 and frames the gun exactly as at the base
	# resolution; the window stretch then scales the whole overlay uniformly with the
	# rest of the UI. (Feeding it the raw window size mismatched the full-rect base
	# space, so STRETCH_KEEP_ASPECT_COVERED rescaled the arms back/small on maximize.)
	var content := Vector2i(get_viewport().get_visible_rect().size)
	if content.x > 0 and content.y > 0 and _viewport.size != content:
		_viewport.size = content
	# Ease the recoil back to rest.
	var t := clampf(RECOIL_RECOVER * delta, 0.0, 1.0)
	_recoil = _recoil.lerp(Vector3.ZERO, t)
	_recoil_rot = lerpf(_recoil_rot, 0.0, t)
	# Reload dip: the viewmodel lowers + cants over reload_time, then rises back.
	var dip := 0.0
	if _reload_left > 0.0:
		_reload_left -= delta
		var pr := clampf(1.0 - _reload_left / maxf(_reload_dur, 0.05), 0.0, 1.0)
		dip = sin(pr * PI)
	if _holder:
		var lift := _pitch * pitch_follow
		_holder.position = _base_pos + _recoil + Vector3(0.0, lift - 0.06 * dip, 0.03 * dip)
		_holder.rotation = Vector3(-_recoil_rot - 0.45 * dip, 0.0, 0.5 * dip)
	_aim_camera()


func _aim_camera() -> void:
	if _cam == null:
		return
	_cam.fov = cam_fov
	_cam.position = cam_position
	_cam.look_at(cam_look_at, Vector3.UP)


## Match the equipped weapon: load its arms+gun viewmodel mesh (mirrors the naming,
## e.g. "Auto Rifle" -> viewmodels/auto_rifle_vm.glb).
func set_weapon(name_: String) -> void:
	if _holder == null:
		return
	if _model and is_instance_valid(_model):
		_model.queue_free()
		_model = null
	var xf: Dictionary = VM_XFORM.get(name_, VM_BASE)
	_base_pos = xf["pos"]
	var vm_path := VM_DIR + String(VM_FILE.get(name_, ""))
	var scene: Resource = null
	if ResourceLoader.exists(vm_path):
		scene = load(vm_path)
	if scene is PackedScene:
		_model = (scene as PackedScene).instantiate() as Node3D
		_holder.add_child(_model)
		_model.position = Vector3.ZERO
		_model.rotation_degrees = xf["rot"]
		_model.scale = Vector3.ONE * float(xf["scale"])
		_metalize(_model, false)
	else:
		_fallback_weapon(name_)
	_muzzle_local = _compute_muzzle(name_)


## No viewmodel mesh yet: show the bare world gun (no arms) so something is drawn.
func _fallback_weapon(name_: String) -> void:
	var file := name_.to_lower().replace(" ", "_")
	var path := "%s%s.glb" % [WEAPON_DIR, file]
	if not ResourceLoader.exists(path):
		return
	var scene: Resource = load(path)
	if scene is PackedScene:
		_model = (scene as PackedScene).instantiate() as Node3D
		_holder.add_child(_model)
		_model.rotation_degrees = Vector3(0, 90, 0)
		_model.position = Vector3(0.12, -0.2, -0.5)
		_metalize(_model, true)


## Punch the metal a touch (Tripo ORM ships dull). The full arms+gun mesh keeps its
## generated Color/Normal; the bare fallback gun gets a stronger metal punch.
func _metalize(model: Node3D, hard: bool) -> void:
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var base := mi.get_active_material(s)
			if not (base is BaseMaterial3D):
				continue
			var mat: BaseMaterial3D = base.duplicate()
			mat.metallic = 1.0 if hard else 0.5
			mat.roughness = clampf(mat.roughness * (0.7 if hard else 0.85), 0.1, 1.0)
			mat.metallic_specular = 0.6 if hard else 0.5
			mi.set_surface_override_material(s, mat)


func set_pitch(pitch: float) -> void:
	_pitch = pitch


func kick(weapon_name := "Auto Rifle") -> void:
	var k: Dictionary = KICK.get(weapon_name, KICK["Auto Rifle"])
	_recoil = Vector3(0.0, float(k["up"]), float(k["back"]))
	_recoil_rot = float(k["rot"])


## Spawn a brief muzzle flash at the gun barrel, inside the viewmodel's own world so it
## composites with the arms. Shape varies per gun type; colour = the weapon's energy
## element (Kinetic pale / Solar orange / Arc cyan / Void purple). Called per shot.
func muzzle_flash(weapon_name := "Auto Rifle", color := Color(1.0, 0.9, 0.7)) -> void:
	if _holder == null:
		return
	var root := Node3D.new()
	_holder.add_child(root)
	root.position = _muzzle_local
	# Point the flash's forward (-Z) down the barrel/aim so the sparks shoot out of the gun.
	root.look_at(root.global_position + _muzzle_forward(), Vector3.UP)
	var sz: Vector2 = MUZZLE_SIZE.get(weapon_name, MUZZLE_SIZE["Auto Rifle"])
	var tint := Color(color.r * 1.3 + 0.35, color.g * 1.3 + 0.35, color.b * 1.3 + 0.35, 1.0)
	# Big spiky star (billboarded) + a bright core - the flash you see end-on.
	var star := _flash_quad("muzzle", sz * 2.4, tint)
	star.scale = Vector3.ONE * 0.55
	root.add_child(star)
	var core := _flash_quad("flare", sz * 0.9, tint)
	root.add_child(core)
	# Sparks shooting FORWARD out of the barrel (the "coming out of the gun" read).
	var sparks := _muzzle_sparks(sz, color)
	root.add_child(sparks)
	var light := OmniLight3D.new()
	light.light_color = color
	light.omni_range = 2.0
	light.light_energy = 7.0
	root.add_child(light)
	var tw := root.create_tween()
	tw.tween_property(star, "scale", Vector3.ONE, 0.04)
	tw.parallel().tween_property(star.material_override, "albedo_color:a", 0.0, 0.07)
	tw.parallel().tween_property(core.material_override, "albedo_color:a", 0.0, 0.06)
	tw.parallel().tween_property(light, "light_energy", 0.0, 0.07)
	tw.tween_interval(0.08)
	tw.tween_callback(root.queue_free)


## Forward (aim) direction in holder space. The viewmodel camera looks toward
## cam_look_at from cam_position, so "down the barrel" is that direction.
func _muzzle_forward() -> Vector3:
	var f := (cam_look_at - cam_position)
	return f.normalized() if f.length() > 0.001 else Vector3(0, 0, -1)


## A one-shot burst of stretched sparks flying forward out of the muzzle (root's -Z),
## element-tinted. Reads even end-on because the sparks radiate outward as they leave.
func _muzzle_sparks(sz: Vector2, color: Color) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 12
	p.lifetime = 0.16
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = true
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, -1)          # down the barrel (root already aimed)
	pm.spread = 24.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 9.0
	pm.gravity = Vector3.ZERO
	pm.damping_min = 4.0
	pm.damping_max = 8.0
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.set_particle_flag(ParticleProcessMaterial.PARTICLE_FLAG_ALIGN_Y_TO_VELOCITY, true)
	pm.color = Color(color.r * 1.5 + 0.4, color.g * 1.4 + 0.3, color.b + 0.2, 1.0)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), color, Color(color, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(sz.x * 0.14, sz.x * 0.6)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	m.vertex_color_use_as_albedo = true
	var sp := MUZZLE_TEX + "spark.png"
	if ResourceLoader.exists(sp):
		m.albedo_texture = load(sp)
	q.material = m
	p.draw_pass_1 = q
	return p


## Barrel-tip position in holder space: the forward-most (most -Z, along the viewmodel
## camera's view) mesh VERTEX of the gun model — the actual muzzle, whatever each mesh's
## own rotation. Computed once per weapon swap (not per shot) and cached. Falls back to
## the tuned per-weapon constant if the model has no readable geometry yet.
func _compute_muzzle(weapon_name: String) -> Vector3:
	var fallback: Vector3 = MUZZLE_POS.get(weapon_name, MUZZLE_POS["Auto Rifle"])
	if _model == null or not is_instance_valid(_model):
		return fallback
	var inv := _holder.global_transform.affine_inverse()
	var best_z := INF
	var best := Vector3.ZERO
	var found := false
	for m in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var gt := inv * mi.global_transform
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			if arrays.size() <= Mesh.ARRAY_VERTEX:
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in verts:
				var p: Vector3 = gt * v
				if p.z < best_z:
					best_z = p.z
					best = p
					found = true
	if not found:
		return fallback
	return best + Vector3(0.0, 0.0, -0.03)   # just ahead of the muzzle


func _flash_quad(tex_name: String, size: Vector2, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.no_depth_test = true                      # a muzzle flash reads over the gun
	m.albedo_color = color
	var path := MUZZLE_TEX + tex_name + ".png"
	if ResourceLoader.exists(path):
		m.albedo_texture = load(path)
	mi.material_override = m
	return mi


## Reload feedback: dip the viewmodel down/back for `duration` seconds (see _process).
func play_reload(duration: float) -> void:
	_reload_dur = maxf(duration, 0.05)
	_reload_left = _reload_dur


func set_shown(shown: bool) -> void:
	if _layer:
		_layer.visible = shown

class_name VfxKit
extends Object

## Shared VFX layers, reconciled from the YouTube VFX study (planning-repo
## docs/VFX_FAL_RESEARCH.md §11). Every explosion/impact tutorial is the SAME
## build: layered one-shot GPUParticles3D (fire + sparks + smoke + a single-particle
## shockwave) on unshaded billboard quads that sample the Godot-baked masks in
## assets/generated/vfx/tex/, driven by scale/alpha/colour curves, plus an OmniLight
## flash, an optional ground Decal, and camera shake. This replaces the bare
## expanding-emissive-sphere primitives (_burst / _explosion_vfx / _impact_vfx).
##
## Non-destructive: if a mask is missing the layer degrades (flat quad), so callers
## keep working. Decal only spawns if its texture exists (arrives in the fal step).

const TEX_DIR := "res://assets/generated/vfx/tex"
const DECAL_DIR := "res://assets/generated/vfx/decals"

static var _cache: Dictionary = {}


## One-shot explosion at `at`. `style`:
##   "fire"  - frag / rocket / magma: fireball + sparks + smoke + shock + scorch + shake
##   "soft"  - healing grenade: gentle rising motes + soft bloom + heal ring, no shrapnel
##   "flash" - flashbang: hard white bloom + fast glare ring, minimal smoke
static func explosion(host: Node, at: Vector3, base_color: Color, radius: float, style: String = "fire") -> void:
	if host == null or not (host is Node):
		return
	var root := Node3D.new()
	host.add_child(root)
	root.global_position = at

	var life := 2.6
	match style:
		"soft":
			_layer_motes(root, base_color, radius)
			_layer_bloom(root, base_color, radius, 0.9)
			_decal(root, "heal_ring", base_color, radius)
			_flash_light(root, base_color, radius, 1.4, 0.5)
		"flash":
			_layer_bloom(root, Color(1, 1, 1), radius, 1.0)
			_layer_shock(root, Color(1, 1, 1), radius, 0.35)
			_layer_smoke(root, Color(0.8, 0.8, 0.85), radius * 0.4, 6)
			_flash_light(root, Color(1, 1, 1), radius * 1.6, 12.0, 0.3)
			_shake(root, at, 0.02)
		"emp":  # EMP Punch: tight electric burst — bright ring + arc sparks, no smoke
			life = 0.9
			_layer_bloom(root, base_color, radius * 0.8, 0.45)
			_layer_shock(root, base_color, radius, 0.3)
			_layer_sparks(root, base_color, radius, 16)
			_flash_light(root, base_color, radius * 1.6, 5.0, 0.22)
		"slam":  # Ground Slam: heavy ground shock + dust + crack decal, no fireball
			_layer_shock(root, base_color, radius, 0.45)
			_layer_smoke(root, Color(0.42, 0.37, 0.30), radius, 10)
			_layer_sparks(root, base_color, radius * 0.7, 12)
			_decal(root, "ground_crack", base_color, radius)
			_flash_light(root, base_color, radius, 3.0, 0.3)
			_shake(root, at, 0.05)
		_:  # "fire"
			_layer_fire(root, base_color, radius)
			_layer_sparks(root, base_color, radius)
			_layer_smoke(root, Color(0.1, 0.09, 0.09), radius, 8)
			_layer_shock(root, base_color, radius, 0.4)
			_decal(root, "scorch", Color(0.15, 0.12, 0.1), radius)
			_flash_light(root, base_color, radius, 6.0, 0.28)
			_shake(root, at, 0.04)

	var t := host.get_tree().create_timer(life)
	t.timeout.connect(root.queue_free)


## Swept melee slash: a stretched additive arc quad (flare_cross) that grows and
## fades in front of the player, + edge sparks. `color` per class (teal/blue/tan).
static func slash(host: Node, at: Vector3, facing: Vector3, color: Color, reach: float) -> void:
	if host == null:
		return
	var root := Node3D.new()
	host.add_child(root)
	root.global_position = at
	var f := facing
	f.y = 0.0
	f = f.normalized() if f.length() > 0.01 else Vector3.FORWARD
	root.look_at(at + f, Vector3.UP)

	# Wide thin arc quad, additive, grows fast then fades.
	var arc := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(reach * 2.2, reach * 0.9)
	arc.mesh = quad
	arc.material_override = _sprite_mat("flare_cross", color, true)
	root.add_child(arc)
	arc.position = Vector3(0, 0, -reach * 0.5)
	arc.scale = Vector3(0.2, 1.0, 1.0)
	var m: StandardMaterial3D = arc.material_override
	var tw := arc.create_tween()
	tw.tween_property(arc, "scale", Vector3(1.0, 1.0, 1.0), 0.14)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, 0.5)

	_layer_sparks(root, color, reach * 0.8, 14)
	var t := host.get_tree().create_timer(0.8)
	t.timeout.connect(root.queue_free)


# --- layers ---------------------------------------------------------------------

## NB: ParticleProcessMaterial.scale_min/max are MULTIPLIERs on the quad size,
## then scale_curve multiplies again over lifetime. Real size = quad * scale * curve.
static func _layer_fire(root: Node3D, color: Color, radius: float) -> void:
	var p := _emitter(20, 0.55, 1.0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius * 0.18
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.gravity = Vector3(0, -radius * 0.6, 0)
	pm.initial_velocity_min = radius * 0.6
	pm.initial_velocity_max = radius * 1.6
	pm.scale_min = 0.6
	pm.scale_max = 1.1
	pm.scale_curve = _grow_shrink(0.15)
	pm.color = color
	pm.color_ramp = _ramp([
		Color(color.r * 1.4 + 0.3, color.g * 1.2 + 0.2, color.b, 1.0),
		Color(color, 1.0), Color(color.darkened(0.4), 0.0)])
	p.process_material = pm
	p.draw_pass_1 = _quad(radius * 0.7, _sprite_mat("flare", color, true))
	root.add_child(p)


static func _layer_sparks(root: Node3D, color: Color, radius: float, amount: int = 22) -> void:
	var p := _emitter(amount, 0.5, 1.0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius * 0.1
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.gravity = Vector3(0, -radius * 2.2, 0)
	pm.initial_velocity_min = radius * 1.6
	pm.initial_velocity_max = radius * 3.4
	pm.damping_min = 1.0
	pm.damping_max = 3.0
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.scale_curve = _grow_shrink(0.05)
	pm.set_particle_flag(ParticleProcessMaterial.PARTICLE_FLAG_ALIGN_Y_TO_VELOCITY, true)
	pm.color = Color(color.r * 1.6 + 0.4, color.g * 1.3 + 0.2, color.b + 0.1, 1.0)
	pm.color_ramp = _ramp([Color(1, 1, 1, 1), Color(color, 1.0), Color(color, 0.0)])
	p.process_material = pm
	# Stretched quad = speed-line spark (thin X, long Y along velocity).
	var mat := _sprite_mat("spark", color, false)
	var quad := QuadMesh.new()
	quad.size = Vector2(radius * 0.06, radius * 0.34)
	quad.material = mat
	p.draw_pass_1 = quad
	root.add_child(p)


static func _layer_smoke(root: Node3D, color: Color, radius: float, amount: int) -> void:
	var p := _emitter(amount, 0.9, 1.0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius * 0.22
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.gravity = Vector3(0, radius * 0.4, 0)      # drifts up
	pm.initial_velocity_min = radius * 0.2
	pm.initial_velocity_max = radius * 0.8
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.scale_min = 0.6
	pm.scale_max = 1.1
	pm.scale_curve = _grow_shrink(0.1)
	pm.color = color
	pm.color_ramp = _ramp([Color(color, 0.0), Color(color, 0.55), Color(color, 0.0)])
	p.process_material = pm
	# Smoke uses MIX (not additive) so dark reads as smoke, unshaded flat.
	p.draw_pass_1 = _quad(radius * 0.5, _sprite_mat("flare", color, false))
	root.add_child(p)


static func _layer_shock(root: Node3D, color: Color, radius: float, life: float) -> void:
	var p := _emitter(1, life, 1.0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	pm.gravity = Vector3.ZERO
	pm.scale_min = 1.0
	pm.scale_max = 1.0
	pm.scale_curve = _ramp_curve([0.1, 1.0])     # expand out
	pm.color_ramp = _ramp([Color(color, 0.9), Color(color, 0.0)])
	p.process_material = pm
	# Flat ground ring: face-Y billboard so it lies on the floor.
	var mat := _sprite_mat("shock_ring", color, true)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	var quad := QuadMesh.new()
	quad.size = Vector2(radius * 2.2, radius * 2.2)
	quad.orientation = PlaneMesh.FACE_Y
	quad.material = mat
	p.draw_pass_1 = quad
	p.position = Vector3(0, 0.08, 0)
	root.add_child(p)


## Gentle rising motes (healing): soft, slow, no gravity fight.
static func _layer_motes(root: Node3D, color: Color, radius: float) -> void:
	var p := _emitter(40, 2.6, 0.2)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_radius = radius
	pm.emission_ring_inner_radius = 0.0
	pm.emission_ring_height = 0.1
	pm.emission_ring_axis = Vector3.UP
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 8.0
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = radius * 0.3
	pm.initial_velocity_max = radius * 0.6
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.color = color
	pm.color_ramp = _ramp([Color(color, 0.0), Color(color, 0.9), Color(color, 0.0)])
	p.process_material = pm
	p.draw_pass_1 = _quad(radius * 0.15, _sprite_mat("flare", color, true))
	root.add_child(p)


## Soft expanding dome/bloom (healing/flash): one big additive flare.
static func _layer_bloom(root: Node3D, color: Color, radius: float, life: float) -> void:
	var p := _emitter(1, life, 1.0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	pm.gravity = Vector3.ZERO
	pm.scale_min = 1.0
	pm.scale_max = 1.0
	pm.scale_curve = _ramp_curve([0.3, 1.0])
	pm.color_ramp = _ramp([Color(color, 0.9), Color(color, 0.0)])
	p.process_material = pm
	p.draw_pass_1 = _quad(radius * 1.5, _sprite_mat("flare", color, true))
	root.add_child(p)


# --- decal + light + shake ------------------------------------------------------

## Ground Decal at the impact point, if its texture exists (arrives in the fal
## decal step). `name` -> assets/generated/vfx/decals/<name>.png. Fades over ~6 s.
static func _decal(root: Node3D, name: String, tint: Color, radius: float) -> void:
	var path := "%s/%s.png" % [DECAL_DIR, name]
	if not ResourceLoader.exists(path):
		return
	var d := Decal.new()
	d.texture_albedo = load(path)
	d.size = Vector3(radius * 1.8, 3.0, radius * 1.8)
	d.modulate = tint
	d.albedo_mix = 1.0
	root.add_child(d)
	var tw := d.create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(d, "albedo_mix", 0.0, 3.0)


static func _flash_light(root: Node3D, color: Color, radius: float, energy: float, fade: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.omni_range = radius * 2.2
	l.light_energy = energy
	root.add_child(l)
	l.position = Vector3(0, radius * 0.3, 0)
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, fade)


static func _shake(root: Node3D, at: Vector3, amount: float) -> void:
	for pl in root.get_tree().get_nodes_in_group("player"):
		if pl is Node3D and pl.has_method("add_recoil"):
			var d: float = (pl as Node3D).global_position.distance_to(at)
			if d < 18.0:
				pl.add_recoil(0.0, amount * clampf(1.0 - d / 18.0, 0.0, 1.0))


# --- builders -------------------------------------------------------------------

static func _emitter(amount: int, lifetime: float, explosiveness: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(1, amount)
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = explosiveness
	p.fixed_fps = 0
	p.emitting = true
	return p


static func _quad(size: float, mat: StandardMaterial3D) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = mat
	return q


static func _sprite_mat(tex_name: String, color: Color, additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = color
	var tex := _tex(tex_name)
	if tex != null:
		m.albedo_texture = tex
	return m


static func _tex(name: String) -> Texture2D:
	if _cache.has(name):
		return _cache[name]
	var path := "%s/%s.png" % [TEX_DIR, name]
	var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_cache[name] = t
	return t


## Grow quickly to full then shrink to 0 over lifetime (particle scale curve).
static func _grow_shrink(peak_at: float) -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.0))
	c.add_point(Vector2(peak_at, 1.0))
	c.add_point(Vector2(1.0, 0.0))
	var ct := CurveTexture.new()
	ct.curve = c
	return ct


## Linear ramp between two 0..1 scale values across lifetime.
static func _ramp_curve(pts: Array) -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0.0, float(pts[0])))
	c.add_point(Vector2(1.0, float(pts[1])))
	var ct := CurveTexture.new()
	ct.curve = c
	return ct


static func _ramp(colors: Array) -> GradientTexture1D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	var n := colors.size()
	for i in n:
		offs.append(float(i) / float(maxi(1, n - 1)))
		cols.append(colors[i])
	g.offsets = offs
	g.colors = cols
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt

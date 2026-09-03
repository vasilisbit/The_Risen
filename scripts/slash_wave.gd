class_name SlashWave
extends Node3D

## Assault Energy Blade projectile (T-0025 rework): instead of an instant cone, the
## blade throws a crescent energy wave that TRAVELS forward, damaging each enemy it
## passes through once, then fades out after a few metres. Spawned by EnergyBlade.
##
## Targeting mirrors the melee helpers (group "enemy" + surface distance) rather than
## physics layers, so it hits big bosses whose origin sits at their feet.

const SPEED := 20.0              # m/s the wave flies forward
const MAX_DIST := 9.0            # metres before it fully fades / frees
const HIT_RADIUS := 2.4          # how close to the wave centre an enemy is caught
const SLASH_GLB := "res://assets/generated/vfx/slash_arc.glb"

var _from: Vector3 = Vector3.ZERO
var _dir: Vector3 = Vector3.FORWARD
var _damage: float = 200.0
var _color: Color = Color(0.45, 0.85, 1.0)
var _traveled: float = 0.0
var _hit: Dictionary = {}        # instance_id -> true (damage each enemy once)
var _mat: StandardMaterial3D
var _light: OmniLight3D
var last_hits: int = 0           # enemies struck, exposed for tests


## Launch from `from` along `dir`, dealing `damage` (already melee-multiplied) tinted
## `color`. Add to the scene AFTER calling this.
func setup(from: Vector3, dir: Vector3, damage: float, color: Color) -> void:
	_from = from                       # applied in _ready (node not in the tree yet)
	# Keep the FULL 3D aim (including pitch) so the wave flies where the player is
	# looking - up a slope, at a raised enemy - not only along the flat heading.
	_dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	_damage = damage
	_color = color


func _ready() -> void:
	global_position = _from
	# look_at with a world UP is degenerate when the aim is near-vertical; pick a
	# non-parallel up in that case. Orientation is mostly cosmetic (the arc mesh
	# billboards to the camera), but a degenerate look_at spams errors.
	var up := Vector3.UP if absf(_dir.dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
	look_at(global_position + _dir, up)
	_build_visual()


func _build_visual() -> void:
	# The crescent GLB, billboarded + additive, so it reads as a flying energy arc.
	var arc := MeshUtil.load_prop(SLASH_GLB)
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_mat.billboard_keep_scale = true
	_mat.albedo_color = Color(_color.r * 1.3 + 0.2, _color.g * 1.2 + 0.2, _color.b + 0.1, 1.0)
	if arc != null:
		add_child(arc)
		MeshUtil.fit(arc, HIT_RADIUS * 2.2)
		for mi in arc.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = _mat
	else:
		var q := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(HIT_RADIUS * 2.2, HIT_RADIUS * 1.1)
		q.mesh = quad
		q.material_override = _mat
		add_child(q)
	_light = OmniLight3D.new()
	_light.light_color = _color
	_light.omni_range = HIT_RADIUS * 2.0
	_light.light_energy = 2.5
	add_child(_light)


func _physics_process(delta: float) -> void:
	var step := SPEED * delta
	global_position += _dir * step
	_traveled += step

	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node3D):
			continue
		var id := (e as Node).get_instance_id()
		if _hit.has(id):
			continue
		var to: Vector3 = (e as Node3D).global_position - global_position
		to.y = 0.0
		if to.length() - _enemy_radius(e) <= HIT_RADIUS:
			_hit[id] = true
			last_hits += 1
			if e.has_method("mark_damage_source"):
				e.mark_damage_source("Energy Blade")
			if e.has_method("take_damage"):
				e.take_damage(_damage)

	# Fade the last third of the flight, then free.
	var frac := clampf(_traveled / MAX_DIST, 0.0, 1.0)
	var a := clampf(1.0 - (frac - 0.6) / 0.4, 0.0, 1.0)
	if _mat:
		_mat.albedo_color.a = a
	if _light:
		_light.light_energy = 2.5 * a
	if _traveled >= MAX_DIST:
		queue_free()


## Horizontal body radius of an enemy (same approach as MeleeAbility), so the wave
## catches a boss by its body surface, not its foot origin.
func _enemy_radius(e: Node) -> float:
	if e.has_meta("_melee_radius"):
		return float(e.get_meta("_melee_radius"))
	var r := 0.5
	var shapes := e.find_children("*", "CollisionShape3D", true, false)
	if not shapes.is_empty():
		var shape: Shape3D = (shapes[0] as CollisionShape3D).shape
		if shape is SphereShape3D or shape is CapsuleShape3D or shape is CylinderShape3D:
			r = shape.radius
		elif shape is BoxShape3D:
			r = maxf(shape.size.x, shape.size.z) * 0.5
	if e is Node3D:
		var s: Vector3 = (e as Node3D).global_transform.basis.get_scale()
		r *= maxf(s.x, s.z)
	e.set_meta("_melee_radius", r)
	return r

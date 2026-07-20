class_name Grenade
extends RigidBody3D

## Base thrown grenade (T-0024). A real RigidBody3D so the throw follows a
## physics arc and bounces off geometry, rather than a scripted parabola.
## Subclasses (frag / healing / flash) declare their identity through the
## constants below and implement _detonate().
##
## The ability that throws these reads GRENADE_NAME / GRENADE_COLOR off the
## subclass, so the payload owns its own presentation. Those two names are
## declared ONLY in subclasses - GDScript forbids shadowing a parent constant,
## so the base keeps its fallbacks under different names.

const DEFAULT_NAME := "Grenade"
const DEFAULT_COLOR := Color(0.8, 0.8, 0.8)

const FUSE := 1.5                 # s from throw to detonation
const BODY_RADIUS := 0.16
const MASS := 0.6
## Bounce/roll: lively enough to skip off a wall, damped enough to settle near
## where it lands. At 0.35 bounce / 0.6 friction a level throw touched down at
## ~10 m and then rolled on to 13.4 m, which made placement guesswork.
const BOUNCE := 0.12
const FRICTION := 1.0
const ANGULAR_DAMP := 5.0
const LINEAR_DAMP := 0.5

var _fuse_left: float = FUSE
var _detonated: bool = false
var _mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("grenade")
	mass = MASS
	# Collide with the world (layer 1) but sit on its own layer so the
	# grenade can never be shot or targeted like an enemy.
	collision_layer = 0
	collision_mask = 1
	continuous_cd = true           # a fast throw must not tunnel through walls
	angular_damp = ANGULAR_DAMP
	linear_damp = LINEAR_DAMP
	_build_body()


func _physics_process(delta: float) -> void:
	if _detonated:
		return
	_fuse_left -= delta
	_pulse()
	if _fuse_left <= 0.0:
		detonate()


## Launch along `dir` at `speed`. Called by the throwing ability.
func throw(from: Vector3, dir: Vector3, speed: float) -> void:
	global_position = from
	linear_velocity = dir.normalized() * speed
	# A little spin so it visibly tumbles through the arc.
	angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))


## Fire the effect once, then clean up. Public so tests can trigger it early.
func detonate() -> void:
	if _detonated:
		return
	_detonated = true
	_detonate()
	queue_free()


## Subclass hook - the actual effect, at global_position.
func _detonate() -> void:
	pass


# --- shared helpers ---------------------------------------------------------

func _host() -> Node:
	var host := get_tree().current_scene
	return host if host != null else get_tree().root


## Living enemies within `radius` of this grenade.
func _enemies_in(radius: float) -> Array:
	var found: Array = []
	var here := global_position
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node3D):
			continue
		if (e as Node3D).global_position.distance_to(here) <= radius:
			found.append(e)
	return found


func _build_body() -> void:
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = BODY_RADIUS
	col.shape = shape
	add_child(col)

	var phys := PhysicsMaterial.new()
	phys.bounce = BOUNCE
	phys.friction = FRICTION
	physics_material_override = phys

	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = BODY_RADIUS
	sphere.height = BODY_RADIUS * 2.0
	mi.mesh = sphere
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = _colour().darkened(0.5)
	_mat.emission_enabled = true
	_mat.emission = _colour()
	_mat.emission_energy_multiplier = 1.5
	mi.material_override = _mat
	add_child(mi)


## Blink faster as the fuse runs down, so the throw is readable in flight.
func _pulse() -> void:
	if _mat == null:
		return
	var t := 1.0 - clampf(_fuse_left / FUSE, 0.0, 1.0)
	var rate := lerpf(4.0, 18.0, t)
	var wave := 0.5 + 0.5 * sin(_fuse_left * rate)
	_mat.emission_energy_multiplier = lerpf(1.0, 5.0, wave)


## Subclasses declare GRENADE_COLOR; read it off the actual script.
func _colour() -> Color:
	var c: Variant = get_script().get_script_constant_map().get("GRENADE_COLOR", DEFAULT_COLOR)
	return c if c is Color else DEFAULT_COLOR


## Expanding translucent sphere marking the effect radius.
func _burst(at: Vector3, color: Color, size: float, time: float) -> void:
	var vfx := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	vfx.mesh = sphere
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, 0.6)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 4.5
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	vfx.material_override = m
	_host().add_child(vfx)
	vfx.global_position = at
	vfx.scale = Vector3.ONE * 0.3
	var tw := vfx.create_tween()
	tw.tween_property(vfx, "scale", Vector3.ONE * size, time)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, time)
	tw.tween_callback(vfx.queue_free)

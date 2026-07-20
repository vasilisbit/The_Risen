class_name Rocket
extends Node3D

## Homing rocket fired by the Assault super, Storm Barrage (T-0023).
## 200 damage in an 8 m splash on impact (GDD §2.4).
##
## This one DOES home, unlike every enemy projectile in the game — those were
## deliberately made linear so the player can strafe out of them. A player
## super that the player aims at nothing in particular has the opposite
## requirement: it should reliably hit what it was launched at.

const SPEED := 26.0
const TURN_RATE := 5.0            # rad/s of steering toward the target
const DAMAGE := 200.0
const SPLASH_RADIUS := 8.0
const LIFETIME := 6.0
const ARM_TIME := 0.15            # s of straight flight before it starts homing
const COLOR := Color(1.0, 0.75, 0.25)

var target: Node3D
var _dir: Vector3 = Vector3.UP
var _life: float = 0.0
var _detonated: bool = false


## Launch from `from`, initially heading `initial_dir`, homing onto `at`.
func setup(from: Vector3, initial_dir: Vector3, at: Node3D) -> void:
	position = from
	_dir = initial_dir.normalized()
	target = at


func _ready() -> void:
	var mi := MeshInstance3D.new()
	var body := CapsuleMesh.new()
	body.radius = 0.12
	body.height = 0.5
	mi.mesh = body
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLOR
	mat.emission_enabled = true
	mat.emission = COLOR
	mat.emission_energy_multiplier = 3.0
	mi.material_override = mat
	add_child(mi)


func _physics_process(delta: float) -> void:
	if _detonated:
		return
	_life += delta
	if _life > LIFETIME:
		detonate()
		return

	# Steer toward the target once armed. A dead target just flies on straight.
	if _life > ARM_TIME and target != null and is_instance_valid(target):
		var want := (target.global_position + Vector3(0, 1.0, 0) - global_position)
		if want.length() > 0.01:
			_dir = _dir.slerp(want.normalized(), clampf(TURN_RATE * delta, 0.0, 1.0))

	var step := _dir * SPEED * delta
	# Detonate on contact with the world or the target itself.
	if target != null and is_instance_valid(target):
		if global_position.distance_to(target.global_position + Vector3(0, 1.0, 0)) <= 1.2:
			global_position += step
			detonate()
			return
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + step, 1)
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		global_position = hit["position"]
		detonate()
		return

	global_position += step
	look_at(global_position + _dir, Vector3.UP)


## Splash damage to every enemy in SPLASH_RADIUS. Public for tests.
func detonate() -> void:
	if _detonated:
		return
	_detonated = true
	var here := global_position
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node3D):
			continue
		if (e as Node3D).global_position.distance_to(here) > SPLASH_RADIUS:
			continue
		if e.has_method("mark_damage_source"):
			e.mark_damage_source("Storm Barrage")
		if e.has_method("take_damage"):
			e.take_damage(DAMAGE)
	_explosion_vfx(here)
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.play_sfx("explosion", here)
	queue_free()


func _explosion_vfx(at: Vector3) -> void:
	var host := get_tree().current_scene
	if host == null:
		host = get_tree().root
	var vfx := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	vfx.mesh = sphere
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(COLOR, 0.7)
	m.emission_enabled = true
	m.emission = COLOR
	m.emission_energy_multiplier = 5.0
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	vfx.material_override = m
	host.add_child(vfx)
	vfx.global_position = at
	vfx.scale = Vector3.ONE * 0.3
	var tw := vfx.create_tween()
	tw.tween_property(vfx, "scale", Vector3.ONE * SPLASH_RADIUS, 0.35)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, 0.35)
	tw.tween_callback(vfx.queue_free)

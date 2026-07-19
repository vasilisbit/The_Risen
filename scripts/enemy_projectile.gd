class_name EnemyProjectile
extends Node3D

## Homing enemy projectile (T-0008). Built and fired from code by the Shooter —
## no scene file needed. Steers toward the target with a capped turn rate (so it
## catches a strafing player but can be dodged with hard direction changes),
## checks walls with a ray each step, and hits the player by proximity so the
## logic is deterministic and testable without physics-server callbacks.

const SPEED := 18.0            # m/s
const TURN_RATE := 3.0         # rad/s max steering toward the target
const LIFETIME := 5.0          # s
const HIT_RADIUS := 0.8        # m to target chest
const TARGET_CHEST := Vector3(0.0, 1.0, 0.0)

var damage: float = 100.0
var _dir: Vector3 = Vector3.FORWARD
var _target: Node3D = null
var _shooter_rid: RID
var _life: float = 0.0


func setup(from: Vector3, target: Node3D, shooter_rid: RID) -> void:
	_target = target
	_shooter_rid = shooter_rid
	position = from
	if target != null:
		_dir = (target.global_position + TARGET_CHEST - from).normalized()


func _ready() -> void:
	# Small emissive orange bolt.
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	mi.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.55, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.1)
	mat.emission_energy_multiplier = 2.5
	mi.material_override = mat
	add_child(mi)


func _physics_process(delta: float) -> void:
	_life += delta
	if _life > LIFETIME:
		queue_free()
		return

	# Steer toward the target with a capped turn rate.
	if _target != null and is_instance_valid(_target):
		var desired := (_target.global_position + TARGET_CHEST - global_position).normalized()
		var angle := _dir.angle_to(desired)
		if angle > 0.0001:
			var t := clampf(TURN_RATE * delta / angle, 0.0, 1.0)
			_dir = _dir.slerp(desired, t).normalized()

	var step := _dir * SPEED * delta

	# Wall check along this step (world layer 1). Enemies are excluded so bolts
	# pass allies; hitting the player body counts as a hit.
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + step, 1)
	var excludes: Array[RID] = [_shooter_rid]
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is CollisionObject3D:
			excludes.append(e.get_rid())
	query.exclude = excludes
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		var collider: Object = hit["collider"]
		if collider is Node and (collider as Node).is_in_group("player"):
			_hit_player(collider as Node)
		else:
			queue_free()          # wall / prop
		return

	global_position += step

	# Proximity hit on the target (deterministic, no Area3D callback needed).
	if _target != null and is_instance_valid(_target):
		if global_position.distance_to(_target.global_position + TARGET_CHEST) <= HIT_RADIUS:
			_hit_player(_target)


func _hit_player(node: Node) -> void:
	if node.has_method("take_damage"):
		node.take_damage(damage)
	queue_free()

class_name EnemyBase
extends CharacterBody3D

## Shared enemy plumbing (T-0007/T-0008/T-0009): health, damage intake, death
## signal, loot drop, player lookup, gravity, headshot test. Subclasses set
## `max_health` in _init() and implement their own _physics_process guarding on
## `_dead`.

signal died(where: Vector3)

## Assigned by the loot system (T-0011); until then a placeholder beacon drops.
@export var loot_scene: PackedScene

## Local height (from the body origin at the feet) at/above which a hit counts
## as a headshot — matches the 1.8 m capsule (top hemisphere).
const HEAD_MIN_LOCAL_Y := 1.4

var max_health: float = 100.0
var health: float = 100.0
var _dead: bool = false
var _player: Node3D = null
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)


func _ready() -> void:
	add_to_group("enemy")
	health = max_health
	_player = _find_player()


func _find_player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


## Re-resolve the player if it was freed; returns true when a target exists.
func _ensure_player() -> bool:
	if _player == null or not is_instance_valid(_player):
		_player = _find_player()
	return _player != null


func _halt_horizontal() -> void:
	velocity.x = 0.0
	velocity.z = 0.0


func _face(target: Vector3) -> void:
	var flat := Vector3(target.x, global_position.y, target.z)
	if global_position.distance_to(flat) > 0.05:
		look_at(flat, Vector3.UP)


## True when a world-space hit point lands in this enemy's head zone.
func is_headshot(world_point: Vector3) -> bool:
	return (world_point.y - global_position.y) >= HEAD_MIN_LOCAL_Y


## Incoming damage (from weapons T-0010). Dies + drops loot at 0 HP.
func take_damage(amount: float) -> void:
	if _dead:
		return
	health = maxf(0.0, health - amount)
	if health <= 0.0:
		_die()


func _die() -> void:
	_dead = true
	var where := global_position
	died.emit(where)
	_drop_loot(where)
	queue_free()


func _drop_loot(where: Vector3) -> void:
	var drop: Node3D
	if loot_scene != null:
		drop = loot_scene.instantiate() as Node3D
	else:
		drop = _placeholder_loot()
	# Parent to the scene (not self — we are about to free) so the drop persists.
	# Add to the tree BEFORE setting global_position (that requires being inside).
	var host := get_tree().current_scene
	if host == null:
		host = get_tree().root
	host.add_child(drop)
	drop.global_position = where + Vector3(0.0, 0.5, 0.0)


## Temporary loot marker until T-0011 provides loot_drop.tscn.
func _placeholder_loot() -> Node3D:
	var mi := MeshInstance3D.new()
	mi.name = "LootDropPlaceholder"
	mi.add_to_group("loot")
	var sphere := SphereMesh.new()
	sphere.radius = 0.2
	sphere.height = 0.4
	mi.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1)
	mat.emission_enabled = true
	mat.emission = Color(1, 1, 1)
	mat.emission_energy_multiplier = 2.0
	mi.material_override = mat
	return mi

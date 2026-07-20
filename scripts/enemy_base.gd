class_name EnemyBase
extends CharacterBody3D

## Shared enemy plumbing (T-0007/T-0008/T-0009): health, damage intake, death
## signal, loot drop, player lookup, gravity, headshot test. Subclasses set
## `max_health` in _init() and implement their own _physics_process guarding on
## `_dead`.

signal died(where: Vector3)

## Loot spawned on death. If unset, the shared loot_drop.tscn (T-0011) is used.
@export var loot_scene: PackedScene

## Local height (from the body origin at the feet) at/above which a hit counts
## as a headshot — matches the 1.8 m capsule (top hemisphere).
const HEAD_MIN_LOCAL_Y := 1.4
const LOOT_SCENE_PATH := "res://scenes/weapons/loot_drop.tscn"

## Mission-wide enemy modifiers set by the Mars debuff picks (T-0018). Static so
## they apply to every enemy, including ones spawned later. Reset per mission.
static var speed_scale: float = 1.0          # -10% speed pick -> 0.9
static var accuracy_penalty: float = 0.0     # -5% accuracy pick -> 0.05


static func reset_modifiers() -> void:
	speed_scale = 1.0
	accuracy_penalty = 0.0

## Force a loot rarity on death (e.g. a boss guaranteeing an Epic). Empty = roll.
var loot_rarity_override: String = ""

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


## Horizontal steering direction toward a NavigationAgent3D waypoint. The
## navmesh sits slightly above the floor, so once the agent is horizontally on
## top of a waypoint the flattened delta collapses to ~0 and the enemy would
## stall every time it reached one. Fall back to heading straight at the final
## target in that case.
func _nav_dir(next: Vector3, fallback_target: Vector3) -> Vector3:
	var dir := next - global_position
	dir.y = 0.0
	if dir.length() < 0.15:
		dir = fallback_target - global_position
		dir.y = 0.0
	return dir


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


## Spawn loot at the death position + a random offset within a 1 m radius
## (GDD §2.7). Uses `loot_scene` if set, else the shared loot_drop.tscn.
func _drop_loot(where: Vector3) -> void:
	var drop: Node3D = null
	if loot_scene != null:
		drop = loot_scene.instantiate() as Node3D
	else:
		var packed := load(LOOT_SCENE_PATH)
		if packed != null:
			drop = packed.instantiate() as Node3D
	if drop == null:
		drop = _placeholder_loot()
	# Force rarity (e.g. boss Epic) before the drop enters the tree and rolls.
	if loot_rarity_override != "" and ("forced_rarity" in drop):
		drop.forced_rarity = loot_rarity_override
	# Parent to the scene (not self — we are about to free) so the drop persists.
	var host := get_tree().current_scene
	if host == null:
		host = get_tree().root
	host.add_child(drop)
	var offset := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	if offset.length() > 1.0:
		offset = offset.normalized()
	drop.global_position = where + Vector3(0.0, 0.4, 0.0) + offset


## Fallback marker if the loot scene fails to load.
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

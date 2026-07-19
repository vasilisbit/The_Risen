class_name Rusher
extends CharacterBody3D

## Melee Rusher enemy (T-0007). Plain-GDScript enum state machine (zero deps —
## LimboAI deferred per tracker Open Decision #2). Detects the player within 10 m,
## chases at 9 m/s via NavigationAgent3D, and melees for 150 damage at 2 m on a
## 1.5 s cooldown. HP 150; drops loot on death.

const MAX_HEALTH := 150.0
const SPRINT_SPEED := 9.0        # m/s
const DETECT_RANGE := 10.0       # m
const ATTACK_RANGE := 2.0        # m
const MELEE_DAMAGE := 150.0
const ATTACK_COOLDOWN := 1.5     # s

enum State { IDLE, CHASE, ATTACK, DEAD }

signal died(where: Vector3)

## Assigned by the loot system (T-0011); until then a placeholder beacon drops.
@export var loot_scene: PackedScene

@onready var _agent: NavigationAgent3D = $NavigationAgent3D

var health: float = MAX_HEALTH
var _state: State = State.IDLE
var _attack_timer: float = 0.0
var _player: Node3D = null
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)


func _ready() -> void:
	add_to_group("enemy")
	_player = _find_player()


func _find_player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return
	if _attack_timer > 0.0:
		_attack_timer -= delta
	if not is_on_floor():
		velocity.y -= _gravity * delta

	if _player == null or not is_instance_valid(_player):
		_player = _find_player()
	if _player == null:
		_halt_horizontal()
		move_and_slide()
		return

	var dist := global_position.distance_to(_player.global_position)
	match _state:
		State.IDLE:
			_halt_horizontal()
			if dist <= DETECT_RANGE:
				_state = State.CHASE
		State.CHASE:
			if dist <= ATTACK_RANGE:
				_state = State.ATTACK
			else:
				_chase()
		State.ATTACK:
			_halt_horizontal()
			_face(_player.global_position)
			if dist > ATTACK_RANGE * 1.25:
				_state = State.CHASE
			elif _attack_timer <= 0.0:
				_do_melee()

	move_and_slide()


func _chase() -> void:
	_agent.target_position = _player.global_position
	var next := _agent.get_next_path_position()
	var dir := next - global_position
	dir.y = 0.0
	if dir.length() > 0.05:
		dir = dir.normalized()
		velocity.x = dir.x * SPRINT_SPEED
		velocity.z = dir.z * SPRINT_SPEED
		_face(global_position + dir)
	else:
		_halt_horizontal()


func _halt_horizontal() -> void:
	velocity.x = 0.0
	velocity.z = 0.0


func _face(target: Vector3) -> void:
	var flat := Vector3(target.x, global_position.y, target.z)
	if global_position.distance_to(flat) > 0.05:
		look_at(flat, Vector3.UP)


func _do_melee() -> void:
	_attack_timer = ATTACK_COOLDOWN
	if _player and _player.has_method("take_damage"):
		_player.take_damage(MELEE_DAMAGE)


## Incoming damage (weapons land in T-0010). Dies + drops loot at 0 HP.
func take_damage(amount: float) -> void:
	if _state == State.DEAD:
		return
	health = maxf(0.0, health - amount)
	if health <= 0.0:
		_die()


func _die() -> void:
	_state = State.DEAD
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

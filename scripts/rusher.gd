class_name Rusher
extends EnemyBase

## Melee Rusher enemy (T-0007). Plain-GDScript enum state machine (zero deps -
## LimboAI deferred per tracker Open Decision #2). Detects the player within 10 m,
## chases at 9 m/s via NavigationAgent3D, and melees for 90 damage at 2 m on a
## 1.5 s cooldown. HP 150; drops loot on death (EnemyBase).

const SPRINT_SPEED := 5.0        # m/s (below the player's 6 m/s walk - kiteable)
const DETECT_RANGE := 10.0       # m (default; per-instance override via `detect_range`)
const ATTACK_RANGE := 2.0        # m

## Aggro radius. Defaults to DETECT_RANGE but spawners can widen it per instance
## (e.g. the Venus ascent, where the player out-ranged the default and picked
## enemies off before they ever woke - venus_mission.gd).
var detect_range: float = DETECT_RANGE
const MELEE_DAMAGE := 90.0        # normal-mode balance: was 150 (nearly 2-shot the player)
const ATTACK_COOLDOWN := 1.5     # s

enum State { IDLE, CHASE, ATTACK }

@onready var _agent: NavigationAgent3D = $NavigationAgent3D

var _state: State = State.IDLE
var _attack_timer: float = 0.0


func _init() -> void:
	max_health = 150.0


func _enemy_voice() -> String:
	return "enemy_rusher"


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if _tick_status(delta):
		return
	if _attack_timer > 0.0:
		_attack_timer -= delta
	if not is_on_floor():
		velocity.y -= _gravity * delta

	if not _ensure_player():
		_halt_horizontal()
		move_and_slide()
		return

	var dist := global_position.distance_to(_player.global_position)
	match _state:
		State.IDLE:
			_halt_horizontal()
			if dist <= detect_range:
				_state = State.CHASE
		State.CHASE:
			if dist <= ATTACK_RANGE:
				_state = State.ATTACK
			else:
				_chase(delta)
		State.ATTACK:
			_halt_horizontal()
			_face(_player.global_position)
			if dist > ATTACK_RANGE * 1.25:
				_state = State.CHASE
			elif _attack_timer <= 0.0:
				_do_melee()

	move_and_slide()


func _chase(delta: float) -> void:
	var dir := _nav_dir(_agent, _player.global_position, delta)
	if dir.length() > 0.05:
		dir = dir.normalized()
		var spd := SPRINT_SPEED * EnemyBase.speed_scale
		velocity.x = dir.x * spd
		velocity.z = dir.z * spd
		_face(global_position + dir)
		_tick_jump(dir, delta)          # hop onto a crate/ledge in the way
	else:
		_halt_horizontal()


func _do_melee() -> void:
	_attack_timer = ATTACK_COOLDOWN
	# Swing first, land the hit at the animation's contact point (EnemyBase).
	melee_strike(MELEE_DAMAGE, "Rusher", ATTACK_RANGE * 1.4)

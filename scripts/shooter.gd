class_name Shooter
extends EnemyBase

## Ranged Shooter enemy (T-0008). Enum state machine (same zero-dep approach as
## the Rusher): detect the player at 20 m → navigate to the best cover marker
## (group "cover_point", within 10 m, preferring markers whose line of sight to
## the player is blocked) → every 3 s peek out sideways until LOS clears →
## fire a homing projectile (100 damage, 2 s cooldown) → slip back into cover.
## HP 100; drops loot on death (EnemyBase).

const MOVE_SPEED := 4.5          # m/s
const DETECT_RANGE := 20.0       # m
const COVER_SEARCH_RADIUS := 10.0
const PEEK_INTERVAL := 3.0       # s in cover between peeks
const PEEK_OFFSET := 1.6         # m sideways step
const PEEK_TIMEOUT := 2.5        # s max out of cover
const SHOOT_COOLDOWN := 2.0      # s between shots
const EYE_HEIGHT := 1.4          # m (muzzle / LOS origin)
const ARRIVE_DIST := 0.8         # m

enum State { IDLE, SEEK_COVER, COVER, PEEK }

@onready var _agent: NavigationAgent3D = $NavigationAgent3D

var _state: State = State.IDLE
var _cover_pos: Vector3
var _peek_timer: float = 0.0
var _peek_elapsed: float = 0.0
var _peek_target: Vector3
var _peek_side: float = 1.0      # flips each peek so both sides get tried
var _shoot_timer: float = 0.0
var shots_fired: int = 0         # exposed for tests/telemetry


func _init() -> void:
	max_health = 100.0


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if _tick_status(delta):
		return
	if _shoot_timer > 0.0:
		_shoot_timer -= delta
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
			if dist <= DETECT_RANGE:
				_cover_pos = _pick_cover()
				_state = State.SEEK_COVER
		State.SEEK_COVER:
			if global_position.distance_to(_cover_pos) <= ARRIVE_DIST:
				_halt_horizontal()
				_peek_timer = 0.0
				_state = State.COVER
			else:
				_navigate_to(_cover_pos)
		State.COVER:
			_halt_horizontal()
			_face(_player.global_position)
			_peek_timer += delta
			if _peek_timer >= PEEK_INTERVAL:
				_begin_peek()
		State.PEEK:
			_peek_elapsed += delta
			_face(_player.global_position)
			if _has_los():
				_halt_horizontal()
				if _shoot_timer <= 0.0:
					_shoot()
					_state = State.SEEK_COVER    # slip back into cover
			elif _peek_elapsed >= PEEK_TIMEOUT:
				_state = State.SEEK_COVER        # could not clear LOS; retry later
			else:
				_move_straight_to(_peek_target)

	move_and_slide()


## Nearest cover marker within range whose eye-height LOS to the player is
## blocked; falls back to the nearest marker, then to standing ground.
func _pick_cover() -> Vector3:
	var markers := get_tree().get_nodes_in_group("cover_point")
	var best_blocked: Node3D = null
	var best_blocked_d := INF
	var best_any: Node3D = null
	var best_any_d := INF
	for m in markers:
		if m is not Node3D:
			continue
		var d := global_position.distance_to((m as Node3D).global_position)
		if d > COVER_SEARCH_RADIUS:
			continue
		if d < best_any_d:
			best_any = m
			best_any_d = d
		if not _los_from((m as Node3D).global_position + Vector3(0, EYE_HEIGHT, 0)) and d < best_blocked_d:
			best_blocked = m
			best_blocked_d = d
	if best_blocked != null:
		return best_blocked.global_position
	if best_any != null:
		return best_any.global_position
	return global_position


func _begin_peek() -> void:
	var to_player := _player.global_position - _cover_pos
	to_player.y = 0.0
	var side := to_player.cross(Vector3.UP).normalized() * PEEK_OFFSET * _peek_side
	_peek_side = -_peek_side
	_peek_target = _cover_pos + side
	_peek_elapsed = 0.0
	_state = State.PEEK


func _navigate_to(pos: Vector3) -> void:
	_agent.target_position = pos
	var next := _agent.get_next_path_position()
	_steer(global_position + _nav_dir(next, pos))


func _move_straight_to(pos: Vector3) -> void:
	_steer(pos)


func _steer(toward: Vector3) -> void:
	var dir := toward - global_position
	dir.y = 0.0
	if dir.length() > 0.05:
		dir = dir.normalized()
		var spd := MOVE_SPEED * EnemyBase.speed_scale
		velocity.x = dir.x * spd
		velocity.z = dir.z * spd
	else:
		_halt_horizontal()


func _eye() -> Vector3:
	return global_position + Vector3(0, EYE_HEIGHT, 0)


func _has_los() -> bool:
	return _los_from(_eye())


## True when the ray from `from` to the player's chest reaches the player.
func _los_from(from: Vector3) -> bool:
	if _player == null:
		return false
	var space := get_world_3d().direct_space_state
	var to := _player.global_position + Vector3(0, 1.0, 0)
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return true
	var collider: Object = hit["collider"]
	return collider is Node and (collider as Node).is_in_group("player")


func _shoot() -> void:
	_shoot_timer = SHOOT_COOLDOWN
	shots_fired += 1
	var p := load("res://scripts/enemy_projectile.gd").new() as Node3D
	var host := get_tree().current_scene
	if host == null:
		host = get_tree().root
	host.add_child(p)
	p.setup(_eye(), _player, get_rid())
	# "-5% enemy accuracy" debuff pick: nudge the shot off-target.
	if EnemyBase.accuracy_penalty > 0.0:
		p._dir = _stray(p._dir, EnemyBase.accuracy_penalty)


## Rotate a firing direction by a random error cone (radians = penalty).
func _stray(dir: Vector3, penalty: float) -> Vector3:
	var axis := dir.cross(Vector3.UP)
	if axis.length() < 0.001:
		axis = Vector3.RIGHT
	axis = axis.normalized()
	var a := randf_range(-penalty, penalty)
	var b := randf_range(-penalty, penalty)
	return dir.rotated(axis, a).rotated(Vector3.UP, b).normalized()

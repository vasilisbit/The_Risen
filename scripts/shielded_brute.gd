class_name ShieldedBrute
extends EnemyBase

## Earth mini-boss (T-0013). 500-point shield GATE (invulnerable until broken),
## then 1500 HP. Chases the player; melee 200 dmg at 3 m / 1.5 s; once the shield
## is broken it can ground-slam (150 dmg in a hard 5 m radius, 10 s cd, knockback).
## Spawns 5 Rusher adds at 50% HP. Drops a guaranteed Epic. Values per GDD §3.2.

const MOVE_SPEED := 4.0
const DETECT_RANGE := 25.0
const MELEE_RANGE := 3.0
const MELEE_DAMAGE := 200.0
const MELEE_COOLDOWN := 1.5
const SLAM_RANGE := 5.0
const SLAM_DAMAGE := 150.0
const SLAM_RADIUS := 5.0          # hard cutoff: hits at 4 m, nothing at 6 m
const SLAM_COOLDOWN := 10.0
const SLAM_KNOCKBACK := 9.0
const MAX_SHIELD := 500.0
const ADDS_COUNT := 5

enum State { IDLE, CHASE, ATTACK }

@onready var _agent: NavigationAgent3D = $NavigationAgent3D

var shield: float = MAX_SHIELD
var _state: State = State.IDLE
var _melee_timer: float = 0.0
var _slam_timer: float = 0.0
var _adds_spawned: bool = false
var _shield_vfx: MeshInstance3D


func _init() -> void:
	max_health = 1500.0
	flux_value = 50
	loot_rarity_override = "Epic"          # guaranteed Epic on death


func _ready() -> void:
	super._ready()
	add_to_group("boss")
	_build_shield_vfx()


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if _tick_status(delta):
		return
	_melee_timer = maxf(0.0, _melee_timer - delta)
	_slam_timer = maxf(0.0, _slam_timer - delta)
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
				_state = State.CHASE
		State.CHASE:
			if dist <= SLAM_RANGE:
				_state = State.ATTACK
			else:
				_chase(delta)
		State.ATTACK:
			_halt_horizontal()
			_face(_player.global_position)
			if dist > SLAM_RANGE * 1.2:
				_state = State.CHASE
			elif shield <= 0.0 and _slam_timer <= 0.0:
				slam()                          # phase 2 only
			elif dist <= MELEE_RANGE and _melee_timer <= 0.0:
				_melee()

	move_and_slide()


func _chase(delta: float) -> void:
	var dir := _nav_dir(_agent, _player.global_position, delta)
	if dir.length() > 0.05:
		dir = dir.normalized()
		var spd := MOVE_SPEED * EnemyBase.speed_scale
		velocity.x = dir.x * spd
		velocity.z = dir.z * spd
		_face(global_position + dir)
		_tick_jump(dir, delta)          # hop onto a crate/ledge in the way
	else:
		_halt_horizontal()


func _melee() -> void:
	_melee_timer = MELEE_COOLDOWN
	play_attack_animation()
	if _player and _player.has_method("take_damage"):
		_player.take_damage(MELEE_DAMAGE, "ShieldedBrute")


## Ground slam: hard-radius AoE + knockback. Public so it is unit-testable.
func slam() -> void:
	_slam_timer = SLAM_COOLDOWN
	_melee_timer = MELEE_COOLDOWN            # don't melee the same frame
	_spawn_slam_vfx()
	if _player == null:
		return
	if global_position.distance_to(_player.global_position) <= SLAM_RADIUS:
		if _player.has_method("take_damage"):
			_player.take_damage(SLAM_DAMAGE, "ShieldedBrute")
		if _player.has_method("apply_knockback"):
			var kb := _player.global_position - global_position
			kb.y = 0.0
			kb = kb.normalized() * SLAM_KNOCKBACK
			kb.y = 4.0                       # a little lift
			_player.apply_knockback(kb)


# --- nameplate (boss tier; the gate shield feeds the shield bar) -------------

func nameplate_tier() -> String:
	return "boss"


func nameplate_shield() -> float:
	return shield + elemental_shield


func nameplate_shield_max() -> float:
	return MAX_SHIELD + max_elemental_shield


func nameplate_head_y() -> float:
	return 3.5


func nameplate_shell_radius() -> float:
	return 1.2


## Shield gates all HP damage until it is depleted (invulnerable phase 1).
func take_damage(amount: float) -> void:
	if _dead or amount <= 0.0:
		return
	amount = absorb_shield(amount)
	if amount <= 0.0:
		return
	if shield > 0.0:
		shield = maxf(0.0, shield - amount)
		_update_shield_vfx()
		if shield <= 0.0 and _shield_vfx:
			_shield_vfx.visible = false
		return
	health = maxf(0.0, health - amount)
	if health <= 0.0:
		_die()
	elif not _adds_spawned and health <= max_health * 0.5:
		_spawn_adds()


func _spawn_adds() -> void:
	_adds_spawned = true
	var scene := load("res://scenes/enemies/rusher.tscn")
	if scene == null:
		return
	var host := get_tree().current_scene
	if host == null:
		host = get_tree().root
	for i in ADDS_COUNT:
		var r := scene.instantiate() as Node3D
		host.add_child(r)
		var ang := TAU * float(i) / float(ADDS_COUNT)
		r.global_position = global_position + Vector3(cos(ang) * 3.0, 1.0, sin(ang) * 3.0)


## The shield telegraph is now the shared blue outline built by the nameplate
## (a silhouette of the Brute), so no separate shield bubble is created here.
## `_shield_vfx` stays null and the guarded references below simply no-op.
func _build_shield_vfx() -> void:
	pass
	_update_shield_vfx()


func _update_shield_vfx() -> void:
	if _shield_vfx:
		_shield_vfx.visible = shield > 0.0


func _spawn_slam_vfx() -> void:
	var host := get_tree().current_scene
	if host == null:
		host = get_tree().root
	var vfx := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	vfx.mesh = sphere
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.5, 1.0, 0.6)
	m.emission_enabled = true
	m.emission = Color(0.3, 0.5, 1.0)
	m.emission_energy_multiplier = 3.0
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	vfx.material_override = m
	host.add_child(vfx)
	vfx.global_position = global_position + Vector3(0, 0.3, 0)
	vfx.scale = Vector3.ONE * 0.3
	var tw := vfx.create_tween()
	tw.tween_property(vfx, "scale", Vector3(SLAM_RADIUS * 2.0, 1.0, SLAM_RADIUS * 2.0), 0.4)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, 0.4)
	tw.tween_callback(vfx.queue_free)

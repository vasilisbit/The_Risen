class_name EmberTyrant
extends EnemyBase

## Venus final boss: The Ember Tyrant (T-0021). 5000 HP across three phases
## (GDD §3.4), driven by a plain enum state machine like the other enemies.
##
##   Phase A (100%-66%): roams, melee 150 @ 3 m / 2 s + fireball 100 / 3 s.
##   Phase B (66%-33%):  roar, then an INVULNERABLE shield. 4 crystals spawn at
##                       the arena's weak_point markers (200 HP each) and only
##                       destroying all 4 drops the shield. 10 Rusher adds over
##                       20 s (2 every 4 s). Attacks continue at 1.5x cooldown.
##   Phase C (33%-0%):   rage. Attack speed +50%, move speed x1.5, AoE slam
##                       (200 dmg / 5 m / 8 s, exact 3 m knockback) and a lava
##                       eruption every 10 s at one of 8 arena markers.
##
## Phases are strictly sequential and cannot be skipped: the boss takes zero
## damage while shielded, so HP can never cross 33% before phase B is resolved.
## Death plays a 3 s sequence, then drops 1 Exotic weapon + 3 Epic armour.

const TOTAL_HEALTH := 5000.0
const PHASE_B_AT := 0.66          # fraction of max HP
const PHASE_C_AT := 0.33

const MOVE_SPEED := 3.6           # x1.5 in phase C = 5.4, still under the
                                  # Guardian's 6.0 walk so the boss stays kiteable
const RAGE_SPEED_MULT := 1.5
const DETECT_RANGE := 35.0

const MELEE_RANGE := 3.0
const MELEE_DAMAGE := 150.0
const MELEE_COOLDOWN := 2.0
const FIREBALL_DAMAGE := 100.0
const FIREBALL_COOLDOWN := 3.0
const FIREBALL_RANGE := 30.0

const SLAM_DAMAGE := 200.0
const SLAM_RADIUS := 5.0
const SLAM_COOLDOWN := 8.0
const SLAM_KNOCKBACK := 3.0       # metres, exact (Guardian.apply_push)
const SLAM_LIFT := 4.0

const ERUPTION_INTERVAL := 10.0   # -> ~10 eruptions per 100 s (card acceptance)
const ADDS_TOTAL := 10
const ADDS_PER_BURST := 2
const ADDS_BURST_INTERVAL := 4.0  # 10 adds over 20 s
const WEAK_POINT_COUNT := 4
const WEAK_POINT_RING := 5.0      # fallback ring radius if markers are missing

const DEATH_TIME := 3.0
const EYE_HEIGHT := 1.9
const BOLT_COLOR := Color(1.0, 0.45, 0.08)
const RUSHER := "res://scenes/enemies/rusher.tscn"
const WEAK_POINT := "res://scenes/enemies/weak_point.tscn"
const ERUPTION := "res://scripts/lava_eruption.gd"

enum Phase { A, B, C }
enum State { IDLE, COMBAT, DYING }

signal phase_changed(phase: int)

@onready var _agent: NavigationAgent3D = $NavigationAgent3D

## Exposed for tests / telemetry.
var phase: Phase = Phase.A
var shielded: bool = false
var crystals_remaining: int = 0
var adds_spawned: int = 0
var eruptions_spawned: int = 0

var _state: State = State.IDLE
var _melee_timer: float = 0.0
var _fireball_timer: float = 0.0
var _slam_timer: float = 0.0
var _eruption_timer: float = ERUPTION_INTERVAL
var _adds_timer: float = 0.0
var _shield_vfx: MeshInstance3D
var _body_mat: StandardMaterial3D


func _init() -> void:
	max_health = TOTAL_HEALTH


func _ready() -> void:
	super._ready()
	add_to_group("boss")
	_apply_body_material()
	_build_shield_vfx()


func _physics_process(delta: float) -> void:
	if _dead or _state == State.DYING:
		return
	if _tick_stun(delta):
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta

	_melee_timer = maxf(0.0, _melee_timer - delta)
	_fireball_timer = maxf(0.0, _fireball_timer - delta)
	_slam_timer = maxf(0.0, _slam_timer - delta)

	if phase == Phase.B and adds_spawned < ADDS_TOTAL:
		_adds_timer -= delta
		if _adds_timer <= 0.0:
			_adds_timer = ADDS_BURST_INTERVAL
			_spawn_adds_burst()

	if phase == Phase.C:
		_eruption_timer -= delta
		if _eruption_timer <= 0.0:
			_eruption_timer = ERUPTION_INTERVAL
			erupt()

	if not _ensure_player():
		_halt_horizontal()
		move_and_slide()
		return

	var dist := global_position.distance_to(_player.global_position)
	match _state:
		State.IDLE:
			_halt_horizontal()
			if dist <= DETECT_RANGE:
				_state = State.COMBAT
		State.COMBAT:
			if dist <= MELEE_RANGE:
				_halt_horizontal()
				_face(_player.global_position)
			else:
				_chase()
			_try_attacks(dist)

	move_and_slide()


func _try_attacks(dist: float) -> void:
	if phase == Phase.C and _slam_timer <= 0.0 and dist <= SLAM_RADIUS:
		slam()
		return
	if dist <= MELEE_RANGE and _melee_timer <= 0.0:
		melee()
	elif dist <= FIREBALL_RANGE and _fireball_timer <= 0.0:
		fireball()


func _chase() -> void:
	_agent.target_position = _player.global_position
	var next := _agent.get_next_path_position()
	var dir := _nav_dir(next, _player.global_position)
	if dir.length() > 0.05:
		dir = dir.normalized()
		var spd := move_speed()
		velocity.x = dir.x * spd
		velocity.z = dir.z * spd
		_face(global_position + dir)
	else:
		_halt_horizontal()


## Current movement speed — 1.5x once enraged (phase C).
func move_speed() -> float:
	var spd := MOVE_SPEED * EnemyBase.speed_scale
	return spd * RAGE_SPEED_MULT if phase == Phase.C else spd


## Cooldown multiplier: phase B fires at reduced frequency, phase C is +50%
## attack speed (i.e. cooldowns divided by 1.5).
func cooldown_scale() -> float:
	match phase:
		Phase.B:
			return 1.5
		Phase.C:
			return 1.0 / RAGE_SPEED_MULT
	return 1.0


# --- attacks (public so they are unit-testable) -----------------------------

func melee() -> void:
	_melee_timer = MELEE_COOLDOWN * cooldown_scale()
	if _player and _player.has_method("take_damage"):
		_player.take_damage(MELEE_DAMAGE)


## Linear fireball. GDD §3.4 calls it homing, but every other projectile in the
## game was made straight-line on purpose (dodgeable by strafing) — see devlog.
func fireball() -> void:
	_fireball_timer = FIREBALL_COOLDOWN * cooldown_scale()
	if _player == null:
		return
	var p := load("res://scripts/enemy_projectile.gd").new() as Node3D
	p.damage = FIREBALL_DAMAGE
	p.bolt_color = BOLT_COLOR          # set before _ready builds the mesh
	var host := _host()
	host.add_child(p)
	p.setup(global_position + Vector3(0, EYE_HEIGHT, 0), _player, get_rid())


## Phase C ground slam: hard-radius AoE plus an exact 3 m knockback.
func slam() -> void:
	_slam_timer = SLAM_COOLDOWN * cooldown_scale()
	_melee_timer = MELEE_COOLDOWN * cooldown_scale()      # no double-dip
	_slam_vfx()
	if _player == null:
		return
	if global_position.distance_to(_player.global_position) > SLAM_RADIUS:
		return
	if _player.has_method("take_damage"):
		_player.take_damage(SLAM_DAMAGE)
	var away := _player.global_position - global_position
	away.y = 0.0
	if away.length() < 0.01:
		away = Vector3.FORWARD
	away = away.normalized()
	if _player.has_method("apply_push"):
		_player.apply_push(away * SLAM_KNOCKBACK)          # exactly 3 m
	if _player.has_method("apply_knockback"):
		_player.apply_knockback(Vector3(0.0, SLAM_LIFT, 0.0))   # lift only


## Phase C environmental hazard: erupt at a random arena eruption marker.
func erupt() -> void:
	var markers := get_tree().get_nodes_in_group("eruption_point")
	if markers.is_empty():
		return
	var script := load(ERUPTION)
	if script == null:
		return
	var e := script.new() as Node3D
	_host().add_child(e)
	e.global_position = (markers[randi() % markers.size()] as Node3D).global_position
	eruptions_spawned += 1


# --- damage + phases --------------------------------------------------------

## The shield gates ALL damage in phase B, which is also what makes the phase
## order unskippable: HP cannot fall toward 33% until the 4 crystals are down.
func take_damage(amount: float) -> void:
	if _dead or amount <= 0.0:
		return
	if shielded:
		return
	health = maxf(0.0, health - amount)
	if health <= 0.0:
		_die()
		return
	_check_phase()


## Float-safe "HP is at or below this fraction of max". A bare <= is a coin flip
## exactly on the boundary: 5000 * 0.33 does not land on the same float that the
## player's accumulated damage subtracts down to, so the transition could be
## missed at precisely the HP the card says it must fire at.
func at_or_below(fraction: float) -> bool:
	return health <= max_health * fraction + 0.001


func _check_phase() -> void:
	if phase == Phase.A and at_or_below(PHASE_B_AT):
		_enter_phase_b()
	elif phase == Phase.B and not shielded and at_or_below(PHASE_C_AT):
		_enter_phase_c()


func _enter_phase_b() -> void:
	phase = Phase.B
	shielded = true
	adds_spawned = 0
	_adds_timer = 0.0                  # first pair arrives immediately
	_roar_vfx()
	if _shield_vfx:
		_shield_vfx.visible = true
	_spawn_crystals()
	phase_changed.emit(Phase.B)


func _enter_phase_c() -> void:
	phase = Phase.C
	_eruption_timer = ERUPTION_INTERVAL
	_rage_vfx()
	phase_changed.emit(Phase.C)


func _spawn_crystals() -> void:
	var scene := load(WEAK_POINT)
	var markers := get_tree().get_nodes_in_group("weak_point")
	var host := _host()
	crystals_remaining = 0
	for i in WEAK_POINT_COUNT:
		var pos: Vector3
		if i < markers.size():
			pos = (markers[i] as Node3D).global_position
		else:
			# Fallback ring around the boss if the arena has no markers.
			var ang := TAU * float(i) / float(WEAK_POINT_COUNT)
			pos = global_position + Vector3(cos(ang), 0.0, sin(ang)) * WEAK_POINT_RING
		var c: Node3D
		if scene != null:
			c = scene.instantiate() as Node3D
		else:
			c = StaticBody3D.new()
			c.set_script(load("res://scripts/weak_point.gd"))
		host.add_child(c)
		c.global_position = pos
		if c.has_signal("destroyed"):
			c.destroyed.connect(_on_crystal_destroyed)
		crystals_remaining += 1


func _on_crystal_destroyed(_where: Vector3) -> void:
	crystals_remaining = maxi(0, crystals_remaining - 1)
	if crystals_remaining == 0:
		_break_shield()


func _break_shield() -> void:
	shielded = false
	if _shield_vfx:
		_shield_vfx.visible = false
	_roar_vfx()
	# Breaking the shield can immediately qualify the boss for phase C.
	_check_phase()


func _spawn_adds_burst() -> void:
	var scene := load(RUSHER)
	if scene == null:
		adds_spawned = ADDS_TOTAL
		return
	var host := _host()
	for i in ADDS_PER_BURST:
		if adds_spawned >= ADDS_TOTAL:
			return
		var r := scene.instantiate() as Node3D
		host.add_child(r)
		var ang := TAU * randf()
		r.global_position = global_position + Vector3(cos(ang) * 6.0, 1.0, sin(ang) * 6.0)
		adds_spawned += 1


# --- death ------------------------------------------------------------------

## 3 s death sequence (sink + fire burst), then the rewards. Overrides
## EnemyBase._die(), which frees the body immediately.
func _die() -> void:
	if _dead:
		return
	_dead = true
	_state = State.DYING
	_halt_horizontal()
	_death_vfx()
	var where := global_position
	await get_tree().create_timer(DEATH_TIME).timeout
	died.emit(where)
	_drop_loot(where)
	queue_free()


## GDD §3.4 reward: 1 Exotic weapon + 3 Epic armour pieces (chest/helmet/gloves).
func _drop_loot(where: Vector3) -> void:
	_drop_item(where, "Exotic", "weapon", "")
	for slot in LootDrop.ARMOR_KINDS:
		_drop_item(where, "Epic", "armor", slot)


func _drop_item(where: Vector3, rarity: String, category: String, kind: String) -> void:
	var packed := load(LOOT_SCENE_PATH)
	if packed == null:
		return
	var drop := packed.instantiate() as Node3D
	# All three must be set before the node enters the tree and rolls.
	drop.forced_rarity = rarity
	drop.category = category
	if kind != "":
		drop.forced_kind = kind
	_host().add_child(drop)
	var ang := TAU * randf()
	drop.global_position = where + Vector3(cos(ang) * 1.6, 0.4, sin(ang) * 1.6)


# --- presentation -----------------------------------------------------------

func _host() -> Node:
	var host := get_tree().current_scene
	return host if host != null else get_tree().root


func _apply_body_material() -> void:
	var mesh := get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null:
		return
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = Color(0.22, 0.08, 0.06)     # cooled magma crust
	_body_mat.emission_enabled = true
	_body_mat.emission = Color(1.0, 0.35, 0.05)
	_body_mat.emission_energy_multiplier = 1.4
	mesh.material_override = _body_mat


func _build_shield_vfx() -> void:
	_shield_vfx = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 2.4
	sphere.height = 4.8
	sphere.is_hemisphere = true
	_shield_vfx.mesh = sphere
	_shield_vfx.position = Vector3(0, 0.1, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.25, 0.55, 1.0, 0.25)
	m.emission_enabled = true
	m.emission = Color(0.35, 0.65, 1.0)
	m.emission_energy_multiplier = 1.5
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shield_vfx.material_override = m
	_shield_vfx.visible = false
	add_child(_shield_vfx)


func _roar_vfx() -> void:
	_burst(Color(1.0, 0.55, 0.15), 6.0, 0.5)


func _rage_vfx() -> void:
	_burst(Color(1.0, 0.25, 0.05), 8.0, 0.6)
	if _body_mat:
		_body_mat.emission_energy_multiplier = 3.2          # glows hotter enraged


func _slam_vfx() -> void:
	var vfx := _burst(Color(1.0, 0.4, 0.1), SLAM_RADIUS * 2.0, 0.4)
	if vfx:
		vfx.position.y = 0.3


func _death_vfx() -> void:
	_burst(Color(1.0, 0.6, 0.2), 10.0, DEATH_TIME)
	# Sink into the arena as it dies.
	var tw := create_tween()
	tw.tween_property(self, "position:y", position.y - 2.0, DEATH_TIME)


func _burst(color: Color, size: float, time: float) -> MeshInstance3D:
	var host := _host()
	var vfx := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	vfx.mesh = sphere
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, 0.7)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 4.0
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	vfx.material_override = m
	host.add_child(vfx)
	vfx.global_position = global_position + Vector3(0, 1.5, 0)
	vfx.scale = Vector3.ONE * 0.3
	var tw := vfx.create_tween()
	tw.tween_property(vfx, "scale", Vector3.ONE * size, time)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, time)
	tw.tween_callback(vfx.queue_free)
	return vfx

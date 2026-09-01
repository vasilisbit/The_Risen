class_name Phantom
extends EnemyBase

## Mars mini-boss: Teleporting Phantom (T-0019). 1800 HP. Holds position and
## fires a purple bolt (150 damage, 1 s cooldown), blinking to a random chamber
## spawn marker every 20 s with a burst VFX at both ends. Summons 3 Rusher adds
## once at 50% HP and drops 2 Rare/Epic items on death. Values per GDD §3.3.

const DETECT_RANGE := 30.0
const SHOOT_COOLDOWN := 1.0
const PROJECTILE_DAMAGE := 100.0   # normal-mode balance: was 150
const TELEPORT_INTERVAL := 20.0
const ADDS_COUNT := 3
const EYE_HEIGHT := 1.6
## Teal soulfire to match the custom Hive-wraith model (T-0044); was purple.
const BOLT_COLOR := Color(0.20, 0.95, 0.90)
const SHELL_COLOR := Color(0.25, 0.90, 0.85)  # teal arc-shield (Earth boss is blue)
const MAX_SHIELD := 600.0                     # gate shield, mirrors the Brute's 500
const RUSHER := "res://scenes/enemies/rusher.tscn"
## It now WALKS toward the player when out past this range (in addition to
## teleporting), using the rig's walk clip; inside it, it holds and casts.
const WALK_SPEED := 3.2
const PREFERRED_RANGE := 14.0

enum State { IDLE, ACTIVE }

@onready var _agent: NavigationAgent3D = $NavigationAgent3D

## Exposed for tests / telemetry.
var teleports_done: int = 0

## Purple energy shield: gates all HP damage until broken, exactly like the Earth
## Shielded Brute's arc shield (rendered as the same silhouette shell, in purple).
var shield: float = MAX_SHIELD
var _state: State = State.IDLE
var _shoot_timer: float = 0.0
var _teleport_timer: float = TELEPORT_INTERVAL
var _adds_spawned: bool = false


func _init() -> void:
	max_health = 1800.0
	flux_value = 75


func _enemy_voice() -> String:
	return "boss_phantom"


## The custom Hive-wraith model (T-0044) ships its own teal PBR, so DON'T tint it -
## the old purple override is what put the "purple around him". Keep its materials.
func external_model_tint() -> Material:
	return null


func _ready() -> void:
	super._ready()
	add_to_group("boss")


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if _tick_status(delta):
		return
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
				_state = State.ACTIVE
		State.ACTIVE:
			_face(_player.global_position)
			# Walk in when far (the walk clip plays via EnemyBase), hold and cast
			# when close; teleporting still repositions it every TELEPORT_INTERVAL.
			if dist > PREFERRED_RANGE:
				var dir := _nav_dir(_agent, _player.global_position, delta)
				if dir.length() > 0.05:
					dir = dir.normalized()
					var spd := WALK_SPEED * EnemyBase.speed_scale
					velocity.x = dir.x * spd
					velocity.z = dir.z * spd
					_tick_jump(dir, delta)
				else:
					_halt_horizontal()
			else:
				_halt_horizontal()
			_shoot_timer -= delta
			if _shoot_timer <= 0.0:
				shoot()
			_teleport_timer -= delta
			if _teleport_timer <= 0.0:
				teleport()

	move_and_slide()


## Fire a purple bolt at the player. Public so it is unit-testable.
func shoot() -> void:
	_shoot_timer = SHOOT_COOLDOWN
	if _player == null:
		return
	var p := load("res://scripts/enemy_projectile.gd").new() as Node3D
	p.damage = PROJECTILE_DAMAGE
	p.bolt_color = BOLT_COLOR          # set before _ready builds the mesh
	p.source_name = "Phantom"
	var host := get_tree().current_scene
	if host == null:
		host = get_tree().root
	host.add_child(p)
	p.setup(global_position + Vector3(0, EYE_HEIGHT, 0), _player, get_rid())


## Blink to a chamber spawn marker whose spot is CLEAR of geometry, so the boss can
## never materialise inside a pillar / crate / wall (a plain random pick could, and
## did). Tries markers in random order and takes the first clear one. Unit-testable.
func teleport() -> void:
	_teleport_timer = TELEPORT_INTERVAL
	var markers := get_tree().get_nodes_in_group("spawn_point")
	if markers.is_empty():
		return
	markers.shuffle()
	var dest: Vector3 = (markers[0] as Node3D).global_position + Vector3(0, 1.0, 0)
	for mk in markers:
		var cand: Vector3 = (mk as Node3D).global_position + Vector3(0, 1.0, 0)
		if _spot_clear(cand):
			dest = cand
			break
	_blink_vfx(global_position + Vector3(0, 1.0, 0))     # leaving
	global_position = dest
	velocity = Vector3.ZERO
	_blink_vfx(dest)                                     # arriving
	teleports_done += 1


## True when a body-sized sphere at `p` doesn't overlap world or enemy geometry, so
## the boss can appear there without clipping into cover or a wall.
func _spot_clear(p: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 1.1
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), p + Vector3(0, 0.2, 0))
	q.collision_mask = WORLD_LAYER | ENEMY_LAYER
	q.exclude = [get_rid()]
	return space.intersect_shape(q, 1).is_empty()


## Purple gate shield first (invulnerable until it breaks, like the Earth boss),
## then straight HP with a one-off adds summon at 50%.
func take_damage(amount: float) -> void:
	if _dead or amount <= 0.0:
		return
	amount = absorb_shield(amount)
	if amount <= 0.0:
		return
	if shield > 0.0:
		shield = maxf(0.0, shield - amount)
		return
	health = maxf(0.0, health - amount)
	if health <= 0.0:
		_die()
	elif not _adds_spawned and health <= max_health * 0.5:
		_spawn_adds()


# --- nameplate: a purple gate shield drives the shared arc-shield shell --------
# nameplate_tier() already returns "boss" (Phantom is in the "boss" group), so it
# gets the gold boss plate; these give it the Brute's silhouette shell in purple.

func nameplate_shield() -> float:
	return shield + elemental_shield


func nameplate_shield_max() -> float:
	return MAX_SHIELD + max_elemental_shield


func nameplate_shield_color() -> Color:
	return SHELL_COLOR


func _spawn_adds() -> void:
	_adds_spawned = true
	var scene := load(RUSHER)
	if scene == null:
		return
	var host := get_tree().current_scene
	if host == null:
		host = get_tree().root
	for i in ADDS_COUNT:
		var r := scene.instantiate() as Node3D
		host.add_child(r)
		var ang := TAU * float(i) / float(ADDS_COUNT)
		r.global_position = global_position + Vector3(cos(ang) * 2.5, 1.0, sin(ang) * 2.5)


## Drops 2 items, each Rare or Epic (GDD §3.3 reward).
func _drop_loot(where: Vector3) -> void:
	for i in 2:
		loot_rarity_override = "Epic" if randf() < 0.5 else "Rare"
		super._drop_loot(where)


func _blink_vfx(at: Vector3) -> void:
	var host := get_tree().current_scene
	if host == null:
		host = get_tree().root
	var vfx := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	vfx.mesh = sphere
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.25, 0.90, 0.85, 0.75)
	m.emission_enabled = true
	m.emission = Color(0.25, 0.90, 0.85)
	m.emission_energy_multiplier = 3.5
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	vfx.material_override = m
	host.add_child(vfx)
	vfx.global_position = at
	vfx.scale = Vector3.ONE * 0.3
	var tw := vfx.create_tween()
	tw.tween_property(vfx, "scale", Vector3.ONE * 3.0, 0.35)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, 0.35)
	tw.tween_callback(vfx.queue_free)

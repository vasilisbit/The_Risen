class_name Phantom
extends EnemyBase

## Mars mini-boss: Teleporting Phantom (T-0019). 1800 HP. Holds position and
## fires a purple bolt (150 damage, 1 s cooldown), blinking to a random chamber
## spawn marker every 20 s with a burst VFX at both ends. Summons 3 Rusher adds
## once at 50% HP and drops 2 Rare/Epic items on death. Values per GDD §3.3.

const DETECT_RANGE := 30.0
const SHOOT_COOLDOWN := 1.0
const PROJECTILE_DAMAGE := 150.0
const TELEPORT_INTERVAL := 20.0
const ADDS_COUNT := 3
const EYE_HEIGHT := 1.6
const BOLT_COLOR := Color(0.70, 0.25, 1.0)
const SHELL_COLOR := Color(0.70, 0.30, 1.0)   # purple arc-shield (Earth boss is blue)
const MAX_SHIELD := 600.0                     # gate shield, mirrors the Brute's 500
const RUSHER := "res://scenes/enemies/rusher.tscn"

enum State { IDLE, ACTIVE }

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


## The ghoul FBX ships without textures; paint it a spectral, emissive purple so
## the Phantom reads as its GDD description.
func external_model_tint() -> Material:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.12, 0.45)
	mat.metallic = 0.1
	mat.roughness = 0.5
	mat.emission_enabled = true
	mat.emission = Color(0.55, 0.25, 0.95)
	mat.emission_energy_multiplier = 0.8
	return mat


func _ready() -> void:
	super._ready()
	add_to_group("boss")
	_apply_phantom_material()


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if _tick_status(delta):
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_halt_horizontal()          # it teleports rather than walks
	move_and_slide()

	if not _ensure_player():
		return
	var dist := global_position.distance_to(_player.global_position)
	match _state:
		State.IDLE:
			if dist <= DETECT_RANGE:
				_state = State.ACTIVE
		State.ACTIVE:
			_face(_player.global_position)
			_shoot_timer -= delta
			if _shoot_timer <= 0.0:
				shoot()
			_teleport_timer -= delta
			if _teleport_timer <= 0.0:
				teleport()


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


## Blink to a random chamber spawn marker (markers sit on room floors, so this
## can't drop the boss inside geometry). Public so it is unit-testable.
func teleport() -> void:
	_teleport_timer = TELEPORT_INTERVAL
	var markers := get_tree().get_nodes_in_group("spawn_point")
	if markers.is_empty():
		return
	var dest: Vector3 = (markers[randi() % markers.size()] as Node3D).global_position + Vector3(0, 1.0, 0)
	_blink_vfx(global_position + Vector3(0, 1.0, 0))     # leaving
	global_position = dest
	velocity = Vector3.ZERO
	_blink_vfx(dest)                                     # arriving
	teleports_done += 1


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


func _apply_phantom_material() -> void:
	var mesh := get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null:
		return
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.45, 0.15, 0.75, 0.85)
	m.emission_enabled = true
	m.emission = Color(0.70, 0.25, 1.0)
	m.emission_energy_multiplier = 2.2
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = m


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
	m.albedo_color = Color(0.70, 0.30, 1.0, 0.75)
	m.emission_enabled = true
	m.emission = Color(0.70, 0.30, 1.0)
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

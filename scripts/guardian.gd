class_name Guardian
extends CharacterBody3D

## Player character (The Risen).
## Movement + shield tuning are ported verbatim from the archived UE prototype
## and match TDD v2.0 §4.1 / GDD §2.1.

# --- Movement tuning (TDD §4.1) ---
const WALK_SPEED := 6.0          # m/s
const SPRINT_SPEED := 9.0        # m/s
const JUMP_HEIGHT := 2.0         # m (peak); jump velocity derived from gravity
                                 # Tuned down from TDD §4.1's 5 m after playtest
                                 # feedback that the jump felt far too floaty.

# --- Camera / look ---
const MOUSE_SENSITIVITY := 0.003
const PITCH_MIN := -1.2          # rad, look down limit
const PITCH_MAX := 0.6           # rad, look up limit

# --- Health / shield tuning (TDD §4.1) ---
const MAX_HEALTH := 100.0
const MAX_SHIELD := 100.0
const SHIELD_RECHARGE_DELAY := 3.0   # s of no damage before recharge starts
const SHIELD_RECHARGE_RATE := 25.0   # shield HP per second
const DEBUG_DAMAGE_AMOUNT := 25.0    # applied by the "debug_damage" action

## Class passives (T-0022) and super abilities (T-0023), GDD §2.4.
## Grenades and melee are T-0024 / T-0025.
const CLASS_STATS := {
	"Assault": {"damage_multiplier": 1.1, "max_health_bonus": 0.0, "damage_reduction": 0.0,
		"super": "res://scripts/storm_barrage.gd",
		"grenade": "res://scripts/frag_grenade.gd",
		"melee": "res://scripts/energy_blade.gd"},
	"Support": {"damage_multiplier": 1.0, "max_health_bonus": 50.0, "damage_reduction": 0.0,
		"super": "res://scripts/guardian_dome.gd",
		"grenade": "res://scripts/healing_grenade.gd",
		"melee": "res://scripts/emp_punch.gd"},
	"Tank":    {"damage_multiplier": 1.0, "max_health_bonus": 0.0, "damage_reduction": 0.2,
		"super": "res://scripts/juggernaut_charge.gd",
		"grenade": "res://scripts/flash_grenade.gd",
		"melee": "res://scripts/ground_slam.gd"},
}

signal health_changed(current: float, maximum: float)
signal shield_changed(current: float, maximum: float)
signal shield_depleted
signal died

@onready var _spring_arm: SpringArm3D = $SpringArm3D

var health: float = MAX_HEALTH
var shield: float = MAX_SHIELD

var is_dead: bool = false

const KNOCKBACK_DECAY := 22.0    # how fast a horizontal knockback push fades
const PUSH_TIME := 0.4           # s a wind gust / boss slam takes to shove you
const STEP_DISTANCE := 2.2       # m of travel between footstep sounds

## Multiplies gravity — a low-gravity Area3D (Mars) sets this to 0.4.
var gravity_scale: float = 1.0
## Fraction of incoming damage ignored (Mars buff: -15% -> 0.15).
var damage_reduction: float = 0.0
## Extra max health from buffs (+50 HP option).
var max_health_bonus: float = 0.0
## Fall-respawn point (Mars platforming); updated by checkpoint triggers.
var checkpoint: Vector3
## Ignores all incoming damage — Juggernaut Charge (T-0023) sets this.
var invulnerable: bool = false
## Scales melee damage — Juggernaut Charge sets 3.0. Read by T-0025's melee.
var melee_multiplier: float = 1.0
## This class's ability kit. Both rebuilt whenever the class changes.
var super_ability: Ability          # T-0023, Q
var grenade_ability: Ability        # T-0024, G
var melee_ability: Ability          # T-0025, V

var _air_speed: float = WALK_SPEED     # horizontal speed locked in at take-off
var _knockback: Vector3 = Vector3.ZERO
var _push_velocity: Vector3 = Vector3.ZERO
var _push_time_left: float = 0.0
var _step_accum: float = 0.0
var _time_since_damage: float = SHIELD_RECHARGE_DELAY
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _spawn_point: Vector3
var _death_screen: CanvasLayer
var _ability_hud: Control
var _weapon_hud: Control

const RESPAWN_DELAY := 2.5    # s before respawning at the spawn point
const FALL_PENALTY := 10.0    # HP lost on a fall respawn (GDD §3.3)


func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Stop the SpringArm3D from colliding with the player's own body.
	_spring_arm.add_excluded_object(get_rid())
	_spawn_point = global_position
	checkpoint = global_position
	_build_death_screen()
	_build_ability_hud()       # before apply_class_stats, which wires the super in
	apply_class_stats()
	health = max_hp()          # spawn at full, including the Support bonus
	health_changed.emit(health, max_hp())
	shield_changed.emit(shield, MAX_SHIELD)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		rotate_y(-motion.relative.x * MOUSE_SENSITIVITY)
		_spring_arm.rotation.x = clampf(
			_spring_arm.rotation.x - motion.relative.y * MOUSE_SENSITIVITY,
			PITCH_MIN, PITCH_MAX)
	elif event.is_action_pressed("ui_cancel"):
		# Toggle mouse capture so the run can be inspected / closed.
		Input.mouse_mode = (Input.MOUSE_MODE_VISIBLE
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED)
	elif event.is_action_pressed("debug_damage"):
		take_damage(DEBUG_DAMAGE_AMOUNT)
	elif event.is_action_pressed("super"):
		# Ability.activate() no-ops and returns false while on cooldown, so
		# "only fires when ready" holds for every class and slot in one place.
		if not is_dead and super_ability != null:
			super_ability.activate()
	elif event.is_action_pressed("grenade"):
		if not is_dead and grenade_ability != null:
			grenade_ability.activate()
	elif event.is_action_pressed("melee"):
		if not is_dead and melee_ability != null:
			melee_ability.activate()


func _physics_process(delta: float) -> void:
	if is_dead:
		# Keep falling but ignore input while dead.
		if not is_on_floor():
			velocity.y -= _gravity * gravity_scale * delta
		velocity.x = move_toward(velocity.x, 0.0, WALK_SPEED)
		velocity.z = move_toward(velocity.z, 0.0, WALK_SPEED)
		move_and_slide()
		return

	if not is_on_floor():
		velocity.y -= _gravity * gravity_scale * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		# v = sqrt(2 * g * h) reaches exactly JUMP_HEIGHT at apex.
		velocity.y = sqrt(2.0 * _gravity * JUMP_HEIGHT)

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	# Sprint only counts while grounded: the horizontal speed is locked in at
	# take-off, so tapping sprint mid-air can't extend a jump. Direction is
	# still steerable in the air, just at the speed you launched with.
	var ground_speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	if is_on_floor():
		_air_speed = ground_speed
	var speed := ground_speed if is_on_floor() else _air_speed

	if direction != Vector3.ZERO:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	# Add any active knockback on top of movement, then let it decay.
	velocity.x += _knockback.x
	velocity.z += _knockback.z
	_knockback = _knockback.move_toward(Vector3.ZERO, KNOCKBACK_DECAY * delta)

	move_and_slide()
	_tick_footsteps(delta)

	# Pushes (Venus wind gusts, boss slams) are a displacement budget, applied
	# AFTER move_and_slide as real motion rather than added to velocity. Going
	# through velocity would let the per-frame friction above eat into it, and
	# any push faster than the walk speed would instead compound frame over
	# frame. move_and_collide still resolves walls, and spending exactly
	# PUSH_TIME seconds of _push_velocity travels exactly the distance asked for.
	if _push_time_left > 0.0:
		var push_dt: float = minf(delta, _push_time_left)
		move_and_collide(_push_velocity * push_dt)
		_push_time_left -= push_dt
	_update_shield(delta)


func _update_shield(delta: float) -> void:
	_time_since_damage += delta
	if shield < MAX_SHIELD and _time_since_damage >= SHIELD_RECHARGE_DELAY:
		shield = minf(MAX_SHIELD, shield + SHIELD_RECHARGE_RATE * delta)
		shield_changed.emit(shield, MAX_SHIELD)


## Footsteps are driven by distance covered, not a fixed timer, so sprinting
## naturally steps faster and standing still is silent (T-0034).
func _tick_footsteps(delta: float) -> void:
	if is_dead or not is_on_floor():
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed < 0.5:
		return
	_step_accum += speed * delta
	if _step_accum >= STEP_DISTANCE:
		_step_accum = 0.0
		_sfx("footstep")


## Fire a UI/self sound. No-ops without the autoload so the player stays
## testable in isolation.
func _sfx(id: String) -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.play_sfx(id, global_position)


## Effective max health (base + class/buff bonus).
func max_hp() -> float:
	return MAX_HEALTH + max_health_bonus


## Apply the saved class's passive (T-0022, GDD §2.4). Called at spawn.
##   Assault +10% weapon damage / Support +50 max HP / Tank -20% damage taken.
## Public so it can be re-applied (and tested) after a class change without
## reloading the scene. Idempotent: each passive is SET, never accumulated.
func apply_class_stats() -> void:
	var sm := get_node_or_null("/root/SaveManager")
	var chosen: String = String(sm.data.get("selected_class", "Assault")) if sm else "Assault"
	var stats: Dictionary = CLASS_STATS.get(chosen, CLASS_STATS["Assault"])

	max_health_bonus = float(stats["max_health_bonus"])
	damage_reduction = float(stats["damage_reduction"])
	health = minf(health, max_hp())
	if health <= 0.0:
		health = max_hp()
	_apply_class_weapon_bonus(float(stats["damage_multiplier"]))
	_build_kit(stats)
	health_changed.emit(health, max_hp())


## Swap in this class's ability kit — super (T-0023) and grenade (T-0024).
## Both are replaced outright, so changing class mid-session can't leave the
## previous class's abilities attached.
func _build_kit(stats: Dictionary) -> void:
	if super_ability != null and is_instance_valid(super_ability):
		super_ability.queue_free()
	if grenade_ability != null and is_instance_valid(grenade_ability):
		grenade_ability.queue_free()
	if melee_ability != null and is_instance_valid(melee_ability):
		melee_ability.queue_free()
	super_ability = _make_ability(String(stats.get("super", "")))
	melee_ability = _make_ability(String(stats.get("melee", "")))

	# All three classes throw with the same ability; only the payload differs,
	# so the grenade script is data rather than another Ability subclass.
	var grenade_path := String(stats.get("grenade", ""))
	if grenade_path != "":
		var g := GrenadeAbility.new()
		g.grenade_script = grenade_path
		g.refresh_identity()          # takes its name/colour from the payload
		g.player = self
		add_child(g)
		grenade_ability = g
	else:
		grenade_ability = null

	if _ability_hud:
		_ability_hud.super_ability = super_ability
		_ability_hud.grenade_ability = grenade_ability
		_ability_hud.melee_ability = melee_ability


func _make_ability(script_path: String) -> Ability:
	if script_path == "":
		return null
	var script := load(script_path)
	if script == null:
		return null
	var ability := script.new() as Ability
	ability.player = self
	add_child(ability)
	return ability


func _apply_class_weapon_bonus(mult: float) -> void:
	var wm := get_node_or_null("WeaponManager")
	if wm == null or not ("_weapons" in wm):
		return
	for w in wm._weapons:
		w.class_multiplier = mult


## Apply incoming damage: shield absorbs first, overflow hits health.
## Resets the shield recharge delay.
func take_damage(amount: float) -> void:
	if amount <= 0.0:
		return
	# Juggernaut Charge (T-0023) is total immunity — checked before armour and
	# shield, so the Tank passive's -20% never even comes into it.
	if invulnerable:
		return
	# Guardian Dome soaks damage before anything else, while you stand in it.
	if super_ability is GuardianDome:
		amount = (super_ability as GuardianDome).absorb(amount, global_position)
		if amount <= 0.0:
			return
	amount *= (1.0 - clampf(damage_reduction, 0.0, 0.9))
	_time_since_damage = 0.0
	_sfx("player_hit")

	if shield > 0.0:
		var absorbed := minf(shield, amount)
		shield -= absorbed
		amount -= absorbed
		shield_changed.emit(shield, MAX_SHIELD)
		if shield <= 0.0:
			shield_depleted.emit()

	if amount > 0.0:
		health = maxf(0.0, health - amount)
		health_changed.emit(health, max_hp())
		if health <= 0.0 and not is_dead:
			_on_death()


## Push the player (used by the Shielded Brute's ground slam knockback).
## Vertical component is an instant impulse; horizontal decays over ~0.3 s.
func apply_knockback(impulse: Vector3) -> void:
	velocity.y += impulse.y
	_knockback = Vector3(impulse.x, 0.0, impulse.z)


## Shove the player a precise distance (Venus wind gusts T-0020, Ember Tyrant
## slam T-0021). Unlike apply_knockback() the total travel equals
## offset.length() exactly, so specs like "push the player back 2 m" or
## "knockback 3 m" are literally what happens, at any frame rate and whether
## the player is grounded, airborne or running. Walls still absorb it.
func apply_push(offset: Vector3) -> void:
	if is_dead or offset == Vector3.ZERO:
		return
	_push_velocity = offset / PUSH_TIME
	_push_time_left = PUSH_TIME


## Move the respawn point. Used by the level checkpoint triggers (Mars
## platforms, Venus climb) and by the mission drivers as objectives advance, so
## dying never sends the player back to the very start of a long level.
func set_checkpoint(pos: Vector3) -> void:
	checkpoint = pos


## Checkpoint wherever the player is standing right now, dropped onto the floor
## beneath them so a checkpoint taken mid-jump doesn't respawn them in mid-air.
## Callers use this instead of an authored per-objective point because a
## hand-placed point can sit ahead of the player and teleport them forward.
func checkpoint_here() -> void:
	if is_on_floor():
		checkpoint = global_position
		return
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0, 0.5, 0), global_position + Vector3(0, -8.0, 0), 1)
	var skip: Array[RID] = [get_rid()]
	query.exclude = skip
	var hit := space.intersect_ray(query)
	checkpoint = (hit["position"] as Vector3) + Vector3(0, 0.2, 0) if not hit.is_empty() else global_position


## Respawn at the last checkpoint after a fall (fall damage disabled — a flat
## -10 HP penalty instead, per GDD §3.3). Does not kill the player.
func fall_respawn() -> void:
	if is_dead:
		return
	global_position = checkpoint
	velocity = Vector3.ZERO
	_knockback = Vector3.ZERO
	health = maxf(1.0, health - FALL_PENALTY)
	health_changed.emit(health, max_hp())


## Environmental hazard hit (Venus lava, T-0020): lose HP, then return to the
## last checkpoint. The damage goes straight to health — it deliberately
## bypasses the shield and armour reduction, because GDD §3.4 specifies lava as
## a flat "instant -50% HP" and a recharging shield would otherwise make the
## first two dunks free. Non-lethal (floors at 1 HP) like fall_respawn(), so a
## platforming mistake costs progress and health, never the whole run.
func hazard_respawn(damage: float) -> void:
	if is_dead:
		return
	# Juggernaut Charge negates the burn, but you still get pulled out of the
	# lava — standing in it unharmed for 5 s would be worse than the hazard.
	if not invulnerable:
		health = maxf(1.0, health - damage)
		_time_since_damage = 0.0
		health_changed.emit(health, max_hp())
	global_position = checkpoint
	velocity = Vector3.ZERO
	_knockback = Vector3.ZERO
	_push_time_left = 0.0


func _on_death() -> void:
	is_dead = true
	died.emit()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if has_node("WeaponManager"):
		$WeaponManager.set_process(false)
	if _death_screen:
		_death_screen.visible = true
	get_tree().create_timer(RESPAWN_DELAY).timeout.connect(_respawn)


## Respawn after death at the last checkpoint, NOT at the level spawn point —
## on Venus that would be a 200 m climb away. `checkpoint` starts at the spawn
## point, so a level with no checkpoints behaves exactly as it did before.
func _respawn() -> void:
	global_position = checkpoint
	velocity = Vector3.ZERO
	_knockback = Vector3.ZERO
	_push_time_left = 0.0
	health = max_hp()
	shield = MAX_SHIELD
	_time_since_damage = SHIELD_RECHARGE_DELAY
	is_dead = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if has_node("WeaponManager"):
		$WeaponManager.set_process(true)
	if _death_screen:
		_death_screen.visible = false
	health_changed.emit(health, max_hp())
	shield_changed.emit(shield, MAX_SHIELD)


## Destiny-style HUD: the ability cluster bottom-left (super diamond + grenade
## and melee tiles) and the weapon panel bottom-right. One cluster owns all
## three ability slots so they can share a layout — the earlier design was a
## separate node per ability and couldn't.
func _build_ability_hud() -> void:
	var layer := get_node_or_null("DebugHUD")
	if layer == null:
		return
	_ability_hud = Control.new()
	_ability_hud.name = "AbilityHUD"
	_ability_hud.set_script(load("res://scripts/ability_hud.gd"))
	layer.add_child(_ability_hud)

	_weapon_hud = Control.new()
	_weapon_hud.name = "WeaponHUD"
	_weapon_hud.set_script(load("res://scripts/weapon_hud.gd"))
	_weapon_hud.weapon_manager = get_node_or_null("WeaponManager")
	layer.add_child(_weapon_hud)


func _build_death_screen() -> void:
	_death_screen = CanvasLayer.new()
	_death_screen.layer = 10
	_death_screen.visible = false
	add_child(_death_screen)
	var tint := ColorRect.new()
	tint.color = Color(0.35, 0.0, 0.0, 0.55)
	tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_screen.add_child(tint)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_screen.add_child(center)
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)
	var title := Label.new()
	title.text = "YOU DIED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	vbox.add_child(title)
	var sub := Label.new()
	sub.text = "Respawning..."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 24)
	vbox.add_child(sub)

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

signal health_changed(current: float, maximum: float)
signal shield_changed(current: float, maximum: float)
signal shield_depleted
signal died

@onready var _spring_arm: SpringArm3D = $SpringArm3D

var health: float = MAX_HEALTH
var shield: float = MAX_SHIELD

var is_dead: bool = false

const KNOCKBACK_DECAY := 22.0    # how fast a horizontal knockback push fades
const WIND_PUSH_TIME := 0.4      # s a wind gust takes to shove the player (Venus)

## Multiplies gravity — a low-gravity Area3D (Mars) sets this to 0.4.
var gravity_scale: float = 1.0
## Fraction of incoming damage ignored (Mars buff: -15% -> 0.15).
var damage_reduction: float = 0.0
## Extra max health from buffs (+50 HP option).
var max_health_bonus: float = 0.0
## Fall-respawn point (Mars platforming); updated by checkpoint triggers.
var checkpoint: Vector3

var _air_speed: float = WALK_SPEED     # horizontal speed locked in at take-off
var _knockback: Vector3 = Vector3.ZERO
var _wind_velocity: Vector3 = Vector3.ZERO
var _wind_time_left: float = 0.0
var _time_since_damage: float = SHIELD_RECHARGE_DELAY
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _spawn_point: Vector3
var _death_screen: CanvasLayer

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
	# TODO(T-0004): apply class stat modifiers from SaveManager at spawn.
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

	# Wind gusts (Venus) are a displacement budget rather than a decaying
	# impulse: spending exactly WIND_PUSH_TIME seconds of _wind_velocity moves
	# the player exactly the requested distance, whatever the frame rate.
	if _wind_time_left > 0.0 and delta > 0.0:
		var wind_dt: float = minf(delta, _wind_time_left)
		velocity += _wind_velocity * (wind_dt / delta)
		_wind_time_left -= wind_dt

	move_and_slide()
	_update_shield(delta)


func _update_shield(delta: float) -> void:
	_time_since_damage += delta
	if shield < MAX_SHIELD and _time_since_damage >= SHIELD_RECHARGE_DELAY:
		shield = minf(MAX_SHIELD, shield + SHIELD_RECHARGE_RATE * delta)
		shield_changed.emit(shield, MAX_SHIELD)


## Effective max health (base + buff bonus).
func max_hp() -> float:
	return MAX_HEALTH + max_health_bonus


## Apply incoming damage: shield absorbs first, overflow hits health.
## Resets the shield recharge delay.
func take_damage(amount: float) -> void:
	if amount <= 0.0:
		return
	amount *= (1.0 - clampf(damage_reduction, 0.0, 0.9))
	_time_since_damage = 0.0

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


## Shove the player a precise distance (Venus wind gusts, T-0020). Unlike
## apply_knockback() the total travel equals offset.length() exactly, so the
## design spec "gusts push the player back 2 m" is literally what happens.
## Obstacles still absorb it — move_and_slide() resolves the collision.
func apply_wind_push(offset: Vector3) -> void:
	if is_dead or offset == Vector3.ZERO:
		return
	_wind_velocity = offset / WIND_PUSH_TIME
	_wind_time_left = WIND_PUSH_TIME


## Set the fall-respawn point (Mars checkpoint triggers).
func set_checkpoint(pos: Vector3) -> void:
	checkpoint = pos


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
	health = maxf(1.0, health - damage)
	_time_since_damage = 0.0
	health_changed.emit(health, max_hp())
	global_position = checkpoint
	velocity = Vector3.ZERO
	_knockback = Vector3.ZERO
	_wind_time_left = 0.0


func _on_death() -> void:
	is_dead = true
	died.emit()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if has_node("WeaponManager"):
		$WeaponManager.set_process(false)
	if _death_screen:
		_death_screen.visible = true
	get_tree().create_timer(RESPAWN_DELAY).timeout.connect(_respawn)


func _respawn() -> void:
	global_position = _spawn_point
	velocity = Vector3.ZERO
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

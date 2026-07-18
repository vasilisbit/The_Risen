class_name Guardian
extends CharacterBody3D

## Player character (The Risen).
## Movement + shield tuning are ported verbatim from the archived UE prototype
## and match TDD v2.0 §4.1 / GDD §2.1.

# --- Movement tuning (TDD §4.1) ---
const WALK_SPEED := 6.0          # m/s
const SPRINT_SPEED := 9.0        # m/s
const JUMP_HEIGHT := 5.0         # m (peak); jump velocity derived from gravity

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

var _time_since_damage: float = SHIELD_RECHARGE_DELAY
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Stop the SpringArm3D from colliding with the player's own body.
	_spring_arm.add_excluded_object(get_rid())
	# TODO(T-0004): apply class stat modifiers from SaveManager at spawn.
	health_changed.emit(health, MAX_HEALTH)
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
	if not is_on_floor():
		velocity.y -= _gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		# v = sqrt(2 * g * h) reaches exactly JUMP_HEIGHT at apex.
		velocity.y = sqrt(2.0 * _gravity * JUMP_HEIGHT)

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED

	if direction != Vector3.ZERO:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	move_and_slide()
	_update_shield(delta)


func _update_shield(delta: float) -> void:
	_time_since_damage += delta
	if shield < MAX_SHIELD and _time_since_damage >= SHIELD_RECHARGE_DELAY:
		shield = minf(MAX_SHIELD, shield + SHIELD_RECHARGE_RATE * delta)
		shield_changed.emit(shield, MAX_SHIELD)


## Apply incoming damage: shield absorbs first, overflow hits health.
## Resets the shield recharge delay.
func take_damage(amount: float) -> void:
	if amount <= 0.0:
		return
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
		health_changed.emit(health, MAX_HEALTH)
		if health <= 0.0:
			died.emit()

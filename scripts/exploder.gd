class_name Exploder
extends EnemyBase

## Exploder enemy (T-0009). Suicide bomber on the same zero-dep enum machine.
## Detects the player at 8 m, sprints at 10 m/s, and detonates on contact for
## 200 damage in a hard 4 m radius (also detonates if killed first). HP 50.
## Continuously pulses a red emissive material and beeps with a pitch/tempo that
## rises as it closes on the player.

const SPRINT_SPEED := 5.5         # m/s (below the player's 6 m/s walk)
const DETECT_RANGE := 8.0
const CONTACT_RANGE := 1.6        # centre distance that triggers detonation
const EXPLOSION_DAMAGE := 200.0
const EXPLOSION_RADIUS := 4.0     # hard cutoff (5 m away takes 0)
const BASE_EMISSION := 0.6
const PULSE_AMPLITUDE := 2.6
const PULSE_SPEED := 9.0

enum State { IDLE, CHASE }

@onready var _agent: NavigationAgent3D = $NavigationAgent3D
@onready var _mesh: MeshInstance3D = $Mesh

var _state: State = State.IDLE
var _mat: StandardMaterial3D
var _beep: AudioStreamPlayer3D
var _pulse_t: float = 0.0
var _beep_accum: float = 0.0


func _init() -> void:
	max_health = 50.0


func _ready() -> void:
	super._ready()
	_mat = StandardMaterial3D.new()          # unique per instance so it can pulse
	_mat.albedo_color = Color(0.65, 0.08, 0.08)
	_mat.emission_enabled = true
	_mat.emission = Color(1.0, 0.1, 0.05)
	_mat.emission_energy_multiplier = BASE_EMISSION
	_mesh.material_override = _mat

	_beep = AudioStreamPlayer3D.new()
	_beep.stream = _make_beep(660.0, 0.06)
	add_child(_beep)


func _physics_process(delta: float) -> void:
	_pulse(delta)
	if _dead:
		return
	if _tick_stun(delta):
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
				_state = State.CHASE
		State.CHASE:
			if dist <= CONTACT_RANGE:
				detonate()
				return
			_chase()
			_beep_step(delta, dist)

	move_and_slide()


func _chase() -> void:
	_agent.target_position = _player.global_position
	var next := _agent.get_next_path_position()
	var dir := _nav_dir(next, _player.global_position)
	if dir.length() > 0.05:
		dir = dir.normalized()
		var spd := SPRINT_SPEED * EnemyBase.speed_scale
		velocity.x = dir.x * spd
		velocity.z = dir.z * spd
		_face(global_position + dir)
	else:
		_halt_horizontal()


func _pulse(delta: float) -> void:
	_pulse_t += delta
	_mat.emission_energy_multiplier = BASE_EMISSION + PULSE_AMPLITUDE * (0.5 + 0.5 * sin(_pulse_t * PULSE_SPEED))


## Proximity 0..1 (1 = at the player, 0 = at/over detection range).
func _proximity(dist: float) -> float:
	return clampf(1.0 - dist / DETECT_RANGE, 0.0, 1.0)


func _beep_params(dist: float) -> Vector2:
	var p := _proximity(dist)
	# x = interval between beeps (s), y = pitch scale.
	return Vector2(lerpf(0.55, 0.08, p), lerpf(1.0, 2.6, p))


func _beep_step(delta: float, dist: float) -> void:
	var params := _beep_params(dist)
	_beep_accum += delta
	if _beep_accum >= params.x:
		_beep_accum = 0.0
		_beep.pitch_scale = params.y
		_beep.play()


## Detonate: hard-radius AoE, VFX, loot, self-destruct. Also called from _die()
## so a weapon-kill still explodes. Guarded by EnemyBase._dead.
func detonate() -> void:
	if _dead:
		return
	_dead = true
	for target in get_tree().get_nodes_in_group("player"):
		if target is Node3D and global_position.distance_to((target as Node3D).global_position) <= EXPLOSION_RADIUS:
			if target.has_method("take_damage"):
				target.take_damage(EXPLOSION_DAMAGE)
	_spawn_explosion_vfx(global_position)
	died.emit(global_position)
	_drop_loot(global_position)
	queue_free()


## A weapon kill (HP <= 0) also detonates.
func _die() -> void:
	detonate()


func _spawn_explosion_vfx(where: Vector3) -> void:
	var host := get_tree().current_scene
	if host == null:
		host = get_tree().root
	var vfx := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	vfx.mesh = sphere
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.5, 0.1, 0.8)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.45, 0.1)
	m.emission_energy_multiplier = 4.0
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	vfx.material_override = m
	host.add_child(vfx)
	vfx.global_position = where + Vector3(0.0, 0.9, 0.0)
	vfx.scale = Vector3.ONE * 0.4
	# Radius 0.5 * scale 8 = 4 m, matching EXPLOSION_RADIUS.
	var tw := vfx.create_tween()
	tw.tween_property(vfx, "scale", Vector3.ONE * 8.0, 0.35)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, 0.35)
	tw.tween_callback(vfx.queue_free)


func _make_beep(freq: float, dur: float) -> AudioStreamWAV:
	var sr := 22050
	var count := int(sr * dur)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in count:
		var t := float(i) / sr
		var env := 1.0 - float(i) / count
		var sample := sin(TAU * freq * t) * env * 0.5
		bytes.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sr
	wav.stereo = false
	wav.data = bytes
	return wav

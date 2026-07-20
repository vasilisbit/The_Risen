class_name WeakPoint
extends StaticBody3D

## Destructible crystal for the Ember Tyrant's phase B (T-0021). 200 HP, glows
## orange and pulses with a matching audio cue so it reads as the thing to
## shoot. Sits on collision layer 1 so the hitscan weapons (T-0010) find it.
## Destroying all four drops the boss's shield — see ember_tyrant.gd.

signal destroyed(where: Vector3)

const MAX_HEALTH := 200.0
const PULSE_PERIOD := 1.2         # s per glow + beep cycle
const BASE_EMISSION := 1.6
const PULSE_EMISSION := 4.5
const CRYSTAL_COLOR := Color(1.0, 0.55, 0.10)

var health: float = MAX_HEALTH
var _broken: bool = false
var _mat: StandardMaterial3D
var _mesh: MeshInstance3D
var _beep: AudioStreamPlayer3D
var _pulse_t: float = 0.0


func _ready() -> void:
	add_to_group("weak_point_crystal")
	collision_layer = 1
	_build_visual()
	_beep = AudioStreamPlayer3D.new()
	_beep.stream = _make_beep(520.0, 0.10)
	_beep.unit_size = 14.0
	add_child(_beep)


func _process(delta: float) -> void:
	if _broken or _mat == null:
		return
	# Pulse the glow, and beep once at the top of each cycle.
	var was := _pulse_t
	_pulse_t = fmod(_pulse_t + delta, PULSE_PERIOD)
	if _pulse_t < was and _beep:
		_beep.play()
	var wave := 0.5 - 0.5 * cos(TAU * _pulse_t / PULSE_PERIOD)
	_mat.emission_energy_multiplier = lerpf(BASE_EMISSION, PULSE_EMISSION, wave)
	if _mesh:
		_mesh.rotation.y += delta * 0.8


## Hit by a player weapon (weapon.gd calls this on any collider that has it).
func take_damage(amount: float) -> void:
	if _broken or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	_flash()
	if health <= 0.0:
		_shatter()


## Crystals are small and uniform — no head zone, so weapons never crit them.
func is_headshot(_world_point: Vector3) -> bool:
	return false


func _shatter() -> void:
	_broken = true
	destroyed.emit(global_position)
	_shatter_vfx()
	queue_free()


func _build_visual() -> void:
	_mesh = MeshInstance3D.new()
	var prism := CylinderMesh.new()          # tapered = crystal shard
	prism.top_radius = 0.05
	prism.bottom_radius = 0.45
	prism.height = 1.8
	prism.radial_segments = 6
	_mesh.mesh = prism
	_mesh.position = Vector3(0, 0.9, 0)
	_mat = StandardMaterial3D.new()          # unique per instance so it can pulse
	_mat.albedo_color = CRYSTAL_COLOR
	_mat.emission_enabled = true
	_mat.emission = CRYSTAL_COLOR
	_mat.emission_energy_multiplier = BASE_EMISSION
	_mesh.material_override = _mat
	add_child(_mesh)

	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.45
	shape.height = 1.8
	col.shape = shape
	col.position = Vector3(0, 0.9, 0)
	add_child(col)


func _flash() -> void:
	if _mat:
		_mat.emission_energy_multiplier = PULSE_EMISSION * 1.6


func _shatter_vfx() -> void:
	var host := get_tree().current_scene
	if host == null:
		host = get_tree().root
	var vfx := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.4
	sphere.height = 0.8
	vfx.mesh = sphere
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(CRYSTAL_COLOR, 0.8)
	m.emission_enabled = true
	m.emission = CRYSTAL_COLOR
	m.emission_energy_multiplier = 5.0
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	vfx.material_override = m
	host.add_child(vfx)
	vfx.global_position = global_position + Vector3(0, 0.9, 0)
	var tw := vfx.create_tween()
	tw.tween_property(vfx, "scale", Vector3.ONE * 3.5, 0.35)
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

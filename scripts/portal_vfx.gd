class_name PortalVFX
extends Node3D
## T-0017 Mars portal VFX: a GPUParticles3D blue swirl, 2 m across, 2 s loop,
## 400 particles (inside the 300-500 budget), with a synced whoosh. Additive
## unshaded billboards so it reads from 20 m. Cleans itself up: close() stops
## emission and frees after the particles fade, and an auto-free safety net
## fires if nothing closes it.

const RING_RADIUS := 1.0        # 2 m diameter
const PARTICLE_COUNT := 400     # budget: 300-500
const SWIRL_LIFETIME := 2.0     # 2 s loop
const AUTO_FREE_AFTER := 8.0    # safety net

var _particles: GPUParticles3D
var _audio: AudioStreamPlayer3D
var _closing: bool = false


func _ready() -> void:
	_build_particles()
	_build_audio()
	_auto_free_guard()


func _build_particles() -> void:
	_particles = GPUParticles3D.new()
	_particles.amount = PARTICLE_COUNT
	_particles.lifetime = SWIRL_LIFETIME
	_particles.preprocess = 0.6          # start already established
	_particles.local_coords = true

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_radius = RING_RADIUS
	pm.emission_ring_inner_radius = RING_RADIUS * 0.72
	pm.emission_ring_height = 0.12
	pm.emission_ring_axis = Vector3.UP
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.15
	pm.initial_velocity_max = 0.6
	pm.tangential_accel_min = 2.5        # the swirl
	pm.tangential_accel_max = 4.5
	pm.radial_accel_min = -0.8           # vortex pull toward the centre
	pm.radial_accel_max = -0.2
	pm.gravity = Vector3.ZERO
	pm.damping_min = 0.2
	pm.damping_max = 0.6
	pm.scale_min = 0.15
	pm.scale_max = 0.35
	pm.color = Color(0.35, 0.65, 1.0)

	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	ramp.colors = PackedColorArray([
		Color(0.60, 0.85, 1.0, 0.0),
		Color(0.70, 0.90, 1.0, 1.0),
		Color(0.25, 0.55, 1.0, 0.85),
		Color(0.10, 0.30, 1.0, 0.0),
	])
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	pm.color_ramp = ramp_tex
	_particles.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2(0.28, 0.28)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.5, 0.75, 1.0)
	quad.material = mat
	_particles.draw_pass_1 = quad

	_particles.emitting = true
	add_child(_particles)


func _build_audio() -> void:
	_audio = AudioStreamPlayer3D.new()
	_audio.stream = _make_whoosh(0.9)
	_audio.unit_size = 12.0            # audible out to ~20 m
	_audio.max_distance = 30.0
	add_child(_audio)
	_audio.play()                      # synced with the VFX appearing


## Stop emitting and free once the live particles have faded.
func close() -> void:
	if _closing:
		return
	_closing = true
	if _particles:
		_particles.emitting = false
	await get_tree().create_timer(SWIRL_LIFETIME).timeout
	queue_free()


func _auto_free_guard() -> void:
	await get_tree().create_timer(AUTO_FREE_AFTER).timeout
	if not _closing and is_inside_tree():
		close()


## Filtered-noise whoosh (no external assets): white noise through a crude
## one-pole lowpass with a rise/fall envelope.
func _make_whoosh(dur: float) -> AudioStreamWAV:
	var sr := 22050
	var count := int(sr * dur)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var last := 0.0
	for i in count:
		var t := float(i) / float(count)
		var env: float = sin(PI * pow(t, 0.6))          # quick rise, slow tail
		last = lerpf(last, rng.randf_range(-1.0, 1.0), 0.15)
		var sample: float = last * env * 0.5
		bytes.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sr
	wav.stereo = false
	wav.data = bytes
	return wav

class_name LavaEruption
extends Node3D

## Ember Tyrant environmental hazard (T-0021). A tall column of lava erupts at one of the arena's
## eruption markers and burns for DURATION seconds, dealing DPS to the player inside RADIUS.
## Telegraphed by a short warning flash so it is dodgeable. Frees itself when it burns out.
##
## VFX: the column uses the same energy look as the Ember Tyrant's shield (boss_shield.gdshader,
## lava-tinted) so it reads as a coherent soulfire hazard, rises tall, and is topped by a
## GPUParticles "upstream" of embers and a pulsing warm light while live.

const DPS := 50.0
const RADIUS := 3.0
const DURATION := 4.0
const WARNING := 1.0             # s of telegraph before damage starts
const COLUMN_H := 13.0           # metres: the pillar rises this high
const LAVA_COLOR := Color(1.0, 0.35, 0.05)
const HOT_COLOR := Color(1.0, 0.72, 0.25)

var _life: float = 0.0
var _mesh: MeshInstance3D
var _fallback_mat: StandardMaterial3D   # only set when the shield shader is absent
var _embers: GPUParticles3D
var _light: OmniLight3D
var _live: bool = false


func _ready() -> void:
	add_to_group("lava_eruption")
	_build_visual()


func _physics_process(delta: float) -> void:
	_life += delta
	if _life >= WARNING + DURATION:
		queue_free()
		return

	if _life < WARNING:
		# Telegraph: a flat pulsing disc marking where the pillar is about to rise.
		var wave := 0.5 - 0.5 * cos(TAU * _life / WARNING * 3.0)
		_mesh.scale = Vector3(1.0, 0.04, 1.0)
		if _fallback_mat:
			_fallback_mat.emission_energy_multiplier = lerpf(1.0, 4.0, wave)
		if _light:
			_light.light_energy = lerpf(0.2, 1.2, wave)
		return

	if not _live:
		_go_live()

	# Full-height pillar with a flickering updraft glow.
	_mesh.scale = Vector3(1.0, 1.0, 1.0)
	if _fallback_mat:
		_fallback_mat.emission_energy_multiplier = 4.5 + 1.5 * sin(_life * 22.0)
	if _light:
		_light.light_energy = 2.8 + 0.9 * sin(_life * 18.0)

	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("take_damage"):
		return
	var flat := (player as Node3D).global_position - global_position
	flat.y = 0.0
	if flat.length() <= RADIUS:
		player.take_damage(DPS * delta, "LavaEruption")


## True while the column is actually burning (past its telegraph).
func is_active() -> bool:
	return _life >= WARNING and _life < WARNING + DURATION


## Kick the eruption into its live look: embers stream up, the light comes on.
func _go_live() -> void:
	_live = true
	if _embers:
		_embers.emitting = true
	if _light:
		_light.light_energy = 2.8


func _build_visual() -> void:
	# Tall tapered pillar, drawn with the Ember Tyrant's energy-shield shader (lava-tinted) so the
	# eruption matches the boss's soulfire language instead of a flat translucent cylinder.
	_mesh = MeshInstance3D.new()
	var col := CylinderMesh.new()
	col.top_radius = RADIUS * 0.45
	col.bottom_radius = RADIUS * 1.05
	col.height = COLUMN_H
	col.radial_segments = 24
	_mesh.mesh = col
	_mesh.position = Vector3(0, COLUMN_H * 0.5, 0)
	if ResourceLoader.exists("res://shaders/boss_shield.gdshader"):
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/boss_shield.gdshader")
		sm.set_shader_parameter("shield_color", Vector3(LAVA_COLOR.r, LAVA_COLOR.g, LAVA_COLOR.b))
		sm.set_shader_parameter("hot_color", Vector3(HOT_COLOR.r, HOT_COLOR.g, HOT_COLOR.b))
		sm.set_shader_parameter("hex_scale", 6.0)
		sm.set_shader_parameter("flicker_speed", 9.0)
		sm.set_shader_parameter("base_alpha", 0.12)
		_mesh.material_override = sm
	else:
		_fallback_mat = StandardMaterial3D.new()
		_fallback_mat.albedo_color = Color(LAVA_COLOR, 0.5)
		_fallback_mat.emission_enabled = true
		_fallback_mat.emission = LAVA_COLOR
		_fallback_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_fallback_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_fallback_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_fallback_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mesh.material_override = _fallback_mat
	_mesh.scale = Vector3(1.0, 0.04, 1.0)
	add_child(_mesh)

	# Rising embers (the "upstream"): unshaded emissive motes shot high, arcing back down.
	_embers = GPUParticles3D.new()
	_embers.amount = 70
	_embers.lifetime = 2.4
	_embers.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 14.0
	pm.initial_velocity_min = 9.0
	pm.initial_velocity_max = 18.0
	pm.gravity = Vector3(0, -6.0, 0)
	pm.scale_min = 0.10
	pm.scale_max = 0.40
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(RADIUS * 0.7, 0.2, RADIUS * 0.7)
	pm.color = HOT_COLOR
	_embers.process_material = pm
	var mote := SphereMesh.new()
	mote.radius = 0.09
	mote.height = 0.18
	mote.radial_segments = 6
	mote.rings = 3
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(1.0, 0.7, 0.3)
	mm.emission_enabled = true
	mm.emission = Color(1.0, 0.5, 0.12)
	mm.emission_energy_multiplier = 5.0
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_embers.draw_pass_1 = mote
	_embers.material_override = mm
	add_child(_embers)

	# Warm updraft light (off until live).
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.5, 0.15)
	_light.omni_range = RADIUS * 3.2
	_light.light_energy = 0.0
	_light.position = Vector3(0, 2.2, 0)
	add_child(_light)

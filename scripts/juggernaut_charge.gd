class_name JuggernautCharge
extends Ability

## Tank super (T-0023, GDD §2.4): 5 s of invulnerability with melee damage x3,
## 60 s cooldown.
##
## Invulnerability is total - it short-circuits Guardian.take_damage() ahead of
## armour and shield, so the class passive's -20% never even comes into play.
## The melee multiplier is written to Guardian.melee_multiplier, which the melee
## attack in T-0025 reads; until that card lands the x3 has nothing to scale,
## and that is the only part of this super not yet observable in play.

const DURATION := 5.0
const MELEE_MULT := 3.0
const CHARGE_COLOR := Color(0.55, 0.75, 1.0)
## Energy-crackle aura via the shared shield shader (docs/VFX_FAL_RESEARCH.md §11.5).
const AURA_SHADER := "res://shaders/shield_dome.gdshader"
const CRACKLE_TEX := "res://assets/generated/vfx/tex/voronoi.png"
const NOISE_TEX := "res://assets/generated/vfx/tex/noise_fbm.png"

## Live state, exposed for the HUD and tests.
var active: bool = false
var time_left: float = 0.0

var _aura: MeshInstance3D
var _mat: StandardMaterial3D          # fallback flat material
var _shader: ShaderMaterial           # preferred crackle material


func _init() -> void:
	ability_name = "Juggernaut Charge"
	ability_color = CHARGE_COLOR


func _process(delta: float) -> void:
	super._process(delta)
	if not active:
		return
	time_left = maxf(0.0, time_left - delta)
	if _aura and is_instance_valid(_aura) and is_instance_valid(player):
		_aura.global_position = player.global_position + Vector3(0, 1.0, 0)
	if time_left <= 0.0:
		_end()


func _execute() -> void:
	active = true
	time_left = DURATION
	player.invulnerable = true
	player.melee_multiplier = MELEE_MULT
	_build_aura()
	# Energy charge-up burst (bright ring + arc sparks + bloom).
	VfxKit.explosion(_host(), player.global_position + Vector3(0, 1, 0), CHARGE_COLOR, 5.0, "emp")
	var am := get_node_or_null("/root/AudioManager")
	if am:
		am.play_sfx("super_charge", player.global_position)


func _end() -> void:
	active = false
	time_left = 0.0
	if is_instance_valid(player):
		player.invulnerable = false
		player.melee_multiplier = 1.0
	if _aura and is_instance_valid(_aura):
		_aura.queue_free()
	_aura = null


func _build_aura() -> void:
	_aura = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.3
	sphere.height = 2.6
	_aura.mesh = sphere
	if ResourceLoader.exists(AURA_SHADER) and ResourceLoader.exists(CRACKLE_TEX):
		_shader = ShaderMaterial.new()
		_shader.shader = load(AURA_SHADER)
		_shader.set_shader_parameter("pattern_tex", load(CRACKLE_TEX))
		_shader.set_shader_parameter("noise_tex", load(NOISE_TEX))
		_shader.set_shader_parameter("shield_color", CHARGE_COLOR)
		_shader.set_shader_parameter("pattern_scale", 2.5)
		_shader.set_shader_parameter("scroll_speed", 0.18)   # faster = crackle
		_shader.set_shader_parameter("brightness", 2.6)
		_shader.set_shader_parameter("strength", 1.0)
		_aura.material_override = _shader
	else:
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = Color(CHARGE_COLOR, 0.25)
		_mat.emission_enabled = true
		_mat.emission = CHARGE_COLOR
		_mat.emission_energy_multiplier = 2.5
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_aura.material_override = _mat
	_host().add_child(_aura)
	_aura.global_position = player.global_position + Vector3(0, 1.0, 0)

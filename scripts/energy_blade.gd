class_name EnergyBlade
extends MeleeAbility

## Assault melee (T-0025, GDD §2.4): energy blade. Reworked from an instant cone
## into a **travelling crescent wave** (SlashWave) that flies forward, damages every
## enemy it passes through (200, melee-multiplied), and fades after a few metres -
## so the Assault can throw a ranged slash rather than only hitting point-blank.

const DAMAGE := 200.0

## Enemies hit by the last wave - filled from the wave as it travels (best-effort;
## the wave outlives this call), kept for the HUD/tests.
var last_hits: int = 0


func _init() -> void:
	super._init()
	ability_name = "Energy Blade"
	ability_color = Color(0.45, 0.85, 1.0)


func _execute() -> void:
	var facing: Vector3 = -player.global_transform.basis.z
	var from: Vector3 = player.global_position + Vector3(0, 1.1, 0) + facing.normalized() * 0.6
	last_hits = 0
	var wave := SlashWave.new()
	wave.setup(from, facing, _damage(DAMAGE), ability_color)
	_host().add_child(wave)
	var am := get_node_or_null("/root/AudioManager")
	if am:
		am.play_sfx("melee_blade", from)

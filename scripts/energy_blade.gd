class_name EnergyBlade
extends MeleeAbility

## Assault melee (T-0025, GDD §2.4): energy blade slash, 200 damage in a 1.5 m
## arc, hitting every enemy in the swing rather than just the nearest - the
## card calls for "πολλαπλοί στόχοι" and it is the whole point of a slash.

const DAMAGE := 200.0
const REACH := 3.0                # was 1.5 - enemies engage/strike from 2-2.8 m, so
                                  # the old blade whiffed on things that were hitting us
const HALF_ARC_DEG := 65.0        # 130 degree swing in front of the player

## Enemies hit by the last swing - exposed for tests.
var last_hits: int = 0


func _init() -> void:
	super._init()
	ability_name = "Energy Blade"
	ability_color = Color(0.45, 0.85, 1.0)


func _strike() -> void:
	last_hits = 0
	for e in _targets_in_cone(REACH, HALF_ARC_DEG):
		if e.has_method("take_damage"):
			_hit(e, _damage(DAMAGE))
			last_hits += 1


func _execute() -> void:
	# Swept energy-arc slash (flare_cross arc + edge sparks) instead of the flat disc.
	var facing: Vector3 = -player.global_transform.basis.z
	var at: Vector3 = player.global_position + Vector3(0, 1.1, 0) + facing.normalized() * (REACH * 0.4)
	VfxKit.slash(_host(), at, facing, ability_color, REACH)
	_strike()

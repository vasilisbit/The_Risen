class_name EnergyBlade
extends MeleeAbility

## Assault melee (T-0025, GDD §2.4): energy blade slash, 200 damage in a 1.5 m
## arc, hitting every enemy in the swing rather than just the nearest — the
## card calls for "πολλαπλοί στόχοι" and it is the whole point of a slash.

const DAMAGE := 200.0
const REACH := 1.5
const HALF_ARC_DEG := 60.0        # 120 degree swing in front of the player

## Enemies hit by the last swing — exposed for tests.
var last_hits: int = 0


func _init() -> void:
	super._init()
	ability_name = "Energy Blade"
	ability_color = Color(0.45, 0.85, 1.0)


func _strike() -> void:
	last_hits = 0
	for e in _targets_in_cone(REACH, HALF_ARC_DEG):
		if e.has_method("take_damage"):
			e.take_damage(_damage(DAMAGE))
			last_hits += 1


func _execute() -> void:
	_swing_vfx(REACH)
	_strike()

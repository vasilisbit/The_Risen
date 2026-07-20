class_name FragGrenade
extends Grenade

## Assault grenade (T-0024, GDD §2.4): 150 damage in a 4 m radius.
## Flat damage across the radius rather than falloff - same reasoning as the
## Exploder's hard-radius AoE: deterministic and testable, and at 4 m there is
## not enough room for falloff to read as anything but inconsistency.

const GRENADE_NAME := "Frag Grenade"
const GRENADE_COLOR := Color(1.0, 0.45, 0.15)

const DAMAGE := 150.0
const RADIUS := 4.0


func _detonate() -> void:
	var here := global_position
	for e in _enemies_in(RADIUS):
		if e.has_method("mark_damage_source"):
			e.mark_damage_source(GRENADE_NAME)
		if e.has_method("take_damage"):
			e.take_damage(DAMAGE)
	_burst(here, GRENADE_COLOR, RADIUS * 2.0, 0.35)
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.play_sfx("explosion", here)

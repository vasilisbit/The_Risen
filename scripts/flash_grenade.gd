class_name FlashGrenade
extends Grenade

## Tank grenade (T-0024, GDD §2.4): blinds every enemy within 5 m for 5 s and
## deals no damage at all. Blinded enemies stop acting entirely (EnemyBase.stun)
## - no chasing, aiming, shooting or detonating - but still fall under gravity,
## so a flashbanged Rusher on a ledge doesn't hang in mid-air.

const GRENADE_NAME := "Flashbang"
const GRENADE_COLOR := Color(1.0, 0.97, 0.75)

const BLIND_DURATION := 5.0
const RADIUS := 5.0

## How many enemies the last detonation blinded - exposed for tests.
var blinded: int = 0


func _detonate() -> void:
	blinded = 0
	for e in _enemies_in(RADIUS):
		if e.has_method("stun"):
			e.stun(BLIND_DURATION)
			blinded += 1
	# Hard white bloom + fast glare ring + strong flash light (VfxKit "flash").
	VfxKit.explosion(_host(), global_position, GRENADE_COLOR, RADIUS, "flash")
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.play_sfx("grenade_flash", global_position)

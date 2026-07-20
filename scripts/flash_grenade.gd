class_name FlashGrenade
extends Grenade

## Tank grenade (T-0024, GDD §2.4): blinds every enemy within 5 m for 5 s and
## deals no damage at all. Blinded enemies stop acting entirely (EnemyBase.stun)
## — no chasing, aiming, shooting or detonating — but still fall under gravity,
## so a flashbanged Rusher on a ledge doesn't hang in mid-air.

const GRENADE_NAME := "Flashbang"
const GRENADE_COLOR := Color(1.0, 0.97, 0.75)

const BLIND_DURATION := 5.0
const RADIUS := 5.0

## How many enemies the last detonation blinded — exposed for tests.
var blinded: int = 0


func _detonate() -> void:
	blinded = 0
	for e in _enemies_in(RADIUS):
		if e.has_method("stun"):
			e.stun(BLIND_DURATION)
			blinded += 1
	_burst(global_position, GRENADE_COLOR, RADIUS * 2.0, 0.25)
	_flash_screen()


## A brief white bloom at the blast, standing in for a real screen flash.
func _flash_screen() -> void:
	var light := OmniLight3D.new()
	light.omni_range = RADIUS * 3.0
	light.light_energy = 8.0
	light.light_color = GRENADE_COLOR
	_host().add_child(light)
	light.global_position = global_position + Vector3(0, 0.5, 0)
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.5)
	tw.tween_callback(light.queue_free)

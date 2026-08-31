class_name HealingGrenade
extends Grenade

## Support grenade (T-0024): a 5 m zone that restores 50 HP over 5 s.
##
## The card specifies a zone over time rather than the GDD's instant heal, so
## it heals 10 HP/s while you stand in it - you have to hold the ground you
## threw it on instead of topping up and walking away. It leaves a lingering
## HealZone behind rather than healing on detonation, so the grenade body can
## free itself as normal.

const GRENADE_NAME := "Healing Grenade"
const GRENADE_COLOR := Color(0.35, 0.95, 0.55)

const HEAL_TOTAL := 50.0
const DURATION := 5.0
const RADIUS := 5.0


func _detonate() -> void:
	var zone := HealZone.new()
	zone.radius = RADIUS
	zone.duration = DURATION
	zone.heal_per_second = HEAL_TOTAL / DURATION
	zone.tint = GRENADE_COLOR
	_host().add_child(zone)
	zone.global_position = global_position
	# Gentle rising motes + soft bloom + heal-ring decal (no shrapnel/scorch).
	VfxKit.explosion(_host(), global_position, GRENADE_COLOR, RADIUS, "soft")
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.play_sfx("grenade_heal", global_position)

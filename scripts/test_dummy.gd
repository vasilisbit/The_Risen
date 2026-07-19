extends StaticBody3D
## T-0010 test dummy: a stationary target that records damage for verifying the
## weapon system. Head zone (local y >= 1.4) so sniper headshots can be checked.

const HEAD_MIN_LOCAL_Y := 1.4

var damage_taken: float = 0.0
var hits: int = 0
var last_headshot: bool = false


func take_damage(amount: float) -> void:
	damage_taken += amount
	hits += 1


func is_headshot(world_point: Vector3) -> bool:
	last_headshot = (world_point.y - global_position.y) >= HEAD_MIN_LOCAL_Y
	return last_headshot

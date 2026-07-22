class_name StormBarrage
extends Ability

## Assault super (T-0023, GDD §2.4): 10 homing rockets, 200 damage each in an
## 8 m splash, 60 s cooldown.
##
## Rockets are spread across the available targets round-robin rather than all
## piling onto the nearest enemy, so the DoD case - 10 targets on 150 HP - kills
## all 10 rather than overkilling one. With fewer targets than rockets the
## remainder wrap around and stack, which is what you want against a boss.

const ROCKET_COUNT := 10
const LAUNCH_INTERVAL := 0.08     # s between rockets, so it reads as a salvo
const TARGET_RANGE := 60.0
const LAUNCH_HEIGHT := 1.4
const LAUNCH_SPREAD := 1.2        # lateral scatter of the launch points


func _init() -> void:
	ability_name = "Storm Barrage"
	ability_color = Color(1.0, 0.65, 0.2)


func _execute() -> void:
	var origin: Vector3 = player.global_position + Vector3(0, LAUNCH_HEIGHT, 0)
	_burst(origin, ability_color, 4.0, 0.4)
	var targets := _enemies_near(player.global_position, TARGET_RANGE)
	for i in ROCKET_COUNT:
		# Re-filter to living targets each rocket: earlier rockets in the salvo
		# kill enemies during the awaits, and indexing a freed instance into a
		# typed Node3D throws "assign previously freed instance".
		var live := targets.filter(func(t: Node) -> bool: return is_instance_valid(t))
		# Round-robin so every enemy in range is engaged before any gets a second.
		var target: Node3D = live[i % live.size()] if not live.is_empty() else null
		_launch(origin, i, target)
		await get_tree().create_timer(LAUNCH_INTERVAL).timeout
		if player == null or not is_instance_valid(player):
			return


func _launch(origin: Vector3, index: int, target: Node3D) -> void:
	var r := Rocket.new()
	_host().add_child(r)
	# Fan the salvo out sideways and upward before the rockets turn in.
	var angle := TAU * float(index) / float(ROCKET_COUNT)
	var up := Vector3.UP * 1.6
	var side := Vector3(cos(angle), 0.0, sin(angle)) * LAUNCH_SPREAD
	r.setup(origin + side * 0.4, (up + side).normalized(), target)


## Test helper: how many rockets are currently in the air.
func live_rockets() -> int:
	var n := 0
	for c in _host().get_children():
		if c is Rocket:
			n += 1
	return n

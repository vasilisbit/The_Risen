class_name EmpPunch
extends MeleeAbility

## Support melee (T-0025, GDD §2.4): EMP punch, 80 damage and a 3 s stun.
## Reuses EnemyBase.stun() from the Flashbang (T-0024), so a stunned target
## stops acting entirely but still falls under gravity.
##
## The damage is minor next to the blade or the slam - this is a panic button
## for peeling something off you, which fits Support having the least
## self-defence in its kit.

const DAMAGE := 80.0
const STUN := 3.0
const REACH := 3.0                # was 2.0 - reach the enemies that are meleeing us
const HALF_ARC_DEG := 55.0        # narrower than the blade: it's a punch

## Enemies hit / stunned by the last punch - exposed for tests.
var last_hits: int = 0


func _init() -> void:
	super._init()
	ability_name = "EMP Punch"
	ability_color = Color(0.5, 0.95, 0.7)


func _strike() -> void:
	last_hits = 0
	for e in _targets_in_cone(REACH, HALF_ARC_DEG):
		_hit(e, _damage(DAMAGE))
		# Stun after the damage: a lethal punch frees the node, and stunning a
		# freed enemy would error.
		if is_instance_valid(e) and e.has_method("stun"):
			e.stun(STUN)
		last_hits += 1


func _execute() -> void:
	# Tight electric burst (bright ring + arc sparks) in front of the punch.
	var facing: Vector3 = -player.global_transform.basis.z
	var at: Vector3 = player.global_position + Vector3(0, 1.1, 0) + facing.normalized() * (REACH * 0.35)
	VfxKit.explosion(_host(), at, ability_color, 2.0, "emp")
	_strike()

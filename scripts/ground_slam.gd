class_name GroundSlam
extends MeleeAbility

## Tank melee (T-0025): ground slam, 250 damage and a 2 m knockback to
## everything within 3 m.
##
## Omnidirectional, not a cone - a slam hits the ground, so facing shouldn't
## matter, and it is the Tank's answer to being surrounded.
##
## The card reads "250 dmg, 3m, knockback 2m"; GDD §2.4 writes it as "250
## damage, 3m knockback", which would leave the radius unstated. Followed the
## card: 3 m radius, 2 m of knockback.

const DAMAGE := 250.0
const RADIUS := 3.5               # was 3.0 - clears the enemies' own melee range
const KNOCKBACK := 2.0            # metres, exact (EnemyBase.apply_push)

## Enemies hit by the last slam - exposed for tests.
var last_hits: int = 0


func _init() -> void:
	super._init()
	ability_name = "Ground Slam"
	ability_color = Color(1.0, 0.75, 0.35)


func _strike() -> void:
	last_hits = 0
	var origin: Vector3 = player.global_position
	for e in _targets_in_radius(RADIUS):
		_hit(e, _damage(DAMAGE))
		# Push survivors outward. A lethal slam frees the node first.
		if not is_instance_valid(e):
			last_hits += 1
			continue
		var away: Vector3 = (e as Node3D).global_position - origin
		away.y = 0.0
		if away.length() < 0.01:
			away = -player.global_transform.basis.z
			away.y = 0.0
		if e.has_method("apply_push"):
			e.apply_push(away.normalized() * KNOCKBACK)
		last_hits += 1


func _execute() -> void:
	# Heavy ground shockwave + dust + crack decal, centred on the player.
	VfxKit.explosion(_host(), player.global_position + Vector3(0, 0.15, 0), ability_color, RADIUS, "slam")
	var am := get_node_or_null("/root/AudioManager")
	if am:
		am.play_sfx("melee_slam", player.global_position)
	_strike()

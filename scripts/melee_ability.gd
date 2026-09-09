class_name MeleeAbility
extends Ability

## Shared melee plumbing (T-0025). One subclass per class kit: EnergyBlade
## (Assault), EmpPunch (Support), GroundSlam (Tank). 5 s cooldown, bound to V,
## with a 1 s swing VFX standing in for the animation.
##
## All three run their damage through _damage(), which applies the Guardian's
## melee_multiplier - this is what finally makes Juggernaut Charge's "melee x3"
## (T-0023) do something, since nothing read that field until now.
##
## Damage lands on the frame the attack fires rather than partway through the
## swing. Every other attack in the game (Brute melee, Tyrant melee, grenades)
## resolves instantly, and a windup would make the effect untestable without
## buying much: the 1 s swing is presentation.

const MELEE_COOLDOWN := 5.0
const SWING_TIME := 1.0           # animation placeholder length


func _init() -> void:
	cooldown_time = MELEE_COOLDOWN
	ability_name = "Melee"
	ability_color = Color(0.9, 0.9, 0.9)
	telemetry_slot = "melee"
	input_prompt = "V"


func _execute() -> void:
	_swing_vfx()
	_strike()


## Subclass hook - the actual attack.
func _strike() -> void:
	pass


## Scale a base damage figure by the player's current melee multiplier.
func _damage(base: float) -> float:
	if player == null or not is_instance_valid(player):
		return base
	return base * float(player.melee_multiplier)


## Attribute a kill to this melee before damaging, so EnemyKilled reports the
## ability rather than "Unknown" (T-0026).
func _hit(target: Node, amount: float) -> void:
	if target.has_method("mark_damage_source"):
		target.mark_damage_source(ability_name)
	if target.has_method("take_damage"):
		target.take_damage(amount)


## Enemies inside a cone in front of the player: within `reach` metres and
## within `half_angle_deg` of where they are facing. Used by the blade and
## punch, which are directional; the slam uses the radius helper instead.
##
## Distance is measured to the enemy's body surface, not its origin: a big
## boss (scale 3-4) has its origin at its feet, metres from the player it is
## looming over, so measuring origin-to-origin whiffed on exactly the enemies
## that were meleeing us. Subtracting the enemy's collision radius makes reach
## line up with what the player sees.
func _targets_in_cone(reach: float, half_angle_deg: float) -> Array:
	var origin: Vector3 = player.global_position
	var facing: Vector3 = -player.global_transform.basis.z
	facing.y = 0.0
	if facing.length() < 0.01:
		facing = Vector3.FORWARD
	facing = facing.normalized()
	var found: Array = []
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node3D):
			continue
		var to: Vector3 = (e as Node3D).global_position - origin
		to.y = 0.0
		var surface := to.length() - _enemy_radius(e)
		if surface > reach:
			continue
		if surface < 0.01:
			found.append(e)          # standing inside us / overlapping: always hit
			continue
		if rad_to_deg(facing.angle_to(to.normalized())) <= half_angle_deg:
			found.append(e)
	return found


## Enemies within `reach` metres in any direction (the slam is omnidirectional).
func _targets_in_radius(reach: float) -> Array:
	var origin: Vector3 = player.global_position
	var found: Array = []
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node3D):
			continue
		var to: Vector3 = (e as Node3D).global_position - origin
		to.y = 0.0
		if to.length() - _enemy_radius(e) <= reach:
			found.append(e)
	return found


## Approximate horizontal radius of an enemy's body, from its first
## CollisionShape3D scaled into world space (falls back to its node scale).
## Cached per enemy so a swing does not re-walk every body it touches.
func _enemy_radius(e: Node) -> float:
	if not (e is Node3D):
		return 0.0
	if e.has_meta("_melee_radius"):
		return float(e.get_meta("_melee_radius"))
	var r := 0.5
	var shapes := (e as Node).find_children("*", "CollisionShape3D", true, false)
	if not shapes.is_empty():
		var shape: Shape3D = (shapes[0] as CollisionShape3D).shape
		if shape is SphereShape3D or shape is CapsuleShape3D or shape is CylinderShape3D:
			r = shape.radius
		elif shape is BoxShape3D:
			r = maxf(shape.size.x, shape.size.z) * 0.5
	var s: Vector3 = (e as Node3D).global_transform.basis.get_scale()
	r *= maxf(s.x, s.z)
	e.set_meta("_melee_radius", r)
	return r


## Flat expanding disc in front of / around the player, standing in for the
## swing animation. Lives for SWING_TIME so the attack reads at a glance.
func _swing_vfx(reach: float = 2.0, ahead: bool = true) -> void:
	var vfx := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = reach
	disc.bottom_radius = reach
	disc.height = 0.08
	vfx.mesh = disc
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(ability_color, 0.5)
	m.emission_enabled = true
	m.emission = ability_color
	m.emission_energy_multiplier = 4.0
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	vfx.material_override = m
	_host().add_child(vfx)
	var facing: Vector3 = -player.global_transform.basis.z
	facing.y = 0.0
	facing = facing.normalized() if facing.length() > 0.01 else Vector3.FORWARD
	var offset := facing * (reach * 0.5) if ahead else Vector3.ZERO
	vfx.global_position = player.global_position + Vector3(0, 1.0, 0) + offset
	vfx.scale = Vector3(0.2, 1.0, 0.2)
	var tw := vfx.create_tween()
	tw.tween_property(vfx, "scale", Vector3(1.0, 1.0, 1.0), SWING_TIME * 0.35)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, SWING_TIME)
	tw.tween_callback(vfx.queue_free)

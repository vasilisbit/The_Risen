class_name GrenadeAbility
extends Ability

## Grenade throw (T-0024). One ability for all three classes - the throw is
## identical, only the payload differs, so the class picks a grenade script and
## this reads the payload's own GRENADE_NAME / GRENADE_COLOR for the HUD.
##
## 30 s cooldown, bound to G. The grenade is a real RigidBody3D launched with an
## impulse, so the arc comes from the physics engine rather than a scripted
## parabola - it bounces off walls and rolls down slopes on its own.

const GRENADE_COOLDOWN := 30.0

## Tuned in-engine so a level throw LANDS ~10 m away (card: "τόξο 10m") with
## roughly 20 degrees of loft, touching down around 1.0 s - comfortably inside
## the 1.5 s fuse, so the grenade comes to rest near the target instead of
## airbursting mid-arc. The first pass at 12 m/s was still flying at the fuse
## and "landed" 15 m out.
const THROW_SPEED := 10.5
const THROW_LOFT := 0.36          # upward component added to the aim direction
const MUZZLE_FORWARD := 0.6       # spawn ahead of the camera, not inside it

## Path to the Grenade subclass this class throws. Set by the Guardian.
var grenade_script: String = ""


func _init() -> void:
	cooldown_time = GRENADE_COOLDOWN
	ability_name = "Grenade"
	ability_color = Color(0.8, 0.8, 0.8)
	telemetry_slot = "grenade"
	input_prompt = "G"


## Pull the payload's identity into the HUD. Called after grenade_script is set.
func refresh_identity() -> void:
	var script := load(grenade_script) if grenade_script != "" else null
	if script == null:
		return
	var consts: Dictionary = script.get_script_constant_map()
	ability_name = String(consts.get("GRENADE_NAME", "Grenade"))
	var c: Variant = consts.get("GRENADE_COLOR", ability_color)
	if c is Color:
		ability_color = c


func _execute() -> void:
	var script := load(grenade_script) if grenade_script != "" else null
	if script == null:
		return
	var g := script.new() as Grenade
	if g == null:
		return
	_host().add_child(g)
	var from := _throw_origin()
	g.throw(from, _throw_dir(), THROW_SPEED)


## Throw from the camera so the arc starts where the player is looking, not
## from the body's feet.
func _throw_origin() -> Vector3:
	var cam := _camera()
	if cam == null:
		return player.global_position + Vector3(0, 1.5, 0)
	return cam.global_position + (-cam.global_transform.basis.z) * MUZZLE_FORWARD


func _throw_dir() -> Vector3:
	var cam := _camera()
	var forward := -cam.global_transform.basis.z if cam != null else -player.global_transform.basis.z
	return (forward + Vector3.UP * THROW_LOFT).normalized()


func _camera() -> Camera3D:
	if player == null or not is_instance_valid(player):
		return null
	return player.get_node_or_null("SpringArm3D/Camera3D") as Camera3D

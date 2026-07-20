class_name GuardianDome
extends Ability

## Support super (T-0023, GDD §2.4): a 5 m shield dome for 10 s that absorbs
## 1500 damage, 60 s cooldown.
##
## The dome is anchored where it was cast, not to the player — it is cover you
## fall back to, and following the player would make it a personal bubble with
## no reason to ever leave it. Damage is only absorbed while the player is
## actually inside the radius. It ends on whichever comes first: the 1500 pool
## running out, or the 10 s expiring.

const RADIUS := 5.0
const DURATION := 10.0
const ABSORB_POOL := 1500.0
const DOME_COLOR := Color(0.35, 0.95, 0.6)

## Live dome state, exposed for the HUD and tests.
var active: bool = false
var absorbed: float = 0.0
var time_left: float = 0.0
var center: Vector3 = Vector3.ZERO

var _mesh: MeshInstance3D
var _mat: StandardMaterial3D


func _init() -> void:
	ability_name = "Guardian Dome"
	ability_color = DOME_COLOR


func _process(delta: float) -> void:
	super._process(delta)
	if not active:
		return
	time_left = maxf(0.0, time_left - delta)
	if time_left <= 0.0:
		_end("expired")


func _execute() -> void:
	center = player.global_position
	active = true
	absorbed = 0.0
	time_left = DURATION
	_build_dome()


## Absorb what the dome can and return the damage that gets through. The
## Guardian calls this before its own shield/health handling.
func absorb(amount: float, at: Vector3) -> float:
	if not active or amount <= 0.0:
		return amount
	# Only protects what is under it.
	var flat := at - center
	flat.y = 0.0
	if flat.length() > RADIUS:
		return amount
	var room := ABSORB_POOL - absorbed
	var taken := minf(room, amount)
	absorbed += taken
	_refresh_dome()
	if absorbed >= ABSORB_POOL:
		_end("broken")
	return amount - taken


## Remaining absorption before the dome shatters.
func pool_left() -> float:
	return maxf(0.0, ABSORB_POOL - absorbed)


func _end(_reason: String) -> void:
	active = false
	time_left = 0.0
	if _mesh and is_instance_valid(_mesh):
		var m := _mat
		var tw := _mesh.create_tween()
		tw.tween_property(m, "albedo_color:a", 0.0, 0.25)
		tw.tween_callback(_mesh.queue_free)
	_mesh = null
	_burst(center + Vector3(0, 1, 0), DOME_COLOR, RADIUS * 1.5, 0.3)


func _build_dome() -> void:
	_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = RADIUS
	sphere.height = RADIUS * 2.0
	sphere.is_hemisphere = true
	_mesh.mesh = sphere
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(DOME_COLOR, 0.22)
	_mat.emission_enabled = true
	_mat.emission = DOME_COLOR
	_mat.emission_energy_multiplier = 1.5
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh.material_override = _mat
	_host().add_child(_mesh)
	_mesh.global_position = center


## Fade the dome out as its pool is spent, so its remaining strength is visible.
func _refresh_dome() -> void:
	if _mat == null:
		return
	var frac := pool_left() / ABSORB_POOL
	_mat.albedo_color = Color(DOME_COLOR, lerpf(0.05, 0.22, frac))
	_mat.emission_energy_multiplier = lerpf(0.4, 1.5, frac)

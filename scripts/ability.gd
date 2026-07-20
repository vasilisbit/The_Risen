class_name Ability
extends Node

## Shared super-ability plumbing (T-0023). One subclass per class kit:
## StormBarrage (Assault), GuardianDome (Support), JuggernautCharge (Tank).
## Handles the 60 s cooldown and the ready/activate contract; subclasses only
## implement _execute(). The Guardian owns exactly one of these, swapped when
## the class changes, and the ability HUD reads cooldown_fraction() from it.

signal activated
signal became_ready

const COOLDOWN := 60.0            # s, all three supers (GDD §2.4)

## Display name / colour used by the cooldown HUD.
var ability_name: String = "Super"
var ability_color: Color = Color(1, 1, 1)

var _cooldown_left: float = 0.0


## The Guardian that owns this ability. Set by the owner before adding it.
var player: Node3D


func _process(delta: float) -> void:
	if _cooldown_left <= 0.0:
		return
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	if _cooldown_left <= 0.0:
		became_ready.emit()


func is_ready() -> bool:
	return _cooldown_left <= 0.0


func cooldown_left() -> float:
	return _cooldown_left


## 0.0 while fully on cooldown, 1.0 when ready — what the radial HUD fills to.
func cooldown_fraction() -> float:
	return 1.0 - (_cooldown_left / COOLDOWN)


## Fire the super. Returns false (and does nothing) if still on cooldown, which
## is what makes "Q only works when the cooldown is up" true for all 3 classes
## rather than each subclass having to remember the check.
func activate() -> bool:
	if not is_ready():
		return false
	if player == null or not is_instance_valid(player):
		return false
	_cooldown_left = COOLDOWN
	_execute()
	activated.emit()
	return true


## Skip the remaining cooldown (debug / tests).
func reset_cooldown() -> void:
	_cooldown_left = 0.0
	became_ready.emit()


## Subclass hook — the actual effect.
func _execute() -> void:
	pass


# --- helpers shared by the subclasses ---------------------------------------

func _host() -> Node:
	var host := get_tree().current_scene
	return host if host != null else get_tree().root


## Living enemies within `radius` of `origin`, nearest first.
func _enemies_near(origin: Vector3, radius: float) -> Array:
	var found: Array = []
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node3D):
			continue
		if (e as Node3D).global_position.distance_to(origin) <= radius:
			found.append(e)
	found.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_to(origin) < b.global_position.distance_to(origin))
	return found


## Expanding translucent sphere, used by every super's cast VFX.
func _burst(at: Vector3, color: Color, size: float, time: float) -> void:
	var vfx := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	vfx.mesh = sphere
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, 0.6)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 4.0
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	vfx.material_override = m
	_host().add_child(vfx)
	vfx.global_position = at
	vfx.scale = Vector3.ONE * 0.3
	var tw := vfx.create_tween()
	tw.tween_property(vfx, "scale", Vector3.ONE * size, time)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, time)
	tw.tween_callback(vfx.queue_free)

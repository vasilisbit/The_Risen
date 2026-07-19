class_name Weapon
extends Node3D

## Base hitscan weapon (T-0010). One script, four configured scenes. Stats are
## @export per TDD §4.2 and match GDD §2.6. Firing raycasts from a supplied
## origin/direction (the player camera) via PhysicsRayQueryParameters3D; hitting
## a node with take_damage() applies damage, doubled on a headshot (is_headshot).

@export var weapon_name: String = "Weapon"
@export var damage: float = 20.0          # total per trigger pull (split over pellets)
@export var rpm: float = 600.0
@export var mag_size: int = 30
@export var reload_time: float = 2.0
@export var effective_range: float = 30.0
@export var pellets: int = 1
@export var spread_degrees: float = 0.0
@export var headshot_mult: float = 1.0
@export var automatic: bool = false

signal state_changed                       # ammo / reload changed

var ammo: int = 0
var _cooldown: float = 0.0
var _reloading: bool = false
var _reload_left: float = 0.0


func _ready() -> void:
	ammo = mag_size


func tick(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta
	if _reloading:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_reloading = false
			ammo = mag_size
			state_changed.emit()


func is_reloading() -> bool:
	return _reloading


func can_fire() -> bool:
	return not _reloading and _cooldown <= 0.0 and ammo > 0


## Fire one shot (all pellets). Returns the list of {collider, headshot, damage}
## for hits. Applies damage to anything with take_damage().
func fire(origin: Vector3, direction: Vector3, world: World3D, exclude: Array = []) -> Array:
	if not can_fire():
		return []
	ammo -= 1
	_cooldown = 60.0 / rpm
	var per_pellet := damage / float(max(1, pellets))
	var results: Array = []
	var space := world.direct_space_state
	for i in pellets:
		var dir := _apply_spread(direction)
		var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * effective_range, 1)
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var collider: Object = hit["collider"]
		if collider != null and collider.has_method("take_damage"):
			var dmg := per_pellet
			var head := false
			if collider.has_method("is_headshot") and collider.is_headshot(hit["position"]):
				dmg *= headshot_mult
				head = true
			collider.take_damage(dmg)
			results.append({"collider": collider, "headshot": head, "damage": dmg})
	state_changed.emit()
	return results


func start_reload() -> void:
	if _reloading or ammo >= mag_size:
		return
	_reloading = true
	_reload_left = reload_time
	state_changed.emit()


func cancel_reload() -> void:
	if _reloading:
		_reloading = false
		state_changed.emit()


func _apply_spread(direction: Vector3) -> Vector3:
	if spread_degrees <= 0.0:
		return direction
	var half := deg_to_rad(spread_degrees) * 0.5
	# Random tilt within a cone around `direction`.
	var cone_basis := Basis.looking_at(direction, Vector3.UP)
	var ang := randf() * TAU
	var mag := randf() * half
	var local := Vector3(sin(mag) * cos(ang), sin(mag) * sin(ang), -cos(mag))
	return (cone_basis * local).normalized()

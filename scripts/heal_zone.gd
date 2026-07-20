class_name HealZone
extends Node3D

## Lingering healing field left by the Support grenade (T-0024). Restores
## `heal_per_second` to the player while they stand inside `radius`, for
## `duration` seconds, then frees itself.
##
## Healing is capped at the player's max HP (including the Support class
## bonus), so it tops up to 150 for a Support Guardian rather than 100.

var radius: float = 5.0
var duration: float = 5.0
var heal_per_second: float = 10.0
var tint: Color = Color(0.35, 0.95, 0.55)

## Total HP actually restored — exposed for tests.
var healed: float = 0.0

var _life: float = 0.0
var _mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("heal_zone")
	_build_visual()


func _physics_process(delta: float) -> void:
	_life += delta
	if _life >= duration:
		queue_free()
		return
	# Fade out over the zone's lifetime so its remaining time is readable.
	if _mat:
		_mat.albedo_color = Color(tint, lerpf(0.28, 0.04, _life / duration))

	var player := get_tree().get_first_node_in_group("player")
	if player == null or not (player is Node3D):
		return
	if player.get("is_dead"):
		return
	var flat: Vector3 = (player as Node3D).global_position - global_position
	flat.y = 0.0
	if flat.length() > radius:
		return
	var max_hp: float = player.max_hp() if player.has_method("max_hp") else 100.0
	var before: float = player.health
	player.health = minf(max_hp, player.health + heal_per_second * delta)
	healed += player.health - before
	if player.health != before and player.has_signal("health_changed"):
		player.health_changed.emit(player.health, max_hp)


func _build_visual() -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.15
	mi.mesh = cyl
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(tint, 0.28)
	_mat.emission_enabled = true
	_mat.emission = tint
	_mat.emission_energy_multiplier = 2.0
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = _mat
	mi.position = Vector3(0, 0.08, 0)
	add_child(mi)

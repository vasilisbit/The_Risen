class_name LavaEruption
extends Node3D

## Ember Tyrant phase C environmental hazard (T-0021). A column of lava erupts
## at one of the arena's 8 eruption markers and burns for DURATION seconds,
## dealing DPS damage per second to the player inside RADIUS. Telegraphed by a
## short warning flash before it goes live, so it is dodgeable rather than a
## surprise tax. Frees itself when it burns out.

const DPS := 50.0
const RADIUS := 3.0
const DURATION := 4.0
const WARNING := 1.0             # s of telegraph before damage starts
const LAVA_COLOR := Color(1.0, 0.35, 0.05)

var _life: float = 0.0
var _mesh: MeshInstance3D
var _mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("lava_eruption")
	_build_visual()


func _physics_process(delta: float) -> void:
	_life += delta
	if _life >= WARNING + DURATION:
		queue_free()
		return

	if _life < WARNING:
		# Telegraph: a flat pulsing disc marking where it is about to erupt.
		var wave := 0.5 - 0.5 * cos(TAU * _life / WARNING * 3.0)
		_mat.emission_energy_multiplier = lerpf(1.0, 4.0, wave)
		_mesh.scale = Vector3(1.0, 0.05, 1.0)
		return

	_mesh.scale = Vector3(1.0, 1.0, 1.0)
	_mat.emission_energy_multiplier = 5.0
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("take_damage"):
		return
	var flat := (player as Node3D).global_position - global_position
	flat.y = 0.0
	if flat.length() <= RADIUS:
		player.take_damage(DPS * delta, "LavaEruption")


## True while the column is actually burning (past its telegraph).
func is_active() -> bool:
	return _life >= WARNING and _life < WARNING + DURATION


func _build_visual() -> void:
	_mesh = MeshInstance3D.new()
	var col := CylinderMesh.new()
	col.top_radius = RADIUS
	col.bottom_radius = RADIUS
	col.height = 5.0
	_mesh.mesh = col
	_mesh.position = Vector3(0, 2.5, 0)
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(LAVA_COLOR, 0.45)
	_mat.emission_enabled = true
	_mat.emission = LAVA_COLOR
	_mat.emission_energy_multiplier = 1.0
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh.material_override = _mat
	_mesh.scale = Vector3(1.0, 0.05, 1.0)
	add_child(_mesh)

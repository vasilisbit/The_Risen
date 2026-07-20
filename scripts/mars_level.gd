extends StaticBody3D
## T-0015 Mars mission blockout, generated in code. A low-gravity platforming
## section (15 platforms, 8 checkpoints, fall kill-plane, gravity Area3D scaling
## the player to 0.4 g) leads into three 15x15 wave rooms joined by portal
## doorways (8 spawn markers each). Red-rock materials. Bakes the parent
## NavigationRegion3D at runtime (the rooms are the walkable combat space).

const T := 0.5
const Y_ROOM := 7.0                 # room floor top / platforming end height

# Platform centres (start -> up toward the rooms). ~5-7 m gaps; low gravity
# makes them easily clearable, and a miss respawns at the last checkpoint.
const PLATFORMS: Array[Vector3] = [
	Vector3(0, 0, 4), Vector3(3, 0.5, -4), Vector3(-3, 1, -12), Vector3(3, 1.5, -20),
	Vector3(-3, 2, -28), Vector3(3, 2.5, -36), Vector3(-3, 3, -44), Vector3(0, 3.5, -54),
	Vector3(3, 4, -62), Vector3(-3, 4.5, -70), Vector3(3, 5, -78), Vector3(-3, 5.5, -86),
	Vector3(0, 6, -96), Vector3(3, 6.5, -104), Vector3(0, 7, -112),
]
const CHECKPOINT_INDICES := [0, 2, 4, 6, 8, 10, 12, 14]     # 8 checkpoints

var _rock: StandardMaterial3D
var _rock2: StandardMaterial3D
var _portal: StandardMaterial3D


func _ready() -> void:
	_rock = _mat(Color(0.50, 0.22, 0.15), 0.0, 0.9)
	_rock2 = _mat(Color(0.40, 0.17, 0.12), 0.1, 0.85)
	_portal = _mat(Color(0.2, 0.4, 1.0), 0.0, 0.3, true, Color(0.3, 0.5, 1.0), 2.5)

	_build_platforms()
	_build_gravity_zone()
	_build_checkpoints()
	_build_kill_plane()
	_build_rooms()
	_build_lights()

	var region := get_parent()
	if region is NavigationRegion3D and region.navigation_mesh != null:
		region.bake_navigation_mesh(false)


func _build_platforms() -> void:
	for i in PLATFORMS.size():
		var size := Vector3(6, T, 6) if i == 0 else Vector3(3, T, 3)
		_box(PLATFORMS[i], size, _rock)


func _build_gravity_zone() -> void:
	# Covers the platforming volume only (ends before Room 1 at z=-114).
	var a := _area(Vector3(0, 7, -50.5), Vector3(26, 45, 125))
	a.body_entered.connect(_on_gravity_entered)
	a.body_exited.connect(_on_gravity_exited)


func _on_gravity_entered(body: Node) -> void:
	if body.is_in_group("player") and ("gravity_scale" in body):
		body.gravity_scale = 0.4


func _on_gravity_exited(body: Node) -> void:
	if body.is_in_group("player") and ("gravity_scale" in body):
		body.gravity_scale = 1.0


func _build_checkpoints() -> void:
	for idx in CHECKPOINT_INDICES:
		var respawn: Vector3 = PLATFORMS[idx] + Vector3(0, 1.5, 0)
		var a := _area(respawn, Vector3(4, 3, 4))
		a.body_entered.connect(_on_checkpoint.bind(respawn))


func _on_checkpoint(body: Node, respawn: Vector3) -> void:
	if body.is_in_group("player") and body.has_method("set_checkpoint"):
		body.set_checkpoint(respawn)


func _build_kill_plane() -> void:
	var a := _area(Vector3(0, -12, -54), Vector3(70, 2, 132))
	a.body_entered.connect(_on_kill_plane)


func _on_kill_plane(body: Node) -> void:
	if body.is_in_group("player") and body.has_method("fall_respawn"):
		body.fall_respawn()


# --- 3 wave rooms (15x15) in a row, joined by 3 m portal doorways ---
func _build_rooms() -> void:
	# One long floor + ceiling + side walls spanning all three rooms.
	_box(Vector3(0, Y_ROOM - T * 0.5, -136.5), Vector3(15, T, 45), _rock2)
	_box(Vector3(0, Y_ROOM + 5 + T * 0.5, -136.5), Vector3(15, T, 45), _rock2)
	_box(Vector3(-7.5, Y_ROOM + 2.5, -136.5), Vector3(T, 5, 45), _rock)
	_box(Vector3(7.5, Y_ROOM + 2.5, -136.5), Vector3(T, 5, 45), _rock)
	# Cross-walls with 3 m doorways at the entrance and between rooms.
	_door_wall(-114.0, true)      # platforming -> Room 1
	_door_wall(-129.0, true)      # Room 1 -> Room 2 (portal)
	_door_wall(-144.0, true)      # Room 2 -> Room 3 (portal)
	_door_wall(-159.0, false)     # Room 3 far wall (solid end)
	# 8 spawn markers per room.
	_room_markers(-121.5)
	_room_markers(-136.5)
	_room_markers(-151.5)


func _door_wall(z: float, has_door: bool) -> void:
	if not has_door:
		_box(Vector3(0, Y_ROOM + 2.5, z), Vector3(15, 5, T), _rock)
		return
	_box(Vector3(-5.25, Y_ROOM + 2.5, z), Vector3(4.5, 5, T), _rock)      # left of door
	_box(Vector3(5.25, Y_ROOM + 2.5, z), Vector3(4.5, 5, T), _rock)       # right of door
	_box(Vector3(0, Y_ROOM + 4, z), Vector3(3, 2, T), _rock)             # lintel
	# Blue portal panel filling the doorway (visual only - no collision).
	_panel(Vector3(0, Y_ROOM + 1.5, z), Vector3(3, 3, 0.08), _portal)


func _room_markers(cz: float) -> void:
	var offs := [Vector3(-4, 0, -4), Vector3(0, 0, -4), Vector3(4, 0, -4), Vector3(-5, 0, 0),
		Vector3(5, 0, 0), Vector3(-4, 0, 4), Vector3(0, 0, 4), Vector3(4, 0, 4)]
	for o in offs:
		_marker(Vector3(0, Y_ROOM + 0.1, cz) + o, "spawn_point")


func _build_lights() -> void:
	var sun := DirectionalLight3D.new()          # dusty red-orange Mars sun
	sun.rotation = Vector3(-0.9, -0.6, 0)
	sun.light_energy = 1.0
	sun.light_color = Color(1.0, 0.7, 0.5)
	sun.shadow_enabled = true
	add_child(sun)
	for cz in [-121.5, -136.5, -151.5]:
		_omni(Vector3(0, Y_ROOM + 4, cz), 16, 1.6, Color(1.0, 0.6, 0.45))


func _box(center: Vector3, size: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = mat
	mesh.position = center
	add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = center
	add_child(col)
	return mesh


func _panel(center: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = mat
	mesh.position = center
	add_child(mesh)


func _area(center: Vector3, size: Vector3) -> Area3D:
	var a := Area3D.new()
	a.position = center
	a.collision_mask = 1
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	a.add_child(col)
	add_child(a)
	return a


func _marker(pos: Vector3, group_name: String) -> void:
	var m := Marker3D.new()
	m.position = pos
	m.add_to_group(group_name, true)
	add_child(m)


func _omni(pos: Vector3, range_m: float, energy: float, color: Color) -> void:
	var light := OmniLight3D.new()
	light.position = pos
	light.omni_range = range_m
	light.light_energy = energy
	light.light_color = color
	add_child(light)


func _mat(color: Color, metallic: float, roughness: float, emission := false, em := Color.BLACK, em_energy := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	if emission:
		m.emission_enabled = true
		m.emission = em
		m.emission_energy_multiplier = em_energy
	return m

extends StaticBody3D
## T-0012 Earth mission blockout, generated in code (like the hub). Three linear
## zones - Street (open), Subway (enclosed, dark), Rooftop (raised, reached by a
## ramp) - ending in a 20x20 m boss arena with 4 cover crates. Geometry is
## BoxMesh + BoxShape3D; 30 spawn markers (group "spawn_point"), a player spawn
## and a boss spawn, interior/overcast lighting. Bakes the parent
## NavigationRegion3D at runtime so AI pathfinding is ready across all zones.

const T := 0.4                    # wall / slab thickness

var _wall: StandardMaterial3D
var _floor: StandardMaterial3D
var _prop: StandardMaterial3D
var _crate: StandardMaterial3D


func _ready() -> void:
	_wall = _mat(Color(0.30, 0.30, 0.33), 0.0, 0.9)
	_floor = _mat(Color(0.22, 0.22, 0.24), 0.1, 0.8)
	_prop = _mat(Color(0.18, 0.20, 0.22), 0.3, 0.7)
	_crate = _mat(Color(0.35, 0.32, 0.12), 0.5, 0.6)

	_build_street()
	_build_subway()
	_build_ramp()
	_build_rooftop()
	_build_arena()
	_build_lights()
	_build_spawns()
	_marker(Vector3(0, 1.0, 5.0), "player_spawn")
	_marker(Vector3(0, 3.1, -85.0), "boss_spawn")

	var region := get_parent()
	if region is NavigationRegion3D and region.navigation_mesh != null:
		region.bake_navigation_mesh(false)


# --- Zone 1: Street (open top), x[-8,8], z[+8,-18] ---
func _build_street() -> void:
	_box(Vector3(0, -0.2, -5), Vector3(16, T, 26), _floor)
	_box(Vector3(-8, 3, -5), Vector3(T, 6, 26), _wall)
	_box(Vector3(8, 3, -5), Vector3(T, 6, 26), _wall)
	_box(Vector3(0, 3, 8), Vector3(16, 6, T), _wall)                 # back wall
	# front wall to subway with a 4 m doorway (x[-2,2])
	_box(Vector3(-5, 3, -18), Vector3(6, 6, T), _wall)
	_box(Vector3(5, 3, -18), Vector3(6, 6, T), _wall)
	_box(Vector3(0, 5, -18), Vector3(4, 2, T), _wall)               # lintel over door
	# abandoned-car cover
	_box(Vector3(-4, 0.5, 0), Vector3(2, 1, 4), _prop)
	_box(Vector3(3, 0.5, -8), Vector3(2, 1, 4), _prop)
	_box(Vector3(-3, 0.5, -14), Vector3(2, 1, 4), _prop)


# --- Zone 2: Subway (enclosed), x[-4,4], z[-18,-44] ---
func _build_subway() -> void:
	_box(Vector3(0, -0.2, -31), Vector3(8, T, 26), _floor)
	_box(Vector3(-4, 2, -31), Vector3(T, 4, 26), _wall)
	_box(Vector3(4, 2, -31), Vector3(T, 4, 26), _wall)
	_box(Vector3(0, 4.2, -31), Vector3(8, T, 26), _wall)            # ceiling
	# front wall to ramp with a 4 m doorway
	_box(Vector3(-3, 2, -44), Vector3(2, 4, T), _wall)
	_box(Vector3(3, 2, -44), Vector3(2, 4, T), _wall)


# --- Ramp: subway floor (y0, z-44) up to rooftop (y3, z-50) ---
func _build_ramp() -> void:
	_box(Vector3(0, 1.5, -47), Vector3(4, T, 6.8), _floor, Vector3(atan2(3.0, 6.0), 0, 0))


# --- Zone 3: Rooftop (raised y3), x[-8,8], z[-50,-70] ---
func _build_rooftop() -> void:
	_box(Vector3(0, 2.8, -60), Vector3(16, T, 20), _floor)
	_box(Vector3(-8, 3.6, -60), Vector3(T, 1.2, 20), _wall)        # parapets
	_box(Vector3(8, 3.6, -60), Vector3(T, 1.2, 20), _wall)


# --- Boss Arena 20x20 (y3), x[-10,10], z[-70,-90] + 4 crates ---
func _build_arena() -> void:
	_box(Vector3(0, 2.8, -80), Vector3(20, T, 20), _floor)
	_box(Vector3(-10, 4.5, -80), Vector3(T, 3, 20), _wall)
	_box(Vector3(10, 4.5, -80), Vector3(T, 3, 20), _wall)
	_box(Vector3(0, 4.5, -90), Vector3(20, 3, T), _wall)          # back wall
	for pos in [Vector3(-5, 4.25, -76), Vector3(5, 4.25, -76), Vector3(-5, 4.25, -84), Vector3(5, 4.25, -84)]:
		var c := _box(pos, Vector3(2.5, 2.5, 2.5), _crate)
		c.add_to_group("cover_crate", true)


func _build_lights() -> void:
	var sun := DirectionalLight3D.new()          # weak overcast sun
	sun.rotation = Vector3(-1.1, -0.5, 0)
	sun.light_energy = 0.6
	sun.light_color = Color(0.85, 0.87, 0.9)
	sun.shadow_enabled = true
	add_child(sun)
	# fill lights for the enclosed subway + arena
	_omni(Vector3(0, 3.6, -24), 14, 1.4, Color(0.7, 0.8, 0.9))
	_omni(Vector3(0, 3.6, -38), 14, 1.4, Color(0.7, 0.8, 0.9))
	_omni(Vector3(0, 5.5, -80), 20, 1.4, Color(0.85, 0.88, 0.95))


func _build_spawns() -> void:
	# Zone 1 Street (10), y ~0.1
	# Kept clear of the player spawn (0,1,5) so nothing aggros at spawn-in.
	var street := [Vector3(-6, 0.1, -7), Vector3(6, 0.1, -7), Vector3(-3, 0.1, -10), Vector3(4, 0.1, -10),
		Vector3(-6, 0.1, -13), Vector3(3, 0.1, -13), Vector3(-4, 0.1, -16), Vector3(6, 0.1, -16),
		Vector3(0, 0.1, -17), Vector3(-2, 0.1, -17)]
	# Zone 2 Subway (10), y ~0.1
	var subway := [Vector3(-3, 0.1, -20), Vector3(3, 0.1, -22), Vector3(0, 0.1, -25), Vector3(-3, 0.1, -28),
		Vector3(3, 0.1, -31), Vector3(-2, 0.1, -34), Vector3(2, 0.1, -36), Vector3(-3, 0.1, -39),
		Vector3(3, 0.1, -41), Vector3(0, 0.1, -43)]
	# Zone 3 Rooftop (10), y ~3.1
	var rooftop := [Vector3(-6, 3.1, -52), Vector3(6, 3.1, -53), Vector3(-2, 3.1, -56), Vector3(5, 3.1, -58),
		Vector3(-5, 3.1, -61), Vector3(2, 3.1, -63), Vector3(-6, 3.1, -66), Vector3(6, 3.1, -67),
		Vector3(0, 3.1, -69), Vector3(-3, 3.1, -68)]
	for p in street:
		_marker(p, "spawn_point")
	for p in subway:
		_marker(p, "spawn_point")
	for p in rooftop:
		_marker(p, "spawn_point")


func _box(center: Vector3, size: Vector3, mat: StandardMaterial3D, rot := Vector3.ZERO) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = mat
	mesh.position = center
	mesh.rotation = rot
	add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = center
	col.rotation = rot
	add_child(col)
	return mesh


func _omni(pos: Vector3, range_m: float, energy: float, color: Color) -> void:
	var light := OmniLight3D.new()
	light.position = pos
	light.omni_range = range_m
	light.light_energy = energy
	light.light_color = color
	add_child(light)


func _marker(pos: Vector3, group_name: String) -> void:
	var m := Marker3D.new()
	m.position = pos
	m.add_to_group(group_name, true)
	add_child(m)


func _mat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m

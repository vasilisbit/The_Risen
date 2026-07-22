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
	_build_kill_plane()
	_marker(Vector3(0, 1.0, 5.0), "player_spawn")
	_marker(Vector3(0, 3.1, -85.0), "boss_spawn")

	var region := get_parent()
	if region is NavigationRegion3D and region.navigation_mesh != null:
		region.bake_navigation_mesh(false)


## Falling off the map kills you and respawns you at the last checkpoint. Sits
## well below the lowest floor and spans the whole level footprint.
func _build_kill_plane() -> void:
	var a := Area3D.new()
	a.position = Vector3(0, -12, -40)
	a.collision_mask = 1
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(80, 3, 130)
	col.shape = shape
	a.add_child(col)
	a.body_entered.connect(_on_kill_plane)
	add_child(a)


func _on_kill_plane(body: Node) -> void:
	if body.is_in_group("player") and body.has_method("fall_to_death"):
		body.fall_to_death()


# --- Zone 1: Street (open top), x[-12,12], z[+8,-18], taller walls ---
func _build_street() -> void:
	_box(Vector3(0, -0.2, -5), Vector3(24, T, 26), _floor)
	_box(Vector3(-12, 4.5, -5), Vector3(T, 9, 26), _wall)
	_box(Vector3(12, 4.5, -5), Vector3(T, 9, 26), _wall)
	_box(Vector3(0, 4.5, 8), Vector3(24, 9, T), _wall)              # back wall
	# front wall to subway with a 4 m doorway (x[-2,2])
	_box(Vector3(-7, 4.5, -18), Vector3(10, 9, T), _wall)
	_box(Vector3(7, 4.5, -18), Vector3(10, 9, T), _wall)
	_box(Vector3(0, 6.5, -18), Vector3(4, 5, T), _wall)             # lintel over door
	# abandoned-car + barricade cover, spread across the wider street
	_box(Vector3(-4, 0.5, 0), Vector3(2, 1, 4), _prop)
	_box(Vector3(3, 0.5, -8), Vector3(2, 1, 4), _prop)
	_box(Vector3(-3, 0.5, -14), Vector3(2, 1, 4), _prop)
	_box(Vector3(8, 0.7, -3), Vector3(2.4, 1.4, 2.4), _crate)
	_box(Vector3(-8, 0.7, -11), Vector3(2.4, 1.4, 2.4), _crate)
	_box(Vector3(6, 0.6, -15), Vector3(3, 1.2, 1), _prop)           # low barricade
	_box(Vector3(-9, 1.5, -6), Vector3(1, 3, 1), _wall)             # pillar
	_box(Vector3(9, 1.5, -13), Vector3(1, 3, 1), _wall)


# --- Zone 2: Subway (enclosed), x[-6,6], z[-18,-44], higher ceiling + pillars ---
func _build_subway() -> void:
	_box(Vector3(0, -0.2, -31), Vector3(12, T, 26), _floor)
	_box(Vector3(-6, 2.75, -31), Vector3(T, 5.5, 26), _wall)
	_box(Vector3(6, 2.75, -31), Vector3(T, 5.5, 26), _wall)
	_box(Vector3(0, 5.5, -31), Vector3(12, T, 26), _wall)           # ceiling
	# front wall to ramp with a 4 m doorway
	_box(Vector3(-4, 2.75, -44), Vector3(4, 5.5, T), _wall)
	_box(Vector3(4, 2.75, -44), Vector3(4, 5.5, T), _wall)
	_box(Vector3(0, 4.5, -44), Vector3(4, 2, T), _wall)             # lintel
	# support pillars + platform cover to break up the corridor
	_box(Vector3(-4, 1.5, -24), Vector3(1.2, 3, 1.2), _prop)
	_box(Vector3(4, 1.5, -30), Vector3(1.2, 3, 1.2), _prop)
	_box(Vector3(-4, 1.5, -38), Vector3(1.2, 3, 1.2), _prop)
	_box(Vector3(3.5, 0.6, -34), Vector3(2.5, 1.2, 2), _crate)
	_box(Vector3(-3.5, 0.6, -27), Vector3(2.5, 1.2, 2), _crate)


# --- Ramp: subway floor (y0, z-44) up to rooftop (y3, z-50) ---
func _build_ramp() -> void:
	_box(Vector3(0, 1.5, -47), Vector3(4, T, 6.8), _floor, Vector3(atan2(3.0, 6.0), 0, 0))


# --- Zone 3: Rooftop (raised y3), x[-12,12], z[-50,-70], with rooftop clutter ---
func _build_rooftop() -> void:
	_box(Vector3(0, 2.8, -60), Vector3(24, T, 20), _floor)
	_box(Vector3(-12, 4.0, -60), Vector3(T, 2.0, 20), _wall)       # taller parapets
	_box(Vector3(12, 4.0, -60), Vector3(T, 2.0, 20), _wall)
	# AC units / vents as cover
	_box(Vector3(-6, 3.7, -55), Vector3(3, 1.8, 3), _prop)
	_box(Vector3(6, 3.7, -62), Vector3(3, 1.8, 3), _prop)
	_box(Vector3(0, 3.5, -58), Vector3(2, 1.4, 5), _crate)
	_box(Vector3(-7, 3.4, -66), Vector3(2, 1.2, 2), _crate)
	_box(Vector3(7, 3.4, -52), Vector3(2, 1.2, 2), _crate)


# --- Boss Arena 26x22 (y3), x[-13,13], z[-69,-91] + 6 crates ---
func _build_arena() -> void:
	_box(Vector3(0, 2.8, -80), Vector3(26, T, 22), _floor)
	_box(Vector3(-13, 5.0, -80), Vector3(T, 4, 22), _wall)
	_box(Vector3(13, 5.0, -80), Vector3(T, 4, 22), _wall)
	_box(Vector3(0, 5.0, -91), Vector3(26, 4, T), _wall)          # back wall (open to rooftop at the front)
	for pos in [Vector3(-6, 3.0, -75), Vector3(6, 3.0, -75), Vector3(-6, 3.0, -85), Vector3(6, 3.0, -85),
			Vector3(-10, 3.0, -80), Vector3(10, 3.0, -80)]:
		_cover_crate(pos)


## A real crate model as cover, with a matching collision box, in the
## "cover_crate" group the Shooter AI reads. `base` is the point on the floor
## the crate sits on.
const PROP_DIR := "res://assets/thirdparty/Sci-Fi Essentials Kit[Standard]/glTF/"

func _cover_crate(base: Vector3) -> void:
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.1, 2.1, 2.1)
	col.shape = shape
	col.position = base + Vector3(0, 1.05, 0)
	add_child(col)
	var scene := load(PROP_DIR + "Prop_Crate.gltf")
	if scene is PackedScene:
		var m := (scene as PackedScene).instantiate() as Node3D
		m.scale = Vector3.ONE * 1.35        # ~2.1 m crate
		m.position = base
		m.add_to_group("cover_crate", true)
		add_child(m)


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

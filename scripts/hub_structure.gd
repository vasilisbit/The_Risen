extends StaticBody3D
## T-0006 hub blockout: builds a 2-room starship interior in code —
## Cockpit 10x10 m (with a 5x3 m viewport window) joined by a 3 m doorway to a
## Weapon Bay 8x8 m — plus interior lighting. Geometry is BoxMesh + BoxShape3D
## parented to this StaticBody3D. Meant to sit under a NavigationRegion3D, which
## this script bakes at runtime so AI pathfinding is ready.

const H := 4.0      # interior height
const T := 0.3      # wall / slab thickness


func _ready() -> void:
	var wall := _mat(Color(0.20, 0.22, 0.28), 0.0, 0.85)
	var floor_mat := _mat(Color(0.13, 0.14, 0.17), 0.1, 0.7)
	var glass := _mat(Color(0.10, 0.25, 0.60), 0.0, 0.2, true, Color(0.20, 0.45, 1.0), 1.4)

	# --- Cockpit 10x10, centered at origin (X[-5,5], Z[-5,5]) ---
	_box(Vector3(0, -T * 0.5, 0), Vector3(10, T, 10), floor_mat)     # floor
	_box(Vector3(0, H + T * 0.5, 0), Vector3(10, T, 10), wall)       # ceiling
	_box(Vector3(-5, H * 0.5, 0), Vector3(T, H, 10), wall)          # left wall
	_box(Vector3(5, H * 0.5, 0), Vector3(T, H, 10), wall)           # right wall
	# front wall Z=-5 with a 5x3 window opening (X[-2.5,2.5], y[1,4])
	_box(Vector3(0, 0.5, -5), Vector3(10, 1.0, T), wall)            # sill strip
	_box(Vector3(-3.75, 2.5, -5), Vector3(2.5, 3.0, T), wall)       # left of window
	_box(Vector3(3.75, 2.5, -5), Vector3(2.5, 3.0, T), wall)        # right of window
	_box(Vector3(0, 2.5, -5), Vector3(5.0, 3.0, 0.06), glass)       # window pane (solid)
	# back wall Z=5 with a 3 m doorway (X[-1.5,1.5], y[0,3])
	_box(Vector3(-3.25, H * 0.5, 5), Vector3(3.5, H, T), wall)      # left of door
	_box(Vector3(3.25, H * 0.5, 5), Vector3(3.5, H, T), wall)       # right of door
	_box(Vector3(0, 3.5, 5), Vector3(3.0, 1.0, T), wall)           # lintel over door

	# --- Weapon Bay 8x8, centered at (0,0,9) (X[-4,4], Z[5,13]) ---
	_box(Vector3(0, -T * 0.5, 9), Vector3(8, T, 8), floor_mat)      # floor
	_box(Vector3(0, H + T * 0.5, 9), Vector3(8, T, 8), wall)        # ceiling
	_box(Vector3(-4, H * 0.5, 9), Vector3(T, H, 8), wall)          # left wall
	_box(Vector3(4, H * 0.5, 9), Vector3(T, H, 8), wall)           # right wall
	_box(Vector3(0, H * 0.5, 13), Vector3(8, H, T), wall)          # back wall
	# (the bay's front side is the cockpit's back wall + doorway above)

	# --- Interior lighting (no dark zones): cool ambient + warm vendor spot ---
	_omni(Vector3(0, 3.5, 0), 18.0, 2.2, Color(0.80, 0.85, 1.0))
	_omni(Vector3(0, 3.5, 9), 16.0, 2.2, Color(0.85, 0.90, 1.0))
	_omni(Vector3(0, 2.8, 10.5), 9.0, 2.6, Color(1.0, 0.80, 0.50))  # warm vendor

	var region := get_parent()
	if region is NavigationRegion3D and region.navigation_mesh != null:
		region.bake_navigation_mesh(false)


func _box(center: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
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

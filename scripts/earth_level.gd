extends StaticBody3D
## Earth mission - a ruined-city combat level ASSEMBLED from fal.ai Tripo P1
## environment chunks (assets/generated/earth/chunks/, one cohesive weathered-
## concrete style) laid out over a built street that runs into a boss plaza.
##
## Each Tripo chunk is unit-cube normalized, so it's uniformly scaled to a target
## size (metres) and auto-seated on the ground (y=0) from its measured world AABB.
## Chunks keep their own PBR textures; the road/ground uses the fal.ai flat-albedo
## textures via triplanar. Trimesh collision per chunk + the ground; the parent
## NavigationRegion3D is baked so enemies path the street. Player spawn, enemy
## spawn_point markers, the Archive Core and the boss are placed along the route
## (earth_mission drives the zone waves off the same z-bands as before).

const CHUNK := "res://assets/generated/earth/chunks/%s.glb"
const GEN_TEX := "res://assets/generated/earth/%s.png"

# [name, x, z, rot_y°, target_size(m)]. Buildings line the street at x=±12–14,
# facing inward; props are roadway cover (x within ±6); the plaza/boss is far -Z.
const BUILDINGS := [
	["apartment_block", -12.0, 2.0, 90, 14.0],
	["shopfront_row", 13.0, 0.0, -90, 16.0],
	["office_ruin", -13.0, -18.0, 90, 14.0],
	["apartment_block", 13.0, -20.0, -90, 13.0],
	["tower", -13.0, -38.0, 90, 18.0],
	["office_ruin", 13.0, -40.0, -90, 14.0],
	["shopfront_row", -14.0, -56.0, 90, 15.0],
	["tower", 14.0, -56.0, -90, 16.0],
]
const PROPS := [
	["barricade", 0.0, -6.0, 0, 4.5],
	["streetlight_props", 5.0, -12.0, 30, 4.0],
	["wrecked_car", -4.0, -18.0, 40, 4.0],
	["rubble_pile", 5.0, -28.0, 0, 4.5],
	["wall_section", -3.5, -34.0, 20, 4.0],
	["wrecked_car", 4.0, -44.0, -30, 4.0],
	["rubble_pile", -5.0, -48.0, 0, 4.0],
	["barricade", 0.0, -52.0, 0, 4.5],
]
const PLAZA := [
	["monument", 0.0, -68.0, 0, 7.0],
	["bunker", -9.0, -66.0, 40, 6.0],
	["bunker", 9.0, -66.0, -40, 6.0],
	["rubble_pile", -6.0, -73.0, 0, 4.0],
	["overpass", 0.0, -82.0, 0, 24.0],
]

const ARCHIVE_Z := -55.0
const BOSS_Z := -68.0

var _tex_cache: Dictionary = {}


func _ready() -> void:
	_build_ground()
	_build_lights()
	for row in BUILDINGS:
		_place_chunk(row)
	for row in PROPS:
		_place_chunk(row)
	for row in PLAZA:
		_place_chunk(row)
	_marker(Vector3(0, 1.0, 9.0), "player_spawn")
	_marker(Vector3(0, 1.0, BOSS_Z), "boss_spawn")
	_build_spawns()
	_build_kill_plane()

	var region := get_parent()
	if region is NavigationRegion3D and region.navigation_mesh != null:
		region.bake_navigation_mesh(false)


## Build + place one chunk: uniform-scale to target size (unit-cube max dim = 1),
## rotate, then seat its base on the ground (y=0) via its measured world AABB.
func _place_chunk(row: Array) -> void:
	var scene := load(CHUNK % String(row[0]))
	if scene == null:
		return
	var m := scene.instantiate() as Node3D
	add_child(m)
	m.rotation.y = deg_to_rad(float(row[3]))
	m.scale = Vector3.ONE * float(row[4])
	var ab := _world_aabb(m)                      # at position (0,0,0), post scale+rot
	m.position = Vector3(float(row[1]), -ab.position.y, float(row[2]))
	for node in m.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).create_trimesh_collision()   # solid, walkable-around


func _world_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var have := false
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var la := mi.get_aabb()
		var xf := mi.global_transform
		for i in 8:
			var corner := la.position + Vector3(
				la.size.x if (i & 1) else 0.0,
				la.size.y if (i & 2) else 0.0,
				la.size.z if (i & 4) else 0.0)
			var w: Vector3 = xf * corner
			if not have:
				result = AABB(w, Vector3.ZERO); have = true
			else:
				result = result.expand(w)
	return result


# --- ground: asphalt street strip over a concrete base, both triplanar-textured --

func _build_ground() -> void:
	_ground_box(Vector3(0, -0.3, -38), Vector3(44, 0.6, 108), "concrete", Color(0.85, 0.83, 0.80), 0.12)  # base/sidewalks
	_ground_box(Vector3(0, 0.02, -34), Vector3(17, 0.5, 92), "asphalt", Color(0.9, 0.9, 0.92), 0.16)      # road
	_ground_box(Vector3(0, 0.03, -72), Vector3(34, 0.5, 26), "rubble", Color(0.9, 0.85, 0.78), 0.2)       # plaza floor


func _ground_box(center: Vector3, size: Vector3, tex: String, tint: Color, scale: float) -> void:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = size
	mesh.mesh = bm
	mesh.position = center
	mesh.material_override = _tex_mat(tex, tint, scale)
	add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new(); shape.size = size
	col.shape = shape; col.position = center
	add_child(col)


func _tex_mat(tex: String, tint: Color, scale: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.roughness = 0.95
	if not _tex_cache.has(tex):
		var p: String = GEN_TEX % tex
		_tex_cache[tex] = load(p) if ResourceLoader.exists(p) else null
	var t: Texture2D = _tex_cache[tex]
	if t != null:
		m.albedo_texture = t
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(scale, scale, scale)
	return m


func _build_lights() -> void:
	var sun := DirectionalLight3D.new()          # bleak overcast war sky
	sun.rotation = Vector3(-1.0, -0.7, 0)
	sun.light_energy = 1.0
	sun.light_color = Color(0.86, 0.86, 0.9)
	sun.shadow_enabled = true
	add_child(sun)


# --- spawns: along the street, split into the z-zones earth_mission reads ---------

func _build_spawns() -> void:
	var zs := [-2.0, -10.0, -16.0, -24.0, -30.0, -38.0, -44.0, -50.0, -58.0, -64.0]
	var lanes := [-5.0, 0.0, 5.0]
	var i := 0
	for z in zs:
		var lane: float = lanes[i % lanes.size()]
		_marker(Vector3(lane, 0.5, z), "spawn_point")
		_marker(Vector3(-lane, 0.5, z - 3.0), "spawn_point")
		i += 1


func _build_kill_plane() -> void:
	var a := Area3D.new()
	a.position = Vector3(0, -10, -38)
	a.collision_mask = 1
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new(); shape.size = Vector3(80, 3, 130)
	col.shape = shape
	a.add_child(col)
	a.body_entered.connect(_on_kill_plane)
	add_child(a)


func _on_kill_plane(body: Node) -> void:
	if body.is_in_group("player") and body.has_method("fall_to_death"):
		body.fall_to_death()


func _marker(pos: Vector3, group_name: String) -> void:
	var m := Marker3D.new()
	m.position = pos
	m.add_to_group(group_name, true)
	add_child(m)

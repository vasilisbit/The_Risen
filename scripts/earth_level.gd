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
	_build_atmosphere()
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
	var sun := DirectionalLight3D.new()          # hazy low war sun through smoke
	sun.rotation = Vector3(-0.62, -0.85, 0)
	sun.light_energy = 0.9
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.shadow_enabled = true
	add_child(sun)


## Destiny-2 ruined-Earth mood: a hazy overcast sky, dusty fog so distant ruins
## fade into smoke, ACES tonemap and a touch of glow. Runtime WorldEnvironment
## (built here, not in Blender - atmosphere is a Godot feature).
func _build_atmosphere() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.48, 0.50, 0.55)
	sky_mat.sky_horizon_color = Color(0.66, 0.62, 0.55)      # dusty tan haze
	sky_mat.ground_horizon_color = Color(0.55, 0.51, 0.46)
	sky_mat.ground_bottom_color = Color(0.32, 0.30, 0.28)
	sky_mat.sun_angle_max = 25.0
	sky_mat.sun_curve = 0.08
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	# Dusty distance fog - ruins dissolve into smoke down the street.
	env.fog_enabled = true
	env.fog_light_color = Color(0.66, 0.62, 0.55)
	env.fog_light_energy = 0.9
	env.fog_density = 0.014
	env.fog_sky_affect = 0.35
	env.fog_aerial_perspective = 0.4
	# A little bloom on the sky/hotspots.
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.glow_bloom = 0.05

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


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

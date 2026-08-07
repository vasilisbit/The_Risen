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

# High-poly street buildings (regenerated via Tripo H3.1) get a cheap AABB box
# collider instead of per-mesh trimesh - see _place_chunk. Plaza structures + props
# stay trimesh (they sit in the play area and must be walkable-around).
const STRUCTURES := ["apartment_block", "tower", "shopfront_row", "office_ruin"]

var _tex_cache: Dictionary = {}


func _ready() -> void:
	_build_ground()
	_build_outskirts()
	_build_bounds()
	_build_fog_ring()
	_build_skyline()
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
	# The player's ship sits parked behind the spawn (up the street, away from the boss)
	# as a landmark + the extraction point (board it to leave).
	var ship := preload("res://scripts/landed_ship.gd").new()
	add_child(ship)
	ship.configure(Vector3(0, 0.0, 23.0), Vector3(0, 1.0, 9.0))
	ship.call_deferred("start_landing")     # arrival: the ship drops onto the pad
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
	if String(row[0]) in STRUCTURES:
		# high-poly street building: one cheap box collider from the seated AABB. Keeps
		# physics + navmesh bake fast (nav parses static colliders) vs trimeshing ~300k
		# tris; the player walks the street past these side facades, never inside them.
		var world := _world_aabb(m)
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		# inset the footprint (x/z) to 0.85 so building edges clear the x=+-5 enemy
		# spawn lanes; keep full height so the facade stays solid to shoot against.
		box.size = Vector3(world.size.x * 0.85, world.size.y, world.size.z * 0.85)
		col.shape = box
		col.position = world.position + world.size * 0.5
		add_child(col)
	else:
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


## Ground + roads spreading out under the skyline so the ruined city sits on real
## terrain (not floating over the void) now that the walls are invisible. Visual only -
## the player is contained by the barriers, so no collision/nav cost out here. A broad
## weathered-concrete slab (tucked just under the play-area ground) plus a grid of
## asphalt streets threading between the outer towers. Distance fog fades it all out.
func _build_outskirts() -> void:
	_deco_ground(Vector3(0, -0.5, -15), Vector3(440, 0.4, 580), "concrete", Color(0.80, 0.78, 0.74), 0.03)
	for x in [-95.0, -62.0, -32.0, 32.0, 62.0, 95.0]:       # north-south avenues
		_deco_ground(Vector3(x, -0.45, -45), Vector3(9, 0.4, 440), "asphalt", Color(0.9, 0.9, 0.92), 0.05)
	for z in [72.0, 34.0, -58.0, -112.0, -165.0]:           # east-west cross streets
		_deco_ground(Vector3(0, -0.45, z), Vector3(320, 0.4, 9), "asphalt", Color(0.9, 0.9, 0.92), 0.05)


func _deco_ground(center: Vector3, size: Vector3, tex: String, tint: Color, scale: float) -> void:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = size
	mesh.mesh = bm
	mesh.position = center
	mesh.material_override = _tex_mat(tex, tint, scale)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)


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
	var t: Texture2D = _gen_tex(tex)
	if t != null:
		m.albedo_texture = t
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(scale, scale, scale)
		# PATINA-generated PBR maps (fal-ai/patina, tools/falgen.py patina). Normal +
		# roughness are linear data; triplanar reuses uv1_scale automatically.
		var n: Texture2D = _gen_tex(tex + "_normal")
		if n != null:
			m.normal_enabled = true
			m.normal_texture = n
		var r: Texture2D = _gen_tex(tex + "_roughness")
		if r != null:
			m.roughness = 1.0  # scalar becomes a multiplier over the texture
			m.roughness_texture = r
			m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	return m


func _gen_tex(name: String) -> Texture2D:
	if not _tex_cache.has(name):
		var p: String = GEN_TEX % name
		_tex_cache[name] = load(p) if ResourceLoader.exists(p) else null
	return _tex_cache[name]


var _sun_dir: Vector3 = Vector3(0, 0.5, -0.8)     # direction TO the sun (for the sky)


func _build_lights() -> void:
	var sun := DirectionalLight3D.new()          # warm afternoon sun, low from the side
	sun.rotation = Vector3(deg_to_rad(-38), deg_to_rad(-125), 0)
	sun.light_energy = 1.35
	sun.light_color = Color(1.0, 0.90, 0.72)     # golden afternoon
	sun.shadow_enabled = true
	add_child(sun)
	_sun_dir = sun.global_transform.basis.z       # a Light faces -Z, so +Z points at the sun


## Afternoon ruined-Earth mood: warm hazy afternoon sky, light golden fog for depth
## (not a thick overcast), ACES tonemap + subtle glow. Runtime WorldEnvironment
## (built here, not in Blender - atmosphere is a Godot feature).
func _build_atmosphere() -> void:
	# Procedural cloud sky (shaders/earth_sky.gdshader) - drifting sunlit clouds over
	# a warm afternoon gradient, sun placed from the DirectionalLight direction.
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/earth_sky.gdshader")
	sky_mat.set_shader_parameter("sun_dir", _sun_dir)
	sky_mat.set_shader_parameter("top_color", Color(0.30, 0.47, 0.76))
	sky_mat.set_shader_parameter("horizon_color", Color(0.84, 0.77, 0.63))
	sky_mat.set_shader_parameter("sun_color", Color(1.0, 0.86, 0.62))
	sky_mat.set_shader_parameter("cloud_cover", 0.38)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.ambient_light_color = Color(0.9, 0.84, 0.72)         # warm bounce
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	# REAL volumetric fog, kept out of the play corridor and concentrated at STREET
	# LEVEL just beyond the invisible barriers via a ring of FogVolumes
	# (_build_fog_ring). The corridor stays clear; a faint global density gives gentle
	# far-distance fade. Sky shader owns the horizon (sky_affect 0) so fog never
	# climbs into the sky. (Plain depth fog off - it washed the whole vertical view.)
	env.fog_enabled = false
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0016            # faint global depth only; the street-
												   # level wall is the FogVolume ring below
	env.volumetric_fog_albedo = Color(0.87, 0.83, 0.75)
	env.volumetric_fog_emission = Color(0.0, 0.0, 0.0)
	env.volumetric_fog_length = 400.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_ambient_inject = 1.0
	env.volumetric_fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_bloom = 0.06

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


## Distant ruined-city skyline beyond the containment walls: silhouette skyscrapers
## (visual only, no collision, shadows off) so the street reads as part of a real
## bombed metropolis. Only the tops clear the 14 m walls; the afternoon haze / aerial
## perspective fades them into the sky. Seeded so the layout is reproducible. Many
## get a broken/stepped crown for a war-torn silhouette.
func _build_skyline() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260731
	# [x_min, x_max, z_min, z_max, count, h_min, h_max]. Dense enough on the back
	# hemisphere (behind/left/right of the z~9 spawn) that the horizon is fully walled
	# off in those directions - near rows + a tall far ring back-fill any gaps.
	var bands := [
		[-120.0, -24.0,   40.0, -150.0, 26, 22.0, 78.0],   # left flank (down the street)
		[  24.0, 120.0,   40.0, -150.0, 26, 22.0, 78.0],   # right flank
		[ -75.0,  75.0, -105.0, -215.0, 24, 34.0, 94.0],   # far skyline down the street
		[ -62.0,  62.0,   48.0,  150.0, 24, 46.0, 102.0],  # tall wall directly behind start
		[-150.0, -22.0,   28.0,  165.0, 28, 34.0,  94.0],  # left side + back-left (near->far)
		[  22.0, 150.0,   28.0,  165.0, 28, 34.0,  94.0],  # right side + back-right
		[-185.0, 185.0,  120.0,  235.0, 26, 52.0, 112.0],  # far outer back ring (gap filler)
		[-185.0, -95.0,  -60.0,  150.0, 16, 40.0, 100.0],  # deep left backdrop
		[  95.0, 185.0,  -60.0,  150.0, 16, 40.0, 100.0],  # deep right backdrop
	]
	for b in bands:
		for i in int(b[4]):
			var x: float = rng.randf_range(b[0], b[1])
			var z: float = rng.randf_range(b[2], b[3])
			var hgt: float = rng.randf_range(b[5], b[6])
			var w := Vector3(rng.randf_range(8.0, 20.0), hgt, rng.randf_range(8.0, 20.0))
			_skyline_box(Vector3(x, hgt * 0.5, z), w, rng)


func _skyline_box(center: Vector3, size: Vector3, rng: RandomNumberGenerator) -> void:
	# Windowed war-damaged facade (fal.ai nano-banana + PATINA) triplanar-mapped so
	# the distant towers read as real skyscrapers, with a per-building brightness/tint
	# jitter for variety. Falls back to a flat grey-blue tint if the texture is absent.
	var mat := StandardMaterial3D.new()
	mat.roughness = 1.0
	var facade: Texture2D = _gen_tex("skyscraper_facade")
	if facade != null:
		var v: float = rng.randf_range(0.72, 1.0)
		mat.albedo_texture = facade
		mat.albedo_color = Color(v, v * 1.02, v * 1.06)      # subtle cool jitter
		mat.uv1_triplanar = true
		mat.uv1_scale = Vector3(0.045, 0.045, 0.045)         # ~1 facade tile / 22 m
		var n: Texture2D = _gen_tex("skyscraper_facade_normal")
		if n != null:
			mat.normal_enabled = true
			mat.normal_texture = n
		var r: Texture2D = _gen_tex("skyscraper_facade_roughness")
		if r != null:
			mat.roughness_texture = r
			mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	else:
		var g: float = rng.randf_range(0.40, 0.60)
		mat.albedo_color = Color(g * 0.90, g * 0.96, g * 1.10)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = size
	mesh.mesh = bm
	mesh.position = center
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	if rng.randf() < 0.55:                                    # broken/stepped crown
		var tb := BoxMesh.new()
		tb.size = Vector3(size.x * rng.randf_range(0.3, 0.7),
			rng.randf_range(4.0, 16.0), size.z * rng.randf_range(0.3, 0.7))
		var top := MeshInstance3D.new()
		top.mesh = tb
		top.position = center + Vector3(rng.randf_range(-size.x * 0.25, size.x * 0.25),
			size.y * 0.5 + tb.size.y * 0.5, rng.randf_range(-size.z * 0.25, size.z * 0.25))
		top.material_override = mat
		top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(top)


## INVISIBLE containment barriers around the street corridor: the player is kept in
## but sees straight out over the outskirts + skyline (the old solid concrete walls
## are gone). Collision-only, no mesh - still parsed by the navmesh (static colliders)
## so enemies also stay in. Sides full length + end caps behind start and plaza.
func _build_bounds() -> void:
	_barrier(Vector3(-15.5, 6.5, -36), Vector3(0.6, 15, 112))
	_barrier(Vector3(15.5, 6.5, -36), Vector3(0.6, 15, 112))
	_barrier(Vector3(0, 6.5, 37), Vector3(48, 15, 0.6))      # behind start (moved back to fit the parked ship)
	_barrier(Vector3(0, 6.5, -87), Vector3(34, 15, 0.6))     # behind plaza


func _barrier(center: Vector3, size: Vector3) -> void:
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new(); shape.size = size
	col.shape = shape; col.position = center
	add_child(col)


## Street-level smog wall beyond the invisible barriers: a ring of box FogVolumes
## hugging the play corridor (real volumetric fog, dense at ground via height_falloff,
## soft edges). The corridor itself is left clear; each slab starts right at a barrier
## and extends outward across the outskirts, so the fog "begins at the walls" and
## thickens into the distance. Needs volumetric_fog_enabled on the environment.
func _build_fog_ring() -> void:
	# A shallower, lighter band hugging each barrier: enough to read as a street-level
	# smog wall at the perimeter, but sheer enough that the enclosing skyscrapers show
	# through it as silhouettes (rather than a solid grey blanket that hides them).
	var d := 0.11
	_fog_slab(Vector3(-52, 16, -36), Vector3(74, 32, 320), d)    # left of the corridor
	_fog_slab(Vector3(52, 16, -36), Vector3(74, 32, 320), d)     # right
	_fog_slab(Vector3(0, 16, 58), Vector3(360, 32, 88), d)       # in front of the start
	_fog_slab(Vector3(0, 16, -133), Vector3(360, 32, 92), d)     # behind the plaza


func _fog_slab(center: Vector3, size: Vector3, density: float) -> void:
	var fv := FogVolume.new()
	fv.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	fv.size = size
	fv.position = center
	var fm := FogMaterial.new()
	fm.density = density
	fm.albedo = Color(0.87, 0.83, 0.75)
	fm.height_falloff = 1.4          # concentrate the smog near the ground
	fm.edge_fade = 0.3               # soften the box edges so it reads as fog
	fv.material = fm
	add_child(fv)


# --- spawns: along the street, split into the z-zones earth_mission reads ---------

func _build_spawns() -> void:
	# 30 markers (earth_mission spawns one enemy per marker; the objective wants 30,
	# so fewer = the mission stalls before the Archive Core). Spread across the three
	# z-zones earth_mission reads, both lanes, kept clear of the player start (z~9).
	var zs := [-2.0, -6.0, -12.0, -16.0, -22.0, -26.0, -32.0, -36.0,
		-42.0, -46.0, -50.0, -54.0, -58.0, -62.0, -64.0]     # 15 * 2 lanes = 30
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

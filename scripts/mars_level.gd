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

const GEN_TEX := "res://assets/generated/mars/%s.png"
const ROCK := "res://assets/generated/mars/rocks/%s.glb"

var _rock: StandardMaterial3D
var _rock2: StandardMaterial3D
var _regolith: StandardMaterial3D
var _portal: StandardMaterial3D
var _tex_cache: Dictionary = {}
var _sun_dir: Vector3 = Vector3(0.4, 0.5, -0.7)     # direction TO the sun (for the sky)


func _ready() -> void:
	# fal.ai Mars PBR rock/regolith (nano-banana + PATINA) applied triplanar; falls
	# back to the old flat red-rock colours if the textures are absent.
	_rock = _mars_mat("rock", Color(0.95, 0.82, 0.74), 0.0, 0.95, 0.22)
	_rock2 = _mars_mat("rock", Color(0.72, 0.60, 0.54), 0.05, 0.9, 0.22)
	_regolith = _mars_mat("regolith", Color(0.98, 0.86, 0.76), 0.0, 1.0, 0.16)
	_portal = _mat(Color(0.2, 0.4, 1.0), 0.0, 0.3, true, Color(0.3, 0.5, 1.0), 2.5)

	_build_platforms()
	_build_gravity_zone()
	_build_checkpoints()
	_build_kill_plane()
	_build_rooms()
	_build_lights()
	_build_atmosphere()
	_build_environment()
	_build_start_base()

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
	# Falling off the low-gravity platforms is now an outright death + respawn at
	# the last checkpoint (checkpoints are frequent), consistent across missions.
	if body.is_in_group("player") and body.has_method("fall_to_death"):
		body.fall_to_death()
	elif body.is_in_group("player") and body.has_method("fall_respawn"):
		body.fall_respawn()


# --- 3 large wave rooms in a row, joined by portal doorways. Big on all 3 axes so
# the fights have real room to move: 34 m wide x 12 m tall x 24 m deep each. ---
const ROOM_W := 34.0
const ROOM_H := 12.0
const ROOM_DEPTH := 24.0
const ROOMS_Z := [-126.0, -150.0, -174.0]     # room centres (entrance at -114)
const SPAN_Z := -150.0                          # centre of the whole 3-room block
const SPAN_LEN := 72.0                          # 3 * ROOM_DEPTH

func _build_rooms() -> void:
	# One long floor + ceiling + side walls spanning all three rooms.
	_box(Vector3(0, Y_ROOM - T * 0.5, SPAN_Z), Vector3(ROOM_W, T, SPAN_LEN), _rock2)
	_box(Vector3(0, Y_ROOM + ROOM_H + T * 0.5, SPAN_Z), Vector3(ROOM_W, T, SPAN_LEN), _rock2)
	_box(Vector3(-ROOM_W * 0.5, Y_ROOM + ROOM_H * 0.5, SPAN_Z), Vector3(T, ROOM_H, SPAN_LEN), _rock)
	_box(Vector3(ROOM_W * 0.5, Y_ROOM + ROOM_H * 0.5, SPAN_Z), Vector3(T, ROOM_H, SPAN_LEN), _rock)
	# Cross-walls with portal doorways at the entrance and between rooms.
	_door_wall(-114.0, true)      # platforming -> Room 1
	_door_wall(-138.0, true)      # Room 1 -> Room 2 (portal)
	_door_wall(-162.0, true)      # Room 2 -> Room 3 (portal)
	_door_wall(-186.0, false)     # Room 3 far wall (solid end)
	# 8 spawn markers per room + cover obstacles.
	for cz in ROOMS_Z:
		_room_markers(cz)
		_room_cover(cz)


## Pillars and crates per room, placed clear of the spawn markers (which sit at
## x/z offsets of +-4/+-5) and the central doorway line, so they give cover
## without blocking navigation.
func _room_cover(cz: float) -> void:
	# Everything here stays off the central doorway axis (x within +-2 at the
	# room's z-edges) so it can never block the 3 m entrance/exit portals - an
	# earlier version put a crate dead-centre on the entrance.
	var c := Vector3(0, Y_ROOM, cz)
	# four tall pillars near the corners of the larger room
	_box(c + Vector3(-12, ROOM_H * 0.5, -6), Vector3(1.6, ROOM_H, 1.6), _rock)
	_box(c + Vector3(12, ROOM_H * 0.5, -6), Vector3(1.6, ROOM_H, 1.6), _rock)
	_box(c + Vector3(-12, ROOM_H * 0.5, 6), Vector3(1.6, ROOM_H, 1.6), _rock)
	_box(c + Vector3(12, ROOM_H * 0.5, 6), Vector3(1.6, ROOM_H, 1.6), _rock)
	# Low cover to duck behind - real Sci-Fi crate + barrel models. All off the x=0
	# through-line so the entrance/exit portals (at the z-edges) stay clear.
	_prop_cover(c + Vector3(-8, 0, -7), "Prop_Crate_Large", 1.15, Vector3(2.2, 1.9, 2.2))
	_prop_cover(c + Vector3(8, 0, 7), "Prop_Crate", 1.35, Vector3(2.1, 2.1, 2.1))
	_prop_cover(c + Vector3(9, 0, -6), "Prop_Barrel2_Closed", 1.3, Vector3(1.2, 1.6, 1.2))
	_prop_cover(c + Vector3(-9, 0, 6), "Prop_Barrel1", 1.3, Vector3(1.2, 1.6, 1.2))
	_prop_cover(c + Vector3(-5, 0, 1), "Prop_Crate", 1.2, Vector3(2.1, 2.1, 2.1))
	_prop_cover(c + Vector3(5, 0, -1), "Prop_Crate_Large", 1.1, Vector3(2.2, 1.9, 2.2))


## A real Sci-Fi Essentials prop as cover, with a matching collision box, in the
## "cover_crate" group the Shooter AI reads (matching earth_level). `base` is the
## floor point the prop sits on.
const PROP_DIR := "res://assets/thirdparty/Sci-Fi Essentials Kit[Standard]/glTF/"

func _prop_cover(base: Vector3, prop: String, model_scale: float, coll: Vector3) -> void:
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = coll
	col.shape = shape
	col.position = base + Vector3(0, coll.y * 0.5, 0)
	add_child(col)
	var scene := load(PROP_DIR + prop + ".gltf")
	if scene is PackedScene:
		var m := (scene as PackedScene).instantiate() as Node3D
		m.scale = Vector3.ONE * model_scale
		m.position = base
		m.add_to_group("cover_crate", true)
		add_child(m)
	else:
		# Fallback to a primitive so cover is never invisible.
		_box(base + Vector3(0, coll.y * 0.5, 0), coll, _rock2).add_to_group("cover_crate", true)


const DOOR_W := 4.0
const DOOR_H := 4.0

func _door_wall(z: float, has_door: bool) -> void:
	var half := ROOM_W * 0.5
	if not has_door:
		_box(Vector3(0, Y_ROOM + ROOM_H * 0.5, z), Vector3(ROOM_W, ROOM_H, T), _rock)
		return
	# DOOR_W-wide doorway centred on x=0; walls fill either side to the room edge.
	var side_w := half - DOOR_W * 0.5
	_box(Vector3(-(DOOR_W * 0.5 + side_w * 0.5), Y_ROOM + ROOM_H * 0.5, z), Vector3(side_w, ROOM_H, T), _rock)
	_box(Vector3(DOOR_W * 0.5 + side_w * 0.5, Y_ROOM + ROOM_H * 0.5, z), Vector3(side_w, ROOM_H, T), _rock)
	_box(Vector3(0, Y_ROOM + DOOR_H + (ROOM_H - DOOR_H) * 0.5, z), Vector3(DOOR_W, ROOM_H - DOOR_H, T), _rock)  # lintel
	# Blue portal panel filling the doorway (visual only - no collision).
	_panel(Vector3(0, Y_ROOM + DOOR_H * 0.5, z), Vector3(DOOR_W, DOOR_H, 0.08), _portal)


func _room_markers(cz: float) -> void:
	# spread across the larger room (well inside the +-17 x / +-12 z walls)
	var offs := [Vector3(-13, 0, -8), Vector3(0, 0, -9), Vector3(13, 0, -8), Vector3(-14, 0, 0),
		Vector3(14, 0, 0), Vector3(-13, 0, 8), Vector3(0, 0, 9), Vector3(13, 0, 8)]
	for o in offs:
		_marker(Vector3(0, Y_ROOM + 0.1, cz) + o, "spawn_point")


func _build_lights() -> void:
	var sun := DirectionalLight3D.new()          # dusty red-orange Mars sun
	sun.rotation = Vector3(-0.9, -0.6, 0)
	sun.light_energy = 1.05
	sun.light_color = Color(1.0, 0.72, 0.52)
	sun.shadow_enabled = true
	add_child(sun)
	_sun_dir = sun.global_transform.basis.z       # a Light faces -Z, so +Z points at the sun
	for cz in ROOMS_Z:                             # brighter/wider for the larger rooms
		_omni(Vector3(0, Y_ROOM + 8, cz), 26, 2.0, Color(1.0, 0.6, 0.45))


## Dusty Mars daytime atmosphere: a butterscotch/salmon sky (shaders/mars_sky.gdshader)
## with a hazy sun, warm sky ambient, ACES tonemap, and a reddish dust fog so the
## canyon backdrop fades into the haze. Runtime WorldEnvironment (replaces the stale
## flat-colour one that used to live in mars.tscn).
func _build_atmosphere() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/mars_sky.gdshader")
	sky_mat.set_shader_parameter("sun_dir", _sun_dir)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.ambient_light_color = Color(0.85, 0.60, 0.48)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	# reddish suspended-dust haze - thickens the canyon distance without hiding the play space
	env.fog_enabled = true
	env.fog_light_color = Color(0.82, 0.55, 0.40)
	env.fog_light_energy = 1.0
	env.fog_density = 0.006
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.5
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.glow_bloom = 0.05

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


## KayKit Space Base kit (CC0), real-world scale (~2 m tiles), base at y=0.
const KAY := "res://assets/thirdparty/KayKit_Space_Base_Bits_1.0_FREE/Assets/gltf/"

## Visual-only Mars-surface backdrop around the low-gravity ascent: a ground plane
## far below the kill plane, towering canyon mesas well outside the play volume, and
## a KayKit mining base scattered along the sides - so the climb reads as traversing
## a real Mars mining canyon instead of floating in an orange void. Everything here
## is decoration with NO collision and sits clear of the +-13 play column, so it
## never touches the platforms, kill plane (y=-12), gravity zone or the room navmesh.
func _build_environment() -> void:
	# Mars ground far below (regolith slab). Now SOLID (has collision) so a fall that
	# somehow clears the kill plane lands on real ground instead of dropping into the
	# void; the kill plane (y=-12) still catches normal misses above it first.
	_box(Vector3(0, -15.0, -54), Vector3(180, 1.0, 210), _regolith)
	# Detailed Tripo H3.1 Mars rock canyon walls running the length of the climb, pushed
	# out to x=+-34 so the widest scaled footprint still clears the +-13 play column.
	var rng := RandomNumberGenerator.new()
	rng.seed = 70315
	var zs := [10.0, -8.0, -26.0, -44.0, -62.0, -80.0, -98.0, -114.0]
	var kinds := ["mars_cliff", "mars_mesa", "mars_spire", "mars_cliff", "mars_mesa", "mars_cliff", "mars_spire", "mars_mesa"]
	for i in zs.size():
		_place_rock(kinds[i], Vector3(-34, -14.5, zs[i]), rng.randf_range(0.0, TAU), 26.0 + rng.randf_range(0.0, 12.0))
		_place_rock(kinds[(i + 3) % kinds.size()], Vector3(34, -14.5, zs[i]), rng.randf_range(0.0, TAU), 26.0 + rng.randf_range(0.0, 12.0))
	# scattered boulders lower down for canyon variety (clear of the +-13 column)
	for b in [Vector3(-21, -14.5, -6), Vector3(21, -14.5, -40), Vector3(-22, -14.5, -76), Vector3(20, -14.5, -104)]:
		_place_rock("mars_boulder", b, rng.randf_range(0.0, TAU), rng.randf_range(6.0, 10.0))
	# A mining base strung along the canyon sides (metal greys read well on red Mars).
	_kay("landingpad_large", Vector3(-15, -14.5, 4), 0.0, 2.6)
	_kay("spacetruck", Vector3(-15, -13.6, 4), 0.7, 2.0)
	_kay("drill_structure", Vector3(16, -14.0, -18), 0.0, 3.2)
	_kay("structure_tall", Vector3(-16, -14.0, -34), 0.3, 3.4)
	_kay("solarpanel", Vector3(16, -14.0, -50), 0.5, 3.2)
	_kay("containers_A", Vector3(-16, -14.0, -64), 0.1, 2.6)
	_kay("structure_low", Vector3(16, -14.0, -80), -0.4, 3.2)
	_kay("containers_C", Vector3(-16, -14.0, -96), 0.2, 2.6)
	_kay("drill_structure", Vector3(15, -14.0, -108), 0.6, 3.6)


## A STANDABLE KayKit landing base behind the spawn (z ~ +4..+19): the player
## arrives here on solid ground ringed by base structures, then jumps -Z into the
## low-gravity ascent. Only the floor slab + a back wall have collision (so you
## can't stroll off the rear into the void); the kit pieces are visual dressing.
## Sits entirely BEHIND the ascent (z > 4), so it never bridges a platform gap.
func _build_start_base() -> void:
	_box(Vector3(0, -0.25, 11), Vector3(18, 0.5, 15), _rock2)          # standable floor
	_box(Vector3(0, 2.0, 18.7), Vector3(18, 4.5, 0.5), _rock)         # back wall (no fall-off)
	# Base structures ringing the courtyard. These now carry SOLID collision (measured
	# from each model's AABB) so the player can't walk through the assets behind spawn.
	_kay("landingpad_large", Vector3(0, 0.02, 15), 0.0, 3.2)          # flat pad - walkable, left visual
	_kay_solid("spacetruck", Vector3(0, 0.6, 15), 0.0, 2.0)
	_kay_solid("structure_tall", Vector3(-7.5, 0, 16.5), 0.25, 2.2)
	_kay_solid("structure_low", Vector3(7.5, 0, 16.5), -0.25, 2.2)
	_kay_solid("containers_A", Vector3(-8.2, 0, 9), 0.1, 2.2)
	_kay_solid("containers_C", Vector3(8.2, 0, 9), -0.1, 2.2)
	_kay_solid("solarpanel", Vector3(-8.2, 0, 4.5), 0.5, 2.4)
	_kay_solid("drill_structure", Vector3(8.2, 0, 4.5), -0.4, 2.4)


## Place a detailed Tripo H3.1 Mars rock: uniform-scale the unit-cube-normalized mesh
## so its largest dimension = target_size (m), rotate, then seat its base at pos.y via
## the measured world AABB. Visual only (no collision) - the canyon frames the play
## column from outside it, so nothing here touches platforms/nav.
func _place_rock(nm: String, pos: Vector3, rot_y: float, target_size: float) -> void:
	var scene := load(ROCK % nm)
	if scene == null:
		return
	var m := (scene as PackedScene).instantiate() as Node3D
	add_child(m)
	m.rotation.y = rot_y
	m.scale = Vector3.ONE * target_size
	var ab := _world_aabb(m)
	m.position = Vector3(pos.x, pos.y - ab.position.y, pos.z)


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


func _kay(nm: String, pos: Vector3, rot_y: float, scl: float) -> void:
	var scene := load(KAY + nm + ".gltf")
	if scene == null:
		return
	var m := scene.instantiate() as Node3D
	m.position = pos
	m.rotation.y = rot_y
	m.scale = Vector3.ONE * scl
	add_child(m)


## Like _kay, but also adds a solid box collider sized from the placed model's world
## AABB, so the player can't walk through it. Used for the start-base structures.
func _kay_solid(nm: String, pos: Vector3, rot_y: float, scl: float) -> void:
	var scene := load(KAY + nm + ".gltf")
	if scene == null:
		return
	var m := scene.instantiate() as Node3D
	m.position = pos
	m.rotation.y = rot_y
	m.scale = Vector3.ONE * scl
	add_child(m)
	var ab := _world_aabb(m)
	if ab.size.length() < 0.05:
		return
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = ab.size
	col.shape = box
	col.position = ab.position + ab.size * 0.5
	add_child(col)


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


func _gen_tex(name: String) -> Texture2D:
	if not _tex_cache.has(name):
		var p: String = GEN_TEX % name
		_tex_cache[name] = load(p) if ResourceLoader.exists(p) else null
	return _tex_cache[name]


## Triplanar-textured Mars material (fal.ai albedo + PATINA normal/roughness). Falls
## back to a flat tinted material when the texture is missing.
func _mars_mat(tex: String, tint: Color, metallic: float, roughness: float, scale: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.metallic = metallic
	m.roughness = roughness
	var t: Texture2D = _gen_tex(tex)
	if t != null:
		m.albedo_texture = t
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(scale, scale, scale)
		var n: Texture2D = _gen_tex(tex + "_normal")
		if n != null:
			m.normal_enabled = true
			m.normal_texture = n
		var r: Texture2D = _gen_tex(tex + "_roughness")
		if r != null:
			m.roughness = 1.0
			m.roughness_texture = r
			m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	return m


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

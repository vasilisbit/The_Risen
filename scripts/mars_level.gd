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
const STRUCT := "res://assets/generated/mars/structures/%s.glb"

# Platforms that PHASE in/out (disappear on an interval) to make the climb harder.
# The checkpoints (even indices) stay solid; the odd rungs between them phase, so
# there's always a path - you just have to time each hop. See _build_phaser/_process.
const PHASE_INDICES := [1, 3, 5, 7, 9, 11, 13]
const PHASE_PERIOD := 7.5         # s for a full solid->gone->solid cycle (solid most of it)

var _rock: StandardMaterial3D
var _rock2: StandardMaterial3D
var _regolith: StandardMaterial3D
var _portal: StandardMaterial3D
var _tex_cache: Dictionary = {}
var _sun_dir: Vector3 = Vector3(0.4, 0.5, -0.7)     # direction TO the sun (for the sky)
var _phasers: Array = []                             # {mesh, col, mat, offset}
var _phase_t: float = 0.0


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
	_build_mountains()

	var region := get_parent()
	if region is NavigationRegion3D and region.navigation_mesh != null:
		region.bake_navigation_mesh(false)


func _build_platforms() -> void:
	for i in PLATFORMS.size():
		var size := Vector3(6, T, 6) if i == 0 else Vector3(3, T, 3)
		if i in PHASE_INDICES:
			_build_phaser(i, PLATFORMS[i], size)
		else:
			_box(PLATFORMS[i], size, _rock)


## A phasing platform: solid + visible for most of its cycle, then a warning pulse,
## then it fades out and drops its collision, then fades back in. Staggered per index
## so the climb reads as a rippling set of energy-rock rungs. The mesh + collider are
## tracked in _phasers and driven by _process.
func _build_phaser(index: int, center: Vector3, size: Vector3) -> void:
	var mat := _rock.duplicate() as StandardMaterial3D
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.8, 1.0)          # cyan energy edge, pulsed in _process
	mat.emission_energy_multiplier = 0.6
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = size
	mesh.mesh = bm
	mesh.material_override = mat
	mesh.position = center
	add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new(); shape.size = size
	col.shape = shape
	col.position = center
	add_child(col)
	# stagger so neighbours aren't all gone at once
	var offset: float = float(index) / float(max(PHASE_INDICES.size(), 1)) * PHASE_PERIOD
	_phasers.append({"mesh": mesh, "col": col, "mat": mat, "offset": offset})


## Drive the phasing platforms. Solid for most of the (now longer) cycle so they
## disappear infrequently. Cycle (fraction 0..1 of PHASE_PERIOD):
##   0.00-0.74 solid   0.74-0.82 warning (fast pulse, still solid)
##   0.82-0.92 gone (faded out, no collision)   0.92-1.00 fading back in
func _process(delta: float) -> void:
	if _phasers.is_empty():
		return
	_phase_t += delta
	for p in _phasers:
		var f: float = fmod(_phase_t + float(p["offset"]), PHASE_PERIOD) / PHASE_PERIOD
		var mesh: MeshInstance3D = p["mesh"]
		var col: CollisionShape3D = p["col"]
		var mat: StandardMaterial3D = p["mat"]
		var alpha := 1.0
		var solid := true
		var glow := 0.6
		if f < 0.74:
			alpha = 1.0; solid = true; glow = 0.6
		elif f < 0.82:                                   # warning: fast cyan pulse
			solid = true
			glow = 0.6 + 3.5 * (0.5 + 0.5 * sin((f - 0.74) * 90.0))
		elif f < 0.92:                                   # gone
			alpha = 0.12; solid = false; glow = 0.2
		else:                                            # fading back in
			alpha = clampf((f - 0.92) / 0.08, 0.0, 1.0); solid = true; glow = 1.2
		var c := mat.albedo_color; c.a = alpha
		mat.albedo_color = c
		mat.emission_energy_multiplier = glow
		mesh.visible = alpha > 0.02
		col.disabled = not solid


func _build_gravity_zone() -> void:
	# Covers the platforming volume only (ends before Room 1 at z=-114).
	var a := _area(Vector3(0, 7, -50.5), Vector3(26, 45, 125))
	a.body_entered.connect(_on_gravity_entered)
	a.body_exited.connect(_on_gravity_exited)


## Floaty Mars fall (0.6 g) BUT a trimmed jump take-off (0.7x). Gravity_scale alone
## couldn't stop skips because the jump velocity is fixed - at 0.6 g a SPRINT jump
## still carried ~19 m (two platforms). Cutting jump_scale drops a sprint jump to
## ~13-14 m: it clears the ~10 m gaps but can't leap-frog, so the climb is rung-by-rung.
func _on_gravity_entered(body: Node) -> void:
	if body.is_in_group("player"):
		if "gravity_scale" in body:
			body.gravity_scale = 0.6
		if "jump_scale" in body:
			body.jump_scale = 0.7


func _on_gravity_exited(body: Node) -> void:
	if body.is_in_group("player"):
		if "gravity_scale" in body:
			body.gravity_scale = 1.0
		if "jump_scale" in body:
			body.jump_scale = 1.0


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


# --- ONE big wave chamber (the inner walls are gone) so all the fighting happens in
# a single hall. 34 m wide x 18 m TALL x 72 m deep, entered through a grand gate. ---
const ROOM_W := 34.0
const ROOM_H := 18.0
const ROOM_DEPTH := 24.0
const ROOMS_Z := [-126.0, -150.0, -174.0]     # marker/cover clusters (entrance at -114)
const SPAN_Z := -150.0                          # centre of the whole hall
const SPAN_LEN := 72.0

func _build_rooms() -> void:
	# One long floor + ceiling + side walls spanning the whole hall.
	_box(Vector3(0, Y_ROOM - T * 0.5, SPAN_Z), Vector3(ROOM_W, T, SPAN_LEN), _rock2)
	_box(Vector3(0, Y_ROOM + ROOM_H + T * 0.5, SPAN_Z), Vector3(ROOM_W, T, SPAN_LEN), _rock2)
	_box(Vector3(-ROOM_W * 0.5, Y_ROOM + ROOM_H * 0.5, SPAN_Z), Vector3(T, ROOM_H, SPAN_LEN), _rock)
	_box(Vector3(ROOM_W * 0.5, Y_ROOM + ROOM_H * 0.5, SPAN_Z), Vector3(T, ROOM_H, SPAN_LEN), _rock)
	# Only the entrance (grand gate) and the far end wall remain - no internal walls.
	_door_wall(-114.0, true)      # platforming -> hall (the grandiose gate)
	_door_wall(-186.0, false)     # far end wall (solid)
	# spawn markers + cover, still clustered in three zones across the long hall.
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
	var scene := load(PROP_DIR + prop + ".gltf")
	if scene is PackedScene:
		var m := (scene as PackedScene).instantiate() as Node3D
		m.scale = Vector3.ONE * model_scale
		m.position = base
		m.add_to_group("cover_crate", true)
		add_child(m)
		# Collider measured from the placed model's world AABB, so it always matches
		# the visible crate (the old hand-guessed box could miss it -> walk-through).
		var ab := _world_aabb(m)
		if ab.size.length() > 0.05:
			var col := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = ab.size
			col.shape = shape
			col.position = ab.position + ab.size * 0.5
			add_child(col)
			return
	# Fallback to a primitive so cover is never invisible (and always solid).
	_box(base + Vector3(0, coll.y * 0.5, 0), coll, _rock2).add_to_group("cover_crate", true)


const DOOR_W := 8.0
const DOOR_H := 9.0

func _door_wall(z: float, has_door: bool) -> void:
	var half := ROOM_W * 0.5
	if not has_door:
		_box(Vector3(0, Y_ROOM + ROOM_H * 0.5, z), Vector3(ROOM_W, ROOM_H, T), _rock)
		return
	# Wide grand doorway centred on x=0; walls fill either side to the room edge.
	var side_w := half - DOOR_W * 0.5
	_box(Vector3(-(DOOR_W * 0.5 + side_w * 0.5), Y_ROOM + ROOM_H * 0.5, z), Vector3(side_w, ROOM_H, T), _rock)
	_box(Vector3(DOOR_W * 0.5 + side_w * 0.5, Y_ROOM + ROOM_H * 0.5, z), Vector3(side_w, ROOM_H, T), _rock)
	_box(Vector3(0, Y_ROOM + DOOR_H + (ROOM_H - DOOR_H) * 0.5, z), Vector3(DOOR_W, ROOM_H - DOOR_H, T), _rock)  # lintel
	_grand_gate(z)


## A grandiose gateway framing the entrance opening. Prefers the fal.ai image-to-3d
## Mars archway model (an actual open arch, so the passage shows through); its wall-
## opening stays clear of collision. Falls back to a primitive column+header gateway
## with cyan accents if the model is missing.
func _grand_gate(z: float) -> void:
	if ResourceLoader.exists(STRUCT % "mars_arch"):
		# Seated on the hall floor, framing the DOOR opening. Rotated 90 deg so the arch
		# is WIDE across the doorway with its opening facing the passage (the raw model
		# faces along x). ~20 m wide -> ~8 m central opening, matching DOOR_W.
		_place_struct("mars_arch", Vector3(0, Y_ROOM, z + 0.5), PI * 0.5, 20.0, false)
		# a little cyan glow at the threshold to keep the sci-fi read
		_panel(Vector3(0, Y_ROOM + 0.15, z + 2.6), Vector3(DOOR_W, 0.3, 0.4), _portal)
		return
	var fz := z + 1.3                                # protrude toward the player
	var col_h := DOOR_H + 4.0
	var cx := DOOR_W * 0.5 + 1.3
	for sx in [-1.0, 1.0]:
		_box(Vector3(sx * cx, Y_ROOM + col_h * 0.5, fz), Vector3(2.6, col_h, 2.8), _rock)
		_box(Vector3(sx * cx, Y_ROOM + col_h + 0.6, fz), Vector3(3.2, 1.2, 3.4), _rock2)   # capital
		_panel(Vector3(sx * (DOOR_W * 0.5 + 0.05), Y_ROOM + DOOR_H * 0.5, fz + 1.45), Vector3(0.15, DOOR_H, 0.4), _portal)
	_box(Vector3(0, Y_ROOM + DOOR_H + 1.7, fz), Vector3(DOOR_W + 5.6, 3.2, 2.8), _rock)
	_box(Vector3(0, Y_ROOM + DOOR_H + 4.1, fz - 0.3), Vector3(DOOR_W + 1.0, 1.8, 2.0), _rock2)
	_panel(Vector3(0, Y_ROOM + DOOR_H + 0.15, fz + 1.45), Vector3(DOOR_W, 0.3, 0.4), _portal)


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
	# fal.ai Mars mining base strung along the canyon sides (replaces the KayKit kit so
	# the whole map is one generated art style). Far below + unreachable, so visual only.
	_place_struct("mars_landing_pad", Vector3(-16, -14.5, 4), 0.0, 12.0, false)
	_place_struct("mars_rover", Vector3(-15, -14.5, 6), 0.7, 6.0, false)
	_place_struct("mars_drill", Vector3(17, -14.5, -18), 0.0, 15.0, false)
	_place_struct("mars_habitat_tall", Vector3(-17, -14.5, -34), 0.3, 12.0, false)
	_place_struct("mars_solar", Vector3(17, -14.5, -50), 0.5, 10.0, false)
	_place_struct("mars_containers", Vector3(-17, -14.5, -64), 0.1, 8.0, false)
	_place_struct("mars_habitat_low", Vector3(17, -14.5, -80), -0.4, 9.0, false)
	_place_struct("mars_containers", Vector3(-17, -14.5, -96), 0.2, 8.0, false)
	_place_struct("mars_drill", Vector3(16, -14.5, -108), 0.6, 16.0, false)


## A STANDABLE KayKit landing base behind the spawn (z ~ +4..+19): the player
## arrives here on solid ground ringed by base structures, then jumps -Z into the
## low-gravity ascent. Only the floor slab + a back wall have collision (so you
## can't stroll off the rear into the void); the kit pieces are visual dressing.
## Sits entirely BEHIND the ascent (z > 4), so it never bridges a platform gap.
func _build_start_base() -> void:
	_box(Vector3(0, -0.25, 11), Vector3(18, 0.5, 15), _rock2)          # standable floor
	_box(Vector3(0, 2.0, 18.7), Vector3(18, 4.5, 0.5), _rock)         # back wall (no fall-off)
	# fal.ai Mars base structures ringing the courtyard, all with SOLID collision
	# (AABB box) so the player can't walk through the assets behind spawn.
	_place_struct("mars_landing_pad", Vector3(0, 0.02, 15), 0.0, 9.0, true)
	_place_struct("mars_rover", Vector3(0, 0.7, 14), 0.0, 4.5, true)
	_place_struct("mars_habitat_tall", Vector3(-7.5, 0, 16.5), 0.25, 6.0, true)
	_place_struct("mars_habitat_low", Vector3(7.5, 0, 16.5), -0.25, 5.0, true)
	_place_struct("mars_containers", Vector3(-8.2, 0, 9), 0.1, 4.5, true)
	_place_struct("mars_containers", Vector3(8.2, 0, 9), -0.1, 4.5, true)
	_place_struct("mars_solar", Vector3(-8.2, 0, 4.5), 0.5, 5.0, true)
	_place_struct("mars_drill", Vector3(8.2, 0, 4.5), -0.4, 8.0, true)


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


## Place a generated Mars structure GLB (mining base / mountain): scale so its largest
## dimension = target_size, rotate, seat its base at pos.y. If `solid`, add a box
## collider from the seated world AABB so the player can't walk through it.
func _place_struct(nm: String, pos: Vector3, rot_y: float, target_size: float, solid: bool) -> void:
	var scene := load(STRUCT % nm)
	if scene == null:
		return
	var m := (scene as PackedScene).instantiate() as Node3D
	add_child(m)
	m.rotation.y = rot_y
	m.scale = Vector3.ONE * target_size
	var ab := _world_aabb(m)
	m.position = Vector3(pos.x, pos.y - ab.position.y, pos.z)
	if solid:
		var world := _world_aabb(m)
		if world.size.length() < 0.05:
			return
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = world.size
		col.shape = box
		col.position = world.position + world.size * 0.5
		add_child(col)


## A ring of huge Mars mountains around the whole level (well beyond the canyon walls
## and the death barrier) so the horizon reads as an endless mountain range and the
## map feels vast without actually being. Visual only; the dust fog fades them out.
func _build_mountains() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 91127
	var cz := -80.0                                  # rough centre of the whole level
	# A huge visual regolith plane under everything so the distant mountains sit on real
	# ground (they were floating over the void beyond the small play-area slab). No
	# collision - the player never reaches out here; the solid play ground stays put.
	var floor_mesh := MeshInstance3D.new()
	var fm := PlaneMesh.new(); fm.size = Vector2(900, 900)
	floor_mesh.mesh = fm
	floor_mesh.material_override = _regolith
	floor_mesh.position = Vector3(0, -15.05, cz)     # just below the mountain bases
	floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(floor_mesh)
	var kinds := ["mars_mountain", "mars_mesa", "mars_mountain", "mars_cliff"]
	var count := 22
	for i in count:
		var ang: float = TAU * float(i) / float(count) + rng.randf_range(-0.12, 0.12)
		var rad: float = rng.randf_range(150.0, 210.0)
		# seat ~2 m INTO the ground plane so no gap shows under the base (the models'
		# AABB bottom isn't always flush with their lowest geometry).
		var pos := Vector3(sin(ang) * rad, -17.0, cz + cos(ang) * rad)
		var size: float = rng.randf_range(70.0, 140.0)
		var nm: String = kinds[i % kinds.size()]
		if nm.begins_with("mars_mountain"):
			_place_struct(nm, pos, rng.randf_range(0.0, TAU), size, false)
		else:
			_place_rock(nm, pos, rng.randf_range(0.0, TAU), size)   # mesa/cliff live in rocks/


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

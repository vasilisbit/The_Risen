extends StaticBody3D
## T-0020 Venus mission blockout, generated in code (same approach as Earth/Mars).
## Three sections per GDD §3.4:
##   1. Exterior Ascent  - 200 m of 15 degrees volcano slope, wind gusts that push
##      the player 2 m back every 5 s, rock cover, lava vents. 20 spawn markers.
##   2. Interior Descent - 150 m lava-river cavern: 20 safe platforms (2 m across,
##      3 m apart), lava contact = -50% max HP + checkpoint respawn, wall ledges
##      for ranged enemies. 15 spawn markers. Ends at the scripted lava pool.
##   3. Boss Arena       - 30 m circular obsidian platform ringed by a lava moat,
##      4 weak-point markers (cardinal, 5 m out) and 8 eruption markers for the
##      Ember Tyrant (T-0021).
## Bakes the parent NavigationRegion3D at runtime.

const T := 0.5                          # slab thickness

# fal.ai generated Venus assets (Tripo H3.1 rocks + nano-banana/PATINA ground textures).
const GEN_TEX := "res://assets/generated/venus/%s.png"
const ROCK := "res://assets/generated/venus/rocks/%s.glb"
# Slope/arena cover uses compact Tripo volcanic rock (never a tall spire, so cover on
# the climb can't wall the player in above the jump apex - see _rock_prop).
const COVER_KINDS := ["venus_boulder", "venus_shard", "venus_boulder", "venus_shard"]

# --- Section 1: Exterior Ascent ---
const SLOPE_DEG := 15.0
const ASCENT_LENGTH := 200.0            # m of path (GDD §3.4)
const ASCENT_SEGMENTS := 10
const ASCENT_WIDTH := 16.0
const WIND_INTERVAL := 5.0              # s between gusts
const WIND_PUSH := 2.0                  # m the player is pushed back

# --- Section 2: Interior Descent ---
const DESCENT_LENGTH := 150.0           # m of path (GDD §3.4)
const PLATFORM_COUNT := 20
const PLATFORM_RADIUS := 1.0            # 2 m diameter
const PLATFORM_GAP := 3.0               # m of empty space between platforms
const PLATFORM_PITCH := PLATFORM_RADIUS * 2.0 + PLATFORM_GAP     # 5 m centre-to-centre
const PLATFORM_DROP := 1.2              # m each platform descends
const LAVA_DAMAGE_FRACTION := 0.5       # -50% max HP on contact
const CAVERN_HALF_WIDTH := 12.0

# --- Section 3: Boss Arena ---
const ARENA_CENTER := Vector3(0, 0, -420)
const ARENA_RADIUS := 24.0              # 48 m diameter (enlarged boss arena)
const WEAK_POINT_RADIUS := 9.0          # spread across the enlarged arena
const ERUPTION_RADIUS := 17.0           # 8 possible eruption sites (T-0021 phase C)

var _y_summit: float = 0.0
var _z_cavern_start: float = 0.0
var _z_pool: float = 0.0

var _rock: StandardMaterial3D
var _rock_dark: StandardMaterial3D
var _obsidian: StandardMaterial3D
var _ash: StandardMaterial3D
var _lava: StandardMaterial3D
var _pool_mat: StandardMaterial3D

var _wind_area: Area3D
var _tex_cache: Dictionary = {}
var _sun_dir: Vector3 = Vector3(0.3, 0.5, -0.8)     # direction TO the sun (for the sky)


func _ready() -> void:
	# fal.ai Venus PBR volcanic-rock/obsidian/ash (nano-banana + PATINA) applied
	# triplanar; falls back to the old flat volcanic colours if the textures are absent.
	# The emissive lava/pool stay hand-authored (they glow, not textured).
	_rock = _venus_mat("volcanic_rock", Color(0.82, 0.72, 0.64), 0.0, 0.9, 0.22)
	_rock_dark = _venus_mat("volcanic_rock", Color(0.52, 0.44, 0.40), 0.0, 0.85, 0.22)
	_obsidian = _venus_mat("obsidian", Color(0.78, 0.70, 0.76), 0.35, 0.35, 0.28, 0.55)
	_ash = _venus_mat("ash", Color(0.66, 0.54, 0.46), 0.0, 1.0, 0.16)
	_lava = _mat(Color(0.95, 0.30, 0.05), 0.0, 0.6, true, Color(1.0, 0.45, 0.08), 3.5)
	_pool_mat = _mat(Color(1.0, 0.72, 0.20), 0.0, 0.5, true, Color(1.0, 0.80, 0.30), 5.0)

	_y_summit = ASCENT_LENGTH * tan(deg_to_rad(SLOPE_DEG))
	_z_cavern_start = -(ASCENT_LENGTH + 12.0)          # summit pad ends here

	_build_ascent()
	_build_wind()
	_build_descent()
	_build_arena()
	_build_lights()
	_build_atmosphere()
	_build_environment()
	_build_spawns()
	_build_kill_plane()

	var region := get_parent()
	if region is NavigationRegion3D and region.navigation_mesh != null:
		region.bake_navigation_mesh(false)


## Void floor beneath the whole level: falling clean off the map (below even the
## lava) is an outright death + checkpoint respawn. The designed lava hazards sit
## far above this and still catch normal mistakes non-lethally (GDD -50% HP).
func _build_kill_plane() -> void:
	var a := _area(Vector3(0, -20, -200), Vector3(120, 4, 500))
	a.body_entered.connect(_on_void)


func _on_void(body: Node) -> void:
	if body.is_in_group("player") and body.has_method("fall_to_death"):
		body.fall_to_death()


# --- Section 1: Exterior Ascent -------------------------------------------

## Height of the slope surface at a given z (z is negative going up the volcano).
func slope_y(z: float) -> float:
	return clampf(-z, 0.0, ASCENT_LENGTH) * tan(deg_to_rad(SLOPE_DEG))


func _build_ascent() -> void:
	# +X rotation tilts the slab normal toward +Z, so the surface rises as z
	# decreases (the player climbs while walking forward).
	var rot := Vector3(deg_to_rad(SLOPE_DEG), 0.0, 0.0)
	var seg_len := ASCENT_LENGTH / float(ASCENT_SEGMENTS)
	var slab := seg_len / cos(deg_to_rad(SLOPE_DEG))       # slab is longer than its z span
	var sink := (T * 0.5) / cos(deg_to_rad(SLOPE_DEG))

	# Flat staging pad at the foot of the volcano (player spawns here).
	_box(Vector3(0, -T * 0.5, 6), Vector3(ASCENT_WIDTH, T, 12), _rock)

	for i in ASCENT_SEGMENTS:
		var cz := -(seg_len * float(i) + seg_len * 0.5)
		var cy := slope_y(cz) - sink
		_box(Vector3(0, cy, cz), Vector3(ASCENT_WIDTH, T, slab), _rock, rot)
		# Side walls keep the player on the path (open sky above).
		_box(Vector3(-ASCENT_WIDTH * 0.5, cy + 3.0, cz), Vector3(T, 6, slab), _rock_dark, rot)
		_box(Vector3(ASCENT_WIDTH * 0.5, cy + 3.0, cz), Vector3(T, 6, slab), _rock_dark, rot)

	# Flat summit pad, joining the ascent to the cavern mouth.
	_box(Vector3(0, _y_summit - T * 0.5, _z_cavern_start + 6.0),
		Vector3(ASCENT_WIDTH, T, 12), _rock)

	_build_ascent_props()
	_build_ascent_checkpoints()


## Rock formations (cover) and lava vents (hazards) dotted up the slope.
func _build_ascent_props() -> void:
	var lanes := [-4.5, 4.5, -4.5, 4.5, -3.0, 3.0, -4.5, 4.5]
	for i in lanes.size():
		var z := -22.0 - 22.0 * float(i)
		var x: float = lanes[i]
		var y := slope_y(z)
		# ~1.8 m rock: blocks a standing sightline but stays under the 2 m jump
		# apex, so the climb can never be walled off by its own cover.
		_rock_prop(Vector3(x, y, z), i, Vector3(3, 1.8, 2))
		# Shooters take cover on the downhill side of each formation.
		_marker(Vector3(x, y + 0.1, z + 2.0), "cover_point")

	# Lava vents: small emissive pits that hurt exactly like the lava river.
	for i in 5:
		var z := -30.0 - 34.0 * float(i)
		var x := 3.5 if i % 2 == 0 else -3.5
		var y := slope_y(z)
		_panel(Vector3(x, y + 0.05, z), Vector3(3, 0.1, 3), _lava)
		_lava_area(Vector3(x, y + 0.6, z), Vector3(3, 1.2, 3))


## A detailed Tripo H3.1 volcanic rock (fal.ai) as cover, seated on the slope with a
## collision box measured from its world AABB. The model is scaled to a fixed ~1.7 m
## HEIGHT (not its raw size) so cover on the climb always stays under the ~2 m jump
## apex and can never wall the player in. Falls back to a primitive if the GLB is
## missing. `base` is the floor point the rock sits on.
const COVER_HEIGHT := 1.7

func _rock_prop(base: Vector3, idx: int, coll: Vector3) -> void:
	var nm: String = COVER_KINDS[idx % COVER_KINDS.size()]
	var scene := load(ROCK % nm)
	if scene is PackedScene:
		var m := (scene as PackedScene).instantiate() as Node3D
		add_child(m)
		m.rotation.y = float(idx) * 1.37
		var raw := _world_aabb(m)
		m.scale = Vector3.ONE * (COVER_HEIGHT / maxf(raw.size.y, 0.001))
		var ab := _world_aabb(m)
		m.position = Vector3(base.x, base.y - ab.position.y, base.z)
		var world := _world_aabb(m)
		if world.size.length() > 0.05:
			var col := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = world.size
			col.shape = box
			col.position = world.position + world.size * 0.5
			add_child(col)
			return
	_box(base + Vector3(0, coll.y * 0.5, 0), coll, _rock_dark)


func _build_ascent_checkpoints() -> void:
	for i in 6:
		var z := -12.0 - 32.0 * float(i)
		_checkpoint(Vector3(0, slope_y(z) + 1.5, z), Vector3(ASCENT_WIDTH, 3, 4))
	_checkpoint(Vector3(0, _y_summit + 1.5, _z_cavern_start + 6.0), Vector3(ASCENT_WIDTH, 3, 4))


## Wind gusts blow down the slope, shoving the player WIND_PUSH metres back
## every WIND_INTERVAL seconds while they are on the exterior climb.
func _build_wind() -> void:
	_wind_area = _area(Vector3(0, _y_summit * 0.5 + 10.0, -ASCENT_LENGTH * 0.5),
		Vector3(ASCENT_WIDTH + 4.0, _y_summit + 40.0, ASCENT_LENGTH + 24.0))
	var timer := Timer.new()
	timer.wait_time = WIND_INTERVAL
	timer.autostart = true
	timer.timeout.connect(_on_wind_gust)
	add_child(timer)


func _on_wind_gust() -> void:
	if _wind_area == null:
		return
	for body in _wind_area.get_overlapping_bodies():
		if not body.is_in_group("player") or not body.has_method("apply_push"):
			continue
		body.apply_push(Vector3(0.0, 0.0, WIND_PUSH))         # +Z = back downhill


# --- Section 2: Interior Descent -------------------------------------------

func _build_descent() -> void:
	var z_end := _z_cavern_start - DESCENT_LENGTH
	var mid_z := _z_cavern_start - DESCENT_LENGTH * 0.5
	var y_lava := _y_summit - PLATFORM_DROP * float(PLATFORM_COUNT) - 6.0

	# Cavern shell: walls + ceiling + far wall. The floor is lava, not rock.
	_box(Vector3(-CAVERN_HALF_WIDTH, y_lava + 20.0, mid_z), Vector3(T, 44, DESCENT_LENGTH), _rock_dark)
	_box(Vector3(CAVERN_HALF_WIDTH, y_lava + 20.0, mid_z), Vector3(T, 44, DESCENT_LENGTH), _rock_dark)
	_box(Vector3(0, _y_summit + 6.0, mid_z), Vector3(CAVERN_HALF_WIDTH * 2, T, DESCENT_LENGTH), _rock_dark)
	_box(Vector3(0, y_lava + 20.0, z_end), Vector3(CAVERN_HALF_WIDTH * 2, 44, T), _rock_dark)

	# Entrance ledge: solid ground just inside the cavern (rushers spawn here).
	_box(Vector3(0, _y_summit - T * 0.5, _z_cavern_start - 10.0),
		Vector3(CAVERN_HALF_WIDTH * 2, T, 20), _rock)

	# The lava river itself, running the length of the platform field.
	var river_len := PLATFORM_PITCH * float(PLATFORM_COUNT) + 10.0
	var river_z := _z_cavern_start - 22.0 - river_len * 0.5
	_box(Vector3(0, y_lava - 1.5, river_z), Vector3(CAVERN_HALF_WIDTH * 2, 3, river_len), _lava)
	_lava_area(Vector3(0, y_lava + 1.0, river_z), Vector3(CAVERN_HALF_WIDTH * 2, 5, river_len))

	_build_platforms()
	_build_wall_ledges()
	_build_pool_chamber(z_end)
	_cavern_arch()


## 20 safe platforms, 2 m across and 3 m apart, descending toward the pool.
## The lateral zig-zag keeps every hop inside the Guardian's jump range.
func _build_platforms() -> void:
	var lane := [0.0, -3.0, 0.0, 3.0]
	for i in PLATFORM_COUNT:
		var z := _z_cavern_start - 24.0 - PLATFORM_PITCH * float(i)
		var y := _y_summit - 2.0 - PLATFORM_DROP * float(i)
		var x: float = lane[i % lane.size()]
		_cylinder(Vector3(x, y - T * 0.5, z), PLATFORM_RADIUS, T, _obsidian)
		# A checkpoint every 4th platform, so a lava hit costs a short retry.
		if i % 4 == 0:
			_checkpoint(Vector3(x, y + 1.2, z), Vector3(2.4, 2.4, 2.4))


## Ledges along the cavern walls give the ranged enemies somewhere to stand.
func _build_wall_ledges() -> void:
	for i in 5:
		var z := _z_cavern_start - 30.0 - 20.0 * float(i)
		var y := _y_summit - 2.0 - PLATFORM_DROP * (float(i) * 4.0)
		var x := (CAVERN_HALF_WIDTH - 2.5) * (1.0 if i % 2 == 0 else -1.0)
		_box(Vector3(x, y - T * 0.5, z), Vector3(5, T, 8), _rock)


## The far end of the cavern: solid floor plus the scripted lava pool that the
## player dives into to reach the hidden passage (GDD §3.4 objective 3).
func _build_pool_chamber(z_end: float) -> void:
	var floor_y := _y_summit - PLATFORM_DROP * float(PLATFORM_COUNT) - 2.0
	var cz := z_end + 14.0
	_box(Vector3(0, floor_y - T * 0.5, cz), Vector3(CAVERN_HALF_WIDTH * 2, T, 28), _rock)
	_checkpoint(Vector3(0, floor_y + 1.5, cz + 12.0), Vector3(CAVERN_HALF_WIDTH * 2, 3, 4))

	# Bright golden pool, visually distinct from the lethal river.
	var pool_pos := Vector3(0, floor_y - 1.5, cz - 6.0)
	_cylinder(pool_pos, 4.0, 3.0, _pool_mat)
	var hole := _area(pool_pos + Vector3(0, 1.6, 0), Vector3(8, 3, 8))
	hole.add_to_group("lava_pool", true)
	_omni(pool_pos + Vector3(0, 3, 0), 14.0, 3.0, Color(1.0, 0.75, 0.3))
	_marker(pool_pos + Vector3(0, 1.5, 0), "lava_pool_marker")


# --- Section 3: Boss Arena -------------------------------------------------

func _build_arena() -> void:
	# 30 m circular obsidian platform.
	_cylinder(ARENA_CENTER + Vector3(0, -T * 0.5, 0), ARENA_RADIUS, T, _obsidian)
	# Surrounding lava moat: anything off the platform is lava.
	_panel(ARENA_CENTER + Vector3(0, -3.0, 0), Vector3(90, 1, 90), _lava)
	_lava_area(ARENA_CENTER + Vector3(0, -2.5, 0), Vector3(90, 3, 90))
	_checkpoint(ARENA_CENTER + Vector3(0, 1.5, 19.0), Vector3(12, 3, 4))

	_marker(ARENA_CENTER + Vector3(0, 1.0, 0), "boss_spawn")
	_marker(ARENA_CENTER + Vector3(0, 1.0, 21.0), "arena_entry")

	# 4 destructible-crystal sites at the cardinal points (T-0021 phase B).
	var cardinals := [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)]
	for c in cardinals:
		_marker(ARENA_CENTER + c * WEAK_POINT_RADIUS + Vector3(0, 1.0, 0), "weak_point")

	# 8 lava-eruption sites (T-0021 phase C).
	for i in 8:
		var a := TAU * float(i) / 8.0
		var off := Vector3(cos(a), 0.0, sin(a)) * ERUPTION_RADIUS
		_marker(ARENA_CENTER + off + Vector3(0, 0.1, 0), "eruption_point")

	_arena_dressing()


## Jagged Tripo obsidian shards rising out of the lava moat around the arena, framing
## the boss fight. Placed BEYOND the platform rim (in the moat) so they never block
## movement or the boss - visual only. Falls back to nothing if the GLB is missing.
func _arena_dressing() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20456
	var count := 10
	for i in count:
		var a := TAU * float(i) / float(count) + rng.randf_range(-0.15, 0.15)
		var rad := ARENA_RADIUS + rng.randf_range(3.0, 9.0)
		var pos := ARENA_CENTER + Vector3(cos(a), -1.5, sin(a)) * Vector3(rad, 1, rad)
		_place_rock("venus_shard", pos, rng.randf_range(0.0, TAU), rng.randf_range(6.0, 12.0))


## A grand natural volcanic arch framing the cavern mouth (ascent summit -> descent).
## Visual only (no collision) so it can't block the passage; scaled to span well
## wider than the ASCENT_WIDTH path so its opening clears the walkway.
func _cavern_arch() -> void:
	if not ResourceLoader.exists(ROCK % "venus_arch"):
		return
	# Rotated 90 deg so the arch's hollow opening faces along the path (the raw model
	# spans the other axis) - the player walks up the centre and through the gateway.
	_place_rock("venus_arch", Vector3(0, _y_summit, _z_cavern_start), PI * 0.5, 28.0)


# --- Hazards ---------------------------------------------------------------

## Lava contact: -50% of max HP, then back to the last checkpoint. A short
## re-arm stops a single dunk from ticking repeatedly.
func _lava_area(center: Vector3, size: Vector3) -> void:
	var a := _area(center, size)
	a.add_to_group("lava", true)
	a.body_entered.connect(_on_lava_entered)


func _on_lava_entered(body: Node) -> void:
	if not body.is_in_group("player") or not body.has_method("hazard_respawn"):
		return
	var max_hp: float = body.max_hp() if body.has_method("max_hp") else 100.0
	body.hazard_respawn(max_hp * LAVA_DAMAGE_FRACTION)


func _checkpoint(respawn: Vector3, size: Vector3) -> void:
	var a := _area(respawn, size)
	a.body_entered.connect(_on_checkpoint.bind(respawn))


func _on_checkpoint(body: Node, respawn: Vector3) -> void:
	if body.is_in_group("player") and body.has_method("set_checkpoint"):
		body.set_checkpoint(respawn)


# --- Spawn markers ---------------------------------------------------------

## Marker creation order matters: venus_mission.gd assigns enemy types by index
## within each section (see _type_for there).
func _build_spawns() -> void:
	_marker(Vector3(0, 1.0, 6.0), "player_spawn")

	# Ascent - 20 markers. First 8 sit next to the rock cover (shooters), the
	# remaining 12 are spread down the open slope (rushers).
	for i in 8:
		var z := -24.0 - 22.0 * float(i)
		var x := -4.5 if i % 2 == 0 else 4.5
		_marker(Vector3(x, slope_y(z) + 1.0, z), "spawn_point")
	for i in 12:
		var z := -18.0 - 15.0 * float(i)
		var x := -2.0 if i % 2 == 0 else 2.0
		_marker(Vector3(x, slope_y(z) + 1.0, z), "spawn_point")

	# Descent - 15 markers: 5 shooters on the wall ledges, 2 exploders and
	# 8 rushers on the connected floors (entrance ledge / pool chamber), where
	# navmesh actually reaches the player.
	for i in 5:
		var z := _z_cavern_start - 30.0 - 20.0 * float(i)
		var y := _y_summit - 2.0 - PLATFORM_DROP * (float(i) * 4.0)
		var x := (CAVERN_HALF_WIDTH - 2.5) * (1.0 if i % 2 == 0 else -1.0)
		_marker(Vector3(x, y + 1.0, z), "spawn_point")

	var floor_y := _y_summit - PLATFORM_DROP * float(PLATFORM_COUNT) - 2.0
	var chamber_z := _z_cavern_start - DESCENT_LENGTH + 14.0
	for i in 2:
		var x := -5.0 if i == 0 else 5.0
		_marker(Vector3(x, floor_y + 1.0, chamber_z + 4.0), "spawn_point")
	for i in 8:
		if i < 4:
			var x := -6.0 + 4.0 * float(i)
			_marker(Vector3(x, _y_summit + 1.0, _z_cavern_start - 8.0 - 4.0 * float(i)), "spawn_point")
		else:
			var x := -6.0 + 4.0 * float(i - 4)
			_marker(Vector3(x, floor_y + 1.0, chamber_z + 10.0), "spawn_point")


# --- Lighting --------------------------------------------------------------

func _build_lights() -> void:
	var sun := DirectionalLight3D.new()          # hazy orange Venus daylight through the deck
	sun.rotation = Vector3(-0.7, 0.5, 0)
	sun.light_energy = 0.9
	sun.light_color = Color(1.0, 0.58, 0.30)
	sun.shadow_enabled = true
	add_child(sun)
	_sun_dir = sun.global_transform.basis.z       # a Light faces -Z, so +Z points at the sun

	# Lava glow up the cavern and around the arena.
	for i in 6:
		var z := _z_cavern_start - 20.0 - 22.0 * float(i)
		var y := _y_summit - 4.0 - PLATFORM_DROP * (float(i) * 3.5)
		_omni(Vector3(0, y, z), 22.0, 2.2, Color(1.0, 0.42, 0.12))
	_omni(ARENA_CENTER + Vector3(0, 8, 0), 40.0, 2.5, Color(1.0, 0.55, 0.25))


# --- Atmosphere + horizon environment --------------------------------------

## Oppressive Venus sky: a thick sulfuric-acid cloud overcast (shaders/venus_sky.
## gdshader) with only a diffuse sun glow, warm sky ambient, ACES tonemap, dense
## orange sulfur fog and lava glow. Runtime WorldEnvironment (replaces the stale
## flat-orange one that used to live in venus.tscn - same trap as Earth/Mars).
func _build_atmosphere() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/venus_sky.gdshader")
	sky_mat.set_shader_parameter("sun_dir", _sun_dir)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.ambient_light_color = Color(0.92, 0.56, 0.30)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	# dense sulfurous haze - thick Venus atmosphere; fades the horizon volcanoes out
	# without drowning the immediate play space.
	env.fog_enabled = true
	env.fog_light_color = Color(0.86, 0.46, 0.17)
	env.fog_light_energy = 1.0
	env.fog_density = 0.009
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.55
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.1

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


## Visual-only Venus surroundings: a vast ash plain far below and a ring of towering
## distant volcanoes fading into the sulfur haze, so the volcano ascent/cavern read
## as part of an endless molten hellscape instead of floating in an orange void.
## Everything here has NO collision and sits far outside the play volume (the real
## ground, kill plane and navmesh are untouched).
func _build_environment() -> void:
	# Huge ash plain under the whole level so the distant volcanoes sit on real ground.
	var floor_mesh := MeshInstance3D.new()
	var fm := PlaneMesh.new()
	fm.size = Vector2(1600, 1600)
	floor_mesh.mesh = fm
	floor_mesh.material_override = _ash
	floor_mesh.position = Vector3(0, -40.0, -200.0)
	floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(floor_mesh)

	var rng := RandomNumberGenerator.new()
	rng.seed = 51877
	var count := 22
	var kinds := ["venus_volcano", "venus_cliff", "venus_volcano", "venus_spire"]
	for i in count:
		var ang: float = TAU * float(i) / float(count) + rng.randf_range(-0.12, 0.12)
		var rad: float = rng.randf_range(270.0, 380.0)
		# seat a couple of metres INTO the plain so no gap shows under the base.
		var pos := Vector3(sin(ang) * rad, -42.0, -200.0 + cos(ang) * rad)
		var size: float = rng.randf_range(90.0, 180.0)
		_place_rock(kinds[i % kinds.size()], pos, rng.randf_range(0.0, TAU), size)


## Place a detailed Tripo H3.1 Venus rock: uniform-scale the mesh so its largest
## dimension = target_size (m), rotate, then seat its base at pos.y via the measured
## world AABB. Visual only (no collision) - used for the horizon ring, arena shards
## and cavern arch, all outside the play volume.
func _place_rock(nm: String, pos: Vector3, rot_y: float, target_size: float) -> void:
	var scene := load(ROCK % nm)
	if scene == null:
		return
	var m := (scene as PackedScene).instantiate() as Node3D
	add_child(m)
	m.rotation.y = rot_y
	var raw := _world_aabb(m)
	var largest: float = maxf(raw.size.x, maxf(raw.size.y, raw.size.z))
	m.scale = Vector3.ONE * (target_size / maxf(largest, 0.001))
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


func _gen_tex(name: String) -> Texture2D:
	if not _tex_cache.has(name):
		var p: String = GEN_TEX % name
		_tex_cache[name] = load(p) if ResourceLoader.exists(p) else null
	return _tex_cache[name]


## Triplanar-textured Venus material (fal.ai albedo + PATINA normal/roughness). Falls
## back to a flat tinted material when the texture is missing. `rough_scalar` scales
## the roughness map (obsidian stays glossy at ~0.55).
func _venus_mat(tex: String, tint: Color, metallic: float, roughness: float, scale: float, rough_scalar := 1.0) -> StandardMaterial3D:
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
			m.roughness = rough_scalar
			m.roughness_texture = r
			m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	return m


# --- Primitive builders ----------------------------------------------------

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


func _cylinder(center: Vector3, radius: float, height: float, mat: StandardMaterial3D) -> void:
	var mesh := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	mesh.mesh = cm
	mesh.material_override = mat
	mesh.position = center
	add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	col.shape = shape
	col.position = center
	add_child(col)


## Visual-only slab (no collision).
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

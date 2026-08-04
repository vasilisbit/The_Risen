extends StaticBody3D
## T-0020 Venus mission blockout, generated in code (same approach as Earth/Mars).
## Three sections per GDD §3.4:
##   1. Exterior Ascent  - 200 m of 15 degrees volcano slope, rock cover, lava vents
##      (which lie flat on the slope and burn you gradually). 20 spawn markers.
##   2. Interior Descent - lava-river cavern: a SPARSE jump puzzle (13 obsidian
##      platforms in a hard left/right zig-zag at jump reach, so you can't run the
##      middle line), wall ledges for ranged enemies. Ends at a real lava POOL you
##      drop through - a lava shaft that falls straight into the boss arena below.
##   3. Boss Arena       - a circular obsidian platform ringed by a lava moat, sitting
##      DIRECTLY BELOW the pool (you fall into it, no teleport), with weak-point +
##      eruption markers for the Ember Tyrant (T-0021).
## Lava is a gradual damage-over-time hazard (jump out to stop); only a 0-HP death
## respawns you at the last checkpoint. Bakes the parent NavigationRegion3D at runtime.

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

# --- Section 2: Interior Descent (sparse jump puzzle) ---
# Platforms alternate hard left/right at PLATFORM_X, PLATFORM_PITCH apart along -Z and
# dropping PLATFORM_DROP each - a committed diagonal hop. The cavern also DAMPENS the
# jump (DESCENT_JUMP_SCALE, via a zone that mirrors Mars' low-g platforming) so you
# can't super-leap the whole field, and the lava river below runs at RIVER_DPS - lethal
# to wade end to end - so a straight run down the middle (the old cheese) now kills you.
# You must actually work the zig-zag. See _build_platforms / _build_jump_zone.
const PLATFORM_COUNT := 13
const PLATFORM_RADIUS := 0.9            # 1.8 m diameter - a smaller, committed target
const PLATFORM_X := 3.0                 # lateral zig-zag magnitude (sign flips each step)
const PLATFORM_PITCH := 5.0             # m centre-to-centre along -Z
const PLATFORM_DROP := 1.2              # m each platform descends
const DESCENT_JUMP_SCALE := 0.75        # jump dampened in the cavern (precise hops, no skip)
const CAVERN_HALF_WIDTH := 12.0
const LAVA_DPS := 26.0                  # HP/s drained standing in a slope vent / arena moat
const RIVER_DPS := 60.0                 # the jump-puzzle river: lethal to wade, survivable to dip

# --- Section 3: Boss Arena (directly below the pool) ---
const ARENA_RADIUS := 24.0              # 48 m diameter (enlarged boss arena)
const ARENA_Y := -30.0                  # arena floor height - a DEEP drop below the pool
const SHAFT_CLEAR := 22.0               # the lava shaft walls stop this far ABOVE the arena
										# floor, so the arena is open (you're not boxed in)
const WEAK_POINT_RADIUS := 9.0          # spread across the enlarged arena
const ERUPTION_RADIUS := 17.0           # 8 possible eruption sites (T-0021 phase C)
const POOL_RADIUS := 6.0                # the lava-pool hole you drop through (wide pit)

var _y_summit: float = 0.0
var _z_cavern_start: float = 0.0
var _z_pool: float = 0.0                # centre of the drop-through lava pool
var _y_pool_floor: float = 0.0          # pool-chamber floor level (top of the shaft)
var _arena_center: Vector3 = Vector3.ZERO   # set under the pool in _build_descent

var _rock: StandardMaterial3D
var _rock_dark: StandardMaterial3D
var _obsidian: StandardMaterial3D
var _ash: StandardMaterial3D
var _lava: ShaderMaterial                # flowing-magma shader (river / moat / vents)
var _pool_mat: ShaderMaterial            # flowing-magma shader (the drop-through pool)

var _lava_areas: Array[Area3D] = []     # DoT volumes, drained in _physics_process
var _tex_cache: Dictionary = {}
var _sun_dir: Vector3 = Vector3(0.3, 0.5, -0.8)     # direction TO the sun (for the sky)
var _crater_top: Vector3 = Vector3.ZERO # magma-bomb launch point (volcano crater rim)
var _player: Node3D                     # cached in _physics_process for the magma spawner


func _ready() -> void:
	# fal.ai Venus PBR volcanic-rock/obsidian/ash (nano-banana + PATINA) applied
	# triplanar; falls back to the old flat volcanic colours if the textures are absent.
	# The emissive lava/pool stay hand-authored (they glow, not textured).
	_rock = _venus_mat("volcanic_rock", Color(0.82, 0.72, 0.64), 0.0, 0.9, 0.22)
	_rock_dark = _venus_mat("volcanic_rock", Color(0.52, 0.44, 0.40), 0.0, 0.85, 0.22)
	_obsidian = _venus_mat("obsidian", Color(0.78, 0.70, 0.76), 0.35, 0.35, 0.28, 0.55)
	_ash = _venus_mat("ash", Color(0.66, 0.54, 0.46), 0.0, 1.0, 0.16)
	# Flowing-magma shader (shaders/lava.gdshader) for every lava surface; a slightly
	# brighter/faster tuning for the drop-through pool so it reads as the way forward.
	_lava = _lava_shader_mat(3.0, 0.05)
	_pool_mat = _lava_shader_mat(4.2, 0.09)

	_y_summit = ASCENT_LENGTH * tan(deg_to_rad(SLOPE_DEG))
	_z_cavern_start = -(ASCENT_LENGTH + 12.0)          # summit pad ends here

	_build_ascent()
	_build_descent()
	_build_arena()
	_build_lights()
	_build_atmosphere()
	_build_environment()
	_build_volcano()
	_build_wind()
	_build_spawns()
	_build_kill_plane()

	var region := get_parent()
	if region is NavigationRegion3D and region.navigation_mesh != null:
		region.bake_navigation_mesh(false)


## Void floor beneath the whole level: falling clean off the map (below even the
## lava) is an outright death + checkpoint respawn. The designed lava hazards sit
## far above this and still catch normal mistakes non-lethally (GDD -50% HP).
func _build_kill_plane() -> void:
	var a := _area(Vector3(0, -55, -200), Vector3(220, 4, 700))
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
		# Side containment: INVISIBLE collision walls (the real generated volcanic cliffs
		# below do the looking). Keeps movement reliable while you ascend a real cliff
		# gorge instead of two grey boxes.
		_collision_box(Vector3(-ASCENT_WIDTH * 0.5, cy + 4.0, cz), Vector3(T, 10, slab), rot)
		_collision_box(Vector3(ASCENT_WIDTH * 0.5, cy + 4.0, cz), Vector3(T, 10, slab), rot)

	# Flat summit pad, joining the ascent to the cavern mouth.
	_box(Vector3(0, _y_summit - T * 0.5, _z_cavern_start + 6.0),
		Vector3(ASCENT_WIDTH, T, 12), _rock)

	_build_ascent_cliffs()
	_build_ascent_props()
	_build_ascent_checkpoints()


## Line both sides of the ascent with generated fal.ai volcanic cliff walls, so the
## climb reads as a real volcanic gorge (not the old grey box walls). The invisible
## collision walls above still contain the player; these are visual, seated on the
## slope at the path edge, tall and overlapping so they form a continuous rampart.
## Falls back to nothing (bare invisible walls) if the model is missing.
func _build_ascent_cliffs() -> void:
	if not ResourceLoader.exists(ROCK % "venus_cliff_wall"):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 33771
	var pieces := 6
	for side in [-1.0, 1.0]:
		var ex: float = side * (ASCENT_WIDTH * 0.5 + 0.5)
		for i in pieces:
			var z: float = -6.0 - (ASCENT_LENGTH + 8.0) / float(pieces) * float(i)
			var y := slope_y(z)
			# Rotate so the wall's long axis runs along the path (Z). Height-scaled so it
			# towers ~18 m over the walkway regardless of the model's raw proportions.
			var yaw: float = (PI * 0.5) * side + rng.randf_range(-0.12, 0.12)
			_place_wall("venus_cliff_wall", Vector3(ex, y - 2.5, z), yaw, 18.0 + rng.randf_range(-2.0, 3.0))


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

	# Lava vents: flowing-magma pits that lie FLAT ON THE SLOPE (rotated to the 15 deg
	# surface, not left horizontal) and burn you gradually while you stand in them.
	var srot := Vector3(deg_to_rad(SLOPE_DEG), 0.0, 0.0)
	for i in 5:
		var z := -30.0 - 34.0 * float(i)
		var x := 3.5 if i % 2 == 0 else -3.5
		var y := slope_y(z)
		_panel(Vector3(x, y + 0.06, z), Vector3(3, 0.1, 3.2), _lava, srot)
		_lava_area(Vector3(x, y + 0.7, z), Vector3(3, 1.4, 3.2), srot)


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


# --- Section 2: Interior Descent -------------------------------------------

func _build_descent() -> void:
	# Derive the platform-field / pool / arena positions from the sparse layout.
	var last_i := PLATFORM_COUNT - 1
	var last_z := _platform_z(last_i)
	var last_y := _platform_y(last_i)
	_z_pool = last_z - 9.0                              # drop-through pool, past the last platform
	_y_pool_floor = last_y - 2.0                        # pool-chamber floor (top of the shaft)
	_arena_center = Vector3(0, ARENA_Y, _z_pool)        # boss arena sits DIRECTLY BELOW the pool

	var field_start_z := _z_cavern_start - 20.0
	var field_end_z := last_z - 4.0
	var y_lava := last_y - 6.0                          # lava river below the lowest platform
	var cav_far_z := _z_pool - 10.0
	var cav_mid_z := (_z_cavern_start + cav_far_z) * 0.5
	var cav_len := _z_cavern_start - cav_far_z

	# Cavern shell: side walls + ceiling + far wall. The floor is the lava river.
	_box(Vector3(-CAVERN_HALF_WIDTH, y_lava + 22.0, cav_mid_z), Vector3(T, 48, cav_len), _rock_dark)
	_box(Vector3(CAVERN_HALF_WIDTH, y_lava + 22.0, cav_mid_z), Vector3(T, 48, cav_len), _rock_dark)
	_box(Vector3(0, _y_summit + 6.0, cav_mid_z), Vector3(CAVERN_HALF_WIDTH * 2, T, cav_len), _rock_dark)
	_box(Vector3(0, y_lava + 22.0, cav_far_z), Vector3(CAVERN_HALF_WIDTH * 2, 48, T), _rock_dark)

	# Entrance ledge: solid ground just inside the cavern (rushers spawn here).
	_box(Vector3(0, _y_summit - T * 0.5, _z_cavern_start - 10.0),
		Vector3(CAVERN_HALF_WIDTH * 2, T, 20), _rock)

	# The lava river under the platform field: flowing magma + a LETHAL DoT volume.
	# At RIVER_DPS a straight run down the middle (the old cheese) drains you dead
	# long before you reach the pool, so the zig-zag is the only way through - but a
	# single missed hop, jumped out of within a second, still survives.
	var river_len: float = field_start_z - field_end_z
	var river_z: float = (field_start_z + field_end_z) * 0.5
	_box(Vector3(0, y_lava - 1.5, river_z), Vector3(CAVERN_HALF_WIDTH * 2, 3, river_len), _lava)
	_lava_area(Vector3(0, y_lava + 1.2, river_z), Vector3(CAVERN_HALF_WIDTH * 2, 5, river_len), Vector3.ZERO, RIVER_DPS)

	_build_platforms()
	_build_wall_ledges(field_end_z)
	_build_jump_zone(field_start_z, field_end_z)
	_build_pool_chamber(field_end_z, cav_far_z)
	_cavern_arch()


## A jump-dampening volume over the platform field: while the player is in it their
## jump take-off is trimmed to DESCENT_JUMP_SCALE (mirrors the Mars low-g platforming
## trick) so a sprint jump clears one committed diagonal but can't super-leap several
## platforms or skip the puzzle. Restored to 1.0 on exit.
func _build_jump_zone(field_start_z: float, field_end_z: float) -> void:
	var mid_z: float = (field_start_z + field_end_z) * 0.5
	var span: float = absf(field_start_z - field_end_z) + 12.0
	var top_y := _y_summit
	var zone := _area(Vector3(0, top_y - 6.0, mid_z), Vector3(CAVERN_HALF_WIDTH * 2, 40, span))
	zone.body_entered.connect(_on_jump_zone_entered)
	zone.body_exited.connect(_on_jump_zone_exited)


func _on_jump_zone_entered(body: Node) -> void:
	if body.is_in_group("player") and "jump_scale" in body:
		body.jump_scale = DESCENT_JUMP_SCALE


func _on_jump_zone_exited(body: Node) -> void:
	if body.is_in_group("player") and "jump_scale" in body:
		body.jump_scale = 1.0


func _platform_z(i: int) -> float:
	return _z_cavern_start - 24.0 - PLATFORM_PITCH * float(i)

func _platform_y(i: int) -> float:
	return _y_summit - 2.0 - PLATFORM_DROP * float(i)

func _platform_x(i: int) -> float:
	return PLATFORM_X if i % 2 == 0 else -PLATFORM_X


## A SPARSE jump puzzle: platforms alternate hard left/right (x = +-PLATFORM_X) so a
## straight run down the middle drops into the lava - every hop is a committed diagonal
## sprint jump. A checkpoint every 3rd platform keeps a fall cheap.
func _build_platforms() -> void:
	for i in PLATFORM_COUNT:
		var pos := Vector3(_platform_x(i), _platform_y(i) - T * 0.5, _platform_z(i))
		_cylinder(pos, PLATFORM_RADIUS, T, _obsidian)
		if i % 3 == 0:
			_checkpoint(Vector3(pos.x, _platform_y(i) + 1.2, pos.z), Vector3(2.6, 2.6, 2.6))


## Ledges along the cavern walls give the ranged enemies somewhere to stand.
func _build_wall_ledges(field_end_z: float) -> void:
	var span: float = (_z_cavern_start - 28.0) - field_end_z
	for i in 5:
		var z: float = _z_cavern_start - 28.0 - (span / 5.0) * float(i)
		var y := _platform_y(i * 2) - 1.5
		var x := (CAVERN_HALF_WIDTH - 2.5) * (1.0 if i % 2 == 0 else -1.0)
		_box(Vector3(x, y - T * 0.5, z), Vector3(5, T, 8), _rock)


## The descent ends at a real lava POOL: a hole in the pool-chamber floor you drop
## THROUGH, down a flowing-lava shaft that falls straight into the boss arena directly
## below (no teleport - see venus_mission). The chamber floor is a ring of solid rock
## around the central hole; the pool disc + shaft render as flowing magma.
func _build_pool_chamber(field_end_z: float, cav_far_z: float) -> void:
	var fy := _y_pool_floor
	var hz := POOL_RADIUS + 0.5                         # half-size of the square hole
	var w := CAVERN_HALF_WIDTH
	# Chamber floor ring (4 boxes) around the hole - OBSIDIAN, so the lava well reads
	# as part of the same volcanic-glass cavern as the platforms/arena (the old rock
	# floor looked out of place - "not consistent with the environment").
	var front_len: float = (_z_pool + hz) - field_end_z
	var back_len: float = cav_far_z - (_z_pool - hz)
	if front_len > 0.1:
		_box(Vector3(0, fy - T * 0.5, (field_end_z + _z_pool + hz) * 0.5), Vector3(w * 2, T, front_len), _obsidian)
	if back_len > 0.1:
		_box(Vector3(0, fy - T * 0.5, (cav_far_z + _z_pool - hz) * 0.5), Vector3(w * 2, T, back_len), _obsidian)
	_box(Vector3(-(hz + (w - hz) * 0.5), fy - T * 0.5, _z_pool), Vector3(w - hz, T, hz * 2), _obsidian)
	_box(Vector3(hz + (w - hz) * 0.5, fy - T * 0.5, _z_pool), Vector3(w - hz, T, hz * 2), _obsidian)

	# A raised obsidian lip ringing the hole, so it reads as a deliberate lava WELL you
	# dive into (not a bare square hole in the floor). Four low bars around the rim.
	var lip_h := 0.7
	var lip_t := 0.9
	for s in [-1.0, 1.0]:
		_box(Vector3(s * (hz + lip_t * 0.5), fy + lip_h * 0.5 - 0.1, _z_pool), Vector3(lip_t, lip_h, hz * 2 + lip_t * 2), _obsidian)
		_box(Vector3(0, fy + lip_h * 0.5 - 0.1, _z_pool + s * (hz + lip_t * 0.5)), Vector3(hz * 2, lip_h, lip_t), _obsidian)

	# Lava shaft: four flowing-magma walls dropping from the pool floor, so you free-fall
	# down a glowing lava pit. They STOP SHAFT_CLEAR metres above the arena floor, so the
	# shaft never becomes a box around the landing - the arena below is fully open to roam
	# (the old walls reached the floor and trapped the player in a 9 m cell). Solid (keeps
	# the fall centred) but NOT a DoT volume - the pool is the way forward, not a hazard.
	var shaft_bottom: float = ARENA_Y + SHAFT_CLEAR
	var shaft_h: float = fy - shaft_bottom
	var shaft_my: float = (fy + shaft_bottom) * 0.5
	for s in [-1.0, 1.0]:
		_box(Vector3(s * (hz + T * 0.5), shaft_my, _z_pool), Vector3(T, shaft_h, hz * 2 + T * 2), _lava)
		_box(Vector3(0, shaft_my, _z_pool + s * (hz + T * 0.5)), Vector3(hz * 2, shaft_h, T), _lava)

	# The pool surface: a flowing-magma disc recessed just inside the lip, VISUAL ONLY
	# (no collision) so the player drops straight THROUGH it into the shaft - no teleport,
	# you free-fall the deep lava pit to the arena (venus_mission). Recessed below the lip
	# so it reads as lava down in the well and never z-fights the floor (the old artifact).
	_disc(Vector3(0, fy - 0.5, _z_pool), POOL_RADIUS, 0.5, _pool_mat)
	var hole := _area(Vector3(0, fy - 0.5, _z_pool), Vector3(hz * 2, 2.5, hz * 2))
	hole.add_to_group("lava_pool", true)
	_omni(Vector3(0, fy + 1.5, _z_pool), 22.0, 3.2, Color(1.0, 0.6, 0.25))
	_marker(Vector3(0, fy, _z_pool), "lava_pool_marker")

	# A floaty draft down almost the whole shaft so the long, deep drop lands softly +
	# dramatically. It stops ~6 m above the arena floor, so the last stretch is normal
	# gravity (a gentle touchdown from the already-slow fall) and the arena is NOT low-grav.
	var draft_top: float = fy
	var draft_bottom: float = ARENA_Y + 6.0
	var draft_h: float = maxf(draft_top - draft_bottom, 4.0)
	var draft := _area(Vector3(0, (draft_top + draft_bottom) * 0.5, _z_pool), Vector3(hz * 2, draft_h, hz * 2))
	draft.body_entered.connect(_on_shaft_entered)
	draft.body_exited.connect(_on_shaft_exited)


func _on_shaft_entered(body: Node) -> void:
	if body.is_in_group("player") and "gravity_scale" in body:
		body.gravity_scale = 0.4


func _on_shaft_exited(body: Node) -> void:
	if body.is_in_group("player") and "gravity_scale" in body:
		body.gravity_scale = 1.0


# --- Section 3: Boss Arena -------------------------------------------------

func _build_arena() -> void:
	# Circular obsidian platform, sitting directly below the pool shaft.
	_cylinder(_arena_center + Vector3(0, -T * 0.5, 0), ARENA_RADIUS, T, _obsidian)
	# Surrounding lava moat: anything off the platform is flowing magma (DoT).
	_panel(_arena_center + Vector3(0, -3.0, 0), Vector3(90, 1, 90), _lava)
	_lava_area(_arena_center + Vector3(0, -2.5, 0), Vector3(90, 3, 90))

	# You arrive by FALLING through the shaft onto the platform centre; the landing
	# checkpoint sits a little off-centre so a boss death respawns you in the arena
	# (not back up the 200 m climb), and the boss spawns across from you.
	_checkpoint(_arena_center + Vector3(0, 1.5, 6.0), Vector3(10, 3, 6))
	_marker(_arena_center + Vector3(0, 1.0, -9.0), "boss_spawn")
	_marker(_arena_center + Vector3(0, 1.0, 6.0), "arena_entry")

	# 4 destructible-crystal sites at the cardinal points (T-0021 phase B).
	var cardinals := [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)]
	for c in cardinals:
		_marker(_arena_center + c * WEAK_POINT_RADIUS + Vector3(0, 1.0, 0), "weak_point")

	# 8 lava-eruption sites (T-0021 phase C).
	for i in 8:
		var a := TAU * float(i) / 8.0
		var off := Vector3(cos(a), 0.0, sin(a)) * ERUPTION_RADIUS
		_marker(_arena_center + off + Vector3(0, 0.1, 0), "eruption_point")

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
		var pos := _arena_center + Vector3(cos(a), -1.5, sin(a)) * Vector3(rad, 1, rad)
		_place_rock("venus_shard", pos, rng.randf_range(0.0, TAU), rng.randf_range(6.0, 12.0))


## A grand natural volcanic arch framing the cavern mouth (ascent summit -> descent).
## Scaled to span wider than the ASCENT_WIDTH path so its opening clears the walkway,
## with SOLID legs (the two side pillars get box colliders) so you walk through the
## central opening but can't clip through the rock - the "no collision, walk right
## through it" bug. See _arch_collision.
func _cavern_arch() -> void:
	if not ResourceLoader.exists(ROCK % "venus_arch"):
		return
	# Rotated 90 deg so the arch's hollow opening faces along the path (the raw model
	# spans the other axis) - the player walks up the centre and through the gateway.
	var arch := _place_rock("venus_arch", Vector3(0, _y_summit, _z_cavern_start), PI * 0.5, 28.0)
	if arch != null:
		_arch_collision(arch, ASCENT_WIDTH)


## Give an arch model solid side pillars without walling the doorway: measure its world
## AABB and drop a box collider over the LEFT and RIGHT thirds (the rock legs), leaving
## the central `opening_w` metres clear so the player can pass through. Cheap + reliable
## vs. a full trimesh bake of a ~300k-tri model.
func _arch_collision(node: Node3D, opening_w: float) -> void:
	var w := _world_aabb(node)
	if w.size.length() < 0.05:
		return
	var half_open: float = clampf(opening_w * 0.5, 0.5, w.size.x * 0.5 - 0.2)
	var leg_w: float = w.size.x * 0.5 - half_open
	if leg_w <= 0.1:
		return
	var cy := w.position.y + w.size.y * 0.5
	var cz := w.position.z + w.size.z * 0.5
	var left_cx: float = w.position.x + leg_w * 0.5
	var right_cx: float = w.position.x + w.size.x - leg_w * 0.5
	for cx in [left_cx, right_cx]:
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(leg_w, w.size.y, w.size.z)
		col.shape = box
		col.position = Vector3(cx, cy, cz)
		add_child(col)


# --- Hazards ---------------------------------------------------------------

## Lava is a gradual damage-over-time hazard now, not an instant chunk + teleport:
## while the player stands in ANY lava volume, _physics_process drains LAVA_DPS HP/s,
## so you just jump out to stop it and only a real 0-HP death respawns you. Each lava
## volume is registered here and polled centrally.
func _lava_area(center: Vector3, size: Vector3, rot := Vector3.ZERO, dps := LAVA_DPS) -> void:
	var a := _area(center, size, rot)
	a.add_to_group("lava", true)
	a.set_meta("dps", dps)
	_lava_areas.append(a)


## Drain HP from each player standing in lava. Central poll (rather than per-area
## enter/exit) so overlapping volumes never double-count and leaving is instant. Each
## volume carries its own DPS (the jump-puzzle river is lethal; vents/moat are not).
func _physics_process(delta: float) -> void:
	if _lava_areas.is_empty():
		return
	for body in get_tree().get_nodes_in_group("player"):
		if not body.has_method("lava_burn"):
			continue
		for a in _lava_areas:
			if is_instance_valid(a) and a.overlaps_body(body):
				body.lava_burn(float(a.get_meta("dps", LAVA_DPS)) * delta)
				break


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

	# Descent - 15 markers, created in the order venus_mission._type_for expects:
	# 5 shooters (wall ledges) + 2 exploders + 8 rushers, on the connected floors
	# (entrance ledge / pool chamber) where navmesh actually reaches the player.
	var field_end_z: float = _platform_z(PLATFORM_COUNT - 1) - 4.0
	var span: float = (_z_cavern_start - 28.0) - field_end_z
	for i in 5:
		var z: float = _z_cavern_start - 28.0 - (span / 5.0) * float(i)
		var y := _platform_y(i * 2) - 1.5
		var x := (CAVERN_HALF_WIDTH - 2.5) * (1.0 if i % 2 == 0 else -1.0)
		_marker(Vector3(x, y + 1.0, z), "spawn_point")
	for i in 2:                                             # 2 exploders on the entrance ledge
		var x := -6.0 if i == 0 else 6.0
		_marker(Vector3(x, _y_summit + 1.0, _z_cavern_start - 8.0), "spawn_point")
	for i in 4:                                             # 4 rushers on the entrance ledge
		var x := -7.5 + 5.0 * float(i)
		_marker(Vector3(x, _y_summit + 1.0, _z_cavern_start - 14.0), "spawn_point")
	for i in 4:                                             # 4 rushers on the pool-chamber floor
		var x := -6.0 + 4.0 * float(i)
		_marker(Vector3(x, _y_pool_floor + 1.0, _z_pool + 7.0), "spawn_point")


# --- Lighting --------------------------------------------------------------

func _build_lights() -> void:
	var sun := DirectionalLight3D.new()          # hazy orange Venus daylight through the deck
	sun.rotation = Vector3(-0.7, 0.5, 0)
	sun.light_energy = 0.9
	sun.light_color = Color(1.0, 0.58, 0.30)
	sun.shadow_enabled = true
	add_child(sun)
	_sun_dir = sun.global_transform.basis.z       # a Light faces -Z, so +Z points at the sun

	# Lava glow down the cavern, in the drop shaft, and around the arena below.
	for i in 6:
		var z: float = _z_cavern_start - 16.0 - 16.0 * float(i)
		var y := _platform_y(mini(i * 2, PLATFORM_COUNT - 1)) - 4.0
		_omni(Vector3(0, y, z), 22.0, 2.2, Color(1.0, 0.42, 0.12))
	_omni(Vector3(0, (_y_pool_floor + ARENA_Y) * 0.5, _z_pool), 20.0, 2.6, Color(1.0, 0.5, 0.2))
	_omni(_arena_center + Vector3(0, 8, 0), 46.0, 2.6, Color(1.0, 0.55, 0.25))


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


# --- The active volcano (summit peak + magma bombardment) -------------------

const MAGMA_INTERVAL := 3.0              # s between eruptions while on the ascent
const MAGMA_ROCK := "res://scripts/magma_rock.gd"
var _magma_rng := RandomNumberGenerator.new()

## The summit is a real active volcano: a towering Tripo peak rises behind the cavern
## mouth (the arch is its base cave, where the mission continues underground), and its
## crater periodically hurls glowing magma bombs that arc down onto the ascent, so the
## climb is under bombardment like a real eruption. Peak + bombs are hazards/visuals;
## the arch legs and slope walls still do the actual blocking.
func _build_volcano() -> void:
	_magma_rng.seed = 77213
	# The magma bombs launch from high above the top of the slope so they rain DOWN the
	# climb toward the player (the eruption is ahead-and-above as you ascend).
	_crater_top = Vector3(0, _y_summit + 55.0, _z_cavern_start + 8.0)
	# The volcano peak itself: a towering Tripo cone rising behind the cavern mouth, so
	# the arch reads as the cave set into its base. Prefers the dedicated active-crater-
	# with-cave hero (venus_crater) over the plain distant cone. Visual only (the arch
	# legs + slope walls do the blocking). A hot glow at the crater sells it as ACTIVE.
	var peak := "venus_crater" if ResourceLoader.exists(ROCK % "venus_crater") else "venus_volcano"
	if ResourceLoader.exists(ROCK % peak):
		_place_rock(peak, Vector3(0, _y_summit - 6.0, _z_cavern_start - 80.0), 0.0, 210.0)
	_omni(_crater_top + Vector3(0, 4, 0), 70.0, 3.0, Color(1.0, 0.45, 0.12))

	var timer := Timer.new()
	timer.wait_time = MAGMA_INTERVAL
	timer.autostart = true
	timer.timeout.connect(_on_magma_tick)
	add_child(timer)


## Each eruption tick lobs 1-2 magma bombs at points on the ascent near the player -
## but only while they are actually out on the exterior climb (not in the cavern/arena).
func _on_magma_tick() -> void:
	var p := _find_player()
	if p == null:
		return
	var pz: float = p.global_position.z
	if pz <= _z_cavern_start or pz >= 8.0:                 # exterior ascent only
		return
	var shots := 1 if _magma_rng.randf() < 0.6 else 2
	for i in shots:
		var tz: float = clampf(pz + _magma_rng.randf_range(-16.0, 6.0), -ASCENT_LENGTH + 4.0, -8.0)
		var tx: float = _magma_rng.randf_range(-6.0, 6.0)
		_spawn_magma_bomb(Vector3(tx, slope_y(tz) + 0.2, tz))


func _spawn_magma_bomb(target: Vector3) -> void:
	var script := load(MAGMA_ROCK)
	if script == null:
		return
	var host := get_tree().current_scene
	if host == null:
		host = self
	var rock := Area3D.new()
	rock.set_script(script)
	host.add_child(rock)
	if rock.has_method("setup"):
		rock.setup(_crater_top, target)


func _find_player() -> Node3D:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	return _player


# --- Venus headwind (constant resistance + visible ash streaks) --------------

const WIND_SPEED := 3.2                  # m/s of constant downhill (+Z) resistance

## A constant headwind over the exterior ascent. It is NOT the old periodic shove:
## guardian.set_wind makes it a resistance that only bites while you are moving or
## airborne (a standing player is never pushed), so it just makes the climb a slog to
## fight up. Paired with a visible ash-streak field blowing down the slope so the wind
## reads on screen. Cleared when the player passes into the cavern.
func _build_wind() -> void:
	var mid_z := -ASCENT_LENGTH * 0.5
	var zone := _area(Vector3(0, _y_summit * 0.5 + 12.0, mid_z),
		Vector3(ASCENT_WIDTH + 10.0, _y_summit + 70.0, ASCENT_LENGTH + 20.0))
	zone.body_entered.connect(_on_wind_entered)
	zone.body_exited.connect(_on_wind_exited)
	_build_wind_visual(mid_z)


func _on_wind_entered(body: Node) -> void:
	if body.is_in_group("player") and body.has_method("set_wind"):
		body.set_wind(Vector3(0.0, 0.0, WIND_SPEED))


func _on_wind_exited(body: Node) -> void:
	if body.is_in_group("player") and body.has_method("set_wind"):
		body.set_wind(Vector3.ZERO)


## Fast-moving ash/ember streaks blowing down the slope (+Z), so the constant wind is
## visible. GPU particles, stretched quads, no collision - purely atmospheric.
func _build_wind_visual(mid_z: float) -> void:
	var p := GPUParticles3D.new()
	p.amount = 140
	p.lifetime = 2.4
	p.visibility_aabb = AABB(Vector3(-ASCENT_WIDTH, -10, mid_z - ASCENT_LENGTH), Vector3(ASCENT_WIDTH * 2, 80, ASCENT_LENGTH * 2))
	p.position = Vector3(0, _y_summit * 0.5 + 8.0, mid_z)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(ASCENT_WIDTH * 0.6, _y_summit * 0.5 + 6.0, ASCENT_LENGTH * 0.5)
	pm.direction = Vector3(0, -0.1, 1)                     # down the slope (+Z), slightly downward
	pm.spread = 12.0
	pm.initial_velocity_min = 16.0
	pm.initial_velocity_max = 26.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	pm.color = Color(0.85, 0.6, 0.42, 0.5)
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.9)                         # thin streaks
	var qm := StandardMaterial3D.new()
	qm.albedo_color = Color(0.9, 0.66, 0.45, 0.45)
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = qm
	p.draw_pass_1 = quad
	add_child(p)


## Place a detailed Tripo H3.1 Venus rock: uniform-scale the mesh so its largest
## dimension = target_size (m), rotate, then seat its base at pos.y via the measured
## world AABB. Visual only (no collision) - used for the horizon ring, arena shards
## and cavern arch, all outside the play volume.
func _place_rock(nm: String, pos: Vector3, rot_y: float, target_size: float) -> Node3D:
	var scene := load(ROCK % nm)
	if scene == null:
		return null
	var m := (scene as PackedScene).instantiate() as Node3D
	add_child(m)
	m.rotation.y = rot_y
	var raw := _world_aabb(m)
	var largest: float = maxf(raw.size.x, maxf(raw.size.y, raw.size.z))
	m.scale = Vector3.ONE * (target_size / maxf(largest, 0.001))
	var ab := _world_aabb(m)
	m.position = Vector3(pos.x, pos.y - ab.position.y, pos.z)
	return m


## Place a generated cliff WALL: scale by HEIGHT (not largest dim) so it towers
## target_height metres over the walkway regardless of the model's raw proportions,
## rotate, then seat its base at base.y. Visual only (the invisible collision walls
## contain the player) - used to line the ascent gorge.
func _place_wall(nm: String, base: Vector3, rot_y: float, target_height: float) -> Node3D:
	var scene := load(ROCK % nm)
	if scene == null:
		return null
	var m := (scene as PackedScene).instantiate() as Node3D
	add_child(m)
	m.rotation.y = rot_y
	var raw := _world_aabb(m)
	m.scale = Vector3.ONE * (target_height / maxf(raw.size.y, 0.01))
	var ab := _world_aabb(m)
	m.position = Vector3(base.x, base.y - ab.position.y, base.z)
	return m


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

## A flowing-magma ShaderMaterial (shaders/lava.gdshader) - emissive world-space
## molten field, so it tiles across any lava surface with no UVs. The pool gets a
## brighter/faster tuning so it reads as the way forward.
func _lava_shader_mat(emission_strength: float, flow_speed: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/lava.gdshader")
	m.set_shader_parameter("emission_strength", emission_strength)
	m.set_shader_parameter("flow_speed", flow_speed)
	return m


func _box(center: Vector3, size: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
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


## Collision-only box (no mesh) - invisible containment, e.g. the ascent gorge walls
## behind the generated cliffs.
func _collision_box(center: Vector3, size: Vector3, rot := Vector3.ZERO) -> void:
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = center
	col.rotation = rot
	add_child(col)


func _cylinder(center: Vector3, radius: float, height: float, mat: Material) -> void:
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


## Visual-only cylinder disc (no collision) - the drop-through lava pool surface.
func _disc(center: Vector3, radius: float, height: float, mat: Material) -> void:
	var mesh := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	mesh.mesh = cm
	mesh.material_override = mat
	mesh.position = center
	add_child(mesh)


## Visual-only slab (no collision).
func _panel(center: Vector3, size: Vector3, mat: Material, rot := Vector3.ZERO) -> void:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = mat
	mesh.position = center
	mesh.rotation = rot
	add_child(mesh)


func _area(center: Vector3, size: Vector3, rot := Vector3.ZERO) -> Area3D:
	var a := Area3D.new()
	a.position = center
	a.rotation = rot
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

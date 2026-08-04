extends StaticBody3D
## T-0006 hub blockout: builds a 2-room starship interior in code -
## Cockpit 10x10 m (with a 5x3 m viewport window) joined by a 3 m doorway to a
## Weapon Bay 8x8 m - plus interior lighting. Geometry is BoxMesh + BoxShape3D
## parented to this StaticBody3D. Meant to sit under a NavigationRegion3D, which
## this script bakes at runtime so AI pathfinding is ready.

const H := 4.0      # interior height
const T := 0.3      # wall / slab thickness


func _ready() -> void:
	# Grungy fal.ai metal panelling on the walls/ceiling (falls back to flat grey
	# before the texture is imported).
	var wall := _panel_mat()
	if wall == null:
		wall = _mat(Color(0.20, 0.22, 0.28), 0.0, 0.85)
	var floor_mat := _mat(Color(0.13, 0.14, 0.17), 0.1, 0.7)
	# Near-clear, faintly cool glass. Earlier passes tinted and lit it enough
	# that space read as bright blue through the window instead of black; the
	# pane should be almost invisible and only catch a little edge light.
	var glass := _mat(Color(0.55, 0.62, 0.72, 0.05), 0.0, 0.05)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED

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
	# The mirror hangs on this wall and its reflection camera sits behind it, so
	# it must not appear in the reflection - put it on the mirror's no-reflect
	# layer (1<<19, kept in sync with mirror.gd NO_REFLECT_LAYER). You never see
	# the wall a mirror is mounted on in its reflection anyway.
	var bay_left := _box(Vector3(-4, H * 0.5, 9), Vector3(T, H, 8), wall)  # left wall
	bay_left.layers = 1 << 19
	_box(Vector3(4, H * 0.5, 9), Vector3(T, H, 8), wall)           # right wall
	_box(Vector3(0, H * 0.5, 13), Vector3(8, H, T), wall)          # back wall
	# (the bay's front side is the cockpit's back wall + doorway above)

	# --- Interior lighting (no dark zones): cool ambient + warm vendor spot ---
	_omni(Vector3(0, 3.5, 0), 18.0, 2.2, Color(0.80, 0.85, 1.0))
	_omni(Vector3(0, 3.5, 9), 16.0, 2.2, Color(0.85, 0.90, 1.0))
	_omni(Vector3(0, 2.8, 10.5), 9.0, 2.6, Color(1.0, 0.80, 0.50))  # warm vendor

	# --- Cover markers (T-0008 shooters): bay side of the doorway wall,
	# behind the Z=5 wall segments so they block LOS to the cockpit ---
	_cover(Vector3(-2.6, 0, 5.9))
	_cover(Vector3(2.6, 0, 5.9))
	_cover(Vector3(-3.3, 0, 6.8))
	_cover(Vector3(3.3, 0, 6.8))

	_build_props()

	var region := get_parent()
	if region is NavigationRegion3D and region.navigation_mesh != null:
		region.bake_navigation_mesh(false)


## Dress the starship with Quaternius Sci-Fi Essentials props (CC0) - decoration
## only, kept against the walls/corners clear of the player spawn (0,1,3), the
## central hologram table, the window and the doorway. Visual-only (no collision,
## so they don't affect nav or block the player).
const PROP_DIR := "res://assets/thirdparty/Sci-Fi Essentials Kit[Standard]/glTF/"
## Fully-textured Fab "Sci-fi Console Game" terminal, used as the cockpit's pilot
## control stations (replaces the plain grey desks).
const CONSOLE_PATH := "res://assets/thirdparty/fab/sci_fi_console_game_fbx/Sci-fi Console Game.fbx"

func _build_props() -> void:
	# Cockpit: two lit sci-fi control terminals flanking the window (angled toward
	# the pilot seat), with the chair between them. The desks used to be plain boxes.
	_console(Vector3(-3.3, 0, -4.2), 0.42)
	# Pilot seat centred in the canopy, between the two flanking consoles - this is
	# the helm you take (scripts/helm_station.gd) to point the ship at a world. The
	# fal.ai hero seat replaces the old kit chair; falls back to it if the GLB is
	# missing (e.g. before the first asset scan).
	# Rest yaw is turned slightly off the window; helm_station swivels it to face the
	# canopy when you take the helm. (PI*0.5 faces the window for this seat model.)
	if not _gen_seat(Vector3(0.0, 0, -3.1), PI * 0.5 + 0.5):
		_prop("Prop_Chair", Vector3(0.0, 0, -3.1), 0.0, 1.0)
	_console(Vector3(3.3, 0, -4.2), -0.42)
	_prop("Prop_Locker", Vector3(-4.5, 0, 1.6), -PI * 0.5, 1.0)
	_prop("Prop_Locker", Vector3(-4.5, 0, 0.3), -PI * 0.5, 1.0)
	_prop("Prop_Shelves_WideTall", Vector3(4.5, 0, 1.2), PI * 0.5, 1.0)
	_prop("Prop_Crate", Vector3(4.2, 0, 4.2), 0.4, 1.0)
	_prop("Prop_Barrel1", Vector3(3.5, 0, 4.3), 0.0, 1.0)
	_prop("Prop_Crate", Vector3(-4.3, 0, 4.2), -0.5, 1.0)
	# Weapon bay: a bit of cargo by the side walls (the vendor stall fills the back).
	_prop("Prop_Shelves_WideTall", Vector3(3.5, 0, 8.0), PI * 0.5, 1.0)
	_prop("Prop_Chest", Vector3(-3.2, 0, 7.8), PI * 0.5, 1.0)
	_build_mirror()
	_build_vendor_stall()
	_build_interior_details()


## fal.ai interior detail props (overhead struts, wall pipes, a side console) that
## dress the cockpit like the reference. Each no-ops if its GLB isn't imported yet.
## Transforms are first-pass; tune against screenshots.
func _build_interior_details() -> void:
	# Overhead ceiling struts spanning the cockpit (hung near the ceiling).
	_gen_prop_glb("res://assets/generated/interior/overhead_struts.glb", Vector3(0.0, 3.5, -1.5), 0.0, 6.0, false)
	# Pipe runs along the cockpit side walls.
	_gen_prop_glb("res://assets/generated/interior/pipe_bundle.glb", Vector3(-4.6, 2.4, 0.5), 0.0, 5.0, false)
	_gen_prop_glb("res://assets/generated/interior/pipe_bundle.glb", Vector3(4.6, 2.4, 2.5), 0.0, 4.0, false)
	# Side control consoles standing against the cockpit side walls (more of them,
	# flanking the pilot like the reference cockpit).
	_gen_prop_glb("res://assets/generated/interior/side_console.glb", Vector3(4.55, 0.0, -1.0), -PI * 0.5, 1.0, true)
	_gen_prop_glb("res://assets/generated/interior/side_console.glb", Vector3(4.55, 0.0, 0.6), -PI * 0.5, 1.0, true)
	_gen_prop_glb("res://assets/generated/interior/side_console.glb", Vector3(-4.55, 0.0, -1.8), PI * 0.5, 1.0, true)
	_gen_prop_glb("res://assets/generated/interior/side_console.glb", Vector3(-4.55, 0.0, 3.0), PI * 0.5, 1.0, true)


## Instance a generated GLB, scale so its larger footprint axis is `target`, sit it
## (base on the floor when `drop`), rotate to yaw, and add solid collision. Returns
## the node or null if the asset is missing.
func _gen_prop_glb(path: String, pos: Vector3, rot_y: float, target: float, drop: bool) -> Node3D:
	var scene := load(path)
	if scene == null or not (scene is PackedScene):
		return null
	var m := (scene as PackedScene).instantiate() as Node3D
	add_child(m)
	m.rotation.y = rot_y
	m.position = pos
	var a := _combined_aabb(m)
	var w: float = maxf(a.size.x, a.size.z)
	if w > 0.01:
		m.scale = Vector3.ONE * (target / w)
	if drop:
		a = _combined_aabb(m)
		m.position.y += pos.y - a.position.y
	_add_prop_collision(m)
	return m


## Full-length mirror on the weapon bay's left wall, facing across the room, so
## the Guardian (and a screenshot) can see the character head to toe.
func _build_mirror() -> void:
	var mirror := Node3D.new()
	mirror.set_script(load("res://scripts/mirror.gd"))
	# Flush against the left wall (interior face at x=-3.85) so the player can't
	# walk behind it. The reflection camera sits behind that wall, so the wall is
	# put on the mirror's no-reflect layer (see below) instead of being cleared by
	# a gap - which lets the mirror sit flush and still reflect from any angle.
	mirror.position = Vector3(-3.82, 0.0, 9.5)
	mirror.rotation.y = PI * 0.5          # glass faces +X, into the bay
	add_child(mirror)


## Turn the placeholder orange vendor box into an actual shopfront on the bay's
## back wall: a counter you trade over, shelves of goods behind it, and a robot
## clerk. The invisible interaction body (ForgeMaster) stays where it was, so
## aiming at the counter and pressing E still opens the shop.
func _build_vendor_stall() -> void:
	var box := get_node_or_null("../../ForgeMaster/Mesh")
	if box is Node3D:
		(box as Node3D).visible = false           # hide the orange placeholder

	var counter_mat := _mat(Color(0.15, 0.16, 0.20), 0.6, 0.45)
	var top_mat := _mat(Color(0.85, 0.62, 0.30), 0.7, 0.3, true, Color(0.6, 0.4, 0.15), 0.4)
	# The fal.ai forge counter IS the trade desk now (the old plain box is gone). An
	# invisible full-height barrier below still seals the shop. If the asset is
	# missing, fall back to the plain box counter so the stall is never open.
	# -PI/2 turns the counter so its length spans left-right (facing the player); the
	# model runs front-to-back at yaw 0, which read as a deep block.
	var counter := _gen_prop_glb("res://assets/generated/interior/forge_counter.glb", Vector3(0.0, 0.0, 11.5), -PI * 0.5, 3.4, true)
	if counter == null:
		_box(Vector3(0, 0.55, 11.4), Vector3(8, 1.1, 0.7), counter_mat)
		_box(Vector3(0, 1.15, 11.35), Vector3(8, 0.1, 0.95), top_mat)
	# A back partition wall sealing the shop area (with a service gap the drone
	# sits in), so there's a proper enclosed store behind the counter. Grungy hull
	# panelling (matches the walls) instead of the flat counter colour, which read as
	# untextured behind the shelves.
	var shop_wall := _panel_mat()
	if shop_wall == null:
		shop_wall = counter_mat
	_box(Vector3(-3.0, 2.0, 12.9), Vector3(2, 4, 0.2), shop_wall)
	_box(Vector3(3.0, 2.0, 12.9), Vector3(2, 4, 0.2), shop_wall)

	# Goods on shelves against the back wall, flush to it, no gaps at the ends.
	_prop("Prop_Shelves_WideTall", Vector3(-3.4, 0, 12.5), PI, 1.0)
	_prop("Prop_Shelves_WideTall", Vector3(3.4, 0, 12.5), PI, 1.0)
	_prop("Prop_Crate", Vector3(-1.6, 0, 12.4), PI, 1.0)
	_prop("Prop_Crate", Vector3(1.6, 0, 12.4), PI, 1.0)

	# The Forge Master himself: the Fab "skm_robot3" mech behind the counter, with
	# his name over his head, facing the player.
	var clerk_scene := load("res://assets/thirdparty/fab/skm_robot/skm_robot3_full.fbx")
	if clerk_scene is PackedScene:
		var clerk := (clerk_scene as PackedScene).instantiate() as Node3D
		add_child(clerk)
		clerk.position = Vector3(0, 0.0, 12.3)     # feet on the floor
		clerk.rotation.y = PI                      # turn to face the counter/player
		clerk.scale = Vector3.ONE * 1.15           # native model is ~1.8 m tall
		# The FBX ships without its base-colour texture, so it renders flat white.
		# Paint it gunmetal so it reads as a proper machine.
		var mech_mat := _mat(Color(0.34, 0.36, 0.40), 0.9, 0.32)
		for m in clerk.find_children("*", "MeshInstance3D", true, false):
			(m as MeshInstance3D).material_override = mech_mat
		var idle := Node.new()                     # subtle standing idle (no clips ship)
		idle.set_script(load("res://scripts/forge_master_idle.gd"))
		clerk.add_child(idle)

	# Invisible full-height barrier at the counter, so the player can't jump the
	# counter and walk into the shop area behind it.
	var bar := CollisionShape3D.new()
	var bshape := BoxShape3D.new()
	bshape.size = Vector3(8, H, 0.4)
	bar.shape = bshape
	bar.position = Vector3(0, H * 0.5, 11.4)
	add_child(bar)
	var nameplate := Label3D.new()
	nameplate.text = "FORGE MASTER"
	nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	nameplate.no_depth_test = true
	nameplate.pixel_size = 0.006
	nameplate.modulate = Color(0.95, 0.78, 0.32)   # gold, matching the UI
	nameplate.outline_modulate = Color(0, 0, 0, 0.85)
	nameplate.outline_size = 14
	nameplate.position = Vector3(0, 2.5, 12.2)
	add_child(nameplate)
	# Warm forge glow over the counter.
	_omni(Vector3(0, 2.4, 11.6), 7.0, 2.2, Color(1.0, 0.72, 0.4))


## A textured sci-fi terminal as a pilot control station. The FBX imports at 100x
## with its local Z as world height, so scale 1.15 gives a ~1.5 m standing console;
## at rot_y 0 the screen faces +Z (toward the player). Solid collision like a prop.
func _console(pos: Vector3, rot_y: float) -> void:
	var scene := load(CONSOLE_PATH)
	if scene == null:
		return
	var m := scene.instantiate() as Node3D
	add_child(m)
	m.position = pos
	m.rotation.y = rot_y
	m.scale = Vector3.ONE * 1.15
	_add_prop_collision(m)


func _prop(name_: String, pos: Vector3, rot_y: float, scale: float) -> void:
	var scene := load(PROP_DIR + name_ + ".gltf")
	if scene == null:
		return
	var m := scene.instantiate() as Node3D
	add_child(m)
	m.position = pos
	m.rotation.y = rot_y
	m.scale = Vector3.ONE * scale
	_add_prop_collision(m)


## Give a decorative prop a solid collision box matching its bounds, so the
## player can't walk through the furniture. This node is a StaticBody3D, so a
## CollisionShape3D child on it is solid world geometry.
func _add_prop_collision(m: Node3D) -> void:
	var aabb := AABB()
	var first := true
	for vi in m.find_children("*", "VisualInstance3D", true, false):
		var a: AABB = (vi as VisualInstance3D).global_transform * (vi as VisualInstance3D).get_aabb()
		if first:
			aabb = a
			first = false
		else:
			aabb = aabb.merge(a)
	if first or aabb.size.length() < 0.01:
		return
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = aabb.size
	col.shape = box
	col.position = to_local(aabb.position + aabb.size * 0.5)
	add_child(col)


## Load a fal.ai-generated interior GLB, scale it to a target height, rest its base
## on the floor at `pos` facing yaw `rot_y`, and give it solid collision. Returns
## false if the GLB is not imported yet, so the caller can fall back to a kit prop.
func _gen_seat(pos: Vector3, rot_y: float, target_h: float = 1.35) -> bool:
	var scene := load("res://assets/generated/interior/pilot_seat.glb")
	if scene == null or not (scene is PackedScene):
		return false
	var m := (scene as PackedScene).instantiate() as Node3D
	add_child(m)
	m.add_to_group("pilot_seat")
	m.rotation.y = rot_y
	m.position = pos
	var aabb := _combined_aabb(m)
	if aabb.size.y > 0.01:
		m.scale = Vector3.ONE * (target_h / aabb.size.y)
	# Re-measure after scaling and drop the base onto the floor at pos.y.
	aabb = _combined_aabb(m)
	m.position.y += pos.y - aabb.position.y
	_add_prop_collision(m)
	return true


## Global-space AABB enclosing every visual in `node` (empty AABB if none).
func _combined_aabb(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for vi in node.find_children("*", "VisualInstance3D", true, false):
		var a: AABB = (vi as VisualInstance3D).global_transform * (vi as VisualInstance3D).get_aabb()
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	return out


func _cover(pos: Vector3) -> void:
	var m := Marker3D.new()
	m.position = pos
	m.add_to_group("cover_point", true)
	add_child(m)


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


func _omni(pos: Vector3, range_m: float, energy: float, color: Color) -> void:
	var light := OmniLight3D.new()
	light.position = pos
	light.omni_range = range_m
	light.light_energy = energy
	light.light_color = color
	add_child(light)


## Grungy sci-fi wall panelling from the fal.ai texture set (albedo + patina normal
## /roughness), world-triplanar so it tiles consistently across the blockout boxes
## whatever their size. Returns null if the albedo isn't imported yet.
func _panel_mat() -> StandardMaterial3D:
	var albedo := load("res://assets/generated/interior/wall_panel_albedo.png") as Texture2D
	if albedo == null:
		return null
	var m := StandardMaterial3D.new()
	m.albedo_texture = albedo
	m.metallic = 0.5
	m.roughness = 1.0
	var nrm := load("res://assets/generated/interior/wall_panel_normal.png") as Texture2D
	if nrm:
		m.normal_enabled = true
		m.normal_texture = nrm
	var rgh := load("res://assets/generated/interior/wall_panel_roughness.png") as Texture2D
	if rgh:
		m.roughness_texture = rgh
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.35        # ~ one panel tile per ~2.8 m
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

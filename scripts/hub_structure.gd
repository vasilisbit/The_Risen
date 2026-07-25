extends StaticBody3D
## T-0006 hub blockout: builds a 2-room starship interior in code -
## Cockpit 10x10 m (with a 5x3 m viewport window) joined by a 3 m doorway to a
## Weapon Bay 8x8 m - plus interior lighting. Geometry is BoxMesh + BoxShape3D
## parented to this StaticBody3D. Meant to sit under a NavigationRegion3D, which
## this script bakes at runtime so AI pathfinding is ready.

const H := 4.0      # interior height
const T := 0.3      # wall / slab thickness


func _ready() -> void:
	var wall := _mat(Color(0.20, 0.22, 0.28), 0.0, 0.85)
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
	_box(Vector3(-4, H * 0.5, 9), Vector3(T, H, 8), wall)          # left wall
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

func _build_props() -> void:
	# Cockpit: a pilot station by the window, storage along the walls.
	_prop("Prop_Desk_Medium", Vector3(-3.4, 0, -4.0), PI, 1.0)
	_prop("Prop_Chair", Vector3(-3.4, 0, -3.1), 0.0, 1.0)
	_prop("Prop_Desk_Medium", Vector3(3.4, 0, -4.0), PI, 1.0)
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


## Full-length mirror on the weapon bay's left wall, facing across the room, so
## the Guardian (and a screenshot) can see the character head to toe.
func _build_mirror() -> void:
	var mirror := Node3D.new()
	mirror.set_script(load("res://scripts/mirror.gd"))
	# Stood a little off the left wall (which is at x=-4), so the reflection
	# camera has a gap behind the glass to clip the wall out of the reflection.
	mirror.position = Vector3(-3.4, 0.0, 9.5)
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
	# Wall-to-wall counter (X[-4,4]) - solid, so you trade over it and can't get
	# to the shop's back. A slim glowing top ledge reads as the trade surface.
	_box(Vector3(0, 0.55, 11.4), Vector3(8, 1.1, 0.7), counter_mat)
	_box(Vector3(0, 1.15, 11.35), Vector3(8, 0.1, 0.95), top_mat)
	# A back partition wall sealing the shop area (with a service gap the drone
	# sits in), so there's a proper enclosed store behind the counter.
	_box(Vector3(-3.0, 2.0, 12.9), Vector3(2, 4, 0.2), counter_mat)
	_box(Vector3(3.0, 2.0, 12.9), Vector3(2, 4, 0.2), counter_mat)

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


func _cover(pos: Vector3) -> void:
	var m := Marker3D.new()
	m.position = pos
	m.add_to_group("cover_point", true)
	add_child(m)


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

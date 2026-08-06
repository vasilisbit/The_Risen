extends StaticBody3D
## T-0006 / space-travel hub — the starship interior.
##
## The room itself is ONE cohesive grungy curved cockpit modelled in Blender
## (tools/blender_ship_interior.py -> assets/generated/interior/ship_interior.glb):
## a lofted vaulted hull with a wraparound windshield up front (-Z, out the
## canopy), structural ribs, a raised deck and ceiling light runs, flowing back
## into an enclosed vendor bay. This script instances that shell (visual only),
## assigns the right material to each named part, then adds LIGHTWEIGHT invisible
## box colliders for player containment + navmesh baking, and re-mounts the kept
## systems onto it — the pilot seat (scripts/helm_station.gd swivels it), the
## hologram table (its own scene), the Forge Master vendor stall and the mirror.
##
## The old fully-procedural box blockout + scattered fal.ai props are retired; a
## trimmed box fallback (_build_fallback) still builds if the shell GLB is missing
## so the hub is never empty.

const H := 4.6       # nominal interior clear height (collider tops)
const SHELL_GLB := "res://assets/generated/interior/ship_interior.glb"
const NO_REFLECT_LAYER := 1 << 19   # kept in sync with mirror.gd


func _ready() -> void:
	if not _build_shell():
		_build_fallback()
	_build_collision()
	_build_lighting()
	_build_console_table()
	_build_glass()
	_place_seat()
	_dress_props()
	_build_mirror()
	_build_vendor_stall()

	var region := get_parent()
	if region is NavigationRegion3D and region.navigation_mesh != null:
		region.bake_navigation_mesh(false)


## ------------------------------------------------------------- the shell
## Instance the Blender-modelled interior and skin each named part. Returns false
## (so the caller falls back to boxes) if the GLB isn't imported yet.
func _build_shell() -> bool:
	var scene := load(SHELL_GLB)
	if not (scene is PackedScene):
		return false
	var shell := (scene as PackedScene).instantiate() as Node3D
	shell.name = "InteriorShell"
	add_child(shell)

	# Grungy hull panelling (world-triplanar) on the walls/ceiling; a slightly
	# darker instance of the same set on the deck so the floor reads distinct but
	# coherent. Gunmetal on the ribs + canopy frame; emissive teal + warm strips.
	var hull := _panel_mat()
	if hull == null:
		hull = _mat(Color(0.20, 0.22, 0.28), 0.4, 0.85)
	hull.cull_mode = BaseMaterial3D.CULL_DISABLED
	var deck := _panel_mat(Color(0.55, 0.55, 0.6))
	if deck == null:
		deck = _mat(Color(0.11, 0.12, 0.15), 0.35, 0.7)
	deck.cull_mode = BaseMaterial3D.CULL_DISABLED
	var metal := _mat(Color(0.19, 0.20, 0.23), 0.85, 0.4)
	metal.cull_mode = BaseMaterial3D.CULL_DISABLED
	var teal := _mat(Color(0.15, 0.55, 0.72), 0.6, 0.3, true, Color(0.15, 0.55, 0.72), 1.6)
	var warm := _mat(Color(1.0, 0.86, 0.62), 0.2, 0.4, true, Color(1.0, 0.8, 0.5), 2.4)

	# Role -> material. CanopyTeal must be tested before Canopy (prefix match).
	var by_role := {
		"CanopyTeal": teal, "Canopy": metal, "Hull": hull, "Deck": deck,
		"Ribs": metal, "Lights": warm,
	}
	# The mirror's reflection camera sits behind the left bay wall; the whole
	# one-piece hull is put on NO_REFLECT_LAYER so it never occludes the mirror
	# (the main + seat cameras still render that layer). The deck stays on the
	# default layer so the floor shows under the Guardian in the reflection.
	var reflect_hidden := {"Hull": true, "Ribs": true, "Lights": true, "Canopy": true, "CanopyTeal": true}

	for mi in shell.find_children("*", "MeshInstance3D", true, false):
		var role := _role_of((mi as MeshInstance3D).name)
		if role != "":
			(mi as MeshInstance3D).material_override = by_role[role]
			if reflect_hidden.get(role, false):
				(mi as MeshInstance3D).layers = NO_REFLECT_LAYER
	return true


## Map an imported mesh-instance name (Blender object name, maybe with a suffix)
## to its material role. CanopyTeal first so it doesn't match the Canopy prefix.
func _role_of(node_name: String) -> String:
	for role in ["CanopyTeal", "Canopy", "Hull", "Deck", "Ribs", "Lights"]:
		if node_name.begins_with(role):
			return role
	return ""


## ------------------------------------------------------- containment + nav
## Invisible box colliders approximating the shell: floor, front/rear bulkheads
## and side walls (cockpit ±5, bay ±4.2). Parsed as static-collider source for
## the navmesh bake, and what actually stops the player — kept simple so nav
## bakes fast and collision is robust regardless of the visual mesh detail.
const FRONT_Z := -4.6
const REAR_Z := 13.8

func _build_collision() -> void:
	var mid := (FRONT_Z + REAR_Z) * 0.5
	var length := REAR_Z - FRONT_Z + 0.6
	# Walls are thick (0.8) and sit so their INNER face is just inside the visual
	# hull, so the player stops before the wall and the camera can never poke
	# through it. A full CEILING collider caps the vault so a jump can't leave the
	# ship. Floor + these are the navmesh source geometry.
	_col(Vector3(0, -0.15, mid), Vector3(11.4, 0.3, length))          # floor
	_col(Vector3(0, 4.35, mid), Vector3(11.4, 0.5, length))           # ceiling cap
	_col(Vector3(0, H * 0.5, FRONT_Z - 0.35), Vector3(11.4, H + 0.6, 0.8))  # front bulkhead
	_col(Vector3(0, H * 0.5, REAR_Z + 0.25), Vector3(9.4, H + 0.6, 0.8))    # rear bulkhead
	_col(Vector3(-5.3, H * 0.5, 0.5), Vector3(0.8, H + 0.6, 11.2))    # left cockpit wall
	_col(Vector3(5.3, H * 0.5, 0.5), Vector3(0.8, H + 0.6, 11.2))     # right cockpit wall
	_col(Vector3(-4.5, H * 0.5, 9.7), Vector3(0.8, H + 0.6, 9.0))     # left bay wall
	_col(Vector3(4.5, H * 0.5, 9.7), Vector3(0.8, H + 0.6, 9.0))      # right bay wall


func _col(center: Vector3, size: Vector3) -> void:
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	col.position = center
	add_child(col)


## Cool ambient down the length + a warm pool at the vendor. No dark zones.
func _build_lighting() -> void:
	_omni(Vector3(0, 3.7, -2.0), 16.0, 2.0, Color(0.80, 0.86, 1.0))
	_omni(Vector3(0, 3.7, 4.0), 16.0, 2.0, Color(0.82, 0.88, 1.0))
	_omni(Vector3(0, 3.7, 9.5), 15.0, 2.0, Color(0.85, 0.90, 1.0))
	_omni(Vector3(0, 2.8, 10.8), 9.0, 2.6, Color(1.0, 0.80, 0.50))


## ------------------------------------------------------- kept systems
## The fal.ai pilot seat at the helm anchor; helm_station.gd finds it by the
## "pilot_seat" group and swivels it to the canopy on sit. Rest yaw is turned
## slightly off the window (helm swivels it square). Kit-chair fallback.
const SEAT_POS := Vector3(0.0, 0, -2.9)

func _place_seat() -> void:
	if not _gen_seat(SEAT_POS, PI * 0.5 + 0.5):
		var scene := load("res://assets/thirdparty/Sci-Fi Essentials Kit[Standard]/glTF/Prop_Chair.gltf")
		if scene:
			var m := scene.instantiate() as Node3D
			add_child(m)
			m.position = SEAT_POS
			m.add_to_group("pilot_seat")


## A grungy panel-textured console table (desk) the cockpit console sits on, in
## front of the seated pilot and clear of the front bulkhead. Solid so the player
## can lean on / stand on it but not walk through.
func _build_console_table() -> void:
	var top := _panel_mat(Color(0.7, 0.72, 0.78))
	if top == null:
		top = _mat(Color(0.16, 0.17, 0.21), 0.5, 0.5)
	top.cull_mode = BaseMaterial3D.CULL_DISABLED
	var m := _box(Vector3(0.0, 0.26, -3.97), Vector3(2.9, 0.52, 1.42), top)
	# a slim gunmetal lip around the top edge for a finished desk read
	var lip := _mat(Color(0.19, 0.20, 0.23), 0.85, 0.35)
	_box(Vector3(0.0, 0.53, -3.97), Vector3(3.02, 0.06, 1.54), lip)
	var col := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(2.9, 0.52, 1.42)
	col.shape = b
	col.position = Vector3(0.0, 0.26, -3.97)
	add_child(col)


## Glass in the canopy so the windshield reads as real windows. Near-clear blue
## panes filling the opening (x[-3.2,3.2] y[1.1,3.8]) split by the two frame
## mullions, low-alpha + smooth so the helm's planet billboards still show
## through. Visual only — the front bulkhead collider already seals the front.
func _build_glass() -> void:
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.42, 0.56, 0.72, 0.14)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.metallic = 0.0
	glass.roughness = 0.05
	glass.rim_enabled = true
	glass.rim = 0.6
	glass.rim_tint = 0.5
	# three panes matching the mullions at x = ±3.2/3
	var edges := [-3.2, -3.2 / 3.0, 3.2 / 3.0, 3.2]
	for i in range(edges.size() - 1):
		var x0: float = edges[i]
		var x1: float = edges[i + 1]
		var pane := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(x1 - x0 - 0.12, 2.7)
		pane.mesh = qm
		pane.material_override = glass
		pane.position = Vector3((x0 + x1) * 0.5, (1.1 + 3.8) * 0.5, -4.62)
		add_child(pane)


## Dress the room with our own props, backs to the walls / facing inward: fal.ai
## side-control consoles down the cockpit flanks, and kit cargo (lockers, crates,
## a barrel, a chest) in the vendor bay. Each no-ops if its asset is missing.
const SIDE_CONSOLE_GLB := "res://assets/generated/interior/side_console.glb"

func _dress_props() -> void:
	# Cockpit flank control consoles (screens facing the room; backs to the walls).
	for spec in [[-4.55, -1.2, PI * 0.5], [-4.55, 1.4, PI * 0.5], [4.55, -1.2, -PI * 0.5], [4.55, 1.4, -PI * 0.5]]:
		var c := _gen_prop_glb(SIDE_CONSOLE_GLB, Vector3(spec[0], 0.0, spec[1]), spec[2], 1.1, true)
		if c:
			c.add_to_group("gen_side_console")
	# Vendor-bay cargo along the side walls.
	_prop("Prop_Locker", Vector3(-3.85, 0, 6.6), PI * 0.5, 1.0)
	_prop("Prop_Locker", Vector3(-3.85, 0, 7.8), PI * 0.5, 1.0)
	_prop("Prop_Crate", Vector3(3.7, 0, 6.6), -0.3, 1.0)
	_prop("Prop_Barrel1", Vector3(3.8, 0, 7.6), 0.0, 1.0)
	_prop("Prop_Chest", Vector3(-3.6, 0, 8.9), PI * 0.5, 1.0)


## Instance a generated GLB, scale so its larger footprint axis is `target`, sit
## its base on the floor at `pos`, rotate to yaw, optional solid collision.
func _gen_prop_glb(path: String, pos: Vector3, rot_y: float, target: float, collide := true) -> Node3D:
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
	a = _combined_aabb(m)
	m.position.y += pos.y - a.position.y
	if collide:
		_add_prop_collision(m)
	return m


## Full-length mirror on the bay's left wall, glass facing +X into the bay. The
## hull is on NO_REFLECT_LAYER so the wall behind the reflection camera doesn't
## occlude it (see _build_shell).
func _build_mirror() -> void:
	var mirror := Node3D.new()
	mirror.set_script(load("res://scripts/mirror.gd"))
	mirror.position = Vector3(-4.05, 0.0, 9.5)
	mirror.rotation.y = PI * 0.5
	add_child(mirror)


## The Forge Master shopfront on the bay's back wall: the fal.ai forge counter as
## the trade desk, a robot clerk behind it, goods on shelves, a sealed barrier so
## the player can't get behind the counter, and a nameplate. The invisible
## interaction body (Hub/ForgeMaster) is untouched, so aim+E still opens the shop.
func _build_vendor_stall() -> void:
	var box := get_node_or_null("../../ForgeMaster/Mesh")
	if box is Node3D:
		(box as Node3D).visible = false

	var counter_mat := _mat(Color(0.15, 0.16, 0.20), 0.6, 0.45)
	var top_mat := _mat(Color(0.85, 0.62, 0.30), 0.7, 0.3, true, Color(0.6, 0.4, 0.15), 0.4)
	var counter: Node3D = null
	var cscene := load("res://assets/generated/interior/forge_counter.glb")
	if cscene is PackedScene:
		counter = (cscene as PackedScene).instantiate() as Node3D
		add_child(counter)
		counter.rotation.y = -PI * 0.5
		counter.scale = Vector3(4.4, 3.7, 6.2)
		var ca := _combined_aabb(counter)
		counter.position = Vector3(0.0, -ca.position.y, 11.5)
		_add_prop_collision(counter)
		counter.add_to_group("gen_counter")
	if counter == null:
		_box(Vector3(0, 0.55, 11.4), Vector3(8, 1.1, 0.7), counter_mat)
		_box(Vector3(0, 1.15, 11.35), Vector3(8, 0.1, 0.95), top_mat)

	# Back partition sealing the shop area behind the counter (grungy hull panels).
	var shop_wall := _panel_mat()
	if shop_wall == null:
		shop_wall = counter_mat
	shop_wall.cull_mode = BaseMaterial3D.CULL_DISABLED
	_box(Vector3(-3.0, 2.0, 12.9), Vector3(2, 4, 0.2), shop_wall)
	_box(Vector3(3.0, 2.0, 12.9), Vector3(2, 4, 0.2), shop_wall)

	# Flanking the clerk, backs to the partition, pulled in off the side walls
	# (they were clipping into them at x±3.4).
	_prop("Prop_Shelves_WideTall", Vector3(-2.35, 0, 12.55), PI, 0.95)
	_prop("Prop_Shelves_WideTall", Vector3(2.35, 0, 12.55), PI, 0.95)

	var clerk_scene := load("res://assets/thirdparty/fab/skm_robot/skm_robot3_full.fbx")
	if clerk_scene is PackedScene:
		var clerk := (clerk_scene as PackedScene).instantiate() as Node3D
		add_child(clerk)
		clerk.position = Vector3(0, 0.0, 12.3)
		clerk.rotation.y = PI
		clerk.scale = Vector3.ONE * 1.15
		var mech_mat := _mat(Color(0.34, 0.36, 0.40), 0.9, 0.32)
		for m in clerk.find_children("*", "MeshInstance3D", true, false):
			(m as MeshInstance3D).material_override = mech_mat
		var idle := Node.new()
		idle.set_script(load("res://scripts/forge_master_idle.gd"))
		clerk.add_child(idle)

	var bar := CollisionShape3D.new()
	var bshape := BoxShape3D.new()
	bshape.size = Vector3(8, H, 0.4)
	bar.shape = bshape
	bar.position = Vector3(0, H * 0.5, 11.4)
	add_child(bar)
	var nameplate := Label3D.new()
	nameplate.text = "FORGE MASTER"
	nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	nameplate.no_depth_test = false
	nameplate.pixel_size = 0.006
	nameplate.modulate = Color(0.95, 0.78, 0.32)
	nameplate.outline_modulate = Color(0, 0, 0, 0.85)
	nameplate.outline_size = 14
	nameplate.position = Vector3(0, 2.5, 12.2)
	add_child(nameplate)
	_omni(Vector3(0, 2.4, 11.6), 7.0, 2.2, Color(1.0, 0.72, 0.4))


## ------------------------------------------------------- fallback blockout
## Minimal box room if the shell GLB isn't imported yet, so the hub still works.
func _build_fallback() -> void:
	var wall := _panel_mat()
	if wall == null:
		wall = _mat(Color(0.20, 0.22, 0.28), 0.0, 0.85)
	var floor_mat := _mat(Color(0.13, 0.14, 0.17), 0.1, 0.7)
	_box(Vector3(0, -0.15, 4.6), Vector3(10.6, 0.3, 19.0), floor_mat)   # floor (visual)
	_box(Vector3(0, 2.3, 5.0), Vector3(0.3, 4.6, 20.0), wall)           # left wall (visual)
	_box(Vector3(0, 2.3, 5.0), Vector3(0.3, 4.6, 20.0), wall)
	# (colliders come from _build_collision; this is only a visual safety net.)


## ------------------------------------------------------- helpers
const PROP_DIR := "res://assets/thirdparty/Sci-Fi Essentials Kit[Standard]/glTF/"

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


## The fal.ai pilot seat: scale to a target height, base on the floor at pos,
## facing rot_y, solid collision, in the "pilot_seat" group. False if missing.
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
	aabb = _combined_aabb(m)
	m.position.y += pos.y - aabb.position.y
	_add_prop_collision(m)
	return true


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


func _box(center: Vector3, size: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = mat
	mesh.position = center
	add_child(mesh)
	return mesh


func _omni(pos: Vector3, range_m: float, energy: float, color: Color) -> void:
	var light := OmniLight3D.new()
	light.position = pos
	light.omni_range = range_m
	light.light_energy = energy
	light.light_color = color
	add_child(light)


## Grungy sci-fi wall panelling (albedo + patina normal/roughness), world-
## triplanar so it tiles across the shell whatever its size. `tint` multiplies
## the albedo (used to darken the deck). Null if the albedo isn't imported yet.
func _panel_mat(tint := Color.WHITE) -> StandardMaterial3D:
	var albedo := load("res://assets/generated/interior/wall_panel_albedo.png") as Texture2D
	if albedo == null:
		return null
	var m := StandardMaterial3D.new()
	m.albedo_texture = albedo
	m.albedo_color = tint
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
	m.uv1_scale = Vector3.ONE * 0.35
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

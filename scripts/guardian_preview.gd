extends SubViewportContainer
## Rotating character preview for the inventory (T-0042): the CUSTOM Guardian rig
## playing its idle, tinted to match the in-game body, with the equipped armour
## plates attached on top. Refreshes live on SaveManager.loadout_changed, so
## equipping / unequipping a piece updates the figure immediately - the same
## loadout the hub mirror shows.
##
## Drop-in replacement for the old model_display turntable in inventory_screen.gd.

const GUARDIAN := "res://assets/generated/guardian/guardian.glb"
## Kept in sync with player_character.gd's body tuning so the preview matches the
## body seen in the hub mirror / first person.
const BODY_TINT := Color(0.19, 0.2, 0.25)
const BODY_METALLIC := 0.15
const BODY_ROUGHNESS := 0.7

var _viewport: SubViewport
var _pivot: Node3D
var _guardian: Node3D
var _skeleton: Skeleton3D
var _armor_root: Node3D          # holds the attached plate meshes, cleared on refresh
var _spin: float = 0.0
var _spin_rate: float = 0.4


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	var sm := get_node_or_null("/root/SaveManager")
	if sm and sm.has_signal("loadout_changed"):
		sm.loadout_changed.connect(_refresh_armor)


func _build() -> void:
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-28.0, -130.0, 0.0)
	key.light_energy = 1.4
	_viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-8.0, 60.0, 0.0)
	fill.light_energy = 0.5
	fill.light_color = Color(0.75, 0.82, 1.0)
	_viewport.add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-6.0, 175.0, 0.0)
	rim.light_energy = 0.9
	rim.light_color = Color(1.0, 0.85, 0.55)
	_viewport.add_child(rim)
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.44, 0.52)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)

	var cam := Camera3D.new()
	_viewport.add_child(cam)
	# frame a ~1.8 m figure (feet at origin), a touch above mid-body
	cam.look_at_from_position(Vector3(0.0, 1.0, 3.0), Vector3(0.0, 0.95, 0.0), Vector3.UP)

	_pivot = Node3D.new()
	_viewport.add_child(_pivot)

	var scene: Resource = load(GUARDIAN)
	if scene is PackedScene:
		_guardian = (scene as PackedScene).instantiate() as Node3D
		_pivot.add_child(_guardian)
		_tint_body(_guardian)
		var skels := _guardian.find_children("*", "Skeleton3D", true, false)
		_skeleton = skels[0] as Skeleton3D if not skels.is_empty() else null
		var aps := _guardian.find_children("*", "AnimationPlayer", true, false)
		if not aps.is_empty() and (aps[0] as AnimationPlayer).has_animation("idle"):
			var ap := aps[0] as AnimationPlayer
			ap.get_animation("idle").loop_mode = Animation.LOOP_LINEAR   # glTF import leaves it non-looping
			ap.play("idle")
	_armor_root = Node3D.new()
	if _skeleton:
		_skeleton.add_child(_armor_root)
	_refresh_armor()


## Same treatment as player_character._prep_body: keep the generated textures, tint
## toward gunmetal, modest metalness. Applied as a per-surface override.
func _tint_body(root: Node3D) -> void:
	for m in root.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var base := mi.get_active_material(s)
			if not (base is BaseMaterial3D):
				continue
			var mat: BaseMaterial3D = base.duplicate()
			mat.albedo_color = BODY_TINT
			mat.metallic = BODY_METALLIC
			mat.roughness = BODY_ROUGHNESS
			mi.set_surface_override_material(s, mat)


## Rebuild the attached armour plates from the equipped loadout. Wired in T-0042
## part (b) once the plate assets exist; for the base Guardian it is a no-op.
func _refresh_armor() -> void:
	if _armor_root == null:
		return
	for c in _armor_root.get_children():
		c.queue_free()
	# Placeholder for the armour-plate attachment pass (BoneAttachment3D per slot).


func _process(delta: float) -> void:
	if _pivot:
		_spin += delta * _spin_rate
		_pivot.rotation.y = _spin

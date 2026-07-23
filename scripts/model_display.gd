extends SubViewportContainer
## Renders a single 3D model into a UI panel with its own world, a framing camera
## and key/fill/rim lights, turning slowly so it reads as a character screen.
## Used by the inventory (player Guardian) and the vendor (Forge Master robot).
##
## Call setup() once after adding to the tree.

var _viewport: SubViewport
var _pivot: Node3D
var _model: Node3D
var _spin: float = 0.0
var _spin_rate: float = 0.5


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## model_path: res:// path to a PackedScene (glTF/FBX). look_y: vertical point the
## camera aims at. dist: camera distance. model_scale/model_y: fit the model.
## override_mat: optional material_override for every mesh (used to paint the
## texture-less robot). spin: radians/sec turntable.
func setup(model_path: String, look_y: float = 1.0, dist: float = 3.2,
		model_scale: float = 1.0, model_y: float = 0.0,
		override_mat: Material = null, spin: float = 0.5) -> void:
	_spin_rate = spin
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-32.0, -130.0, 0.0)
	key.light_energy = 1.5
	_viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-8.0, 60.0, 0.0)
	fill.light_energy = 0.55
	fill.light_color = Color(0.75, 0.82, 1.0)
	_viewport.add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-6.0, 175.0, 0.0)
	rim.light_energy = 0.9
	rim.light_color = Color(1.0, 0.85, 0.55)
	_viewport.add_child(rim)

	var cam := Camera3D.new()
	_viewport.add_child(cam)
	# look_at() needs the node in the tree; this is called during _build(), before
	# the container is parented, so set the framing transform directly.
	cam.look_at_from_position(Vector3(0.0, look_y, dist), Vector3(0.0, look_y, 0.0), Vector3.UP)

	_pivot = Node3D.new()
	_viewport.add_child(_pivot)

	var scene: Resource = load(model_path)
	if scene is PackedScene:
		_model = (scene as PackedScene).instantiate() as Node3D
		_model.scale = Vector3.ONE * model_scale
		_model.position = Vector3(0.0, model_y, 0.0)
		if override_mat != null:
			for m in _model.find_children("*", "MeshInstance3D", true, false):
				(m as MeshInstance3D).material_override = override_mat
		_pivot.add_child(_model)


func _process(delta: float) -> void:
	if _pivot:
		_spin += delta * _spin_rate
		_pivot.rotation.y = _spin

extends Area3D
## Archive Core pickup (T-0014): a glowing objective item with a 2.5 m proximity
## prompt. On interact it emits `collected` and frees itself.

signal collected

const PICKUP_RADIUS := 2.5

const MODEL := "res://assets/generated/earth/archive_core.glb"

var _in_range: bool = false
var _collected: bool = false
var _prompt: Label3D
var _spin: Node3D


func _ready() -> void:
	add_to_group("archive_core")
	collision_mask = 1
	var col := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = PICKUP_RADIUS
	col.shape = sph
	add_child(col)

	# fal.ai hero model (Hunyuan Pro image-to-3d, decimated + 2K PBR); falls back to a
	# glowing box if the GLB is missing. A green OmniLight sells the energy-core glow.
	if ResourceLoader.exists(MODEL):
		var vis := (load(MODEL) as PackedScene).instantiate() as Node3D
		vis.scale = Vector3.ONE * 1.15
		vis.position = Vector3(0, 0.95, 0)
		add_child(vis)
		_spin = vis
	else:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.6, 0.6, 0.6)
		mesh.mesh = box
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.2, 0.9, 0.5)
		m.emission_enabled = true
		m.emission = Color(0.2, 1.0, 0.6)
		m.emission_energy_multiplier = 3.0
		mesh.material_override = m
		mesh.position = Vector3(0, 0.5, 0)
		add_child(mesh)
		_spin = mesh

	var glow := OmniLight3D.new()
	glow.light_color = Color(0.3, 1.0, 0.55)
	glow.light_energy = 3.5
	glow.omni_range = 7.0
	glow.position = Vector3(0, 1.0, 0)
	add_child(glow)

	_prompt = Label3D.new()
	_prompt.text = "Press E - Archive Core"
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.position = Vector3(0, 2.3, 0)   # clear above the core model (not inside it)
	_prompt.visible = false
	add_child(_prompt)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	if _spin != null:
		_spin.rotate_y(delta * 0.8)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_in_range = true
		_prompt.visible = true


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_in_range = false
		_prompt.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if _in_range and not _collected and event.is_action_pressed("interact"):
		collect()


func collect() -> void:
	if _collected:
		return
	_collected = true
	collected.emit()
	queue_free()

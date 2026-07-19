extends Area3D
## Archive Core pickup (T-0014): a glowing objective item with a 2.5 m proximity
## prompt. On interact it emits `collected` and frees itself.

signal collected

const PICKUP_RADIUS := 2.5

var _in_range: bool = false
var _collected: bool = false
var _prompt: Label3D


func _ready() -> void:
	add_to_group("archive_core")
	collision_mask = 1
	var col := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = PICKUP_RADIUS
	col.shape = sph
	add_child(col)

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

	_prompt = Label3D.new()
	_prompt.text = "Press E — Archive Core"
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.position = Vector3(0, 1.4, 0)
	_prompt.visible = false
	add_child(_prompt)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


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

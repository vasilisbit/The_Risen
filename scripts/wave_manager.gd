class_name WaveManager
extends Node
## T-0016 Mars wave spawner. 12 waves across the 3 chambers (4 waves each, GDD
## §3.3 compositions). Enemies spawn at random room spawn_point markers with a
## 0.5 s stagger, each telegraphed by a portal VFX 2 s ahead. A wave counter UI
## shows "Wave n/12" and the remaining count; clearing a wave starts a 15 s
## intermission then the buff selection, and clearing wave 12 completes the
## mission (save + fade to hub).

signal wave_started(number: int)
signal wave_cleared(number: int)
signal all_waves_complete

const RUSHER := "res://scenes/enemies/rusher.tscn"
const SHOOTER := "res://scenes/enemies/shooter.tscn"
const EXPLODER := "res://scenes/enemies/exploder.tscn"

const STAGGER := 0.5           # s between successive portal openings
const PORTAL_LEAD := 2.0       # s a portal is visible before its enemy appears
const INTERMISSION := 15.0     # s countdown after a wave is cleared
const BUFF_TIMEOUT := 10.0     # s before the buff picker auto-selects

## GDD §3.3 wave table — [rushers, shooters, exploders] per wave.
## Wave 12 also gets the Teleporting Phantom once T-0019 lands.
const WAVES := [
	[8, 2, 0], [6, 4, 2], [10, 5, 0], [8, 5, 2],        # Room 1, waves 1-4
	[10, 5, 0], [12, 4, 2], [15, 5, 0], [12, 6, 2],     # Room 2, waves 5-8
	[15, 5, 0], [12, 8, 2], [18, 7, 0], [10, 5, 0],     # Room 3, waves 9-12
]
## Marker z-bands per chamber (Mars rooms centred at -121.5 / -136.5 / -151.5).
const ROOM_BANDS := [[-129.0, -114.0], [-144.0, -129.0], [-159.0, -144.0]]

@export var mission_id: String = "Mars"
@export var return_scene: String = "res://scenes/hub/hub.tscn"

var wave_index: int = -1       # -1 until the first wave starts
var remaining: int = 0         # enemies of this wave still alive

var _pending: int = 0          # portal coroutines that have not spawned yet
var _spawn_done: bool = false
var _wave_active: bool = false
var _label: Label
var _buff_layer: CanvasLayer


## Waves begin when the player crosses into the first chamber rather than on a
## timer — otherwise enemies would spawn while the player is still platforming.
const START_TRIGGER_Z := -114.0

var _started: bool = false


func _ready() -> void:
	_build_ui()
	_update_label("Reach the Nexus Chamber")


func _physics_process(_delta: float) -> void:
	if _started:
		return
	var p := get_tree().get_first_node_in_group("player")
	if p != null and (p as Node3D).global_position.z <= START_TRIGGER_Z:
		_started = true
		start_wave(0)


# --- wave lifecycle ---------------------------------------------------------

func start_wave(index: int) -> void:
	if index >= WAVES.size():
		return
	wave_index = index
	remaining = 0
	_pending = 0
	_spawn_done = false
	_wave_active = true
	wave_started.emit(index + 1)
	_update_label()
	_spawn_wave(index)


func _spawn_wave(index: int) -> void:
	var types := _wave_types(index)
	var markers := _room_markers(room_for_wave(index))
	if markers.is_empty():
		_spawn_done = true
		return
	for t in types:
		var m: Node3D = markers[randi() % markers.size()]
		_spawn_one(t, m.global_position)
		await get_tree().create_timer(STAGGER).timeout
	_spawn_done = true
	_check_cleared()


## Open a portal, wait PORTAL_LEAD, then drop the enemy through it.
func _spawn_one(type_path: String, pos: Vector3) -> void:
	_pending += 1
	var vfx := _portal_vfx(pos)
	await get_tree().create_timer(PORTAL_LEAD).timeout
	if is_instance_valid(vfx):
		vfx.queue_free()
	var scene := load(type_path)
	if scene != null:
		var e := scene.instantiate() as Node3D
		var host := get_tree().current_scene
		if host:
			host.add_child(e)
			e.global_position = pos + Vector3(0, 1, 0)
			remaining += 1
			if e.has_signal("died"):
				e.died.connect(_on_enemy_died)
	_pending -= 1
	_update_label()
	_check_cleared()


func _on_enemy_died(_where: Vector3) -> void:
	remaining = maxi(0, remaining - 1)
	_update_label()
	_check_cleared()


func _check_cleared() -> void:
	if not _wave_active or not _spawn_done or _pending > 0 or remaining > 0:
		return
	_wave_active = false
	wave_cleared.emit(wave_index + 1)
	if wave_index >= WAVES.size() - 1:
		_on_all_complete()
	else:
		_intermission()


func _intermission() -> void:
	var left := INTERMISSION
	while left > 0.0:
		_update_label("Wave %d cleared — next in %d" % [wave_index + 1, int(ceil(left))])
		await get_tree().create_timer(1.0).timeout
		left -= 1.0
	_show_buff_ui()


func _on_all_complete() -> void:
	_update_label("All waves cleared!")
	all_waves_complete.emit()
	var sm := get_node_or_null("/root/SaveManager")
	if sm and sm.has_method("complete_mission"):
		sm.complete_mission(mission_id)
	var gs := get_node_or_null("/root/GameState")
	if gs and gs.has_method("transition_to"):
		gs.transition_to(return_scene)
	else:
		get_tree().change_scene_to_file(return_scene)


# --- helpers ----------------------------------------------------------------

func room_for_wave(index: int) -> int:
	return clampi(index / 4, 0, ROOM_BANDS.size() - 1)


func _wave_types(index: int) -> Array:
	var row: Array = WAVES[index]
	var list: Array = []
	for i in int(row[0]):
		list.append(RUSHER)
	for i in int(row[1]):
		list.append(SHOOTER)
	for i in int(row[2]):
		list.append(EXPLODER)
	list.shuffle()
	return list


func _room_markers(room: int) -> Array:
	var band: Array = ROOM_BANDS[room]
	var res: Array = []
	for m in get_tree().get_nodes_in_group("spawn_point"):
		var z: float = (m as Node3D).global_position.z
		if z > float(band[0]) and z <= float(band[1]):
			res.append(m)
	return res


func _portal_vfx(pos: Vector3) -> Node3D:
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.55
	torus.outer_radius = 0.95
	mi.mesh = torus
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.25, 0.5, 1.0)
	m.emission_enabled = true
	m.emission = Color(0.35, 0.6, 1.0)
	m.emission_energy_multiplier = 3.0
	mi.material_override = m
	var host := get_tree().current_scene
	if host == null:
		host = get_tree().root
	host.add_child(mi)
	mi.global_position = pos + Vector3(0, 1.0, 0)
	mi.rotation.x = PI * 0.5                      # lie flat like a gateway
	var tw := mi.create_tween().set_loops()
	tw.tween_property(mi, "scale", Vector3.ONE * 1.25, 0.6)
	tw.tween_property(mi, "scale", Vector3.ONE * 0.9, 0.6)
	return mi


# --- UI ---------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_label.position = Vector2(-160, 14)
	_label.custom_minimum_size = Vector2(320, 0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 22)
	layer.add_child(_label)


func _update_label(override_text: String = "") -> void:
	if _label == null:
		return
	if override_text != "":
		_label.text = override_text
		return
	_label.text = "Wave %d/%d    Enemies: %d" % [wave_index + 1, WAVES.size(), remaining]


func _show_buff_ui() -> void:
	_buff_layer = CanvasLayer.new()
	_buff_layer.layer = 20
	add_child(_buff_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buff_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_buff_layer.add_child(center)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	center.add_child(vbox)
	var title := Label.new()
	title.text = "CHOOSE A BUFF"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)
	for opt in [["damage", "+20% Weapon Damage"], ["health", "+50 Max HP"], ["armor", "-15% Damage Taken"]]:
		var b := Button.new()
		b.text = opt[1]
		b.custom_minimum_size = Vector2(320, 44)
		var id: String = opt[0]
		b.pressed.connect(func() -> void: _choose_buff(id))
		vbox.add_child(b)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_auto_pick_after(BUFF_TIMEOUT)


func _auto_pick_after(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	if _buff_layer != null and is_instance_valid(_buff_layer):
		_choose_buff("damage")          # auto-select if the player didn't pick


func _choose_buff(id: String) -> void:
	if _buff_layer == null or not is_instance_valid(_buff_layer):
		return
	apply_buff(id)
	_buff_layer.queue_free()
	_buff_layer = null
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	start_wave(wave_index + 1)


## Apply a buff to the player. Public so it is unit-testable.
func apply_buff(id: String) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	match id:
		"damage":
			var wm := player.get_node_or_null("WeaponManager")
			if wm and ("_weapons" in wm):
				for w in wm._weapons:
					w.damage_multiplier *= 1.2
		"health":
			player.max_health_bonus += 50.0
			player.health += 50.0
			player.health_changed.emit(player.health, player.max_hp())
		"armor":
			player.damage_reduction = clampf(player.damage_reduction + 0.15, 0.0, 0.9)

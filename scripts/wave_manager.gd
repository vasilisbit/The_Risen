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
const PORTAL_SCENE := "res://scenes/vfx/portal_vfx.tscn"
const BUFF_UI_SCENE := "res://ui/buff_select.tscn"
const PHANTOM := "res://scenes/enemies/phantom.tscn"

const STAGGER := 0.5           # s between successive portal openings
const PORTAL_LEAD := 2.0       # s a portal is visible before its enemy appears
const INTERMISSION := 15.0     # s countdown after a wave is cleared
const BUFF_TIMEOUT := 10.0     # s before the buff picker auto-selects

## GDD §3.3 wave table - [rushers, shooters, exploders] per wave.
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
## timer - otherwise enemies would spawn while the player is still platforming.
const START_TRIGGER_Z := -114.0

var _started: bool = false


func _ready() -> void:
	# Enemy modifiers are static, so clear any left over from a previous run.
	EnemyBase.reset_modifiers()
	var tel := get_node_or_null("/root/Telemetry")
	if tel:
		tel.mission_started(mission_id)
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
	# Each wave is a checkpoint. Mars has no ObjectiveManager, and without this
	# a death on wave 11 would drop the player back at the last platforming
	# checkpoint, outside the chambers entirely.
	var p := get_tree().get_first_node_in_group("player")
	if p and p.has_method("checkpoint_here"):
		p.checkpoint_here()
	wave_started.emit(index + 1)
	var tel := get_node_or_null("/root/Telemetry")
	if tel:
		tel.wave_started(index + 1)
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
	# Final wave also brings the Teleporting Phantom mini-boss (T-0019). It goes
	# through the same portal telegraph and counts toward the clear condition.
	if index == WAVES.size() - 1:
		var bm: Node3D = markers[randi() % markers.size()]
		_spawn_one(PHANTOM, bm.global_position)
	_spawn_done = true
	_check_cleared()


## Open a portal, wait PORTAL_LEAD, then drop the enemy through it.
func _spawn_one(type_path: String, pos: Vector3) -> void:
	_pending += 1
	var vfx := _portal_vfx(pos)
	await get_tree().create_timer(PORTAL_LEAD).timeout
	if is_instance_valid(vfx):
		# Let the portal close gracefully (stops emitting, frees once faded).
		if vfx.has_method("close"):
			vfx.close()
		else:
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
		_update_label("Wave %d cleared - next in %d" % [wave_index + 1, int(ceil(left))])
		await get_tree().create_timer(1.0).timeout
		left -= 1.0
	_show_buff_ui()


func _on_all_complete() -> void:
	_update_label("All waves cleared!")
	all_waves_complete.emit()
	var tel := get_node_or_null("/root/Telemetry")
	if tel:
		# The last wave has no buff pick, so it reports an empty selection.
		tel.wave_completed(wave_index + 1, "")
		tel.mission_completed(mission_id)
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


## Open the T-0017 GPUParticles3D portal at a spawn marker.
func _portal_vfx(pos: Vector3) -> Node3D:
	var scene := load(PORTAL_SCENE)
	if scene == null:
		return null
	var vfx := scene.instantiate() as Node3D
	var host := get_tree().current_scene
	if host == null:
		host = get_tree().root
	host.add_child(vfx)
	vfx.global_position = pos + Vector3(0, 1.0, 0)
	return vfx


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


## Open the T-0018 selection UI (3 random buff/debuff options, 10 s auto-pick).
func _show_buff_ui() -> void:
	var scene := load(BUFF_UI_SCENE)
	if scene == null:
		start_wave(wave_index + 1)
		return
	_buff_layer = CanvasLayer.new()
	_buff_layer.layer = 20
	add_child(_buff_layer)
	var ui := scene.instantiate() as Control
	_buff_layer.add_child(ui)
	ui.option_chosen.connect(_on_option_chosen)


## WaveComplete is logged here rather than at clear time: buff_selected is one
## of its parameters and it isn't known until the player picks.
func _on_option_chosen(id: String) -> void:
	var tel := get_node_or_null("/root/Telemetry")
	if tel:
		tel.wave_completed(wave_index + 1, id)
	apply_modifier(id)
	if _buff_layer != null and is_instance_valid(_buff_layer):
		_buff_layer.queue_free()
	_buff_layer = null
	start_wave(wave_index + 1)


## Apply a buff/debuff. Modifiers are SET per type (not stacked), so a pick lasts
## until the mission ends or the same type is picked again - matching the card's
## "until the end of the mission or the next pick". Public for testing.
func apply_modifier(id: String) -> void:
	var player := get_tree().get_first_node_in_group("player")
	match id:
		"damage":
			if player:
				var wm := player.get_node_or_null("WeaponManager")
				if wm and ("_weapons" in wm):
					for w in wm._weapons:
						w.damage_multiplier = 1.2
		"health":
			if player:
				var delta: float = 50.0 - float(player.max_health_bonus)
				player.max_health_bonus = 50.0
				player.health = minf(player.health + maxf(delta, 0.0), player.max_hp())
				player.health_changed.emit(player.health, player.max_hp())
		"armor":
			if player:
				player.damage_reduction = 0.15
		"enemy_speed":
			EnemyBase.speed_scale = 0.9          # -10% enemy movement
		"enemy_accuracy":
			EnemyBase.accuracy_penalty = 0.05    # -5% enemy accuracy

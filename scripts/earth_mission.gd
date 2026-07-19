extends Node
## Earth mission driver (T-0014, spawn tuning). Each zone's enemies spawn only
## when the player advances into that zone (not all 30 at spawn-in, so you are
## not swarmed on arrival). Deaths feed the ObjectiveManager kill counter. The
## Archive Core and the Shielded Brute are revealed in objective order.

const RUSHER := "res://scenes/enemies/rusher.tscn"
const SHOOTER := "res://scenes/enemies/shooter.tscn"
const EXPLODER := "res://scenes/enemies/exploder.tscn"
const BRUTE := "res://scenes/enemies/shielded_brute.tscn"
const ARCHIVE_CORE := "res://scripts/archive_core.gd"

const ARCHIVE_POS := Vector3(0, 3.1, -78)     # in the boss arena
const BOSS_POS := Vector3(0, 3.1, -85)

# Player advances toward -Z; spawn a zone once the player crosses its trigger.
const ZONE_TRIGGER_Z := [0.0, -18.0, -50.0]

@onready var _obj: ObjectiveManager = get_node("../ObjectiveManager")

var _player: Node3D
var _zone_spawned: Array[bool] = [false, false, false]


func _ready() -> void:
	if _obj:
		_obj.objective_advanced.connect(_on_objective_advanced)


func _physics_process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return
	var z := _player.global_position.z
	for zone in 3:
		if not _zone_spawned[zone] and z <= ZONE_TRIGGER_Z[zone]:
			_spawn_zone(zone)


func _spawn_zone(zone: int) -> void:
	_zone_spawned[zone] = true
	var host := get_tree().current_scene
	var markers := _zone_markers(zone)
	for i in markers.size():
		var scene := load(_type_for(zone, i))
		if scene == null:
			continue
		var e := scene.instantiate() as Node3D
		host.add_child(e)
		e.global_position = markers[i].global_position + Vector3(0, 1, 0)
		if e.has_signal("died"):
			e.died.connect(_on_enemy_killed)


## spawn_point markers filtered to a zone by z band:
## 0 Street z>-18, 1 Subway -44<z<=-18, 2 Rooftop z<=-44.
func _zone_markers(zone: int) -> Array:
	var lo: float = [-18.0, -44.0, -100000.0][zone]
	var hi: float = [100000.0, -18.0, -44.0][zone]
	var res: Array = []
	for m in get_tree().get_nodes_in_group("spawn_point"):
		var z: float = (m as Node3D).global_position.z
		if z > lo and z <= hi:
			res.append(m)
	return res


## GDD §3.2 per-zone mix: Street 5R+5S, Subway 8R+2S, Rooftop 3R+5S+2E.
func _type_for(zone: int, i: int) -> String:
	match zone:
		0:
			return SHOOTER if i < 5 else RUSHER
		1:
			return SHOOTER if i < 2 else RUSHER
		2:
			if i < 2:
				return EXPLODER
			elif i < 7:
				return SHOOTER
			return RUSHER
	return RUSHER


func _on_enemy_killed(_where: Vector3) -> void:
	if _obj:
		_obj.register_kill()


func _on_objective_advanced(index: int) -> void:
	if index == 1:
		_spawn_archive_core()
	elif index == 2:
		_spawn_boss()


func _spawn_archive_core() -> void:
	var core := Area3D.new()
	core.set_script(load(ARCHIVE_CORE))
	get_tree().current_scene.add_child(core)
	core.global_position = ARCHIVE_POS
	if core.has_signal("collected"):
		core.collected.connect(func() -> void: _obj.notify_flag("archive"))


func _spawn_boss() -> void:
	var scene := load(BRUTE)
	if scene == null:
		return
	var boss := scene.instantiate() as Node3D
	get_tree().current_scene.add_child(boss)
	boss.global_position = BOSS_POS + Vector3(0, 1, 0)
	if boss.has_signal("died"):
		boss.died.connect(func(_w: Vector3) -> void: _obj.notify_flag("boss"))

extends Node
## Earth mission driver (T-0014): spawns the 30 zone enemies at the spawn_point
## markers, wires their deaths to the ObjectiveManager, and reveals the Archive
## Core and the Shielded Brute in objective order (so the boss can't be killed
## before its objective is active).

const RUSHER := "res://scenes/enemies/rusher.tscn"
const SHOOTER := "res://scenes/enemies/shooter.tscn"
const EXPLODER := "res://scenes/enemies/exploder.tscn"
const BRUTE := "res://scenes/enemies/shielded_brute.tscn"
const ARCHIVE_CORE := "res://scripts/archive_core.gd"

const ARCHIVE_POS := Vector3(0, 3.1, -78)     # in the boss arena
const BOSS_POS := Vector3(0, 3.1, -85)

@onready var _obj: ObjectiveManager = get_node("../ObjectiveManager")


func _ready() -> void:
	# Defer so the level's runtime-built spawn_point markers exist first.
	_spawn_enemies.call_deferred()
	if _obj:
		_obj.objective_advanced.connect(_on_objective_advanced)


func _spawn_enemies() -> void:
	var markers := get_tree().get_nodes_in_group("spawn_point")
	var host := get_tree().current_scene
	for i in markers.size():
		var scene := load(_type_for(i))
		if scene == null:
			continue
		var e := scene.instantiate() as Node3D
		host.add_child(e)
		e.global_position = (markers[i] as Node3D).global_position + Vector3(0, 1, 0)
		if e.has_signal("died"):
			e.died.connect(_on_enemy_killed)


## Mix ~16 Rushers / 12 Shooters / 2 Exploders over the 30 markers.
func _type_for(i: int) -> String:
	if i % 15 == 14:
		return EXPLODER
	elif i % 5 < 2:
		return SHOOTER
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

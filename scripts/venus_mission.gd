extends Node
## T-0020 Venus mission driver. Mirrors earth_mission.gd: enemies spawn per
## section as the player advances (not all 35 at once), and the ordered
## objectives from GDD §3.4 are driven by section triggers plus the scripted
## lava-pool dive that teleports the player into the boss arena.
##
## The Ember Tyrant itself is T-0021 - until that scene exists the final
## objective simply cannot complete, and the mission is a playable blockout.

const RUSHER := "res://scenes/enemies/rusher.tscn"
const SHOOTER := "res://scenes/enemies/shooter.tscn"
const EXPLODER := "res://scenes/enemies/exploder.tscn"
const EMBER_TYRANT := "res://scenes/enemies/ember_tyrant.tscn"

const SECTION_ASCENT := 0
const SECTION_DESCENT := 1

## Seconds between the Ember Tyrant dying and the mission completing. GDD §3.4
## says 5 s before the victory screen; 8 s here because completing the mission
## frees the level, and with it the boss's four guaranteed drops - the player
## needs long enough to actually walk over them.
const VICTORY_DELAY := 8.0

# Section boundaries along -Z. Must track venus_level.gd: the ascent is 200 m
# long and its summit pad runs 12 m further to the cavern mouth.
const SUMMIT_Z := -170.0        # far enough up the slope to count as "summit"
const CAVERN_Z := -212.0        # cavern mouth = end of the summit pad

@onready var _obj: ObjectiveManager = get_node("../ObjectiveManager")

var _player: Node3D
var _spawned: Array[bool] = [false, false]
var _dived: bool = false


func _ready() -> void:
	for pool in get_tree().get_nodes_in_group("lava_pool"):
		(pool as Area3D).body_entered.connect(_on_pool_entered)


func _physics_process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return
	var z := _player.global_position.z

	if not _spawned[SECTION_ASCENT]:
		_spawn_section(SECTION_ASCENT)
	if z <= SUMMIT_Z:
		_obj.notify_flag("summit")
	if z <= CAVERN_Z:
		if not _spawned[SECTION_DESCENT]:
			_spawn_section(SECTION_DESCENT)
		_obj.notify_flag("descent")


# --- spawning ---------------------------------------------------------------

func _spawn_section(section: int) -> void:
	_spawned[section] = true
	var host := get_tree().current_scene
	var markers := _section_markers(section)
	for i in markers.size():
		var scene := load(_type_for(section, i))
		if scene == null:
			continue
		var e := scene.instantiate() as Node3D
		host.add_child(e)
		e.global_position = (markers[i] as Node3D).global_position + Vector3(0, 1, 0)
		if e.has_signal("died"):
			e.died.connect(_on_enemy_killed)


## spawn_point markers split by z: the ascent is everything above the cavern
## mouth, the descent is everything beyond it.
func _section_markers(section: int) -> Array:
	var res: Array = []
	for m in get_tree().get_nodes_in_group("spawn_point"):
		var z: float = (m as Node3D).global_position.z
		var in_ascent := z > CAVERN_Z
		if (section == SECTION_ASCENT) == in_ascent:
			res.append(m)
	return res


## GDD §3.4 per-section mix. Marker creation order in venus_level.gd puts the
## cover/ledge positions first, so the shooters land where cover exists.
##   Ascent  (20): 8 Shooters (rock cover) + 12 Rushers (open slope)
##   Descent (15): 5 Shooters (wall ledges) + 2 Exploders + 8 Rushers (floors)
func _type_for(section: int, i: int) -> String:
	if section == SECTION_ASCENT:
		return SHOOTER if i < 8 else RUSHER
	if i < 5:
		return SHOOTER
	elif i < 7:
		return EXPLODER
	return RUSHER


func _on_enemy_killed(_where: Vector3) -> void:
	if _obj:
		_obj.register_kill()


# --- scripted lava-pool dive ------------------------------------------------

## GDD §3.4 objective 3: the player jumps into the pool and is carried through a
## hidden passage to the boss chamber. This pool is deliberately NOT a lava
## hazard - it is the way forward.
func _on_pool_entered(body: Node) -> void:
	if _dived or not body.is_in_group("player"):
		return
	_dived = true
	_obj.notify_flag("pool")
	_teleport_to_arena(body as Node3D)
	_spawn_boss()


func _teleport_to_arena(player: Node3D) -> void:
	var entry := get_tree().get_first_node_in_group("arena_entry")
	if entry == null:
		return
	player.global_position = (entry as Node3D).global_position
	player.velocity = Vector3.ZERO
	if player.has_method("set_checkpoint"):
		player.set_checkpoint((entry as Node3D).global_position)


func _spawn_boss() -> void:
	if not ResourceLoader.exists(EMBER_TYRANT):
		print("Venus: Ember Tyrant not implemented yet (T-0021)")
		return
	var scene := load(EMBER_TYRANT)
	if scene == null:
		return
	var spawn := get_tree().get_first_node_in_group("boss_spawn")
	var boss := scene.instantiate() as Node3D
	get_tree().current_scene.add_child(boss)
	if spawn:
		boss.global_position = (spawn as Node3D).global_position
	if boss.has_signal("died"):
		boss.died.connect(_on_boss_died)


func _on_boss_died(_where: Vector3) -> void:
	await get_tree().create_timer(VICTORY_DELAY).timeout
	if is_instance_valid(_obj):
		_obj.notify_flag("boss")

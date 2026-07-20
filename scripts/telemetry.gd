extends Node

## Telemetry autoload (T-0026). Appends one JSON object per line to
## user://logs/telemetry_YYYY-MM-DD.json:
##
##     {"timestamp": "2026-07-20T14:31:07Z", "event": "EnemyKilled",
##      "params": {"enemy_type": "Rusher", "weapon_used": "Auto Rifle",
##                 "headshot": false}}
##
## Event and parameter names are taken verbatim from docs/TELEMETRY.md, because
## scripts/telemetry_analyzer.py reads these keys directly and the card requires
## it to run unchanged.
##
## The file handle stays open and is flushed periodically rather than reopened
## per event - a mission produces hundreds of lines and reopening each time
## would be needless syscalls.

const LOG_DIR := "user://logs"
const FLUSH_EVERY := 20            # events between flushes
const SUPER_WINDOW := 5.0          # s counted toward enemies_killed_during

## Set false to disable logging (playtest builds keep it on).
var enabled: bool = true

## Counters the mission events report. Reset by mission_started().
var deaths_this_mission: int = 0
var loot_this_mission: int = 0

var _file: FileAccess
var _path: String = ""
var _since_flush: int = 0
var _mission_id: String = ""
var _mission_start_msec: int = 0
var _wave_start_msec: int = 0
var _phase_msec: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_open()


func _exit_tree() -> void:
	_close()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_close()


# --- file -------------------------------------------------------------------

func _open() -> void:
	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	var date := Time.get_datetime_string_from_system(true).substr(0, 10)
	_path = "%s/telemetry_%s.json" % [LOG_DIR, date]
	# Append: a day's play across several launches belongs in one file.
	if FileAccess.file_exists(_path):
		_file = FileAccess.open(_path, FileAccess.READ_WRITE)
		if _file:
			_file.seek_end()
	else:
		_file = FileAccess.open(_path, FileAccess.WRITE)
	if _file == null:
		push_warning("Telemetry: cannot open %s (%d)" % [_path, FileAccess.get_open_error()])


func _close() -> void:
	if _file:
		_file.flush()
		_file.close()
		_file = null


## Absolute path of today's log - handy for tests and for finding it on disk.
func log_path() -> String:
	return ProjectSettings.globalize_path(_path)


func flush() -> void:
	if _file:
		_file.flush()
	_since_flush = 0


# --- core -------------------------------------------------------------------

## Append one event. `params` keys must match docs/TELEMETRY.md.
func log_event(event_name: String, params: Dictionary = {}) -> void:
	if not enabled or _file == null:
		return
	var line := {
		"timestamp": Time.get_datetime_string_from_system(true) + "Z",
		"event": event_name,
		"params": params,
	}
	_file.store_line(JSON.stringify(line))
	_since_flush += 1
	if _since_flush >= FLUSH_EVERY:
		flush()


func _class_name() -> String:
	var sm := get_node_or_null("/root/SaveManager")
	return String(sm.data.get("selected_class", "Assault")) if sm else "Assault"


func current_mission() -> String:
	return _mission_id


# --- mission ----------------------------------------------------------------

func mission_started(mission_id: String) -> void:
	_mission_id = mission_id
	_mission_start_msec = Time.get_ticks_msec()
	deaths_this_mission = 0
	loot_this_mission = 0
	# Record where the ship is parked, for the hub window planet (T-0028).
	# Done here because every mission driver already reports its start.
	var sm := get_node_or_null("/root/SaveManager")
	if sm:
		sm.data["last_mission"] = mission_id
		sm.save_game()
	log_event("MissionStart", {
		"mission_id": mission_id,
		"class": _class_name(),
		"timestamp": Time.get_datetime_string_from_system(true) + "Z",
	})


func mission_completed(mission_id: String) -> void:
	log_event("MissionComplete", {
		"mission_id": mission_id,
		"duration_seconds": _elapsed(_mission_start_msec),
		"deaths": deaths_this_mission,
		"loot_earned": loot_this_mission,
	})
	flush()             # a completed run should survive a crash afterwards


func mission_failed(mission_id: String, reason: String) -> void:
	log_event("MissionFailed", {
		"mission_id": mission_id,
		"reason": reason,
		"timestamp": Time.get_datetime_string_from_system(true) + "Z",
	})
	flush()


# --- combat -----------------------------------------------------------------

func player_died(location: Vector3, enemy_type: String) -> void:
	deaths_this_mission += 1
	log_event("PlayerDeath", {
		"mission_id": _mission_id,
		# Rounded to whole metres: this feeds a balance heatmap, not a replay.
		"location": [int(round(location.x)), int(round(location.y)), int(round(location.z))],
		"enemy_type": enemy_type,
		"timestamp": Time.get_datetime_string_from_system(true) + "Z",
	})


func enemy_killed(enemy_type: String, weapon_used: String, headshot: bool) -> void:
	log_event("EnemyKilled", {
		"enemy_type": enemy_type,
		"weapon_used": weapon_used,
		"headshot": headshot,
	})


func loot_picked(item_type: String, rarity: String) -> void:
	loot_this_mission += 1
	log_event("LootPicked", {
		"item_type": item_type,
		"rarity": rarity,
		"mission_id": _mission_id,
	})


# --- abilities --------------------------------------------------------------

## Supers report how many enemies died in the SUPER_WINDOW after the cast, so
## the write is deferred by that long. The event still carries the activation
## timestamp, so ordering by time stays correct.
func used_super() -> void:
	var at := Time.get_datetime_string_from_system(true) + "Z"
	var before := _enemy_count()
	await get_tree().create_timer(SUPER_WINDOW).timeout
	if not enabled or _file == null:
		return
	var killed: int = maxi(0, before - _enemy_count())
	_file.store_line(JSON.stringify({
		"timestamp": at,
		"event": "PlayerUsedSuper",
		"params": {
			"class": _class_name(),
			"mission_id": _mission_id,
			"enemies_killed_during": killed,
		},
	}))
	_since_flush += 1


func used_grenade() -> void:
	log_event("PlayerUsedGrenade", {"class": _class_name(), "mission_id": _mission_id})


func used_melee() -> void:
	log_event("PlayerUsedMelee", {"class": _class_name(), "mission_id": _mission_id})


func _enemy_count() -> int:
	var tree := get_tree()
	return tree.get_nodes_in_group("enemy").size() if tree else 0


# --- waves / boss / vendor --------------------------------------------------

func wave_started(wave_number: int) -> void:
	_wave_start_msec = Time.get_ticks_msec()
	log_event("WaveStart", {"wave_number": wave_number})


## `buff_selected` is the pick made after the wave; "" until the player chooses.
func wave_completed(wave_number: int, buff_selected: String = "") -> void:
	log_event("WaveComplete", {
		"wave_number": wave_number,
		"time_seconds": _elapsed(_wave_start_msec),
		"buff_selected": buff_selected,
	})


func boss_phase_transition(boss_id: String, phase_from: String, phase_to: String) -> void:
	var now := Time.get_ticks_msec()
	# Time spent in the phase being left; the first transition measures from
	# the mission start, which is the closest thing to "fight began".
	var since := _phase_msec if _phase_msec > 0 else _mission_start_msec
	_phase_msec = now
	log_event("BossPhaseTransition", {
		"boss_id": boss_id,
		"phase_from": phase_from,
		"phase_to": phase_to,
		"time_seconds": _elapsed(since),
	})


func vendor_interaction(action: String, item_type: String, cost: int) -> void:
	log_event("VendorInteraction", {"action": action, "item_type": item_type, "cost": cost})


func difficulty_selected(modifier_type: String, mission_id: String) -> void:
	log_event("DifficultyModifierSelected", {
		"modifier_type": modifier_type, "mission_id": mission_id})


func _elapsed(since_msec: int) -> float:
	if since_msec <= 0:
		return 0.0
	return snappedf(float(Time.get_ticks_msec() - since_msec) / 1000.0, 0.1)

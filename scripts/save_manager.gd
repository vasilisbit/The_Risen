extends Node
## SaveManager (autoload): JSON persistence for The Risen.
## Schema is aligned verbatim with TDD v2.0 §4.7 (= GDD §6.3).
## File: user://risen_save_01.json (FileAccess + JSON).

const SAVE_PATH := "user://risen_save_01.json"

## Mission order for unlock gating — each unlocks when the previous completes.
const MISSION_ORDER: Array[String] = ["Earth", "Mars", "Venus"]

signal game_loaded
signal game_saved

var data: Dictionary = {}


func _ready() -> void:
	# Autoload runs before the hub scene, so this covers "load on hub start".
	load_game()


## A fresh default save (first launch). Field names match TDD §4.7 exactly.
func _default_data() -> Dictionary:
	return {
		"player_level": 1,
		"current_xp": 0,
		"selected_class": "Assault",
		# False until the player picks on the class-selection screen (T-0022).
		# selected_class already has a value, so this is what marks it a default
		# rather than a real choice. Backfilled into older saves on load.
		"class_chosen": false,
		"owned_weapons": [],
		"owned_armor": [],
		"flux_currency": 0,
		"mission_completion_flags": {"Earth": false, "Mars": false, "Venus": false},
		"difficulty_unlocks": {"Heroic": false, "Legendary": false},
		"total_kills": 0,
		"total_deaths": 0,
		"total_playtime": 0.0,
		# Linear 0..1 per audio bus (T-0034). Backfilled into older saves.
		"audio_volumes": {"Master": 1.0, "Music": 1.0, "SFX": 1.0},
	}


## Load the save, or create defaults on first launch / unreadable / corrupt file.
## Missing keys are backfilled from defaults so older saves stay compatible.
func load_game() -> void:
	var defaults := _default_data()
	if not FileAccess.file_exists(SAVE_PATH):
		data = defaults
		save_game()
		game_loaded.emit()
		return

	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		push_warning("SaveManager: cannot open save; using defaults.")
		data = defaults
		game_loaded.emit()
		return
	var text := f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SaveManager: corrupt save; using defaults.")
		data = defaults
		game_loaded.emit()
		return

	data = defaults
	for key in (parsed as Dictionary):
		data[key] = (parsed as Dictionary)[key]
	game_loaded.emit()


## Write the current data to disk as pretty JSON. Returns true on success.
func save_game() -> bool:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("SaveManager: cannot write save to %s" % SAVE_PATH)
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	game_saved.emit()
	return true


## Mark a mission complete and auto-save (called on return to the hub).
func complete_mission(mission: String) -> void:
	var flags: Dictionary = data.get("mission_completion_flags", {})
	flags[mission] = true
	data["mission_completion_flags"] = flags
	save_game()


## True if a mission is playable: the first one, or the previous is complete.
func is_mission_unlocked(mission: String) -> bool:
	var idx := MISSION_ORDER.find(mission)
	if idx <= 0:
		return true
	var prev: String = MISSION_ORDER[idx - 1]
	var flags: Dictionary = data.get("mission_completion_flags", {})
	return bool(flags.get(prev, false))


## Record the player's class choice (T-0022) and persist it.
func select_class(class_name_: String) -> void:
	data["selected_class"] = class_name_
	data["class_chosen"] = true
	save_game()


## True once the player has actually been through the class picker.
func has_chosen_class() -> bool:
	return bool(data.get("class_chosen", false))


## Start a brand-new save (defaults) and persist it.
func reset() -> void:
	data = _default_data()
	save_game()

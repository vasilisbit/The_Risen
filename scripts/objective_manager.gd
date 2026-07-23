class_name ObjectiveManager
extends Node
## Ordered mission objectives + top-left UI + completion chain (T-0014).
## Objectives complete strictly in order; events for a non-current objective are
## ignored so nothing can be bypassed. When the last one completes it saves the
## mission and fades back to the hub via the GameState autoload.

signal objective_advanced(index: int)
signal all_complete

@export var mission_id: String = "Earth"
@export var return_scene: String = "res://scenes/hub/hub.tscn"
## Seconds to loot the area after the last objective before returning to the ship.
@export var extraction_time: float = 30.0

# Ordered objectives per mission. "kill" uses target; "flag" objectives are
# completed by notify_flag(<flag>). Picked by mission_id at _ready().
const MISSION_OBJECTIVES := {
	"Earth": [
		{"text": "Eliminate enemies", "type": "kill", "target": 30, "current": 0, "done": false},
		{"text": "Retrieve the Archive Core", "type": "flag", "flag": "archive", "done": false},
		{"text": "Defeat the Shielded Brute", "type": "flag", "flag": "boss", "done": false},
	],
	# GDD §3.4. The final objective is fired by the Ember Tyrant (T-0021).
	"Venus": [
		{"text": "Climb to the volcano summit", "type": "flag", "flag": "summit", "done": false},
		{"text": "Descend to the lava river", "type": "flag", "flag": "descent", "done": false},
		{"text": "Dive into the lava pool", "type": "flag", "flag": "pool", "done": false},
		{"text": "Defeat the Ember Tyrant", "type": "flag", "flag": "boss", "done": false},
	],
}

var _objectives: Array = []
var _index: int = 0
var _complete: bool = false
var _labels: Array[Label] = []


func _ready() -> void:
	# duplicate(true): the const table is read-only, and we mutate progress.
	var list: Array = MISSION_OBJECTIVES.get(mission_id, [])
	_objectives = list.duplicate(true)
	var tel := get_node_or_null("/root/Telemetry")
	if tel:
		tel.mission_started(mission_id)
	_build_ui()
	_refresh_ui()


func current_index() -> int:
	return _index


func is_complete() -> bool:
	return _complete


## Count one kill toward the current objective (if it is a "kill" objective).
func register_kill() -> void:
	if _complete or _index >= _objectives.size():
		return
	var o: Dictionary = _objectives[_index]
	if o["type"] != "kill":
		return
	o["current"] = mini(int(o["current"]) + 1, int(o["target"]))
	if int(o["current"]) >= int(o["target"]):
		_advance()
	_refresh_ui()


## Complete the current objective if it is a matching "flag" objective.
func notify_flag(flag: String) -> void:
	if _complete or _index >= _objectives.size():
		return
	var o: Dictionary = _objectives[_index]
	if o["type"] == "flag" and o.get("flag", "") == flag:
		_advance()
		_refresh_ui()


func _advance() -> void:
	_objectives[_index]["done"] = true
	_index += 1
	checkpoint_at_player()
	if _index >= _objectives.size():
		_on_all_complete()
	else:
		objective_advanced.emit(_index)


## Anchor the respawn point to wherever the player is standing when an
## objective completes, so dying sends them back to their current objective
## rather than the level entrance. Deliberately uses the player's own position
## instead of an authored point per objective: a hand-placed point can sit
## ahead of the player and would then teleport them *forward* on death.
## Public so the mission drivers can also call it at finer-grained beats.
func checkpoint_at_player() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("checkpoint_here"):
		player.checkpoint_here()


func _on_all_complete() -> void:
	_complete = true
	all_complete.emit()
	_refresh_ui()
	var tel := get_node_or_null("/root/Telemetry")
	if tel:
		tel.mission_completed(mission_id)
	# Bank the completion now (flag + Flux persist even if the player quits during
	# the loot window), then give them time to grab drops before extracting.
	var sm := get_node_or_null("/root/SaveManager")
	if sm and sm.has_method("complete_mission"):
		sm.complete_mission(mission_id)
	var ec := ExtractionCountdown.new()
	add_child(ec)
	ec.begin(extraction_time, return_scene)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := VBoxContainer.new()
	# Left edge, vertically centred - clear of the top-left radar and the
	# top-centre vitals bar.
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.offset_left = 20.0
	panel.offset_top = -70.0
	panel.add_theme_constant_override("separation", 4)
	layer.add_child(panel)
	var title := Label.new()
	title.text = "OBJECTIVES"
	title.add_theme_font_size_override("font_size", 18)
	panel.add_child(title)
	for o in _objectives:
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 16)
		panel.add_child(l)
		_labels.append(l)


func _refresh_ui() -> void:
	for i in _objectives.size():
		if i >= _labels.size():
			continue
		var o: Dictionary = _objectives[i]
		var l := _labels[i]
		var progress := ""
		if o["type"] == "kill":
			progress = "  %d/%d" % [int(o["current"]), int(o["target"])]
		if o.get("done", false):
			l.text = "✓ %s" % o["text"]
			l.modulate = Color(0.4, 1.0, 0.5)          # green check
		elif i == _index and not _complete:
			l.text = "▸ %s%s" % [o["text"], progress]
			l.modulate = Color(1, 1, 1)
		else:
			l.text = "• %s" % o["text"]
			l.modulate = Color(0.6, 0.6, 0.65)          # pending, dim

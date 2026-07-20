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
	if _index >= _objectives.size():
		_on_all_complete()
	else:
		objective_advanced.emit(_index)


func _on_all_complete() -> void:
	_complete = true
	all_complete.emit()
	_refresh_ui()
	var sm := get_node_or_null("/root/SaveManager")
	if sm and sm.has_method("complete_mission"):
		sm.complete_mission(mission_id)
	var gs := get_node_or_null("/root/GameState")
	if gs and gs.has_method("transition_to"):
		gs.transition_to(return_scene)
	else:
		get_tree().change_scene_to_file(return_scene)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := VBoxContainer.new()
	panel.position = Vector2(16, 156)         # top-left, clear of the HP/shield bars
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

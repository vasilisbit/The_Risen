extends Node

## Legendary time limit (T-0027). Counts down from Difficulty.time_limit() and
## fails the mission at zero: logs MissionFailed(reason "timeout") and returns
## to the hub. On any other tier it removes itself, so the node can sit in every
## mission scene unconditionally.
##
## This is the first thing in the game that can actually fail a mission - until
## now death only cost a checkpoint - which is why Telemetry.mission_failed()
## had an API but no caller.

const WARN_AT := 60.0             # s remaining when the clock turns red
const RETURN_SCENE := "res://scenes/hub/hub.tscn"

signal expired

@export var mission_id: String = ""

var time_left: float = 0.0
var running: bool = false

var _label: Label
var _expired: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var diff := get_node_or_null("/root/Difficulty")
	var limit: float = diff.time_limit() if diff else 0.0
	if limit <= 0.0:
		queue_free()             # not a timed tier
		return
	time_left = limit
	running = true
	_build_ui()


func _process(delta: float) -> void:
	if not running or _expired:
		return
	time_left = maxf(0.0, time_left - delta)
	_refresh()
	if time_left <= 0.0:
		_fail()


func _refresh() -> void:
	if _label == null:
		return
	var minutes := int(time_left) / 60
	var seconds := int(time_left) % 60
	_label.text = "%d:%02d" % [minutes, seconds]
	_label.modulate = Color(1.0, 0.35, 0.3) if time_left <= WARN_AT else Color(1, 1, 1)


## Public so the failure path is testable without waiting ten minutes.
func fail_now() -> void:
	time_left = 0.0
	_fail()


func _fail() -> void:
	if _expired:
		return
	_expired = true
	running = false
	expired.emit()
	var tel := get_node_or_null("/root/Telemetry")
	if tel:
		tel.mission_failed(_mission(), "timeout")
	_show_banner()
	await get_tree().create_timer(2.5).timeout
	var gs := get_node_or_null("/root/GameState")
	if gs and gs.has_method("transition_to"):
		gs.transition_to(RETURN_SCENE)
	else:
		get_tree().change_scene_to_file(RETURN_SCENE)


## Prefer the exported id, else the scene name - every mission scene is named
## after its mission.
func _mission() -> String:
	if mission_id != "":
		return mission_id
	var scene := get_tree().current_scene
	return String(scene.name) if scene else ""


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	box.position = Vector2(-70, 48)
	box.custom_minimum_size = Vector2(140, 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(box)

	var caption := Label.new()
	caption.text = "TIME REMAINING"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 12)
	caption.modulate = Color(0.7, 0.72, 0.8)
	box.add_child(caption)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 30)
	box.add_child(_label)
	_refresh()


func _show_banner() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var tint := ColorRect.new()
	tint.color = Color(0.3, 0.0, 0.0, 0.55)
	tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(tint)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var text := Label.new()
	text.text = "OUT OF TIME"
	text.add_theme_font_size_override("font_size", 56)
	center.add_child(text)

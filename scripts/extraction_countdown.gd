class_name ExtractionCountdown
extends CanvasLayer

## Post-objective extraction window. When the last objective (or final wave)
## completes, the mission is marked done immediately (flag + Flux persist), but
## instead of yanking the player straight to the ship this gives them a timed
## window to loot the area - most importantly the boss's guaranteed drops, which
## used to vanish the instant the fight ended. When it runs out, it returns to
## the hub via GameState.

const RETURN_FALLBACK := "res://scenes/hub/hub.tscn"

var _left: float = 0.0
var _return_scene: String = RETURN_FALLBACK
var _label: Label
var _going: bool = false


## Show the window and start counting. Add this to the running scene first.
func begin(seconds: float, return_scene: String) -> void:
	_left = seconds
	_return_scene = return_scene
	layer = 30
	# Keep counting even when the tree is paused - opening the inventory pauses
	# it, and the extraction clock must not stop while you sort your loot.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	set_process(true)


func _build_ui() -> void:
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_label.position = Vector2(-260, 54)
	_label.custom_minimum_size = Vector2(520, 0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 26)
	_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.34))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(_label)


func _process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0:
		_return_to_ship()
		return
	_label.text = "AREA SECURED  -  loot up!\nReturning to your ship in %d s" % int(ceil(_left))


func _return_to_ship() -> void:
	if _going:
		return
	_going = true
	set_process(false)
	# Clear any pause left on by an open menu, so the hub isn't frozen on arrival.
	get_tree().paused = false
	var gs := get_node_or_null("/root/GameState")
	if gs and gs.has_method("transition_to"):
		gs.transition_to(_return_scene)
	else:
		get_tree().change_scene_to_file(_return_scene)

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
	# Keep counting (and, critically, keep able to return home) even if the tree is
	# paused by a menu - PROCESS_MODE_ALWAYS means the clock never stalls while you
	# sort loot, and the scene swap still fires when it hits zero.
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
	# Belt-and-suspenders: if the faded transition somehow hasn't swapped the scene
	# shortly after (a stuck fade, a missing GameState), force it. The timer is
	# owned by the tree, so it still fires under a menu pause; if the swap DID
	# happen this node is already freed and the callback is a safe no-op.
	var guard := get_tree().create_timer(2.0)
	guard.timeout.connect(_force_return)


## Last-resort scene swap. Runs only if we are still in the finished mission.
func _force_return() -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.scene_file_path == _return_scene:
		return                                  # already home, nothing to do
	get_tree().paused = false
	get_tree().change_scene_to_file(_return_scene)

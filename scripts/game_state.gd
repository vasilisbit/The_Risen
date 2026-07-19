extends CanvasLayer
## GameState autoload (TDD §4.12): fade-to-black scene transitions. Persists
## across scene changes (autoload), so the fade covers the swap.

var _rect: ColorRect
var _busy: bool = false


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.color = Color(0, 0, 0, 0)
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)


## Fade to black, swap to `path`, fade back in.
func transition_to(path: String) -> void:
	if _busy:
		return
	_busy = true
	var tw := create_tween()
	tw.tween_property(_rect, "color:a", 1.0, 0.5)
	tw.tween_callback(func() -> void: get_tree().change_scene_to_file(path))
	tw.tween_interval(0.15)
	tw.tween_property(_rect, "color:a", 0.0, 0.5)
	tw.tween_callback(func() -> void: _busy = false)

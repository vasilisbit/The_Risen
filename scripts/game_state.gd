extends CanvasLayer
## GameState autoload (TDD §4.12): fade-to-black scene transitions. Persists
## across scene changes (autoload), so the fade covers the swap.

var _rect: ColorRect
var _busy: bool = false
## A scene change requested while a fade was already running. Held here instead of
## being dropped, then run when the in-flight fade finishes. Without this, an
## extraction that expires while the inventory's open/close fade is mid-flight (or
## any overlapping fade) silently no-ops and soft-locks the player in the level.
var _pending_scene: String = ""


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
		# A fade is already running (e.g. the inventory opening/closing). Queue the
		# swap rather than dropping it, so it happens the moment that fade releases.
		_pending_scene = path
		return
	_busy = true
	var tw := create_tween()
	tw.tween_property(_rect, "color:a", 1.0, 0.5)
	tw.tween_callback(func() -> void: get_tree().change_scene_to_file(path))
	tw.tween_interval(0.15)
	tw.tween_property(_rect, "color:a", 0.0, 0.5)
	tw.tween_callback(_release)


## Clear the busy flag and run any transition that was requested mid-fade.
func _release() -> void:
	_busy = false
	if _pending_scene != "":
		var path := _pending_scene
		_pending_scene = ""
		transition_to(path)


## Fade to black, run `at_black` (e.g. reveal a screen), fade back in - without
## a scene change. Used for the transition into the vendor screen. Runs while the
## tree is paused because this autoload is PROCESS_MODE_ALWAYS.
func fade_black_then(at_black: Callable, dur: float = 0.28) -> void:
	if _busy:
		at_black.call()
		return
	_busy = true
	var tw := create_tween()
	tw.tween_property(_rect, "color:a", 1.0, dur)
	tw.tween_callback(at_black)
	tw.tween_interval(0.05)
	tw.tween_property(_rect, "color:a", 0.0, dur)
	tw.tween_callback(_release)

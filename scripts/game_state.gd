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


## Fail the current run: flash a red banner, log the failure, then return to the hub.
## Shared by the Legendary time limit (mission_timer) and the Legendary death cap
## (guardian). `reason` is the telemetry tag; `banner` is the on-screen text.
func fail_mission(reason: String, banner: String = "MISSION FAILED",
		return_scene: String = "res://scenes/hub/hub.tscn") -> void:
	var tel := get_node_or_null("/root/Telemetry")
	if tel and tel.has_method("mission_failed"):
		var scene := get_tree().current_scene
		tel.mission_failed(String(scene.name) if scene else "", reason)
	var banner_node := _show_fail_banner(banner)
	# create_timer defaults to process_always, so the wait ticks even if the tree
	# was paused (e.g. a death that opened a menu).
	await get_tree().create_timer(2.5).timeout
	get_tree().paused = false
	# GameState is an autoload that outlives the scene swap, so the banner must be
	# freed explicitly or it would hang over the hub forever.
	if is_instance_valid(banner_node):
		banner_node.queue_free()
	transition_to(return_scene)


## Build the red fail banner as one throwaway Control (tint + centred label) and
## return it so the caller can free it after the scene swap.
func _show_fail_banner(text: String) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var tint := ColorRect.new()
	tint.color = Color(0.3, 0.0, 0.0, 0.55)
	tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tint)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 56)
	center.add_child(label)
	return root


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

extends Control

## Transient notice in the bottom-left of the hub - currently used when you
## select a mission you have not unlocked yet.
##
## It lives here rather than as a print() because a locked planet giving no
## visible feedback reads as the table being broken. Fades out on its own so it
## never becomes permanent clutter.

signal shown(message: String)

const HOLD := 2.6            # s fully visible before fading
const FADE := 0.9            # s to fade out
const WARN := Color(1.0, 0.62, 0.30)
const MARGIN := Vector2(34, 34)

var _label: Label
var _left: float = 0.0


func _ready() -> void:
	add_to_group("hub_notice")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.0
	anchor_top = 1.0
	anchor_right = 0.0
	anchor_bottom = 1.0
	offset_left = MARGIN.x
	offset_top = -(MARGIN.y + 30.0)
	offset_right = MARGIN.x + 560.0
	offset_bottom = -MARGIN.y
	_build()


func _process(delta: float) -> void:
	if _left <= 0.0:
		return
	_left -= delta
	# Hold at full opacity, then fade over the last FADE seconds.
	_label.modulate.a = clampf(_left / FADE, 0.0, 1.0)
	if _left <= 0.0:
		_label.visible = false


## Show `message` for HOLD + FADE seconds. Re-showing restarts the timer.
func notify(message: String) -> void:
	_label.text = message
	_label.visible = true
	_label.modulate.a = 1.0
	_left = HOLD + FADE
	shown.emit(message)


## True while a notice is on screen - exposed for tests.
func is_showing() -> bool:
	return _left > 0.0


func _build() -> void:
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", WARN)
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.visible = false
	add_child(_label)

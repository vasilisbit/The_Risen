extends Control

## Settings overlay (T-0034). Master / Music / SFX volume sliders that apply to
## the audio buses live as you drag them, and persist through SaveManager.
##
## Styled to match the main menu - dark panel, gold accents - and opened from
## it. It is the only settings content the game has, so the menu entry no
## longer needs to say "not implemented".

const GOLD := Color(0.95, 0.78, 0.32)
const DIM := Color(0.55, 0.58, 0.66)
const BUSES := ["Master", "Music", "SFX"]

var _sliders: Dictionary = {}
var _values: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Anchors AND offsets, explicitly: set_anchors_preset alone left this
	# shrink-wrapped to its content, so the dim only covered the panel.
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()


func open() -> void:
	_refresh_from_buses()
	visible = true


func close() -> void:
	visible = false


## Current slider value for a bus - exposed so the wiring can be asserted.
func value_of(bus_name: String) -> float:
	return float(_values.get(bus_name, 1.0))


func _refresh_from_buses() -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio == null:
		return
	for bus_name in BUSES:
		var v: float = audio.get_volume(bus_name)
		_values[bus_name] = v
		var slider: HSlider = _sliders[bus_name]
		slider.set_value_no_signal(v * 100.0)
		_update_readout(bus_name)


func _on_slider(bus_name: String, value: float) -> void:
	var linear := value / 100.0
	_values[bus_name] = linear
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.set_volume(bus_name, linear)      # applies immediately
	_update_readout(bus_name)
	var sm := get_node_or_null("/root/SaveManager")
	if sm and sm.has_method("save_game"):
		sm.save_game()


func _update_readout(bus_name: String) -> void:
	var readout: Label = _sliders[bus_name].get_meta("readout")
	readout.text = "%d%%" % int(round(value_of(bus_name) * 100.0))


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.97)
	style.border_color = GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(26)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	var title := Label.new()
	title.text = "SETTINGS"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", GOLD)
	box.add_child(title)

	var sub := Label.new()
	sub.text = "Audio levels apply immediately and are saved."
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", DIM)
	box.add_child(sub)

	for bus_name in BUSES:
		box.add_child(_build_row(bus_name))

	var back := Button.new()
	back.text = "BACK"
	back.custom_minimum_size = Vector2(160, 42)
	back.pressed.connect(close)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(back)
	box.add_child(row)


func _build_row(bus_name: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)

	var label := Label.new()
	label.text = bus_name.to_upper()
	label.custom_minimum_size = Vector2(110, 0)
	label.add_theme_font_size_override("font_size", 17)
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = 100.0
	slider.custom_minimum_size = Vector2(320, 28)
	slider.value_changed.connect(func(v: float) -> void: _on_slider(bus_name, v))
	row.add_child(slider)

	var readout := Label.new()
	readout.text = "100%"
	readout.custom_minimum_size = Vector2(64, 0)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	readout.add_theme_font_size_override("font_size", 16)
	readout.add_theme_color_override("font_color", DIM)
	row.add_child(readout)

	slider.set_meta("readout", readout)
	_sliders[bus_name] = slider
	return row

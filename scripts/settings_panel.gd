extends Control

## Settings overlay (T-0034 / T-0046). Three sections:
##  * AUDIO    - Master / Music / SFX sliders (apply live via AudioManager).
##  * GRAPHICS - Fullscreen + VSync toggles (DisplayServer, via GameSettings).
##  * CONTROLS - Mouse sensitivity slider + Invert-Y, plus a read-only keybind
##               reference. The Guardian mirrors these live.
##
## All values persist through GameSettings (a global options file), so they are the
## same across every save slot. Styled to match the main menu / pause menu - dark
## panel, gold accents. Reusable: added under the main menu and the pause layer.

const GOLD := Color(0.95, 0.78, 0.32)
const DIM := Color(0.55, 0.58, 0.66)
const BUSES := ["Master", "Music", "SFX"]

## Gameplay bindings shown, read-only, in the Controls section (action -> label).
const KEYBINDS := [
	["move_forward", "Move Forward"], ["move_back", "Move Back"],
	["move_left", "Move Left"], ["move_right", "Move Right"],
	["jump", "Jump"], ["sprint", "Sprint"], ["fire", "Fire"], ["reload", "Reload"],
	["super", "Super"], ["grenade", "Grenade"], ["melee", "Melee"],
	["interact", "Interact"], ["inventory", "Inventory"],
	["weapon_1", "Weapon 1"], ["weapon_2", "Weapon 2"], ["weapon_3", "Weapon 3"],
]

var _sliders: Dictionary = {}
var _values: Dictionary = {}
var _fullscreen_chk: CheckButton
var _vsync_chk: CheckButton
var _sens_slider: HSlider
var _sens_readout: Label
var _invert_chk: CheckButton


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
	_refresh_from_state()
	visible = true


func close() -> void:
	visible = false


## Current slider value for a bus - exposed so the wiring can be asserted.
func value_of(bus_name: String) -> float:
	return float(_values.get(bus_name, 1.0))


func _refresh_from_state() -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		for bus_name in BUSES:
			var v: float = audio.get_volume(bus_name)
			_values[bus_name] = v
			var slider: HSlider = _sliders[bus_name]
			slider.set_value_no_signal(v * 100.0)
			_update_readout(bus_name)
	var gs := get_node_or_null("/root/GameSettings")
	if gs:
		_fullscreen_chk.set_pressed_no_signal(gs.is_fullscreen())
		_vsync_chk.set_pressed_no_signal(gs.is_vsync())
		_sens_slider.set_value_no_signal(gs.sensitivity_fraction() * 100.0)
		_invert_chk.set_pressed_no_signal(gs.invert_y())
		_update_sens_readout()


# --- audio -------------------------------------------------------------------

func _on_slider(bus_name: String, value: float) -> void:
	var linear := value / 100.0
	_values[bus_name] = linear
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.set_volume(bus_name, linear)      # applies immediately + persists
	_update_readout(bus_name)


func _update_readout(bus_name: String) -> void:
	var readout: Label = _sliders[bus_name].get_meta("readout")
	readout.text = "%d%%" % int(round(value_of(bus_name) * 100.0))


# --- graphics / controls -----------------------------------------------------

func _on_fullscreen(pressed: bool) -> void:
	var gs := get_node_or_null("/root/GameSettings")
	if gs:
		gs.set_fullscreen(pressed)


func _on_vsync(pressed: bool) -> void:
	var gs := get_node_or_null("/root/GameSettings")
	if gs:
		gs.set_vsync(pressed)


func _on_sensitivity(value: float) -> void:
	var gs := get_node_or_null("/root/GameSettings")
	if gs:
		gs.set_sensitivity_fraction(value / 100.0)
	_update_sens_readout()


func _on_invert(pressed: bool) -> void:
	var gs := get_node_or_null("/root/GameSettings")
	if gs:
		gs.set_invert_y(pressed)


func _update_sens_readout() -> void:
	_sens_readout.text = "%d%%" % int(round(_sens_slider.value))


# --- construction ------------------------------------------------------------

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
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var title := Label.new()
	title.text = "SETTINGS"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", GOLD)
	box.add_child(title)

	# The three sections live inside a height-capped scroll so the panel never
	# runs off a small window.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 440)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)

	# AUDIO ------------------------------------------------------------------
	content.add_child(_section_header("AUDIO"))
	for bus_name in BUSES:
		content.add_child(_build_slider_row(bus_name))

	# GRAPHICS ---------------------------------------------------------------
	content.add_child(_section_header("GRAPHICS"))
	_fullscreen_chk = _build_check_row(content, "Fullscreen", _on_fullscreen)
	_vsync_chk = _build_check_row(content, "V-Sync", _on_vsync)

	# CONTROLS ---------------------------------------------------------------
	content.add_child(_section_header("CONTROLS"))
	content.add_child(_build_sensitivity_row())
	_invert_chk = _build_check_row(content, "Invert Look Y", _on_invert)
	content.add_child(_build_keybind_list())

	var back := Button.new()
	back.text = "BACK"
	back.custom_minimum_size = Vector2(160, 42)
	back.pressed.connect(close)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(back)
	box.add_child(row)


func _section_header(text: String) -> Control:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", GOLD)
	return l


func _build_slider_row(bus_name: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)

	var label := Label.new()
	label.text = bus_name.to_upper()
	label.custom_minimum_size = Vector2(140, 0)
	label.add_theme_font_size_override("font_size", 16)
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = 100.0
	slider.custom_minimum_size = Vector2(300, 26)
	slider.value_changed.connect(func(v: float) -> void: _on_slider(bus_name, v))
	row.add_child(slider)

	var readout := Label.new()
	readout.text = "100%"
	readout.custom_minimum_size = Vector2(58, 0)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	readout.add_theme_font_size_override("font_size", 15)
	readout.add_theme_color_override("font_color", DIM)
	row.add_child(readout)

	slider.set_meta("readout", readout)
	_sliders[bus_name] = slider
	return row


func _build_check_row(parent: Control, text: String, cb: Callable) -> CheckButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(140, 0)
	label.add_theme_font_size_override("font_size", 16)
	row.add_child(label)
	var chk := CheckButton.new()
	chk.toggled.connect(cb)
	row.add_child(chk)
	parent.add_child(row)
	return chk


func _build_sensitivity_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)

	var label := Label.new()
	label.text = "Mouse Sensitivity"
	label.custom_minimum_size = Vector2(140, 0)
	label.add_theme_font_size_override("font_size", 16)
	row.add_child(label)

	_sens_slider = HSlider.new()
	_sens_slider.min_value = 0.0
	_sens_slider.max_value = 100.0
	_sens_slider.step = 1.0
	_sens_slider.value = 50.0
	_sens_slider.custom_minimum_size = Vector2(300, 26)
	_sens_slider.value_changed.connect(_on_sensitivity)
	row.add_child(_sens_slider)

	_sens_readout = Label.new()
	_sens_readout.text = "50%"
	_sens_readout.custom_minimum_size = Vector2(58, 0)
	_sens_readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_sens_readout.add_theme_font_size_override("font_size", 15)
	_sens_readout.add_theme_color_override("font_color", DIM)
	row.add_child(_sens_readout)
	return row


## A compact two-column reference of the current gameplay keys (read-only for now).
func _build_keybind_list() -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.08, 0.9)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 5)
	panel.add_child(grid)

	for entry in KEYBINDS:
		var action := String(entry[0])
		var name_lbl := Label.new()
		name_lbl.text = String(entry[1])
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.add_theme_color_override("font_color", DIM)
		grid.add_child(name_lbl)

		var key_lbl := Label.new()
		key_lbl.text = _key_for(action)
		key_lbl.add_theme_font_size_override("font_size", 13)
		key_lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
		grid.add_child(key_lbl)
	return panel


## The primary bound key/button for an action, as readable text.
func _key_for(action: String) -> String:
	if not InputMap.has_action(action):
		return "-"
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			var code := k.physical_keycode if k.keycode == 0 else k.keycode
			return OS.get_keycode_string(code)
		if ev is InputEventMouseButton:
			match (ev as InputEventMouseButton).button_index:
				MOUSE_BUTTON_LEFT: return "Mouse L"
				MOUSE_BUTTON_RIGHT: return "Mouse R"
				MOUSE_BUTTON_MIDDLE: return "Mouse M"
				_: return "Mouse"
	return "-"

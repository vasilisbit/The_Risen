extends Control

## T-0033 main menu, styled to match the in-game HUD: an animated starfield,
## an angled gold title bar, and a column of entries each marked by a diamond
## that lights up on hover — the same shape language as the super icon.
##
## New Game clears the class-selection flag so the picker (T-0022) runs again
## on entering the hub; Continue just loads whatever is saved. Quit asks first.
## Settings is a stub per the card, and says so rather than doing nothing
## silently.

const HUB := "res://scenes/hub/hub.tscn"
const GOLD := Color(0.95, 0.78, 0.32)
const DIM := Color(0.55, 0.58, 0.66)
const STAR_COUNT := 220

var _entries: Array[Dictionary] = []
var _hovered: int = -1
var _confirm: Control
var _settings: Control
var _status: Label
var _stars: Array[Vector3] = []      # x, y, speed
var _time: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	_seed_stars()
	_build_ui()


func _process(delta: float) -> void:
	_time += delta
	# Drift the starfield sideways; wrap at the edges.
	for i in _stars.size():
		var s := _stars[i]
		s.x -= s.z * delta * 14.0
		if s.x < -0.02:
			s.x = 1.02
			s.y = randf()
		_stars[i] = s
	queue_redraw()


func _draw() -> void:
	var vp := size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.03, 0.04, 0.06))
	for s in _stars:
		var p := Vector2(s.x * vp.x, s.y * vp.y)
		var a: float = 0.25 + 0.55 * s.z
		# Twinkle, keyed off each star's own speed so they don't pulse in sync.
		a *= 0.75 + 0.25 * sin(_time * (1.0 + s.z * 3.0) + s.y * 20.0)
		draw_circle(p, 0.6 + s.z * 1.4, Color(0.75, 0.85, 1.0, a))

	# Angled gold band behind the title, echoing the HUD's super bar.
	var band_y := vp.y * 0.22
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, band_y), Vector2(vp.x * 0.62, band_y),
		Vector2(vp.x * 0.58, band_y + 4.0), Vector2(0, band_y + 4.0)]), GOLD)
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, band_y + 7.0), Vector2(vp.x * 0.34, band_y + 7.0),
		Vector2(vp.x * 0.32, band_y + 9.5), Vector2(0, band_y + 9.5)]),
		Color(GOLD, 0.45))

	# Menu entry markers: a diamond per row, filled when hovered.
	for i in _entries.size():
		var r: Rect2 = _entries[i]["rect"]
		var c := Vector2(r.position.x - 26.0, r.position.y + r.size.y * 0.5)
		var pts := PackedVector2Array([
			c + Vector2(0, -9), c + Vector2(9, 0), c + Vector2(0, 9), c + Vector2(-9, 0)])
		if i == _hovered:
			draw_colored_polygon(pts, GOLD)
			# Underline sweeping out from the selected entry.
			draw_rect(Rect2(Vector2(r.position.x, r.end.y + 2.0),
				Vector2(r.size.x * 0.75, 2.0)), Color(GOLD, 0.7))
		else:
			var loop := PackedVector2Array(pts)
			loop.append(pts[0])
			draw_polyline(loop, DIM, 1.6, true)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var was := _hovered
		_hovered = _entry_at((event as InputEventMouseMotion).position)
		if was != _hovered:
			_refresh_entry_colours()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var hit := _entry_at(mb.position)
			if hit >= 0:
				_activate(hit)


func _entry_at(pos: Vector2) -> int:
	for i in _entries.size():
		var r: Rect2 = _entries[i]["rect"]
		# Widen the hit area to include the diamond marker.
		if Rect2(r.position - Vector2(36, 4), r.size + Vector2(40, 8)).has_point(pos):
			return i
	return -1


# --- actions ----------------------------------------------------------------

func _activate(index: int) -> void:
	match String(_entries[index]["id"]):
		"new":
			_new_game()
		"continue":
			_continue()
		"settings":
			if _settings:
				_settings.open()
		"quit":
			_show_confirm()


## Start fresh: wipe the save so the class picker runs again in the hub.
func _new_game() -> void:
	var sm := get_node_or_null("/root/SaveManager")
	if sm and sm.has_method("reset"):
		sm.reset()
	_go(HUB)


## Continue: load whatever is on disk and drop straight into the hub. If the
## save has no class yet the hub's picker will still catch it.
func _continue() -> void:
	var sm := get_node_or_null("/root/SaveManager")
	if sm and sm.has_method("load_game"):
		sm.load_game()
	_go(HUB)


func _go(path: String) -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs and gs.has_method("transition_to"):
		gs.transition_to(path)
	else:
		get_tree().change_scene_to_file(path)


func _show_confirm() -> void:
	if _confirm:
		_confirm.visible = true


func _quit() -> void:
	get_tree().quit()


# --- construction -----------------------------------------------------------

func _seed_stars() -> void:
	for i in STAR_COUNT:
		_stars.append(Vector3(randf(), randf(), randf_range(0.15, 1.0)))


func _build_ui() -> void:
	var title := Label.new()
	title.text = "THE RISEN"
	title.add_theme_font_size_override("font_size", 76)
	title.add_theme_color_override("font_color", Color(0.96, 0.96, 0.98))
	title.position = Vector2(96, 0)
	title.size = Vector2(760, 90)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(title)

	var subtitle := Label.new()
	subtitle.text = "A GUARDIAN AWAKENS"
	subtitle.add_theme_font_size_override("font_size", 17)
	subtitle.add_theme_color_override("font_color", GOLD)
	subtitle.position = Vector2(100, 0)
	subtitle.size = Vector2(600, 26)
	add_child(subtitle)

	var defs := [
		{"id": "new", "text": "NEW GAME", "hint": "Choose a class and begin"},
		{"id": "continue", "text": "CONTINUE", "hint": "Resume your saved Guardian"},
		{"id": "settings", "text": "SETTINGS", "hint": "Audio levels"},
		{"id": "quit", "text": "QUIT", "hint": "Leave the game"},
	]
	for i in defs.size():
		var d: Dictionary = defs[i]
		var label := Label.new()
		label.text = String(d["text"])
		label.add_theme_font_size_override("font_size", 30)
		label.add_theme_color_override("font_color", DIM)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)
		var hint := Label.new()
		hint.text = String(d["hint"])
		hint.add_theme_font_size_override("font_size", 13)
		hint.add_theme_color_override("font_color", Color(0.45, 0.48, 0.55))
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(hint)
		_entries.append({"id": d["id"], "label": label, "hint": hint, "rect": Rect2()})

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 14)
	_status.add_theme_color_override("font_color", GOLD)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status)

	_settings = Control.new()
	_settings.set_script(load("res://scripts/settings_panel.gd"))
	add_child(_settings)

	_build_confirm()
	_layout()
	resized.connect(_layout)


## Placed in code so the menu survives any window size.
func _layout() -> void:
	var vp := size
	var x := 100.0
	var top := vp.y * 0.22 + 64.0
	get_child(0).position = Vector2(x - 4.0, vp.y * 0.22 - 104.0)     # title
	get_child(1).position = Vector2(x, vp.y * 0.22 + 14.0)            # subtitle
	for i in _entries.size():
		var y := top + float(i) * 74.0
		var label: Label = _entries[i]["label"]
		var hint: Label = _entries[i]["hint"]
		label.position = Vector2(x, y)
		label.size = Vector2(420, 38)
		# Hint sits below the hover underline, not under it.
		hint.position = Vector2(x + 2.0, y + 44.0)
		hint.size = Vector2(420, 18)
		_entries[i]["rect"] = Rect2(Vector2(x, y), Vector2(320, 38))
	_status.position = Vector2(x, top + float(_entries.size()) * 74.0 + 10.0)
	_status.size = Vector2(620, 20)
	# The confirm and settings overlays anchor to the full rect themselves;
	# setting their size here fought the anchors and logged a warning.


func _refresh_entry_colours() -> void:
	for i in _entries.size():
		var label: Label = _entries[i]["label"]
		label.add_theme_color_override("font_color",
			Color(1, 1, 1) if i == _hovered else DIM)


func _build_confirm() -> void:
	_confirm = Control.new()
	# Anchors and offsets both, so the overlay fills the screen instead of
	# shrink-wrapping to its content (see settings_panel.gd for the same fix).
	_confirm.anchor_right = 1.0
	_confirm.anchor_bottom = 1.0
	_confirm.offset_right = 0.0
	_confirm.offset_bottom = 0.0
	_confirm.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm.visible = false
	add_child(_confirm)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confirm.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm.add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)

	var q := Label.new()
	q.text = "Quit The Risen?"
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.add_theme_font_size_override("font_size", 28)
	box.add_child(q)

	var note := Label.new()
	note.text = "Progress is saved automatically when you complete a mission."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", DIM)
	box.add_child(note)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)

	var yes := Button.new()
	yes.text = "QUIT"
	yes.custom_minimum_size = Vector2(150, 44)
	yes.pressed.connect(_quit)
	row.add_child(yes)

	var no := Button.new()
	no.text = "CANCEL"
	no.custom_minimum_size = Vector2(150, 44)
	no.pressed.connect(func() -> void: _confirm.visible = false)
	row.add_child(no)

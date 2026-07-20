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
const STAR_COUNT := 260
## Screen widths per second at full parallax depth; each star scales this by
## its own depth. This is a distant field behind a menu, not a warp tunnel.
## Measured: at 0.35 a mid-depth star still crossed in under 6 s, which read as
## travelling. At 0.10 the nearest take ~10 s and the furthest around a minute.
const STAR_DRIFT := 0.10

## Background planets. `spin` turns the surface; `orbit`/`sway` move the whole
## body on a slow sine so it drifts and returns instead of scrolling off — a
## menu backdrop should loop, not go anywhere.
const MENU_PLANETS := [
	{"pos": Vector2(0.78, 0.34), "radius": 120.0,
		"spin": 0.05, "orbit": 0.045, "sway": Vector2(0.030, 0.016),
		"base": Color(0.16, 0.30, 0.55), "band": Color(0.35, 0.62, 0.85)},
	{"pos": Vector2(0.58, 0.80), "radius": 46.0,
		"spin": 0.09, "orbit": 0.062, "sway": Vector2(0.045, 0.022),
		"base": Color(0.42, 0.18, 0.12), "band": Color(0.72, 0.36, 0.20)},
	{"pos": Vector2(0.93, 0.70), "radius": 28.0,
		"spin": 0.13, "orbit": 0.085, "sway": Vector2(0.028, 0.034),
		"base": Color(0.45, 0.34, 0.14), "band": Color(0.78, 0.62, 0.28)},
]

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
	# Drift the starfield sideways; wrap at the edges. Slow — this is a distant
	# field, not a warp effect; at the original speed it read as motion sickness.
	for i in _stars.size():
		var s := _stars[i]
		s.x -= s.z * delta * STAR_DRIFT
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

	for info in MENU_PLANETS:
		_draw_menu_planet(info, vp)

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


## A banded disc with a crescent of night, drifting slowly with the starfield.
## Drawn with arcs rather than a texture, like the rest of the game's art.
func _draw_menu_planet(info: Dictionary, vp: Vector2) -> void:
	var frac: Vector2 = info["pos"]
	var r: float = info["radius"]
	# Periodic drift: a slow Lissajous around the anchor point, so each planet
	# wanders and comes back rather than scrolling away and wrapping.
	var orbit: float = float(info["orbit"])
	var sway: Vector2 = info["sway"]
	var offset := Vector2(
		sin(_time * orbit) * sway.x,
		cos(_time * orbit * 0.73) * sway.y)
	var c := (frac + offset) * vp
	if c.x < -r * 2.0 or c.x > vp.x + r * 2.0:
		return
	# Surface rotation: the band pattern scrolls through its own phase.
	var spin: float = _time * float(info["spin"])

	var base: Color = info["base"]
	var band: Color = info["band"]
	draw_circle(c, r, base)

	# Latitude bands: horizontal chords. Each is sized to the NARROWER of its
	# two edges so it stays inside the disc — using the centre width let the
	# corners poke past the limb and the planet came out visibly stepped.
	var rows := int(r / 3.0)
	for i in rows:
		var t0 := (float(i) / float(rows)) * 2.0 - 1.0        # -1..1 across the disc
		var t1 := (float(i + 1) / float(rows)) * 2.0 - 1.0
		var outer := maxf(absf(t0), absf(t1))
		var half := sqrt(maxf(0.0, 1.0 - outer * outer)) * r
		if half <= 0.5:
			continue
		var shade := 0.5 + 0.5 * sin(t0 * 7.0 + frac.x * 12.0 + spin * TAU)
		var col := base.lerp(band, shade * 0.55)
		draw_rect(Rect2(Vector2(c.x - half, c.y + t0 * r),
			Vector2(half * 2.0, (t1 - t0) * r + 0.5)), col)

	# Night side: a crescent, drawn as offset discs fading to the background.
	for i in 7:
		var k := float(i) / 6.0
		draw_circle(c + Vector2(r * 0.55 * k, r * 0.18 * k),
			r * (1.0 - 0.06 * k), Color(0.02, 0.03, 0.05, 0.16))
	# Thin lit limb on the sunward side.
	draw_arc(c, r - 1.0, PI * 0.55, PI * 1.45, 32, Color(band, 0.5), 2.0, true)


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

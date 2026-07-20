extends Control

## Difficulty prompt (T-0027, reworked). Opens when a mission sphere is
## selected on the hologram table and launches that mission on confirm, so the
## choice is made in the moment it matters instead of sitting permanently on
## screen - where it also blocked the view out of the cockpit window.
##
## Three cards with tooltips; locked tiers are greyed and say what unlocks them.
## The choice persists through SaveManager, so it carries between runs.

signal launch_confirmed(mission_id: String)

const GOLD := Color(0.95, 0.78, 0.32)
const DIM := Color(0.55, 0.58, 0.66)
const LOCKED := Color(0.35, 0.36, 0.40)
const CARD_SIZE := Vector2(236, 156)

var mission_id: String = ""

var _cards: Dictionary = {}
var _note: Label
var _heading: Label
var _launch: Button


func _ready() -> void:
	add_to_group("difficulty_select")
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Anchors AND offsets: the preset alone leaves this shrink-wrapped to its
	# content, so the dim would only cover the panel.
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


## Show the prompt for `mission`. Pauses the world behind it.
func open(mission: String) -> void:
	mission_id = mission
	_heading.text = "DEPLOY TO %s" % mission.to_upper()
	refresh()
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func refresh() -> void:
	var diff := get_node_or_null("/root/Difficulty")
	if diff == null:
		return
	var current: String = diff.current()
	for id in _cards:
		var card: PanelContainer = _cards[id]
		var unlocked: bool = diff.is_unlocked(id)
		var selected: bool = (id == current)
		var style: StyleBoxFlat = card.get_theme_stylebox("panel")
		style.border_color = GOLD if selected else (DIM if unlocked else LOCKED)
		style.set_border_width_all(3 if selected else 1)
		style.bg_color = Color(0.12, 0.11, 0.08, 0.97) if selected else Color(0.08, 0.09, 0.11, 0.95)
		card.modulate = Color(1, 1, 1) if unlocked else Color(0.55, 0.55, 0.58)
		(card.get_meta("lock") as Label).visible = not unlocked
	var applies: bool = diff.APPLIES_TO.has(mission_id)
	_note.text = ("Modifiers apply to this mission.   Selected: %s" % current) if applies \
		else "Modifiers do not apply to %s - it runs on Normal." % mission_id
	_launch.text = "LAUNCH  -  %s" % (current if applies else "Normal")


func _select(id: String) -> void:
	var diff := get_node_or_null("/root/Difficulty")
	if diff == null:
		return
	if not diff.is_unlocked(id):
		_note.text = "%s is locked - complete the Venus mission first." % id
		return
	if diff.select(id):
		var tel := get_node_or_null("/root/Telemetry")
		if tel:
			tel.difficulty_selected(id, mission_id)
		var audio := get_node_or_null("/root/AudioManager")
		if audio:
			audio.play_sfx("ui_click")
		refresh()


func _confirm() -> void:
	var mission := mission_id
	close()
	launch_confirmed.emit(mission)


func _build() -> void:
	var diff := get_node_or_null("/root/Difficulty")
	var tiers: Array = diff.TIERS if diff else []

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	_heading = Label.new()
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heading.add_theme_font_size_override("font_size", 30)
	_heading.add_theme_color_override("font_color", GOLD)
	box.add_child(_heading)

	var sub := Label.new()
	sub.text = "Choose your difficulty."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", DIM)
	box.add_child(sub)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	for t in tiers:
		row.add_child(_build_card(t))

	_note = Label.new()
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.add_theme_font_size_override("font_size", 12)
	_note.add_theme_color_override("font_color", DIM)
	box.add_child(_note)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 14)
	box.add_child(buttons)

	_launch = Button.new()
	_launch.custom_minimum_size = Vector2(260, 46)
	_launch.pressed.connect(_confirm)
	buttons.add_child(_launch)

	var cancel := Button.new()
	cancel.text = "CANCEL"
	cancel.custom_minimum_size = Vector2(140, 46)
	cancel.pressed.connect(close)
	buttons.add_child(cancel)


func _build_card(tier: Dictionary) -> PanelContainer:
	var id := String(tier["id"])
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE
	card.tooltip_text = String(tier["details"])
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(5)
	style.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", style)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	card.add_child(col)

	var name_label := Label.new()
	name_label.text = String(tier["title"])
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 21)
	name_label.add_theme_color_override("font_color", tier["color"])
	col.add_child(name_label)

	var blurb := Label.new()
	blurb.text = String(tier["blurb"])
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.add_theme_font_size_override("font_size", 12)
	blurb.modulate = Color(0.78, 0.80, 0.86)
	blurb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(blurb)

	var lock := Label.new()
	lock.text = "LOCKED - clear Venus"
	lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lock.add_theme_font_size_override("font_size", 11)
	lock.add_theme_color_override("font_color", LOCKED)
	col.add_child(lock)
	card.set_meta("lock", lock)

	var hit := Button.new()
	hit.flat = true
	hit.set_anchors_preset(Control.PRESET_FULL_RECT)
	hit.tooltip_text = String(tier["details"])
	hit.pressed.connect(func() -> void: _select(id))
	card.add_child(hit)

	_cards[id] = card
	return card

extends Control

## Difficulty picker at the hologram table (T-0027). Three cards with tooltips;
## locked tiers are greyed out and say what unlocks them. The choice persists
## through SaveManager and applies the next time a mission loads.
##
## It sits beside the table rather than interrupting mission launch: the tier
## is a standing preference, and a modal step in front of every mission start
## would be tiresome on the runs where you never change it.

const GOLD := Color(0.95, 0.78, 0.32)
const DIM := Color(0.5, 0.53, 0.60)
const LOCKED := Color(0.35, 0.36, 0.40)
## Compact and stacked down the left edge. A centred row of tall cards sat
## directly in front of the cockpit window, hiding the T-0028 planet, and the
## bottom of the screen is taken by the ability cluster and weapon panel.
const CARD_SIZE := Vector2(252, 62)

var _cards: Dictionary = {}          # id -> PanelContainer
var _note: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	refresh()
	var diff := get_node_or_null("/root/Difficulty")
	if diff:
		diff.difficulty_changed.connect(func(_id: String) -> void: refresh())


## Re-read the save and repaint. Public so the hub can call it after a mission
## returns and a tier has just unlocked.
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
		style.bg_color = Color(0.12, 0.11, 0.08, 0.95) if selected else Color(0.08, 0.09, 0.11, 0.92)
		card.modulate = Color(1, 1, 1) if unlocked else Color(0.55, 0.55, 0.58)
		(card.get_meta("lock") as Label).visible = not unlocked
	_note.text = "Applies to Earth and Venus.   Current: %s" % current


func _select(id: String) -> void:
	var diff := get_node_or_null("/root/Difficulty")
	if diff == null:
		return
	if not diff.is_unlocked(id):
		_note.text = "%s is locked — complete the Venus mission first." % id
		return
	if diff.select(id):
		var tel := get_node_or_null("/root/Telemetry")
		if tel:
			tel.difficulty_selected(id, "")
		var audio := get_node_or_null("/root/AudioManager")
		if audio:
			audio.play_sfx("ui_click")
		refresh()


func _build() -> void:
	var diff := get_node_or_null("/root/Difficulty")
	var tiers: Array = diff.TIERS if diff else []

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	root.position = Vector2(24.0, -((CARD_SIZE.y + 8.0) * 3.0 + 48.0) * 0.5)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var title := Label.new()
	title.text = "DIFFICULTY"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", GOLD)
	root.add_child(title)

	for t in tiers:
		root.add_child(_build_card(t))

	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(CARD_SIZE.x, 0)
	_note.add_theme_font_size_override("font_size", 12)
	_note.add_theme_color_override("font_color", DIM)
	root.add_child(_note)


func _build_card(tier: Dictionary) -> PanelContainer:
	var id := String(tier["id"])
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE
	card.tooltip_text = String(tier["details"])
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(5)
	style.set_content_margin_all(8)
	card.add_theme_stylebox_override("panel", style)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	card.add_child(col)

	var name_label := Label.new()
	name_label.text = String(tier["title"])
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.add_theme_color_override("font_color", tier["color"])
	col.add_child(name_label)

	var blurb := Label.new()
	blurb.text = String(tier["blurb"])
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.add_theme_font_size_override("font_size", 11)
	blurb.modulate = Color(0.78, 0.80, 0.86)
	blurb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(blurb)

	var lock := Label.new()
	lock.text = "LOCKED — clear Venus"
	lock.add_theme_font_size_override("font_size", 10)
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

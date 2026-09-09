extends Control
## T-0018 buff/debuff selection UI. Offers 3 random options drawn from the buff
## and debuff pools, and a visible countdown that doubles as the next-wave timer:
## it appears the instant a wave clears (see WaveManager) and auto-picks one of
## the shown options if the player doesn't choose before it runs out.
## Styled to match the mission difficulty prompt (centred gold-bordered cards).
## Does NOT pause - the counter runs normally so the player can read, move and
## loot between waves. Emits `option_chosen(id)`; the WaveManager applies it.

signal option_chosen(id: String)

const PICK_COUNT := 3
## Long enough to read three cards and still walk over to loot before it fires.
const TIMEOUT := 14.0

const GOLD := Color(0.95, 0.78, 0.32)
const DIM := Color(0.60, 0.63, 0.70)
const BUFF_COLOR := Color(0.42, 0.86, 0.55)
const DEBUFF_COLOR := Color(1.0, 0.62, 0.30)
const CARD_SIZE := Vector2(250, 168)

## Buffs act on the player, debuffs weaken the enemies. 3 of these 5 are offered.
const OPTIONS: Array[Dictionary] = [
	{"id": "damage", "kind": "BUFF", "title": "+20% Weapon Damage",
		"desc": "All weapons deal 20% more damage for the rest of the mission."},
	{"id": "health", "kind": "BUFF", "title": "+50 Max HP",
		"desc": "Raises maximum health by 50 and heals you for the same amount."},
	{"id": "armor", "kind": "BUFF", "title": "-15% Damage Taken",
		"desc": "You take 15% less damage from every source."},
	{"id": "enemy_speed", "kind": "DEBUFF", "title": "-10% Enemy Speed",
		"desc": "Every enemy moves 10% slower, including ones spawned later."},
	{"id": "enemy_accuracy", "kind": "DEBUFF", "title": "-5% Enemy Accuracy",
		"desc": "Enemy shots stray further from their target."},
]

var _offered: Array[Dictionary] = []
var _time_left: float = TIMEOUT
var _resolved: bool = false
var _timer_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	_offered = _roll_options()
	_build_ui()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	if _resolved:
		return
	_time_left = maxf(0.0, _time_left - delta)
	if _timer_label:
		_timer_label.text = "Next wave in %d s   -   choose an upgrade (or press 1 / 2 / 3)" % int(ceil(_time_left))
	if _time_left <= 0.0:
		# Timeout: pick at random from what was actually offered.
		_choose(_offered[randi() % _offered.size()]["id"])


func _unhandled_input(event: InputEvent) -> void:
	# Number keys pick a card too, so the player can choose without giving up the
	# mouse - handy while looting between waves.
	if _resolved:
		return
	for i in _offered.size():
		if event.is_action_pressed("weapon_%d" % (i + 1)):
			_choose(_offered[i]["id"])
			get_viewport().set_input_as_handled()
			return


## 3 distinct options from the pool.
func _roll_options() -> Array[Dictionary]:
	var pool := OPTIONS.duplicate()
	pool.shuffle()
	return pool.slice(0, PICK_COUNT)


func _choose(id: String) -> void:
	if _resolved:
		return
	_resolved = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	option_chosen.emit(id)
	queue_free()


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	var title := Label.new()
	title.text = "CHOOSE AN UPGRADE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", GOLD)
	box.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	for i in _offered.size():
		row.add_child(_build_card(_offered[i], i + 1))

	_timer_label = Label.new()
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override("font_size", 16)
	_timer_label.add_theme_color_override("font_color", GOLD)
	box.add_child(_timer_label)


func _build_card(opt: Dictionary, number: int) -> PanelContainer:
	var is_buff: bool = opt["kind"] == "BUFF"
	var accent: Color = BUFF_COLOR if is_buff else DEBUFF_COLOR

	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE
	card.tooltip_text = String(opt["desc"])
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.11, 0.96)
	style.border_color = accent
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", style)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	card.add_child(col)

	var tag := Label.new()
	tag.text = "%d.  %s" % [number, opt["kind"]]
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_size_override("font_size", 13)
	tag.add_theme_color_override("font_color", accent)
	col.add_child(tag)

	var name_label := Label.new()
	name_label.text = String(opt["title"])
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 19)
	col.add_child(name_label)

	var blurb := Label.new()
	blurb.text = String(opt["desc"])
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.add_theme_font_size_override("font_size", 12)
	blurb.modulate = Color(0.78, 0.80, 0.86)
	blurb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(blurb)

	var id: String = opt["id"]
	var hit := Button.new()
	hit.flat = true
	hit.set_anchors_preset(Control.PRESET_FULL_RECT)
	hit.tooltip_text = String(opt["desc"])
	hit.pressed.connect(func() -> void: _choose(id))
	card.add_child(hit)
	return card


## Test helper: the ids currently on offer.
func offered_ids() -> Array:
	var ids: Array = []
	for o in _offered:
		ids.append(o["id"])
	return ids

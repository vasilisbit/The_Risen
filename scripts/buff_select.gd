extends Control
## T-0018 buff/debuff selection UI. Offers 3 random options drawn from the buff
## and debuff pools with tooltips, and a visible 10 s countdown that auto-picks
## one of the shown options at random if the player doesn't choose.
## Emits `option_chosen(id)`; the WaveManager applies the effect.

signal option_chosen(id: String)

const PICK_COUNT := 3
const TIMEOUT := 10.0

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
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_offered = _roll_options()
	_build_ui()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	if _resolved:
		return
	_time_left = maxf(0.0, _time_left - delta)
	if _timer_label:
		_timer_label.text = "Auto-select in %d..." % int(ceil(_time_left))
	if _time_left <= 0.0:
		# Timeout: pick at random from what was actually offered.
		_choose(_offered[randi() % _offered.size()]["id"])


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
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "CHOOSE AN UPGRADE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	vbox.add_child(title)

	for opt in _offered:
		var b := Button.new()
		b.text = "[%s]  %s" % [opt["kind"], opt["title"]]
		b.tooltip_text = opt["desc"]          # hover tooltip
		b.custom_minimum_size = Vector2(420, 48)
		var id: String = opt["id"]
		b.pressed.connect(func() -> void: _choose(id))
		vbox.add_child(b)
		var desc := Label.new()
		desc.text = opt["desc"]
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc.add_theme_font_size_override("font_size", 13)
		desc.modulate = Color(0.75, 0.78, 0.85)
		vbox.add_child(desc)

	_timer_label = Label.new()
	_timer_label.text = "Auto-select in %d..." % int(TIMEOUT)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override("font_size", 18)
	_timer_label.modulate = Color(1.0, 0.85, 0.4)
	vbox.add_child(_timer_label)


## Test helper: the ids currently on offer.
func offered_ids() -> Array:
	var ids: Array = []
	for o in _offered:
		ids.append(o["id"])
	return ids

extends Control
## T-0022 class selection screen. Three cards (GDD §2.4) with the class passive
## and its ability kit; clicking one highlights it, Confirm saves the choice to
## SaveManager and applies the passive to the live Guardian.
##
## Shown once, on first entry to the hub - SaveManager.has_chosen_class() is
## false until the player confirms, so this frees itself immediately on every
## later run. `selected_class` alone can't gate it: it already defaults to
## "Assault", which is indistinguishable from a real pick.
##
## Supers, grenades and melee (the rest of each kit) land in T-0023..T-0025;
## only the passives are wired up here.

signal class_confirmed(class_name_: String)

const CLASSES: Array[Dictionary] = [
	{
		"id": "Assault",
		"passive": "+10% weapon damage",
		"desc": "Every weapon you carry hits 10% harder. The straightforward pick:\nmore damage, no trade-offs.",
		"kit": "Super: Storm Barrage   ·   Grenade: Frag   ·   Melee: Energy Blade",
		"color": Color(1.0, 0.55, 0.25),
	},
	{
		"id": "Support",
		"passive": "+50 max HP (150 total)",
		"desc": "Half again as much health to work with. Survives mistakes that\nwould end an Assault run.",
		"kit": "Super: Guardian Dome   ·   Grenade: Healing   ·   Melee: EMP Punch",
		"color": Color(0.4, 0.9, 0.55),
	},
	{
		"id": "Tank",
		"passive": "-20% damage taken",
		"desc": "All incoming damage is reduced by a fifth, shield and health alike.\nBest against the heavy hitters.",
		"kit": "Super: Juggernaut Charge   ·   Grenade: Flashbang   ·   Melee: Ground Slam",
		"color": Color(0.45, 0.65, 1.0),
	},
]

const CARD_SIZE := Vector2(300, 260)

var selected: String = ""

var _cards: Dictionary = {}          # id -> PanelContainer
var _confirm: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sm := get_node_or_null("/root/SaveManager")
	if sm and sm.has_method("has_chosen_class") and sm.has_chosen_class():
		queue_free()               # already picked on a previous run
		return
	_build_ui()
	_select(CLASSES[0]["id"])       # default highlight so Confirm is never dead
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Highlight a card. Public so it is testable without synthesising clicks.
func _select(id: String) -> void:
	selected = id
	for card_id in _cards:
		var card: PanelContainer = _cards[card_id]
		card.modulate = Color(1, 1, 1) if card_id == id else Color(0.55, 0.55, 0.6)
	if _confirm:
		_confirm.text = "CONFIRM  -  %s" % id


## Commit the choice: persist it, apply the passive to the live player, close.
## Public so tests (and a future main menu) can drive it directly.
func confirm() -> void:
	if selected == "":
		return
	var sm := get_node_or_null("/root/SaveManager")
	if sm and sm.has_method("select_class"):
		sm.select_class(selected)
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("apply_class_stats"):
		player.apply_class_stats()
		# Spawn at full health so the Support bonus is live immediately.
		player.health = player.max_hp()
		player.health_changed.emit(player.health, player.max_hp())
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	class_confirmed.emit(selected)
	queue_free()


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "CHOOSE YOUR CLASS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "This cannot be changed later."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.modulate = Color(0.7, 0.72, 0.78)
	vbox.add_child(subtitle)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(row)
	for c in CLASSES:
		row.add_child(_build_card(c))

	_confirm = Button.new()
	_confirm.custom_minimum_size = Vector2(320, 50)
	_confirm.pressed.connect(confirm)
	var confirm_row := CenterContainer.new()
	confirm_row.add_child(_confirm)
	vbox.add_child(confirm_row)


func _build_card(info: Dictionary) -> PanelContainer:
	var id: String = info["id"]
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.11, 0.14, 0.95)
	style.border_color = info["color"]
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(14)
	card.add_theme_stylebox_override("panel", style)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	card.add_child(col)

	var name_label := Label.new()
	name_label.text = id.to_upper()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 26)
	name_label.add_theme_color_override("font_color", info["color"])
	col.add_child(name_label)

	var passive := Label.new()
	passive.text = info["passive"]
	passive.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	passive.add_theme_font_size_override("font_size", 17)
	col.add_child(passive)

	var desc := Label.new()
	desc.text = info["desc"]
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 13)
	desc.modulate = Color(0.78, 0.80, 0.86)
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(desc)

	var kit := Label.new()
	kit.text = info["kit"]
	kit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	kit.add_theme_font_size_override("font_size", 11)
	kit.modulate = Color(0.55, 0.57, 0.64)
	col.add_child(kit)

	# A transparent button over the whole card makes the card itself clickable.
	var hit := Button.new()
	hit.flat = true
	hit.set_anchors_preset(Control.PRESET_FULL_RECT)
	hit.pressed.connect(func() -> void: _select(id))
	card.add_child(hit)

	_cards[id] = card
	return card

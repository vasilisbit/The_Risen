extends Control

## Inventory overlay, toggled with I. Lists the weapons and armour you have
## picked up, coloured by rarity, plus your Flux balance.
##
## Until now loot went straight into SaveManager and the only feedback was a
## running count in the corner - you could not see what you had actually
## collected. This is that screen.
##
## Read-only for the moment: equipping is not implemented (weapons come from
## the fixed loadout, and nothing reads owned_armor yet), so the panel says so
## rather than implying a slot system that does not exist.

const GOLD := Color(0.95, 0.78, 0.32)
const DIM := Color(0.55, 0.58, 0.66)
const PANEL_SIZE := Vector2(720, 470)

## Matches loot_drop.gd so a Rare here is the same blue it was on the floor.
const RARITY_COLORS := {
	"Common": Color(0.88, 0.90, 0.94),
	"Rare": Color(0.35, 0.62, 1.00),
	"Epic": Color(0.65, 0.35, 1.00),
	"Exotic": Color(1.00, 0.80, 0.20),
}

var _flux: Label
var _weapon_list: VBoxContainer
var _armor_list: VBoxContainer
var _weapon_head: Label
var _armor_head: Label
var _empty_note: Label


func _ready() -> void:
	add_to_group("inventory_screen")
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
	visible = false
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	refresh()
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	visible = false
	get_tree().paused = false
	# The hub still wants a captured mouse; only the menus release it.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Rebuild both lists from the save. Public so tests can inspect the contents.
func refresh() -> void:
	var sm := get_node_or_null("/root/SaveManager")
	var weapons: Array = sm.data.get("owned_weapons", []) if sm else []
	var armor: Array = sm.data.get("owned_armor", []) if sm else []
	_flux.text = "FLUX  %d" % (int(sm.data.get("flux_currency", 0)) if sm else 0)
	_weapon_head.text = "WEAPONS  (%d)" % weapons.size()
	_armor_head.text = "ARMOUR  (%d)" % armor.size()
	_fill(_weapon_list, weapons)
	_fill(_armor_list, armor)
	_empty_note.visible = weapons.is_empty() and armor.is_empty()


func _fill(list: VBoxContainer, items: Array) -> void:
	for child in list.get_children():
		child.queue_free()
	for item in items:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		list.add_child(_build_row(item))


func _build_row(item: Dictionary) -> Control:
	var rarity := String(item.get("rarity", "Common"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	# Rarity swatch, so the list scans by colour before you read it.
	var swatch := ColorRect.new()
	swatch.color = RARITY_COLORS.get(rarity, Color.WHITE)
	swatch.custom_minimum_size = Vector2(6, 22)
	row.add_child(swatch)

	var name_label := Label.new()
	name_label.text = String(item.get("name", "Unknown"))
	name_label.custom_minimum_size = Vector2(200, 0)
	name_label.add_theme_font_size_override("font_size", 16)
	row.add_child(name_label)

	var rarity_label := Label.new()
	rarity_label.text = rarity
	rarity_label.add_theme_font_size_override("font_size", 14)
	rarity_label.add_theme_color_override("font_color",
		RARITY_COLORS.get(rarity, Color.WHITE))
	row.add_child(rarity_label)
	return row


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
	panel.custom_minimum_size = PANEL_SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.97)
	style.border_color = GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)

	var header := HBoxContainer.new()
	col.add_child(header)
	var title := Label.new()
	title.text = "INVENTORY"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_flux = Label.new()
	_flux.add_theme_font_size_override("font_size", 22)
	_flux.add_theme_color_override("font_color", GOLD)
	header.add_child(_flux)

	var hint := Label.new()
	hint.text = "Spend Flux at the Forge Master in the hub.   Equipping is not implemented yet."
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", DIM)
	col.add_child(hint)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 26)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(columns)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	_weapon_head = _section_header()
	left.add_child(_weapon_head)
	_weapon_list = VBoxContainer.new()
	_weapon_list.add_theme_constant_override("separation", 4)
	left.add_child(_weapon_list)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	_armor_head = _section_header()
	right.add_child(_armor_head)
	_armor_list = VBoxContainer.new()
	_armor_list.add_theme_constant_override("separation", 4)
	right.add_child(_armor_list)

	_empty_note = Label.new()
	_empty_note.text = "Nothing collected yet. Defeated enemies drop loot - walk over it and press E."
	_empty_note.add_theme_font_size_override("font_size", 14)
	_empty_note.add_theme_color_override("font_color", DIM)
	col.add_child(_empty_note)

	var close_row := HBoxContainer.new()
	close_row.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(close_row)
	var close_btn := Button.new()
	close_btn.text = "CLOSE  (I)"
	close_btn.custom_minimum_size = Vector2(160, 40)
	close_btn.pressed.connect(close)
	close_row.add_child(close_btn)


func _section_header() -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Color(0.85, 0.88, 0.94))
	return l

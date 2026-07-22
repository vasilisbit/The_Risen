extends Control

## Inventory overlay, toggled with I. Lists the weapons and armour you have
## earned, each with a rarity-boxed icon and its stats, and lets you EQUIP them:
## up to three weapons are carried into a mission (weapon slots 1-3) and one
## armour piece per slot grants passive damage reduction.
##
## Loadout changes go through SaveManager, which emits loadout_changed - the
## WeaponManager rebuilds the carried guns and the Guardian refreshes its armour
## bonus off that signal, so an equip here is reflected in the next mission (and
## live, if you open this mid-fight).

const GOLD := Color(0.95, 0.78, 0.32)
const DIM := Color(0.62, 0.65, 0.72)
const PANEL_SIZE := Vector2(860, 560)

## Base (Common) stats per weapon kind, mirroring the four weapon scenes, so the
## inventory can show what a given rarity roll actually does without loading them.
const WEAPON_BASE := {
	"Auto Rifle": {"dmg": 20.0, "rpm": 600, "mag": 30, "reload": 2.0},
	"Shotgun": {"dmg": 80.0, "rpm": 60, "mag": 8, "reload": 2.5},
	"Sniper": {"dmg": 300.0, "rpm": 40, "mag": 5, "reload": 3.0},
	"Hand Cannon": {"dmg": 60.0, "rpm": 180, "mag": 12, "reload": 1.5},
}

var _flux: Label
var _weapon_list: VBoxContainer
var _armor_list: VBoxContainer
var _weapon_head: Label
var _armor_head: Label
var _empty_note: Label
var _status: Label
var _mod_picker: Control
var _mod_picker_list: VBoxContainer
var _mod_picker_title: Label
var _pending_weapon: String = ""


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
		# Esc backs out of the mod picker first, then the inventory itself.
		if _mod_picker and _mod_picker.visible:
			_mod_picker.visible = false
		else:
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
	if _mod_picker:
		_mod_picker.visible = false
	get_tree().paused = false
	# The hub still wants a captured mouse; only the menus release it.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Rebuild both lists from the save. Public so tests can inspect the contents.
func refresh() -> void:
	var sm := get_node_or_null("/root/SaveManager")
	var weapons: Array = sm.data.get("owned_weapons", []) if sm else []
	var armor: Array = sm.data.get("owned_armor", []) if sm else []
	var equipped_w: Array = sm.data.get("equipped_weapons", []) if sm else []
	_flux.text = "FLUX  %d" % (int(sm.data.get("flux_currency", 0)) if sm else 0)
	_weapon_head.text = "WEAPONS  (%d/%d slots)" % [equipped_w.size(),
		sm.MAX_EQUIPPED_WEAPONS if sm else 3]
	_armor_head.text = "ARMOUR  (%d)" % armor.size()
	_fill_weapons(weapons, sm)
	_fill_armor(armor, sm)
	_empty_note.visible = weapons.size() <= 1 and armor.is_empty()


func _fill_weapons(items: Array, sm: Node) -> void:
	for child in _weapon_list.get_children():
		child.queue_free()
	for item in items:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		_weapon_list.add_child(_build_weapon_row(item, sm))


func _fill_armor(items: Array, sm: Node) -> void:
	for child in _armor_list.get_children():
		child.queue_free()
	for item in items:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		_armor_list.add_child(_build_armor_row(item, sm))


func _build_weapon_row(item: Dictionary, sm: Node) -> Control:
	var id := String(item.get("id", ""))
	var kind := String(item.get("name", "Auto Rifle"))
	var rarity := String(item.get("rarity", "Common"))
	var equipped: bool = sm != null and sm.is_weapon_equipped(id)

	var row := _row_panel(equipped)
	var hbox: HBoxContainer = row.get_child(0)

	hbox.add_child(_icon(kind, rarity, false))

	var mods: Array = item.get("mods", [])
	var element := _weapon_element(mods)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	hbox.add_child(info)
	info.add_child(_name_line(kind, rarity, element))
	info.add_child(_stat_line(_weapon_stats_text(kind, rarity, mods, item.get("rolls", {}))))
	info.add_child(_mod_chips(id, rarity, mods))

	var btn := _equip_button(equipped)
	if equipped:
		btn.pressed.connect(func() -> void: _on_unequip_weapon(id))
	else:
		btn.pressed.connect(func() -> void: _on_equip_weapon(id))
	hbox.add_child(btn)
	return row


func _build_armor_row(item: Dictionary, sm: Node) -> Control:
	var id := String(item.get("id", ""))
	var slot := String(item.get("name", "Chest Plate"))
	var rarity := String(item.get("rarity", "Common"))
	var equipped: bool = sm != null and sm.is_armor_equipped(id)

	var row := _row_panel(equipped)
	var hbox: HBoxContainer = row.get_child(0)

	hbox.add_child(_icon(slot, rarity, true))

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	hbox.add_child(info)
	info.add_child(_name_line(slot, rarity))
	var reduction := int(round(float(sm.ARMOR_REDUCTION.get(rarity, 0.0)) * 100.0)) if sm else 0
	info.add_child(_stat_line("-%d%% damage taken" % reduction))

	var btn := _equip_button(equipped)
	if equipped:
		btn.pressed.connect(func() -> void: _on_unequip_armor(slot))
	else:
		btn.pressed.connect(func() -> void: _on_equip_armor(id))
	hbox.add_child(btn)
	return row


# --- equip actions ----------------------------------------------------------

func _on_equip_weapon(id: String) -> void:
	var sm := get_node_or_null("/root/SaveManager")
	if sm and sm.equip_weapon(id):
		_note("Equipped. Carried weapons: switch with 1-3.")
	refresh()


func _on_unequip_weapon(id: String) -> void:
	var sm := get_node_or_null("/root/SaveManager")
	if sm and not sm.unequip_weapon(id):
		_note("You must carry at least one weapon.")
	refresh()


func _on_equip_armor(id: String) -> void:
	var sm := get_node_or_null("/root/SaveManager")
	if sm and sm.equip_armor(id):
		_note("Armour equipped.")
	refresh()


func _on_unequip_armor(slot: String) -> void:
	var sm := get_node_or_null("/root/SaveManager")
	if sm:
		sm.unequip_armor(slot)
	refresh()


func _note(text: String) -> void:
	if _status:
		_status.text = text


# --- stat text --------------------------------------------------------------

func _weapon_stats_text(kind: String, rarity: String, mods: Array, rolls: Dictionary) -> String:
	var base: Dictionary = WEAPON_BASE.get(kind, WEAPON_BASE["Auto Rifle"])
	# Same rarity+roll bands the weapon builds with, so the numbers here match the
	# gun in hand and two same-rarity drops read differently.
	var dmg := int(round(float(base["dmg"]) * Weapon.stat_band("damage", rarity, float(rolls.get("damage", 0.5)))))
	var reload := float(base["reload"]) * Weapon.stat_band("reload", rarity, float(rolls.get("reload", 0.5)))
	var recoil := Weapon.stat_band("recoil", rarity, float(rolls.get("recoil", 0.5)))
	var mag := float(base["mag"]) * Weapon.stat_band("mag", rarity, float(rolls.get("mag", 0.5)))
	if mods.has("mag"):
		mag *= 1.5
	# Stability is the readable inverse of recoil (higher = steadier).
	var stability := int(clampf((1.15 - recoil) / 0.6 * 100.0, 5.0, 99.0))
	return "DMG %d   MAG %d   RLD %.2fs   STAB %d" % [dmg, int(round(mag)), reload, stability]


## The weapon's element, derived from whichever element mod (if any) is installed.
func _weapon_element(mods: Array) -> String:
	for id in mods:
		var m: Dictionary = Weapon.MODS.get(id, {})
		if m.has("element"):
			return String(m["element"])
	return "Kinetic"


## The mod-slot row under a weapon: filled slots as removable chips, empty slots
## as a "+ Mod" button that opens the picker. Common weapons (0 slots) say so.
func _mod_chips(weapon_id: String, rarity: String, mods: Array) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	var slots := int(Weapon.MOD_SLOTS.get(rarity, 0))
	if slots == 0:
		var l := _stat_line("No mod slots (Rare+ only)")
		box.add_child(l)
		return box
	for i in slots:
		if i < mods.size():
			box.add_child(_mod_chip(weapon_id, String(mods[i])))
		else:
			var add := Button.new()
			add.text = "+ Mod"
			add.add_theme_font_size_override("font_size", 12)
			add.pressed.connect(func() -> void: _open_mod_picker(weapon_id))
			box.add_child(add)
	return box


func _mod_chip(weapon_id: String, mod_id: String) -> Button:
	var m: Dictionary = Weapon.MODS.get(mod_id, {})
	var chip := Button.new()
	chip.text = "%s  x" % String(m.get("name", mod_id))
	chip.tooltip_text = "%s - click to remove" % String(m.get("desc", ""))
	chip.add_theme_font_size_override("font_size", 12)
	if m.has("element"):
		chip.add_theme_color_override("font_color",
			Weapon.ELEMENT_COLORS.get(String(m["element"]), Color.WHITE))
	chip.pressed.connect(func() -> void: _on_remove_mod(weapon_id, mod_id))
	return chip


func _on_remove_mod(weapon_id: String, mod_id: String) -> void:
	var sm := get_node_or_null("/root/SaveManager")
	if sm and sm.remove_mod(weapon_id, mod_id):
		_note("Mod removed.")
	refresh()


func _open_mod_picker(weapon_id: String) -> void:
	_pending_weapon = weapon_id
	var sm := get_node_or_null("/root/SaveManager")
	var w: Dictionary = sm.weapon_by_id(weapon_id) if sm else {}
	_mod_picker_title.text = "INSTALL MOD  -  %s %s   (Flux %d)" % [
		String(w.get("name", "")), String(w.get("rarity", "")),
		int(sm.data.get("flux_currency", 0)) if sm else 0]
	for child in _mod_picker_list.get_children():
		child.queue_free()
	for mod_id in Weapon.MODS:
		_mod_picker_list.add_child(_mod_option_row(String(mod_id)))
	_mod_picker.visible = true


func _mod_option_row(mod_id: String) -> Control:
	var m: Dictionary = Weapon.MODS[mod_id]
	var row := _row_panel(false)
	var hbox: HBoxContainer = row.get_child(0)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info)
	var name_l := Label.new()
	name_l.text = String(m["name"])
	name_l.add_theme_font_size_override("font_size", 15)
	if m.has("element"):
		name_l.add_theme_color_override("font_color",
			Weapon.ELEMENT_COLORS.get(String(m["element"]), Color.WHITE))
	info.add_child(name_l)
	info.add_child(_stat_line("%s   -   %d Flux" % [String(m["desc"]), int(m["cost"])]))
	var btn := Button.new()
	btn.text = "INSTALL"
	btn.custom_minimum_size = Vector2(112, 0)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(func() -> void: _on_install_mod(mod_id))
	hbox.add_child(btn)
	return row


func _on_install_mod(mod_id: String) -> void:
	var sm := get_node_or_null("/root/SaveManager")
	if sm:
		_note(sm.install_mod(_pending_weapon, mod_id))
	_mod_picker.visible = false
	refresh()


# --- widget builders --------------------------------------------------------

func _icon(kind: String, rarity: String, armor: bool) -> Control:
	var icon := Control.new()
	icon.set_script(load("res://scripts/weapon_icon.gd"))
	icon.custom_minimum_size = Vector2(54, 54)
	icon.call("configure", kind, rarity, armor)
	return icon


func _row_panel(equipped: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.12, 0.16, 0.9) if equipped else Color(0.07, 0.08, 0.10, 0.7)
	if equipped:
		style.border_color = GOLD
		style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(7)
	panel.add_theme_stylebox_override("panel", style)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	panel.add_child(hbox)
	return panel


func _name_line(name_: String, rarity: String, element: String = "Kinetic") -> Label:
	var l := Label.new()
	var suffix := "   · %s" % element if element != "Kinetic" else ""
	l.text = "%s   %s%s" % [name_, rarity, suffix]
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color",
		LootIcon.RARITY_COLORS.get(rarity, Color.WHITE).lightened(0.2))
	return l


func _stat_line(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", DIM)
	return l


func _equip_button(equipped: bool) -> Button:
	var btn := Button.new()
	btn.text = "EQUIPPED" if equipped else "EQUIP"
	btn.custom_minimum_size = Vector2(112, 0)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return btn


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
	hint.text = "Equip up to 3 weapons (slots 1-3) and one piece per armour slot. Buy and sell at the Forge Master."
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", DIM)
	col.add_child(hint)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 26)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(columns)

	_weapon_head = _section_header()
	_weapon_list = VBoxContainer.new()
	_weapon_list.add_theme_constant_override("separation", 6)
	columns.add_child(_column(_weapon_head, _weapon_list))

	_armor_head = _section_header()
	_armor_list = VBoxContainer.new()
	_armor_list.add_theme_constant_override("separation", 6)
	columns.add_child(_column(_armor_head, _armor_list))

	_empty_note = Label.new()
	_empty_note.text = "Defeated enemies sometimes drop loot - walk over it and press E to collect."
	_empty_note.add_theme_font_size_override("font_size", 14)
	_empty_note.add_theme_color_override("font_color", DIM)
	col.add_child(_empty_note)

	var footer := HBoxContainer.new()
	col.add_child(footer)
	_status = Label.new()
	_status.text = ""
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", Color(0.55, 0.9, 0.65))
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_status)
	var close_btn := Button.new()
	close_btn.text = "CLOSE  (I)"
	close_btn.custom_minimum_size = Vector2(160, 40)
	close_btn.pressed.connect(close)
	footer.add_child(close_btn)

	_build_mod_picker()


## A modal-over-modal for choosing which mod to install on the pending weapon.
## Sits above the inventory panel and is hidden until "+ Mod" is pressed.
func _build_mod_picker() -> void:
	_mod_picker = Control.new()
	_mod_picker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mod_picker.mouse_filter = Control.MOUSE_FILTER_STOP
	_mod_picker.visible = false
	add_child(_mod_picker)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_mod_picker.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mod_picker.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 460)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.10, 0.14, 0.99)
	style.border_color = GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)

	_mod_picker_title = Label.new()
	_mod_picker_title.add_theme_font_size_override("font_size", 20)
	_mod_picker_title.add_theme_color_override("font_color", GOLD)
	col.add_child(_mod_picker_title)

	_mod_picker_list = VBoxContainer.new()
	_mod_picker_list.add_theme_constant_override("separation", 6)
	_mod_picker_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_mod_picker_list)

	var cancel := Button.new()
	cancel.text = "CANCEL"
	cancel.custom_minimum_size = Vector2(140, 36)
	cancel.pressed.connect(func() -> void: _mod_picker.visible = false)
	col.add_child(cancel)


## A titled, scrolling column so a long weapon list stays inside the panel.
func _column(head: Label, list: VBoxContainer) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 360)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	box.add_child(scroll)
	return box


func _section_header() -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Color(0.85, 0.88, 0.94))
	return l

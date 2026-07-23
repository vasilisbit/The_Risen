extends Control
## Forge Master vendor shop (T-0005). Built programmatically so the .tscn stays
## trivial. Opens on interact (E) with the ForgeMaster; 3 tabs
## (Weapons/Armor/Consumables); the Weapons tab has 4 slots with placeholder
## rarity icons, stats and Flux prices. Buying deducts Flux, adds the weapon to
## SaveManager.owned_weapons and persists via SaveManager.save_game(); an already
## owned weapon shows "Owned"; insufficient Flux shows an error and buys nothing.

# Rarity Flux prices per TDD §4.8 (Common 10 / Rare 25 / Epic 50 / Exotic 100).
const WEAPONS: Array[Dictionary] = [
	{"id": "auto_rifle", "name": "Auto Rifle", "rarity": "Common", "price": 10, "dmg": 18, "rpm": 600},
	{"id": "hand_cannon", "name": "Hand Cannon", "rarity": "Rare", "price": 25, "dmg": 55, "rpm": 120},
	{"id": "shotgun", "name": "Shotgun", "rarity": "Rare", "price": 25, "dmg": 96, "rpm": 90},
	{"id": "sniper", "name": "Sniper", "rarity": "Epic", "price": 50, "dmg": 150, "rpm": 45},
]

const RARITY_COLORS := {
	"Common": Color(0.7, 0.7, 0.7),
	"Rare": Color(0.2, 0.5, 1.0),
	"Epic": Color(0.6, 0.25, 1.0),
	"Exotic": Color(1.0, 0.75, 0.1),
}

## Shared palette with the inventory screen, so the two menus match.
const GOLD := Color(0.95, 0.78, 0.32)
const DIM := Color(0.62, 0.65, 0.72)

# Resolved at runtime (avoids depending on editor autoload-global registration).
@onready var _sm: Node = get_node("/root/SaveManager")

var _flux_label: Label
var _status_label: Label
var _buy_buttons: Dictionary = {}      # weapon id -> Button
var _sell_list: VBoxContainer          # rows in the Sell tab, rebuilt on change
var _mods_list: VBoxContainer          # rows in the Mods tab, rebuilt on change

var _buy_sound: AudioStreamPlayer
var _error_sound: AudioStreamPlayer


func _ready() -> void:
	add_to_group("vendor_shop")
	process_mode = Node.PROCESS_MODE_ALWAYS   # keep working while the tree is paused
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build_audio()
	_build_ui()
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	_refresh()
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true


func close() -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Attempt to buy a weapon by id. Returns a status string (also shown in the UI).
func buy_weapon(id: String) -> String:
	var weapon := _weapon_by_id(id)
	if weapon.is_empty():
		return "Unknown weapon"
	if _owns(id):
		return "Already owned"
	var flux: int = int(_sm.data.get("flux_currency", 0))
	var price: int = int(weapon["price"])
	if flux < price:
		_error_sound.play()
		_set_status("Insufficient Flux (need %d)" % price, true)
		_refresh()
		return "Insufficient Flux"
	_sm.data["flux_currency"] = flux - price
	var owned: Array = _sm.data.get("owned_weapons", [])
	owned.append({
		"id": "%s_%d" % [id, Time.get_ticks_usec()],
		"name": weapon["name"], "rarity": weapon["rarity"],
		"mods": [], "rolls": Weapon.roll_stats(),
	})
	_sm.data["owned_weapons"] = owned
	_sm.save_game()
	var tel := get_node_or_null("/root/Telemetry")
	if tel:
		tel.vendor_interaction("buy", String(weapon["name"]), price)
	_buy_sound.play()
	_set_status("Purchased %s" % weapon["name"], false)
	_refresh()
	return "Purchased"


# --- internals ---------------------------------------------------------------

func _weapon_by_id(id: String) -> Dictionary:
	for w in WEAPONS:
		if w["id"] == id:
			return w
	return {}


func _owns(id: String) -> bool:
	for w in _sm.data.get("owned_weapons", []):
		if typeof(w) == TYPE_DICTIONARY and w.get("id", "") == id:
			return true
	return false


func _set_status(text: String, is_error: bool) -> void:
	if _status_label == null:
		return
	_status_label.text = text
	_status_label.modulate = Color(1, 0.4, 0.35) if is_error else Color(0.5, 1, 0.6)


func _refresh() -> void:
	if _flux_label:
		_flux_label.text = "Flux: %d" % int(_sm.data.get("flux_currency", 0))
	var flux: int = int(_sm.data.get("flux_currency", 0))
	for id in _buy_buttons:
		var btn: Button = _buy_buttons[id]
		var weapon := _weapon_by_id(id)
		if _owns(id):
			btn.text = "Owned"
			btn.disabled = true
		else:
			btn.text = "Buy (%d)" % int(weapon["price"])
			btn.disabled = flux < int(weapon["price"])
	_refresh_sell()
	_refresh_mods()


# --- mods (install / remove on owned weapons) --------------------------------

func _build_mods_tab() -> Control:
	var root := VBoxContainer.new()
	root.name = "Mods"
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 330)
	root.add_child(scroll)
	_mods_list = VBoxContainer.new()
	_mods_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mods_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_mods_list)
	return root


func _refresh_mods() -> void:
	if _mods_list == null:
		return
	for c in _mods_list.get_children():
		c.queue_free()
	var weapons: Array = _sm.data.get("owned_weapons", [])
	if weapons.is_empty():
		var l := Label.new()
		l.text = "No weapons to mod."
		l.modulate = Color(0.7, 0.72, 0.78)
		_mods_list.add_child(l)
		return
	for w in weapons:
		if typeof(w) == TYPE_DICTIONARY:
			_mods_list.add_child(_make_mod_weapon_panel(w))


func _make_mod_weapon_panel(item: Dictionary) -> PanelContainer:
	var id := String(item.get("id", ""))
	var rarity := String(item.get("rarity", "Common"))
	var mods: Array = item.get("mods", [])
	var slots := int(Weapon.MOD_SLOTS.get(rarity, 0))

	var panel := _styled_panel()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)

	var head := Label.new()
	head.text = "%s  [%s]   -   %d/%d slots" % [String(item.get("name", "?")), rarity, mods.size(), slots]
	head.add_theme_font_size_override("font_size", 15)
	head.add_theme_color_override("font_color", RARITY_COLORS.get(rarity, Color.WHITE))
	col.add_child(head)

	if slots == 0:
		col.add_child(_dim_label("No mod slots - Rare or better weapons only."))
		return panel

	# Installed mods, each removable.
	if not mods.is_empty():
		var installed := HBoxContainer.new()
		installed.add_theme_constant_override("separation", 6)
		col.add_child(installed)
		for mod_id in mods:
			var m: Dictionary = Weapon.MODS.get(String(mod_id), {})
			var rm := Button.new()
			rm.text = "%s  x" % String(m.get("name", mod_id))
			rm.tooltip_text = "Remove this mod"
			rm.add_theme_font_size_override("font_size", 12)
			var mid: String = String(mod_id)
			rm.pressed.connect(func() -> void: _remove_mod(id, mid))
			installed.add_child(rm)

	# Install options when there's a free slot.
	if mods.size() < slots:
		col.add_child(_dim_label("Install (100 Flux each):"))
		var opts := HBoxContainer.new()
		opts.add_theme_constant_override("separation", 6)
		col.add_child(opts)
		for mod_id in Weapon.MODS:
			var m: Dictionary = Weapon.MODS[mod_id]
			var b := Button.new()
			b.text = String(m["name"])
			b.tooltip_text = String(m["desc"])
			b.add_theme_font_size_override("font_size", 12)
			if m.has("element"):
				b.add_theme_color_override("font_color",
					Weapon.ELEMENT_COLORS.get(String(m["element"]), Color.WHITE))
			var wid := id
			var mid := String(mod_id)
			b.pressed.connect(func() -> void: _install_mod(wid, mid))
			opts.add_child(b)
	return panel


func _install_mod(weapon_id: String, mod_id: String) -> void:
	var status := String(_sm.install_mod(weapon_id, mod_id))
	var ok := status.begins_with("Installed")
	if ok:
		_buy_sound.play()
	else:
		_error_sound.play()
	_set_status(status, not ok)
	_refresh()


func _remove_mod(weapon_id: String, mod_id: String) -> void:
	if _sm.remove_mod(weapon_id, mod_id):
		_set_status("Mod removed.", false)
	_refresh()


func _dim_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.modulate = Color(0.72, 0.74, 0.80)
	return l


# --- selling -----------------------------------------------------------------

func _build_sell_tab() -> Control:
	var root := VBoxContainer.new()
	root.name = "Sell"
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 330)
	root.add_child(scroll)
	_sell_list = VBoxContainer.new()
	_sell_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sell_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_sell_list)
	return root


## Rebuild the sell list from the current inventory.
func _refresh_sell() -> void:
	if _sell_list == null:
		return
	for c in _sell_list.get_children():
		c.queue_free()
	var weapons: Array = _sm.data.get("owned_weapons", [])
	var armor: Array = _sm.data.get("owned_armor", [])
	if weapons.is_empty() and armor.is_empty():
		var l := Label.new()
		l.text = "Nothing to sell."
		l.modulate = Color(0.7, 0.72, 0.78)
		_sell_list.add_child(l)
		return
	for w in weapons:
		if typeof(w) == TYPE_DICTIONARY:
			_sell_list.add_child(_make_sell_row(w, "weapon"))
	for a in armor:
		if typeof(a) == TYPE_DICTIONARY:
			_sell_list.add_child(_make_sell_row(a, "armor"))


func _make_sell_row(item: Dictionary, category: String) -> PanelContainer:
	var rarity := String(item.get("rarity", "Common"))
	var row_panel := _styled_panel()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row_panel.add_child(row)

	var swatch := ColorRect.new()
	swatch.color = RARITY_COLORS.get(rarity, Color.WHITE)
	swatch.custom_minimum_size = Vector2(10, 40)
	row.add_child(swatch)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var name_label := Label.new()
	name_label.text = "%s  [%s]" % [String(item.get("name", "?")), rarity]
	name_label.add_theme_font_size_override("font_size", 16)
	info.add_child(name_label)

	var value := int(_sm.sell_value(item))
	var sell_btn := Button.new()
	sell_btn.text = "Sell (%d)" % value
	sell_btn.custom_minimum_size = Vector2(140, 0)
	sell_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var id: String = String(item.get("id", ""))
	sell_btn.pressed.connect(func() -> void: _sell(id, category))
	row.add_child(sell_btn)
	return row_panel


func _sell(id: String, category: String) -> void:
	var got: int = _sm.sell_weapon(id) if category == "weapon" else _sm.sell_armor(id)
	if got < 0:
		_error_sound.play()
		_set_status("Can't sell your last weapon.", true)
	else:
		_buy_sound.play()
		_set_status("Sold for %d Flux." % got, false)
	_refresh()


func _build_audio() -> void:
	_buy_sound = AudioStreamPlayer.new()
	_buy_sound.stream = _make_beep(880.0, 0.09)
	add_child(_buy_sound)
	_error_sound = AudioStreamPlayer.new()
	_error_sound.stream = _make_beep(180.0, 0.14)
	add_child(_error_sound)


## Build a short decaying sine blip as an AudioStreamWAV (no external assets).
func _make_beep(freq: float, dur: float) -> AudioStreamWAV:
	var sr := 22050
	var count := int(sr * dur)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in count:
		var t := float(i) / sr
		var env := 1.0 - float(i) / count
		var sample := sin(TAU * freq * t) * env * 0.5
		bytes.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sr
	wav.stereo = false
	wav.data = bytes
	return wav


## Full-screen vendor screen: the Forge Master rendered on the left (Destiny
## faction-screen style), the shop tabs on the right.
func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 26)
	margin.add_child(split)

	# --- Left: the Forge Master portrait ---
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(430, 0)
	left.add_theme_constant_override("separation", 6)
	split.add_child(left)

	var title := Label.new()
	title.text = "FORGE MASTER"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", GOLD)
	left.add_child(title)
	var role := Label.new()
	role.text = "VANGUARD ARMOURY"
	role.add_theme_font_size_override("font_size", 13)
	role.add_theme_color_override("font_color", DIM)
	left.add_child(role)

	var portrait := _portrait_panel()
	portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(portrait)

	var flavour := Label.new()
	flavour.text = "The Forge Master builds, mods and buys Guardian gear. Trade with Flux."
	flavour.add_theme_font_size_override("font_size", 12)
	flavour.add_theme_color_override("font_color", DIM)
	flavour.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(flavour)

	# --- Right: the shop ---
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	split.add_child(right)

	var header := HBoxContainer.new()
	right.add_child(header)
	var shop_title := Label.new()
	shop_title.text = "ARMOURY"
	shop_title.add_theme_font_size_override("font_size", 24)
	shop_title.add_theme_color_override("font_color", Color(0.88, 0.9, 0.96))
	shop_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(shop_title)
	_flux_label = Label.new()
	_flux_label.add_theme_font_size_override("font_size", 22)
	_flux_label.add_theme_color_override("font_color", GOLD)
	header.add_child(_flux_label)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(tabs)

	var weapons_tab := VBoxContainer.new()
	weapons_tab.name = "Weapons"
	weapons_tab.add_theme_constant_override("separation", 8)
	tabs.add_child(weapons_tab)
	for weapon in WEAPONS:
		weapons_tab.add_child(_make_weapon_row(weapon))

	tabs.add_child(_build_mods_tab())
	tabs.add_child(_build_sell_tab())

	var footer := HBoxContainer.new()
	right.add_child(footer)
	_status_label = Label.new()
	_status_label.text = ""
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_status_label)

	var close_btn := Button.new()
	close_btn.text = "CLOSE  (Esc)"
	close_btn.custom_minimum_size = Vector2(160, 40)
	close_btn.pressed.connect(close)
	footer.add_child(close_btn)


## A dark bordered panel holding the turntable render of the Forge Master robot.
func _portrait_panel() -> Control:
	var panel := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.07, 0.10, 0.95)
	s.border_color = GOLD
	s.set_border_width_all(1)
	s.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", s)

	var disp := SubViewportContainer.new()
	disp.set_script(load("res://scripts/model_display.gd"))
	panel.add_child(disp)
	var mech_mat := StandardMaterial3D.new()
	mech_mat.albedo_color = Color(0.34, 0.36, 0.40)
	mech_mat.metallic = 0.9
	mech_mat.roughness = 0.32
	disp.call("setup", "res://assets/thirdparty/fab/skm_robot/skm_robot3_full.fbx",
		1.05, 2.9, 1.3, 0.0, mech_mat, 0.45)
	return panel


## Dark rounded row panel, matching the inventory rows.
func _styled_panel() -> PanelContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.07, 0.08, 0.10, 0.7)
	s.set_corner_radius_all(4)
	s.set_content_margin_all(8)
	p.add_theme_stylebox_override("panel", s)
	return p


func _make_weapon_row(weapon: Dictionary) -> PanelContainer:
	var row_panel := _styled_panel()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row_panel.add_child(row)

	var icon := ColorRect.new()
	icon.color = RARITY_COLORS.get(weapon["rarity"], Color.WHITE)
	icon.custom_minimum_size = Vector2(48, 48)
	row.add_child(icon)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var name_label := Label.new()
	name_label.text = "%s  [%s]" % [weapon["name"], weapon["rarity"]]
	name_label.add_theme_font_size_override("font_size", 18)
	info.add_child(name_label)
	var stats_label := Label.new()
	stats_label.text = "DMG %d   RPM %d" % [int(weapon["dmg"]), int(weapon["rpm"])]
	stats_label.modulate = Color(0.8, 0.8, 0.85)
	info.add_child(stats_label)

	var buy := Button.new()
	buy.custom_minimum_size = Vector2(140, 0)
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var wid: String = weapon["id"]
	buy.pressed.connect(func() -> void: buy_weapon(wid))
	_buy_buttons[wid] = buy
	row.add_child(buy)

	return row_panel


func _make_placeholder_tab(tab_name: String, message: String) -> Control:
	var c := CenterContainer.new()
	c.name = tab_name
	var l := Label.new()
	l.text = message
	l.modulate = Color(0.75, 0.75, 0.8)
	c.add_child(l)
	return c

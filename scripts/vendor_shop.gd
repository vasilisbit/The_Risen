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

# Resolved at runtime (avoids depending on editor autoload-global registration).
@onready var _sm: Node = get_node("/root/SaveManager")

var _flux_label: Label
var _status_label: Label
var _buy_buttons: Dictionary = {}      # weapon id -> Button

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
	owned.append({"id": id, "name": weapon["name"], "rarity": weapon["rarity"]})
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


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 520)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	margin.add_child(inner)

	var header := HBoxContainer.new()
	inner.add_child(header)
	var title := Label.new()
	title.text = "FORGE MASTER"
	title.add_theme_font_size_override("font_size", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_flux_label = Label.new()
	_flux_label.add_theme_font_size_override("font_size", 20)
	header.add_child(_flux_label)

	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(0, 380)
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(tabs)

	var weapons_tab := VBoxContainer.new()
	weapons_tab.name = "Weapons"
	weapons_tab.add_theme_constant_override("separation", 8)
	tabs.add_child(weapons_tab)
	for weapon in WEAPONS:
		weapons_tab.add_child(_make_weapon_row(weapon))

	tabs.add_child(_make_placeholder_tab("Armor", "Armor stock coming soon."))
	tabs.add_child(_make_placeholder_tab("Consumables", "Consumables coming soon."))

	_status_label = Label.new()
	_status_label.text = "Aim at an item and buy with Flux."
	inner.add_child(_status_label)

	var close_btn := Button.new()
	close_btn.text = "Close (Esc)"
	close_btn.pressed.connect(close)
	inner.add_child(close_btn)


func _make_weapon_row(weapon: Dictionary) -> PanelContainer:
	var row_panel := PanelContainer.new()
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

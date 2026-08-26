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
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
	# Transition into the vendor "scene" with a quick fade to black and back.
	var gs := get_node_or_null("/root/GameState")
	if gs and gs.has_method("fade_black_then"):
		gs.fade_black_then(_do_open)
	else:
		_do_open()


func _do_open() -> void:
	_refresh()
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true


func close() -> void:
	# Fade out through black just like the open, so leaving the shop isn't a hard cut.
	var gs := get_node_or_null("/root/GameState")
	if gs and gs.has_method("fade_black_then"):
		gs.fade_black_then(_do_close)
	else:
		_do_close()


func _do_close() -> void:
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
	var id: String = String(item.get("id", ""))
	var equipped: bool = _sm.is_weapon_equipped(id) if category == "weapon" else _sm.is_armor_equipped(id)
	var sell_btn := Button.new()
	sell_btn.custom_minimum_size = Vector2(140, 0)
	sell_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if equipped:
		# Equipped gear can't be sold - unequip it in the inventory first.
		sell_btn.text = "Equipped"
		sell_btn.disabled = true
		sell_btn.tooltip_text = "Unequip this in the inventory before selling it."
	else:
		sell_btn.text = "Sell (%d)" % value
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


## A dedicated vendor "screen": a 3D staged backdrop of the Forge Master standing
## at his stall on the left, the shop panel on the right. The Guardian is frozen
## (the tree is paused) - only the cursor moves to pick items.
func _build_ui() -> void:
	# Full-screen 3D backdrop (the stall + the robot), drawn behind everything.
	add_child(_build_backdrop())

	# Name plate over the robot, lower-left.
	var plate := VBoxContainer.new()
	plate.anchor_top = 1.0
	plate.anchor_bottom = 1.0
	plate.offset_left = 50.0
	plate.offset_top = -132.0
	plate.grow_vertical = Control.GROW_DIRECTION_BEGIN
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plate)
	var role := Label.new()
	role.text = "VANGUARD ARMOURY"
	role.add_theme_font_size_override("font_size", 15)
	role.add_theme_color_override("font_color", GOLD)
	plate.add_child(role)
	var big := Label.new()
	big.text = "FORGE MASTER"
	big.add_theme_font_size_override("font_size", 42)
	big.add_theme_color_override("font_color", Color.WHITE)
	big.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	big.add_theme_constant_override("outline_size", 8)
	plate.add_child(big)
	var sub := Label.new()
	sub.text = "Builds, mods and buys Guardian gear."
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", Color(0.8, 0.82, 0.88))
	plate.add_child(sub)

	# Right-hand shop panel.
	var right := PanelContainer.new()
	right.anchor_left = 0.52
	right.anchor_right = 1.0
	right.anchor_top = 0.0
	right.anchor_bottom = 1.0
	right.offset_left = 0.0
	right.offset_right = 0.0
	right.offset_top = 0.0
	right.offset_bottom = 0.0
	right.mouse_filter = Control.MOUSE_FILTER_STOP
	var rs := StyleBoxFlat.new()
	rs.bg_color = Color(0.05, 0.06, 0.09, 0.88)
	rs.border_color = Color(0.30, 0.33, 0.40, 0.7)
	rs.border_width_left = 1
	rs.content_margin_left = 34
	rs.content_margin_right = 34
	rs.content_margin_top = 30
	rs.content_margin_bottom = 26
	right.add_theme_stylebox_override("panel", rs)
	add_child(right)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	right.add_child(inner)

	var header := HBoxContainer.new()
	inner.add_child(header)
	var shop_title := Label.new()
	shop_title.text = "ARMOURY"
	shop_title.add_theme_font_size_override("font_size", 26)
	shop_title.add_theme_color_override("font_color", Color(0.90, 0.92, 0.97))
	shop_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(shop_title)
	_flux_label = Label.new()
	_flux_label.add_theme_font_size_override("font_size", 22)
	_flux_label.add_theme_color_override("font_color", GOLD)
	header.add_child(_flux_label)

	var desc := Label.new()
	desc.text = "Trade with Flux. Aim your cursor and select an item."
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", DIM)
	inner.add_child(desc)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(tabs)

	# Weapons tab: an icon-tile grid.
	var weapons_tab := VBoxContainer.new()
	weapons_tab.name = "Weapons"
	weapons_tab.add_theme_constant_override("separation", 10)
	tabs.add_child(weapons_tab)
	var wlabel := Label.new()
	wlabel.text = "WEAPONS"
	wlabel.add_theme_font_size_override("font_size", 14)
	wlabel.add_theme_color_override("font_color", GOLD)
	weapons_tab.add_child(wlabel)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	weapons_tab.add_child(grid)
	for weapon in WEAPONS:
		grid.add_child(_make_weapon_tile(weapon))

	tabs.add_child(_build_mods_tab())
	tabs.add_child(_build_sell_tab())

	var footer := HBoxContainer.new()
	inner.add_child(footer)
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


## The 3D staged backdrop: a slice of the weapon-bay stall with the Forge Master
## robot standing behind the counter on the left, warmly lit. Rendered in a
## full-screen SubViewport with its own world, so it reads like a vendor scene.
func _build_backdrop() -> Control:
	var vc := SubViewportContainer.new()
	vc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vc.stretch = true
	vc.custom_minimum_size = get_viewport().get_visible_rect().size
	vc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vc.add_child(vp)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.045, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.26, 0.27, 0.34)
	env.ambient_light_energy = 0.5
	we.environment = env
	vp.add_child(we)

	# Stall geometry (a recreation of the bay corner the vendor stands in).
	_stage_box(vp, Vector3(0, -0.05, -1.5), Vector3(16, 0.1, 9), Color(0.13, 0.14, 0.17), 0.6)
	_stage_box(vp, Vector3(0, 2.4, -4.2), Vector3(16, 7, 0.3), Color(0.19, 0.21, 0.27), 0.9)
	# The fal.ai forge counter as the trade desk in the staged shot (replaces the
	# plain box; falls back to it if the asset is missing).
	var fc_scene: Resource = load("res://assets/generated/interior/forge_counter.glb")
	if fc_scene is PackedScene:
		var fc := (fc_scene as PackedScene).instantiate() as Node3D
		vp.add_child(fc)
		# Fixed transform (the SubViewport isn't in the tree here, so a global-AABB fit
		# would read identity). -PI/2 spans it left-right; placed as the foreground trade
		# desk in front of the clerk (tuned in-engine).
		fc.rotation.y = -PI * 0.5
		fc.scale = Vector3.ONE * 3.1
		fc.position = Vector3(-1.2, 0.72, 0.45)
	else:
		_stage_box(vp, Vector3(1.6, 0.55, -0.2), Vector3(11, 1.1, 0.7), Color(0.15, 0.16, 0.20), 0.5)
		_stage_box(vp, Vector3(1.6, 1.15, -0.15), Vector3(11, 0.1, 0.95), Color(0.85, 0.62, 0.30), 0.3)
	_stage_box(vp, Vector3(4.6, 2.7, -3.9), Vector3(3.2, 0.1, 0.8), Color(0.10, 0.11, 0.14), 0.7)
	_stage_box(vp, Vector3(4.6, 1.9, -3.9), Vector3(3.2, 0.1, 0.8), Color(0.10, 0.11, 0.14), 0.7)

	var key := OmniLight3D.new()
	key.position = Vector3(-1.2, 3.2, 2.2)
	key.light_energy = 3.4
	key.omni_range = 13.0
	key.light_color = Color(1.0, 0.78, 0.52)
	vp.add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(3.5, 3.0, 1.5)
	fill.light_energy = 1.8
	fill.omni_range = 14.0
	fill.light_color = Color(0.72, 0.82, 1.0)
	vp.add_child(fill)

	# The custom Meshy-rigged Forge Master (T-0043) - same asset as the hub bay, so
	# the clerk you talk to matches the one behind the counter. Ships its own PBR
	# (gunmetal + gold + teal + forge-orange core) and a real rigged idle.
	var robot_scene: Resource = load("res://assets/generated/hub/forge_master.glb")
	if robot_scene is PackedScene:
		var robot := (robot_scene as PackedScene).instantiate() as Node3D
		robot.scale = Vector3.ONE * 1.15
		robot.position = Vector3(-1.82, -0.1, -0.9)
		robot.rotation.y = PI - 0.55                 # face 3/4 toward the camera
		vp.add_child(robot)
		var idle := Node.new()                       # real rigged idle (guardian pattern)
		idle.set_script(load("res://scripts/forge_master_idle.gd"))
		robot.add_child(idle)

	var cam := Camera3D.new()
	cam.fov = 38.0
	vp.add_child(cam)
	# Zoomed in on the robot at the left, so the counter's side edges fall
	# outside the frame and it reads as an endless stall wall.
	cam.look_at_from_position(Vector3(0.0, 1.5, 2.15), Vector3(-1.2, 1.4, -0.9), Vector3.UP)
	return vc


func _stage_box(vp: SubViewport, center: Vector3, size: Vector3, color: Color, rough: float) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	mat.metallic = 0.1
	mi.material_override = mat
	mi.position = center
	vp.add_child(mi)


## Global-space AABB enclosing a staged node's visuals (for scaling/seating a GLB).
func _stage_aabb(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for vi in node.find_children("*", "VisualInstance3D", true, false):
		var a: AABB = (vi as VisualInstance3D).global_transform * (vi as VisualInstance3D).get_aabb()
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	return out


## A weapon tile for the buy grid: rarity-bordered card with icon, name, stats
## and a Buy button (registered in _buy_buttons so _refresh() updates it).
func _make_weapon_tile(weapon: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 118)
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.08, 0.09, 0.12, 0.92)
	cs.border_color = RARITY_COLORS.get(weapon["rarity"], Color.WHITE)
	cs.set_border_width_all(1)
	cs.set_corner_radius_all(5)
	cs.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", cs)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	card.add_child(v)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	v.add_child(top)
	var icon := ColorRect.new()
	icon.color = RARITY_COLORS.get(weapon["rarity"], Color.WHITE)
	icon.custom_minimum_size = Vector2(42, 42)
	top.add_child(icon)
	var nm := VBoxContainer.new()
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	var nlabel := Label.new()
	nlabel.text = String(weapon["name"])
	nlabel.add_theme_font_size_override("font_size", 16)
	nlabel.add_theme_color_override("font_color",
		RARITY_COLORS.get(weapon["rarity"], Color.WHITE).lightened(0.2))
	nm.add_child(nlabel)
	var rlabel := Label.new()
	rlabel.text = "%s   DMG %d  RPM %d" % [String(weapon["rarity"]), int(weapon["dmg"]), int(weapon["rpm"])]
	rlabel.add_theme_font_size_override("font_size", 11)
	rlabel.add_theme_color_override("font_color", DIM)
	nm.add_child(rlabel)

	var buy := Button.new()
	buy.custom_minimum_size = Vector2(0, 32)
	var wid: String = weapon["id"]
	buy.pressed.connect(func() -> void: buy_weapon(wid))
	_buy_buttons[wid] = buy
	v.add_child(buy)
	return card


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

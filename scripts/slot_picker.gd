extends Control

## Reusable save-slot picker overlay (T-0046). Lists SaveManager's slots with a
## short summary + timestamp and calls back with the chosen slot index. One widget
## serves three modes:
##   * "load" - only occupied slots are selectable (resume a game).
##   * "save" - any slot; overwriting an occupied one asks to confirm.
##   * "new"  - any slot; overwriting an occupied one asks to confirm.
##
## Added under the main menu (a Control) and the pause layer (a CanvasLayer);
## PROCESS_MODE_ALWAYS so it works while the pause menu has the tree frozen.

const GOLD := Color(0.95, 0.78, 0.32)
const DIM := Color(0.55, 0.58, 0.66)
const TEXT := Color(0.9, 0.92, 0.97)

var _mode := "load"
var _on_pick: Callable = Callable()
var _list: VBoxContainer
var _title: Label
var _confirm: Control
var _confirm_label: Label
var _pending_slot: int = -1


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
	visible = false
	_build()


## Show the picker. `on_pick` receives the chosen slot index (0-based).
func open(mode: String, title: String, on_pick: Callable) -> void:
	_mode = mode
	_on_pick = on_pick
	_title.text = title
	_confirm.visible = false
	_refresh()
	visible = true


func close() -> void:
	visible = false


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	var sm := get_node_or_null("/root/SaveManager")
	if sm == null:
		return
	for i in sm.SLOT_COUNT:
		_list.add_child(_build_card(i, sm.slot_summary(i)))


func _build_card(slot: int, summary: Dictionary) -> Control:
	var exists := bool(summary.get("exists", false))
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(560, 68)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 16)
	btn.clip_text = false
	# Load mode can't pick an empty slot; save/new can (to create a new game there).
	btn.disabled = (_mode == "load" and not exists)

	var head := "SLOT %d" % (slot + 1)
	var detail := ""
	if exists:
		var cls := String(summary.get("class", "Assault"))
		if not bool(summary.get("class_chosen", true)):
			cls = "No class"
		detail = "Lv %d  %s   ·   %s Flux   ·   %d/%d missions   ·   %s\n%s" % [
			int(summary.get("level", 1)), cls,
			_commas(int(summary.get("flux", 0))),
			int(summary.get("missions_done", 0)), int(summary.get("missions_total", 3)),
			String(summary.get("last_mission", "Earth")),
			_stamp(int(summary.get("saved_at", 0)))]
	else:
		detail = "Empty"
	btn.text = "%s\n%s" % [head, detail]
	btn.add_theme_color_override("font_color", TEXT if exists else DIM)
	btn.pressed.connect(func() -> void: _on_card(slot, exists))
	return btn


func _on_card(slot: int, exists: bool) -> void:
	if _mode == "load":
		if exists:
			_finish(slot)
		return
	# save / new: confirm before clobbering an occupied slot.
	if exists:
		_pending_slot = slot
		var verb := "overwrite" if _mode == "save" else "start a new game in"
		_confirm_label.text = "Slot %d has a saved game.\nReally %s it?" % [slot + 1, verb]
		_confirm.visible = true
	else:
		_finish(slot)


func _finish(slot: int) -> void:
	visible = false
	if _on_pick.is_valid():
		_on_pick.call(slot)


func _commas(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out


func _stamp(unix: int) -> String:
	if unix <= 0:
		return "Saved"
	return "Saved " + Time.get_datetime_string_from_unix_time(unix, true)


# --- construction ------------------------------------------------------------

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.97)
	style.border_color = GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	_title = Label.new()
	_title.text = "SELECT SLOT"
	_title.add_theme_font_size_override("font_size", 28)
	_title.add_theme_color_override("font_color", GOLD)
	box.add_child(_title)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	box.add_child(_list)

	var back := Button.new()
	back.text = "BACK"
	back.custom_minimum_size = Vector2(160, 42)
	back.pressed.connect(close)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(back)
	box.add_child(row)

	_build_confirm()


func _build_confirm() -> void:
	_confirm = Control.new()
	_confirm.anchor_right = 1.0
	_confirm.anchor_bottom = 1.0
	_confirm.offset_right = 0.0
	_confirm.offset_bottom = 0.0
	_confirm.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm.visible = false
	add_child(_confirm)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confirm.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm.add_child(center)

	var cpanel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.08, 0.09, 0.98)
	style.border_color = GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(22)
	cpanel.add_theme_stylebox_override("panel", style)
	center.add_child(cpanel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	cpanel.add_child(box)

	_confirm_label = Label.new()
	_confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_label.add_theme_font_size_override("font_size", 18)
	box.add_child(_confirm_label)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)

	var yes := Button.new()
	yes.text = "CONFIRM"
	yes.custom_minimum_size = Vector2(150, 44)
	yes.pressed.connect(func() -> void:
		_confirm.visible = false
		if _pending_slot >= 0:
			_finish(_pending_slot))
	row.add_child(yes)

	var no := Button.new()
	no.text = "CANCEL"
	no.custom_minimum_size = Vector2(150, 44)
	no.pressed.connect(func() -> void: _confirm.visible = false)
	row.add_child(no)

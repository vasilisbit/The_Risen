extends CanvasLayer
## PauseMenu (autoload, T-0046): the global in-game pause menu, opened with Escape.
##
## Escape now opens Pause (and frees the cursor); Resume re-captures it - replacing
## the old "Escape toggles mouse capture" in missions. It is context-aware: it will
## NOT open on the main menu, while the tree is already paused by another modal
## (vendor / class / difficulty select), while the inventory is open (that owns
## Escape to close itself), or during a cinematic where the player is frozen (the
## helm, the Fold, a landing / lift-off) - those keep Escape as their own skip /
## cancel. See _can_open().
##
## Buttons: Resume, Save Game (slot picker), Load Game (slot picker), Settings,
## Return to Hub (missions only), Main Menu, Quit to Desktop.

const MAIN_MENU_PATH := "res://ui/main_menu.tscn"
const HUB_PATH := "res://scenes/hub/hub.tscn"

const GOLD := Color(0.95, 0.78, 0.32)
const DIM := Color(0.55, 0.58, 0.66)

var _open := false
var _prev_mouse := Input.MOUSE_MODE_CAPTURED
var _root: Control
var _hub_btn: Button           # "Return to Hub" - only in a mission
var _menu_btn: Button          # "Main Menu"
var _toast: Label
var _settings: Control
var _picker: Control
var _toast_timer := 0.0


func _ready() -> void:
	layer = 120                # above HUD, below GameState's fade (128)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func _process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			_toast.visible = false


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _open:
		# A sub-overlay (settings / slot picker) takes Escape first, stepping back to
		# the pause menu rather than resuming the game.
		if _settings.visible:
			_settings.close()
		elif _picker.visible:
			_picker.close()
		else:
			_resume()
		get_viewport().set_input_as_handled()
	elif _can_open():
		_open_menu()
		get_viewport().set_input_as_handled()


## True only in ordinary, controllable gameplay (hub or a mission) - see the class
## comment for everything this deliberately steps aside for.
func _can_open() -> bool:
	var tree := get_tree()
	if tree == null or tree.paused:
		return false                                   # vendor / class / difficulty modal
	var scene := tree.current_scene
	if scene == null or scene.scene_file_path == MAIN_MENU_PATH:
		return false
	var inv := tree.get_first_node_in_group("inventory_screen")
	if inv and inv is CanvasItem and (inv as CanvasItem).visible:
		return false                                   # inventory owns Escape to close
	var player := tree.get_first_node_in_group("player")
	if player == null or not (player as Node).can_process():
		return false                                   # cutscene froze the player, or no player
	return true


func _in_mission() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return false
	return scene.scene_file_path.contains("/missions/")


# --- open / close ------------------------------------------------------------

func _open_menu() -> void:
	_open = true
	_prev_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_hub_btn.visible = _in_mission()
	_toast.visible = false
	_settings.visible = false
	_picker.visible = false
	_root.visible = true
	get_tree().paused = true


func _resume() -> void:
	_open = false
	get_tree().paused = false
	_root.visible = false
	Input.mouse_mode = _prev_mouse if _prev_mouse == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED


## Leave to another scene (Load / Return to Hub / Main Menu): drop the pause, then
## let GameState fade-swap. The destination scene sets its own mouse mode.
func _leave_to(path: String) -> void:
	_open = false
	_root.visible = false
	get_tree().paused = false
	var gs := get_node_or_null("/root/GameState")
	if gs and gs.has_method("transition_to"):
		gs.transition_to(path)
	else:
		get_tree().change_scene_to_file(path)


# --- button actions ----------------------------------------------------------

func _on_save() -> void:
	_picker.open("save", "SAVE GAME", _do_save)


func _do_save(slot: int) -> void:
	var sm := get_node_or_null("/root/SaveManager")
	if sm and sm.has_method("save_to_slot") and sm.save_to_slot(slot):
		_show_toast("Saved to Slot %d" % (slot + 1))
	else:
		_show_toast("Save failed")


func _on_load() -> void:
	_picker.open("load", "LOAD GAME", _do_load)


func _do_load(slot: int) -> void:
	var sm := get_node_or_null("/root/SaveManager")
	if sm and sm.has_method("load_slot"):
		sm.load_slot(slot)
	_leave_to(HUB_PATH)


func _on_settings() -> void:
	_settings.open()


func _on_hub() -> void:
	_leave_to(HUB_PATH)


func _on_menu() -> void:
	_leave_to(MAIN_MENU_PATH)


func _on_quit() -> void:
	get_tree().quit()


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast.visible = true
	_toast_timer = 2.2


# --- construction ------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.97)
	style.border_color = GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", GOLD)
	box.add_child(title)

	_toast = Label.new()
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 15)
	_toast.add_theme_color_override("font_color", Color(0.6, 0.9, 0.7))
	_toast.visible = false
	box.add_child(_toast)

	box.add_child(_menu_button("RESUME", _resume))
	box.add_child(_menu_button("SAVE GAME", _on_save))
	box.add_child(_menu_button("LOAD GAME", _on_load))
	box.add_child(_menu_button("SETTINGS", _on_settings))
	_hub_btn = _menu_button("RETURN TO HUB", _on_hub)
	box.add_child(_hub_btn)
	_menu_btn = _menu_button("MAIN MENU", _on_menu)
	box.add_child(_menu_btn)
	box.add_child(_menu_button("QUIT TO DESKTOP", _on_quit))

	# Shared sub-overlays, above the pause panel.
	_settings = Control.new()
	_settings.set_script(load("res://scripts/settings_panel.gd"))
	_root.add_child(_settings)

	_picker = Control.new()
	_picker.set_script(load("res://scripts/slot_picker.gd"))
	_root.add_child(_picker)


func _menu_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(300, 44)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(cb)
	return b

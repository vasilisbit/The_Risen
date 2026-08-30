extends Control
class_name Credits

## T-0039 credits roll. A single 30-second auto-scroll over an animated starfield,
## styled to match the main menu (black space, gold section headers, the game's
## diamond/gold shape language). ESC (or E / Enter) skips at any time.
##
## Two entry points, both routed by `next_scene` (set by the caller before the
## scene change; defaults to the main menu):
##   - Main menu "CREDITS" entry           -> returns to the main menu.
##   - After clearing Venus on LEGENDARY    -> played between the lift-off-to-orbit
##     cinematic and spawning in the hub, then continues into the hub.
##
## The content mirrors docs/ASSET_LIST.md (planning repo) 1:1 — keep them in sync.

## Where to go when the roll finishes or is skipped. A static so the caller can set
## it just before change_scene (scene args can't be passed through change_scene_to_file).
static var next_scene: String = "res://ui/main_menu.tscn"

const GOLD := Color(0.95, 0.78, 0.32)
const WHITE := Color(0.94, 0.95, 0.98)
const DIM := Color(0.62, 0.66, 0.74)
const STAR_COUNT := 220
const STAR_DRIFT := 0.09
const SCROLL_TIME := 30.0        # seconds for the whole roll to pass the screen
const ROLL_WIDTH := 720.0

var _stars: Array[Vector3] = []
var _time: float = 0.0
var _roll: Control
var _roll_h: float = 0.0
var _speed: float = 60.0
var _fade: ColorRect
var _finishing: bool = false
var _started: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	_seed_stars()
	_build_roll()
	_build_fade()
	# Start the roll below the screen and let _process scroll it up.
	call_deferred("_place_roll")


func _seed_stars() -> void:
	for i in STAR_COUNT:
		_stars.append(Vector3(randf(), randf(), randf_range(0.15, 1.0)))


## The scrolling column of credits, built in code so it survives any window size.
func _build_roll() -> void:
	_roll = VBoxContainer.new()
	_roll.add_theme_constant_override("separation", 6)
	_roll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_roll.custom_minimum_size = Vector2(ROLL_WIDTH, 0)
	add_child(_roll)

	_title("THE RISEN")
	_line("A Guardian Awakens", 20, GOLD)
	_gap(52)

	_header("DEVELOPED BY")
	_line("Vasileios Bitzas", 30, WHITE)
	_line("Design · Programming · Art Direction", 15, DIM)
	_gap(44)

	_header("BUILT WITH")
	_pair("Godot Engine 4.7", "Godot Foundation · MIT")
	_pair("Blender 5.2", "Blender Foundation")
	_pair("Godot AI (godot-ai)", "In-editor AI tooling")
	_pair("fal.ai", "Generative model API")
	_gap(44)

	_header("ART & 3D — AI-GENERATED (fal.ai)")
	_pair("Guardian & viewmodel", "nano-banana-pro · Meshy")
	_pair("Weapons ×4", "nano-banana-pro · Tripo H3.1")
	_pair("Enemies & bosses ×6", "nano-banana-pro · Meshy")
	_pair("Forge Master vendor", "nano-banana-pro · Meshy")
	_pair("Ship, interior & planets", "nano-banana-pro · Tripo H3.1")
	_pair("Environments & textures", "nano-banana-pro · Tripo · PATINA")
	_pair("UI / HUD icons ×12", "nano-banana-pro")
	_gap(44)

	_header("AUDIO — AI-GENERATED (fal.ai)")
	_pair("Music", "Stable Audio 3")
	_pair("Sound effects", "ElevenLabs")
	_pair("Vendor voice", "ElevenLabs TTS")
	_gap(44)

	_header("CINEMATICS — AI-GENERATED (fal.ai)")
	_pair("Fold & lift-off clips", "nano-banana-pro · Seedance 2.0")
	_gap(44)

	_header("THIRD-PARTY ASSETS")
	_pair("Sci-Fi Essentials Kit", "Quaternius · CC0")
	_pair("3D Planet Generator addon", "naejimer · MIT")
	_gap(44)

	_header("fal.ai MODELS")
	_line("nano-banana-pro / edit", 15, DIM)
	_line("Tripo H3.1 & P1 image/text-to-3d", 15, DIM)
	_line("Meshy v7 multi-image-to-3d + rigging", 15, DIM)
	_line("fal-ai/patina", 15, DIM)
	_line("Stable Audio 3", 15, DIM)
	_line("ElevenLabs sound-effects & TTS", 15, DIM)
	_line("Bytedance Seedance 2.0", 15, DIM)
	_gap(44)

	_header("SPECIAL THANKS")
	_line("The Godot Engine community", 17, WHITE)
	_line("The Blender & open-source 3D community", 17, WHITE)
	_line("fal.ai", 17, WHITE)
	_line("Quaternius, for years of CC0 game art", 17, WHITE)
	_line("Friends, family & every playtester", 17, WHITE)
	_gap(60)

	_line("Thank you for playing.", 22, GOLD)
	_gap(24)
	_line("The Risen", 16, DIM)
	_gap(120)


func _title(text: String) -> void:
	_line(text, 64, WHITE)


func _header(text: String) -> void:
	_gap(10)
	_line(text, 22, GOLD)
	_gap(6)


func _line(text: String, sz: int, col: Color) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(ROLL_WIDTH, 0)
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_roll.add_child(l)


## A "Label — sublabel" credit row (name left-ish, source dimmer under it), centered.
func _pair(name_: String, source: String) -> void:
	_line(name_, 19, WHITE)
	_line(source, 14, DIM)
	_gap(8)


func _gap(px: float) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(ROLL_WIDTH, px)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_roll.add_child(s)


func _build_fade() -> void:
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)     # start black, fade in
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	create_tween().tween_property(_fade, "color:a", 0.0, 0.8)


## Position the roll centered horizontally, starting just below the screen, and set
## the scroll speed so the whole column crosses the screen in SCROLL_TIME.
func _place_roll() -> void:
	_roll_h = _roll.get_combined_minimum_size().y
	_roll.size = Vector2(ROLL_WIDTH, _roll_h)
	_roll.position = Vector2((size.x - ROLL_WIDTH) * 0.5, size.y + 20.0)
	# Travel = from below the screen to fully off the top.
	_speed = (size.y + _roll_h + 40.0) / SCROLL_TIME
	_started = true


func _process(delta: float) -> void:
	_time += delta
	for i in _stars.size():
		var s := _stars[i]
		s.x -= s.z * delta * STAR_DRIFT
		if s.x < -0.02:
			s.x = 1.02
			s.y = randf()
		_stars[i] = s
	if _started and not _finishing and _roll:
		_roll.position.y -= _speed * delta
		# Keep it centered if the window resizes mid-roll.
		_roll.position.x = (size.x - ROLL_WIDTH) * 0.5
		if _roll.position.y <= -_roll_h - 20.0:
			_finish()
	queue_redraw()


func _draw() -> void:
	var vp := size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0))
	for s in _stars:
		var p := Vector2(s.x * vp.x, s.y * vp.y)
		var a: float = 0.25 + 0.55 * s.z
		a *= 0.75 + 0.25 * sin(_time * (1.0 + s.z * 3.0) + s.y * 20.0)
		draw_circle(p, 0.6 + s.z * 1.4, Color(0.75, 0.85, 1.0, a))
	# Skip hint, bottom-right, subtle.
	var f := get_theme_default_font()
	if f:
		var hint := "[ESC] SKIP"
		var fs := 14
		var w := f.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2(vp.x - w - 28.0, vp.y - 24.0), hint,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.6, 0.64, 0.72, 0.8))


func _unhandled_input(event: InputEvent) -> void:
	if _finishing:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept") \
			or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_finish()


func _finish() -> void:
	if _finishing:
		return
	_finishing = true
	set_process_unhandled_input(false)
	var target := next_scene
	# Reset the static so a later menu visit returns to the menu by default.
	next_scene = "res://ui/main_menu.tscn"
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.5)
	tw.tween_callback(func() -> void: _go(target))


func _go(path: String) -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs and gs.has_method("transition_to"):
		gs.transition_to(path)
	else:
		get_tree().change_scene_to_file(path)

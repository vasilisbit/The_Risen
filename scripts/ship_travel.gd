extends CanvasLayer
## ShipTravel autoload (P1) - the public entry point for the Fold cinematic and the keeper
## of the SEAMLESS hand-off into the mission's real-time landing.
##
## The verb: from the helm (or the hologram table) you pick a world and confirm a
## difficulty; that funnels here. `begin()` plays the Fold - the warp-to-planet transition -
## and then dissolves straight into the mission, whose own landed_ship.start_landing() runs
## the INTERACTIVE, in-engine landing on the surface (that half is deliberately NOT baked, so
## it stays live/replayable). There is no white flash any more: the swap happens under a
## short dark dissolve while the destination is preloaded, so the fold flows into the landing
## as one continuous shot.
##
## The Fold itself is played one of two ways, best-first:
##   1. A PRE-BAKED VIDEO  (assets/generated/fold/<mission>.ogv, made by tools/gen_fold_video.py
##      on fal.ai Seedance) - a filmic warp+approach+atmospheric-entry clip. Preferred when the
##      file is present; this is the "do the fold with video" path.
##   2. The in-engine `travel_cutscene` - a real-time chase-cam flight of hero_ship.glb to the
##      3D planet. The always-available fallback when no video is baked.
##
## It is an autoload (not scene-scoped) so the API reads as `ShipTravel.begin(...)` and so the
## dissolve + preloaded swap survive the scene change that frees the fold.
##
## SAFE FALLBACK: if neither a video nor the in-engine cutscene assets are available, `begin()`
## returns false and the caller does its existing plain fade instead - the Fold never dead-ends.

enum State { IDLE, FOLD, APPROACH, DESCENT, HANDOFF }

const CUTSCENE_SCENE := "res://scenes/hub/travel_cutscene.tscn"
const SHIP_GLB := "res://assets/generated/ship/hero_ship.glb"
const FOLD_DIR := "res://assets/generated/fold/"
## The generic lift-off clip (ship leaves atmosphere -> docks into the mothership), reused on
## every planet. Played by play_liftoff() after the in-engine lift-off climb.
const LIFTOFF_VIDEO := "res://assets/generated/fold/liftoff.ogv"
## The NEW-GAME intro cinematic (assets/generated/intro/intro.mp4, made by
## tools/gen_intro_cinematic.py). Self-contained B&W lore film with its own baked orchestral
## score + narration; played by play_intro() before the hub loads on a fresh character.
## Playback is FREE and needs no addon: Godot's core VideoStreamPlayer only decodes Theora, which
## macroblocks this film in-engine, and the only mp4 addon (GDE GoZen) is paid/compile-your-own. So
## the film ships as a WebP frame pack (intro_frames.bin) + its baked mix (intro_audio.ogg) and is
## played in sync by scripts/intro_sequence_player.gd - no codec, no purchase, straight from res://.
## GoZen (its `VideoPlayback` wrapper node, playing intro.mp4) is kept as an OPTIONAL fallback for
## anyone who has the compiled addon; EIRTeam.FFmpeg is a last-ditch fallback (broken on 4.7). The
## B&W look is a playback shader (shaders/intro_bw.gdshader). If nothing is available, play_intro()
## no-ops and the hub loads straight away, so the game never hard-depends on the intro.
const INTRO_VIDEO := "res://assets/generated/intro/intro.mp4"
## FREE, core-Godot playback (PREFERRED): the film as a WebP frame pack + its baked mix, played by
## scripts/intro_sequence_player.gd. No addon, no purchase; made by tools/pack_intro_frames.py.
## The .bin is a non-resource file - add `*.bin` to the export preset's non-resource filters (the
## player also falls back to a copy beside the .exe). The .ogg imports normally.
const INTRO_FRAMES := "res://assets/generated/intro/intro_frames.bin"
const INTRO_AUDIO := "res://assets/generated/intro/intro_audio.ogg"
const INTRO_SEQ_PLAYER := "res://scripts/intro_sequence_player.gd"
## GoZen's GDScript wrapper node (OPTIONAL fallback if the user has the paid/compiled addon).
## `class_name VideoPlayback` lives in the script server (NOT in ClassDB), so we detect the addon by
## its native class + this script, and instantiate by path.
const GOZEN_PLAYBACK_SCRIPT := "res://addons/gde_gozen/video_playback.gd"
const INTRO_LENGTH := 114.5   # seconds; BACKUP end timer (GoZen also fires video_ended at EOF)

## Mission planet -> level scene (same map the helm/table interactors keep locally).
const MISSION_SCENES := {
	"Earth": "res://scenes/missions/earth/earth.tscn",
	"Mars": "res://scenes/missions/mars/mars.tscn",
	"Venus": "res://scenes/missions/venus/venus.tscn",
}

## Realistic fold title-card text (shared by the video overlay AND the in-engine cutscene, so
## there is one source of truth). Each landing site is a real planetary feature so the card
## names the specific place the ship is dropping onto, with a grounded environmental readout.
##   Earth -> a ruined-city archive dig (Geneva). Mars -> Valles Marineris (a real canyon).
##   Venus -> Maat Mons (a real Venusian volcano - matches the volcano-ascent mission).
const FOLD_TEXT := {
	"Earth": {
		"designation": "SOL III   ·   EARTH",
		"site": "GENEVA ARCHIVE RUINS",
		"readout": "ATMOSPHERE BREATHABLE    GRAVITY 1.0 G    ARCHIVE CORE DETECTED",
	},
	"Mars": {
		"designation": "SOL IV   ·   MARS",
		"site": "VALLES MARINERIS OUTPOST",
		"readout": "THIN CO2 ATMOSPHERE    GRAVITY 0.38 G    DUST STORM INBOUND",
	},
	"Venus": {
		"designation": "SOL II   ·   VENUS",
		"site": "MAAT MONS ASCENT",
		"readout": "SULFURIC OVERCAST    GRAVITY 0.90 G    SURFACE 464 °C",
	},
}

## Observable current beat (mirrors the cutscene's state machine), exposed for tests.
var state: int = State.IDLE

var _running: bool = false
var _cutscene: Node3D = null
var _fade: ColorRect                 # black dissolve that covers the seamless swap
var _pending_path: String = ""       # mission scene, threaded-preloaded during the fold

# Video-fold overlay (present only on the video path; freed on the swap).
var _video: VideoStreamPlayer = null
var _video_ui: Control = null
var _intro_audio: AudioStreamPlayer = null   # (reserved) separate audio for the intro if needed
var _intro_node: Node = null                 # GoZen VideoPlayback node (when that addon is used)
var _intro_overlay: ColorRect = null         # screen-read B&W grade over the GoZen video
var _skipped: bool = false


func _ready() -> void:
	layer = 140                       # above GameState's fade (128) and HUDs
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)   # black, transparent until the hand-off
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)


## Start the Fold to `mission`. `planet_node` is the aimed world - accepted per the design
## API, used only as a hint. Returns true if the fold was launched, false if nothing can play
## it (caller should fall back to a plain fade). Prefers the baked video, else the in-engine
## cutscene.
func begin(mission: String, _planet_node: Node3D = null) -> bool:
	if _running:
		return true
	if not MISSION_SCENES.has(mission):
		return false
	var video_path := _video_for(mission)
	var can_cutscene := _assets_ready()
	if video_path == "" and not can_cutscene:
		return false                  # nothing to play - caller does its plain fade
	var scene := get_tree().current_scene
	if scene == null:
		return false

	# Preload the destination NOW so the swap under the dissolve is instant (no load hitch -
	# the old white screen was partly hiding that stall). The heavy runtime level build still
	# runs on the swap, but the dark hold covers it.
	_pending_path = MISSION_SCENES[mission]
	ResourceLoader.load_threaded_request(_pending_path)

	_running = true
	_skipped = false
	state = State.FOLD
	_freeze_scene()

	if video_path != "":
		_begin_video(mission, video_path)
	else:
		_begin_cutscene(mission, scene)
	return true


## Freeze the walking player so its camera/input can't fight the fold; it is discarded on the
## swap, so no restore is needed. Also hide the "[E] Deploy to X" crosshair prompt (its owner,
## the player, is disabled for the fold).
func _freeze_scene() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player:
		player.visible = false
		player.process_mode = Node.PROCESS_MODE_DISABLED
	var prompt := get_tree().get_first_node_in_group("interact_prompt") as CanvasItem
	if prompt:
		prompt.visible = false


# --- Video-fold path -------------------------------------------------------

## The baked fold clip for a mission, or "" if none is present.
func _video_for(mission: String) -> String:
	var p := FOLD_DIR + mission.to_lower() + ".ogv"
	return p if ResourceLoader.exists(p) else ""


## Play the pre-baked Seedance fold clip full-screen, with the realistic title card over it,
## and hand off to the mission when it finishes (or when skipped).
func _begin_video(mission: String, path: String) -> void:
	var stream := load(path)
	if not (stream is VideoStream):
		_begin_cutscene(mission, get_tree().current_scene)   # corrupt/missing import -> fallback
		return
	_video = VideoStreamPlayer.new()
	_video.stream = stream
	_video.expand = true
	_video.set_anchors_preset(Control.PRESET_FULL_RECT)
	_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_video.audio_track = 0
	add_child(_video)
	_video.finished.connect(_on_video_finished.bind(mission))
	_video.play()

	_build_video_ui(mission)
	_fade.move_to_front()             # keep the dissolve above the video + card
	set_process_unhandled_input(true)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_fold_audio()
	state = State.APPROACH


## Letterbox bars + the realistic title card over the video (mirrors the in-engine cutscene's
## styling), fading up a beat after the clip starts.
func _build_video_ui(mission: String) -> void:
	_video_ui = Control.new()
	_video_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_video_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_video_ui)

	var bar_top := _mk_bar()
	bar_top.anchor_right = 1.0
	bar_top.offset_bottom = 96.0
	_video_ui.add_child(bar_top)
	var bar_bottom := _mk_bar()
	bar_bottom.anchor_right = 1.0
	bar_bottom.anchor_top = 1.0
	bar_bottom.anchor_bottom = 1.0
	bar_bottom.offset_top = -96.0
	_video_ui.add_child(bar_bottom)

	var t: Dictionary = FOLD_TEXT.get(mission, {"site": mission.to_upper(), "designation": mission.to_upper(), "readout": ""})
	var title := Label.new()
	title.text = t["site"]
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.90, 0.96, 1.0))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	title.add_theme_constant_override("outline_size", 6)
	title.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	title.position = Vector2(56, -128)
	title.modulate.a = 0.0
	_video_ui.add_child(title)

	var sub := Label.new()
	sub.text = "%s      %s" % [t["designation"], t["readout"]]
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", Color(0.6, 0.82, 0.98))
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	sub.add_theme_constant_override("outline_size", 4)
	sub.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	sub.position = Vector2(58, -92)
	sub.modulate.a = 0.0
	_video_ui.add_child(sub)

	var skip := Label.new()
	skip.text = "[E] SKIP"
	skip.add_theme_font_size_override("font_size", 14)
	skip.add_theme_color_override("font_color", Color(0.7, 0.75, 0.82))
	skip.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	skip.add_theme_constant_override("outline_size", 4)
	skip.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	skip.position = Vector2(-96, -40)
	_video_ui.add_child(skip)

	var tw := create_tween()
	tw.tween_interval(0.6)
	tw.tween_property(title, "modulate:a", 1.0, 0.6)
	tw.parallel().tween_property(sub, "modulate:a", 1.0, 0.6).set_delay(0.2)


func _mk_bar() -> ColorRect:
	var bar := ColorRect.new()
	bar.color = Color(0, 0, 0, 1)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bar


func _on_video_finished(_mission: String) -> void:
	_finish_to(_pending_path)


## Play the pre-baked LIFT-OFF clip (the ship leaves the atmosphere and docks into the
## mothership where it rests), then dissolve into `next_scene` (the hub). Called by
## landed_ship AFTER its in-engine lift-off climb, so the sequence is: in-engine climb ->
## this video -> hub. Returns false if there is no clip (caller then does its plain
## transition). ONE generic clip, reused on every planet. Skippable.
func play_liftoff(next_scene: String) -> bool:
	if _running:
		return false
	if not ResourceLoader.exists(LIFTOFF_VIDEO):
		return false
	var stream := load(LIFTOFF_VIDEO)
	if not (stream is VideoStream):
		return false
	_running = true
	_skipped = false
	state = State.APPROACH
	_pending_path = next_scene
	ResourceLoader.load_threaded_request(next_scene)
	_video = VideoStreamPlayer.new()
	_video.stream = stream
	_video.expand = true
	_video.set_anchors_preset(Control.PRESET_FULL_RECT)
	_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_video.modulate.a = 0.0
	add_child(_video)
	_video.finished.connect(_on_video_finished.bind(""))
	_video.play()
	create_tween().tween_property(_video, "modulate:a", 1.0, 0.4)   # ease in from the in-engine climb
	_build_liftoff_ui()
	_fade.move_to_front()
	set_process_unhandled_input(true)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_fold_audio()
	return true


## Minimal overlay for the lift-off clip: letterbox bars + a small caption + skip hint.
func _build_liftoff_ui() -> void:
	_video_ui = Control.new()
	_video_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_video_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_video_ui)
	var bar_top := _mk_bar()
	bar_top.anchor_right = 1.0
	bar_top.offset_bottom = 90.0
	_video_ui.add_child(bar_top)
	var bar_bottom := _mk_bar()
	bar_bottom.anchor_right = 1.0
	bar_bottom.anchor_top = 1.0
	bar_bottom.anchor_bottom = 1.0
	bar_bottom.offset_top = -90.0
	_video_ui.add_child(bar_bottom)
	var cap := Label.new()
	cap.text = "RETURNING TO ORBIT"
	cap.add_theme_font_size_override("font_size", 26)
	cap.add_theme_color_override("font_color", Color(0.90, 0.96, 1.0))
	cap.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	cap.add_theme_constant_override("outline_size", 6)
	cap.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	cap.position = Vector2(56, -110)
	_video_ui.add_child(cap)
	var skip := Label.new()
	skip.text = "[E] SKIP"
	skip.add_theme_font_size_override("font_size", 14)
	skip.add_theme_color_override("font_color", Color(0.7, 0.75, 0.82))
	skip.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	skip.add_theme_constant_override("outline_size", 4)
	skip.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	skip.position = Vector2(-96, -40)
	_video_ui.add_child(skip)


## Play the NEW-GAME intro cinematic full-screen (its own baked score + narration), then
## dissolve into `next_scene` (the hub). Skippable with [E]/Esc. Returns false if the clip is
## missing so the caller can just load the hub directly. Unlike the fold, this plays NO overlay
## title and NO fold audio - the graded film carries its own picture and sound.
func play_intro(next_scene: String) -> bool:
	if _running:
		return false
	# Pick a playback path, best-first:
	#   1. FREE frame-pack player (no addon; the shipping path).
	#   2. GoZen mp4 (optional, only if the compiled addon + mp4 are present).
	#   3. EIRTeam.FFmpeg (last-ditch, broken on 4.7).
	# GoZen ships a GDScript wrapper `VideoPlayback` (class_name in addons/gde_gozen); a class_name
	# lives in the script server, NOT ClassDB, so detect it by its NATIVE class + the wrapper script
	# on disk and instantiate by path. EIRTeam is detected by its native FFmpegVideoStream.
	var seq_bin := INTRO_SEQ_PLAYER != "" and (FileAccess.file_exists(INTRO_FRAMES) \
		or FileAccess.file_exists(OS.get_executable_path().get_base_dir().path_join("intro_frames.bin")))
	var use_seq := seq_bin and ResourceLoader.exists(INTRO_SEQ_PLAYER)
	var use_gozen := ClassDB.class_exists("GoZenVideo") and ResourceLoader.exists(GOZEN_PLAYBACK_SCRIPT) and FileAccess.file_exists(INTRO_VIDEO)
	var use_eirteam := ClassDB.class_exists("FFmpegVideoStream") and FileAccess.file_exists(INTRO_VIDEO)
	if not use_seq and not use_gozen and not use_eirteam:
		push_warning("ShipTravel.play_intro: no playable intro (frame pack / GoZen / EIRTeam). Loading hub directly.")
		return false
	_running = true
	_skipped = false
	state = State.APPROACH
	_pending_path = next_scene
	ResourceLoader.load_threaded_request(next_scene)
	# Silence the menu/hub music bed so only the film's baked audio is heard. stop_music() alone
	# isn't enough: AudioManager's scene "director" re-starts the current scene's track every tick,
	# so suppress the director for the duration of the intro (restored in _reset()).
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("set_music_suppressed"):
		am.set_music_suppressed(true)
	elif am and am.has_method("stop_music"):
		am.stop_music()
	if use_seq:
		# FREE core-Godot path: WebP frame pack + baked mix, played in sync by intro_sequence_player.
		var seq: Node = (load(INTRO_SEQ_PLAYER) as Script).new()
		if seq == null or not seq.call("load_pack", INTRO_FRAMES, INTRO_AUDIO):
			if seq != null:
				seq.queue_free()
			_reset()
			return false
		_intro_node = seq
		add_child(seq)
		if seq.has_signal("finished"):
			seq.connect("finished", Callable(self, "_on_video_finished").bind(""))
		seq.call("play")
	elif use_gozen:
		# GoZen GDE: the `VideoPlayback` wrapper node, fed an ABSOLUTE on-disk path (it opens the
		# file through FFmpeg and cannot resolve res://).
		var abs_path := _intro_abs_path()
		if not FileAccess.file_exists(abs_path):
			push_warning("ShipTravel.play_intro: GoZen present but intro mp4 not on disk (%s). Loading hub directly." % abs_path)
			_reset()
			return false
		var vp: Node = (load(GOZEN_PLAYBACK_SCRIPT) as Script).new()
		if vp == null:
			_reset()
			return false
		_intro_node = vp
		if vp is Control:
			var vc := vp as Control
			vc.set_anchors_preset(Control.PRESET_FULL_RECT)
			vc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vp.set("enable_audio", true)        # play the film's baked score + narration track
		vp.set("enable_auto_play", true)    # start as soon as the (threaded) open finishes
		add_child(vp)
		# GoZen DOES signal the end of the film; use it (the INTRO_LENGTH timer stays as a backup).
		if vp.has_signal("video_ended"):
			vp.connect("video_ended", Callable(self, "_on_video_finished").bind(""))
		# set_video_path opens the file (on a worker thread) and, with enable_auto_play, plays it.
		vp.call("set_video_path", abs_path)
		# The mp4 is colour-encoded monochrome; the B&W look (luma + S-curve + vignette) is graded
		# at playback. GoZen renders through its own internal yuv->rgb shader, so grade it as a
		# screen-read overlay drawn on top rather than a material on the video node.
		_add_intro_bw_overlay()
	else:
		# EIRTeam.FFmpeg (fallback only): FFmpegVideoStream on a normal VideoStreamPlayer. Its build
		# targets Godot 4.1 and floods push-constant errors on 4.7 (audio, no picture); kept solely
		# so the game degrades gracefully if only this addon is present.
		var stream: Object = ClassDB.instantiate("FFmpegVideoStream")
		if stream == null:
			_reset(); return false
		stream.set("file", INTRO_VIDEO)
		_video = VideoStreamPlayer.new()
		_video.stream = stream
		_video.expand = true
		_video.set_anchors_preset(Control.PRESET_FULL_RECT)
		_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_video)
		_video.finished.connect(_on_video_finished.bind(""))
		_video.play()
		# VideoStreamPlayer draws the frame as its own TEXTURE, so the canvas_item B&W shader
		# applies directly on the player.
		if ResourceLoader.exists("res://shaders/intro_bw.gdshader"):
			var mat := ShaderMaterial.new()
			mat.shader = load("res://shaders/intro_bw.gdshader")
			_video.material = mat
	# Backup end timer matched to the clip length (GoZen's video_ended is primary; the
	# VideoStreamPlayer path also fires its own `finished`).
	get_tree().create_timer(INTRO_LENGTH).timeout.connect(_on_intro_timeout)
	_build_intro_ui()
	_fade.move_to_front()
	set_process_unhandled_input(true)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	return true


func _on_intro_timeout() -> void:
	if _running and not _skipped and state != State.HANDOFF:
		_finish_to(_pending_path)


## Resolve the intro mp4 to an ABSOLUTE on-disk path for GoZen (it opens files via FFmpeg and
## cannot read res://). In the editor, globalize_path points at the project file. In an EXPORTED
## build res:// lives inside the .pck (not on disk), so the mp4 must ship BESIDE the executable;
## we look there first, then in an `intro/` subfolder, then fall back to globalize_path.
func _intro_abs_path() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path(INTRO_VIDEO)
	var exe_dir := OS.get_executable_path().get_base_dir()
	var beside := exe_dir.path_join(INTRO_VIDEO.get_file())
	if FileAccess.file_exists(beside):
		return beside
	var sub := exe_dir.path_join("intro").path_join(INTRO_VIDEO.get_file())
	if FileAccess.file_exists(sub):
		return sub
	return ProjectSettings.globalize_path(INTRO_VIDEO)


## The B&W cinematic grade for the GoZen path: a full-screen ColorRect whose shader reads the
## already-rendered video from the screen texture (GoZen draws through its own yuv->rgb shader, so
## the grade can't be a material on the video node). No-op if the shader is missing - the mp4's
## content is already monochrome, so the picture still reads B&W without it.
func _add_intro_bw_overlay() -> void:
	if not ResourceLoader.exists("res://shaders/intro_bw_screen.gdshader"):
		return
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/intro_bw_screen.gdshader")
	rect.material = mat
	add_child(rect)                 # added after the video node -> composites/reads it on top
	_intro_overlay = rect


## Minimal overlay for the intro: just a small skip hint (the film is already graded/letterboxed
## and self-titled, so no bars or title card).
func _build_intro_ui() -> void:
	_video_ui = Control.new()
	_video_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_video_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_video_ui)
	var skip := Label.new()
	skip.text = "[E] SKIP"
	skip.add_theme_font_size_override("font_size", 14)
	skip.add_theme_color_override("font_color", Color(0.7, 0.75, 0.82))
	skip.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	skip.add_theme_constant_override("outline_size", 4)
	skip.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	skip.position = Vector2(-96, -40)
	_video_ui.add_child(skip)


# --- In-engine cutscene path (fallback) ------------------------------------

func _begin_cutscene(mission: String, scene: Node) -> void:
	var packed := load(CUTSCENE_SCENE)
	if not (packed is PackedScene):
		# No fold at all - reveal straight into the mission via the dissolve.
		_on_handoff(mission)
		return
	_cutscene = (packed as PackedScene).instantiate() as Node3D
	if _cutscene == null:
		_on_handoff(mission)
		return
	scene.add_child(_cutscene)
	if _cutscene.has_signal("state_changed"):
		_cutscene.state_changed.connect(func(s: int) -> void: state = s)
	if _cutscene.has_signal("handoff"):
		_cutscene.handoff.connect(_on_handoff)
	if _cutscene.has_method("play"):
		_cutscene.play(mission)


## Both the ship model and the cutscene scene must load for the in-engine fold.
func _assets_ready() -> bool:
	return ResourceLoader.exists(SHIP_GLB) and ResourceLoader.exists(CUTSCENE_SCENE)


# --- Seamless hand-off (shared) --------------------------------------------

## Fold done (in-engine cutscene path): resolve the mission scene and finish into it.
func _on_handoff(mission: String) -> void:
	_finish_to(MISSION_SCENES.get(mission, ""))


## Dissolve to black, swap to the preloaded `path` under the dark (covering the level build),
## then dissolve back up as the destination's own cinematic plays - no white flash, no visible
## cut. Shared by the fold (-> mission + its landing) and the lift-off (-> hub).
func _finish_to(path: String) -> void:
	if state == State.HANDOFF:
		return
	state = State.HANDOFF
	if path == "":
		_reset()
		return
	set_process_unhandled_input(false)
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.35)
	tw.tween_callback(func() -> void: _swap(path))
	tw.tween_interval(0.55)           # hold black over the runtime level build
	tw.tween_property(_fade, "color:a", 0.0, 0.7)
	tw.tween_callback(_reset)


func _swap(path: String) -> void:
	# Free the video overlay before the scene change (the in-engine cutscene is freed with the
	# old scene automatically).
	if _video and is_instance_valid(_video):
		_video.queue_free()
	_video = null
	if _video_ui and is_instance_valid(_video_ui):
		_video_ui.queue_free()
	_video_ui = null
	if _intro_audio and is_instance_valid(_intro_audio):
		_intro_audio.queue_free()
	_intro_audio = null
	if _intro_overlay and is_instance_valid(_intro_overlay):
		_intro_overlay.queue_free()
	_intro_overlay = null
	if _intro_node and is_instance_valid(_intro_node):
		# GoZen's VideoPlayback tears down its FFmpeg handles + audio bus in close()/_exit_tree.
		if _intro_node.has_method("close"):
			_intro_node.call("close")
		_intro_node.queue_free()
	_intro_node = null
	_cutscene = null
	_stop_audio()
	var packed: PackedScene = null
	if _pending_path == path and ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		packed = ResourceLoader.load_threaded_get(path) as PackedScene   # blocks only if not finished
	if packed != null:
		get_tree().change_scene_to_packed(packed)
	else:
		get_tree().change_scene_to_file(path)
	_pending_path = ""
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _reset() -> void:
	_running = false
	state = State.IDLE
	_skipped = false
	# Let the scene director resume normal music (the destination scene picks its own track).
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("set_music_suppressed"):
		am.set_music_suppressed(false)


# --- Fold audio (video path; the in-engine cutscene runs its own) -----------

func _fold_audio() -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am == null:
		return
	if am.has_method("play_sfx"):
		am.play_sfx("warp")
	if am.has_method("play_music"):
		am.play_music("travel")


func _stop_audio() -> void:
	pass


func _unhandled_input(event: InputEvent) -> void:
	if not _running or _skipped or state == State.HANDOFF:
		return
	# Only the video path listens here (the in-engine cutscene handles its own skip).
	if _video == null and _intro_node == null:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_skipped = true
		_finish_to(_pending_path)

extends Control
## FREE, core-Godot player for the New-Character intro cinematic - no video addon, no purchase.
##
## Godot 4.7's core VideoStreamPlayer only decodes Theora, which macroblocks this film, and the one
## mp4 addon (GDE GoZen) is paid/compile-your-own. So the film ships as a compact WebP frame pack
## (tools/pack_intro_frames.py -> intro_frames.bin) plus its baked mix (intro_audio.ogg), and this
## node plays them in sync entirely from GDScript. The AUDIO is the clock: each frame the current
## audio position picks the frame to show, so picture and sound never drift. A background thread
## streams+decodes frames a couple of seconds ahead into a small ring buffer so playback is smooth
## and memory stays bounded. Because frames are shown through a real TextureRect, the existing
## shaders/intro_bw.gdshader (canvas_item, samples TEXTURE) applies directly - the B&W look is free.
##
## Pack format (little-endian) - see tools/pack_intro_frames.py:
##   magic "GZIF" | u32 version | u32 count | u32 fps_milli | u32 width | u32 height
##   | count x u32 blob_length | WebP blobs back-to-back.  Frame data starts at 24 + count*4.

signal finished

const _MAGIC := "GZIF"
const _LOOKAHEAD := 48        # frames to keep decoded ahead of playback (~2s @ 24fps)
const _HEADER := 24           # bytes before the length table

var _pack_path := ""
var _count := 0
var _fps := 24.0
var _size := Vector2i.ZERO
var _data_start := 0
var _offsets: PackedInt64Array = PackedInt64Array()
var _lengths: PackedInt32Array = PackedInt32Array()

var _rect: TextureRect = null
var _tex: ImageTexture = null
var _audio: AudioStreamPlayer = null

var _thread: Thread = null
var _mutex: Mutex = Mutex.new()
var _buf: Dictionary = {}     # frame_index -> Image (guarded by _mutex)
var _want := 0                # frame the main thread currently needs (loader stays ahead of this)
var _cur := -1                # frame currently on screen
var _stop := false
var _started := false
var _ended := false


## Resolve a pack/audio resource to something readable in BOTH editor (res://) and exported builds.
## res:// non-resource files (the .bin) must be added to the export preset's non-resource filters;
## as a fallback we also look beside the executable. The .ogg is a normal imported resource.
static func _resolve(path: String) -> String:
	if FileAccess.file_exists(path):
		return path
	var beside := OS.get_executable_path().get_base_dir().path_join(path.get_file())
	if FileAccess.file_exists(beside):
		return beside
	return path


## Read the pack header + open the audio. Returns false (and plays nothing) if the pack is missing
## or malformed, so the caller can fall back to loading the hub directly.
func load_pack(bin_path: String, audio_path: String) -> bool:
	_pack_path = _resolve(bin_path)
	var fa := FileAccess.open(_pack_path, FileAccess.READ)
	if fa == null:
		push_warning("IntroSequencePlayer: cannot open frame pack %s" % _pack_path)
		return false
	if fa.get_buffer(4).get_string_from_ascii() != _MAGIC:
		push_warning("IntroSequencePlayer: bad magic in %s" % _pack_path)
		return false
	var _version := fa.get_32()
	_count = fa.get_32()
	_fps = float(fa.get_32()) / 1000.0
	_size = Vector2i(fa.get_32(), fa.get_32())
	if _count <= 0 or _fps <= 0.0:
		push_warning("IntroSequencePlayer: empty/invalid pack")
		return false
	_data_start = _HEADER + _count * 4
	_offsets.resize(_count)
	_lengths.resize(_count)
	var running := _data_start
	for i in _count:
		var ln := fa.get_32()
		_lengths[i] = ln
		_offsets[i] = running
		running += ln
	fa = null

	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect = TextureRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists("res://shaders/intro_bw.gdshader"):
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/intro_bw.gdshader")
		_rect.material = mat
	add_child(_rect)

	_audio = AudioStreamPlayer.new()
	var apath := _resolve(audio_path)
	var stream: Resource = load(apath) if ResourceLoader.exists(apath) else null
	if stream == null and FileAccess.file_exists(apath):
		# Beside-exe .ogg (not imported): load it as a raw Ogg stream.
		stream = AudioStreamOggVorbis.load_from_file(apath)
	if stream is AudioStream:
		_audio.stream = stream
	_audio.finished.connect(_on_audio_finished)
	add_child(_audio)
	return true


func play() -> void:
	if _started or _count == 0:
		return
	_started = true
	_stop = false
	_thread = Thread.new()
	_thread.start(_loader)
	if _audio and _audio.stream != null:
		_audio.play()
	set_process(true)


func _process(_delta: float) -> void:
	if not _started or _ended:
		return
	# The audio is the clock. If there is no audio track, fall back to a wall-clock estimate.
	var pos := _audio.get_playback_position() if (_audio and _audio.playing) else 0.0
	var idx := int(pos * _fps)
	if idx < 0:
		idx = 0
	if idx >= _count:
		idx = _count - 1
	_want = idx
	if idx != _cur:
		_mutex.lock()
		var img: Image = _buf.get(idx, null)
		_mutex.unlock()
		if img != null:
			if _tex == null:
				_tex = ImageTexture.create_from_image(img)
				_rect.texture = _tex
			elif img.get_size() == _size:
				_tex.update(img)
			else:
				_tex.set_image(img)
			_cur = idx


## Background: stream+decode frames, staying ~_LOOKAHEAD ahead of _want; drop frames already shown.
func _loader() -> void:
	var fa := FileAccess.open(_pack_path, FileAccess.READ)
	if fa == null:
		return
	var i := 0
	while i < _count and not _stop:
		if i > _want + _LOOKAHEAD:
			OS.delay_msec(4)
			continue
		fa.seek(_offsets[i])
		var blob := fa.get_buffer(_lengths[i])
		var img := Image.new()
		if img.load_webp_from_buffer(blob) == OK:
			if img.get_format() != Image.FORMAT_RGB8:
				img.convert(Image.FORMAT_RGB8)
			_mutex.lock()
			_buf[i] = img
			for k in _buf.keys():
				if k < _want - 2:
					_buf.erase(k)
			_mutex.unlock()
		i += 1
	fa = null


func _on_audio_finished() -> void:
	if _ended:
		return
	_ended = true
	finished.emit()


## Stop playback and join the loader thread. Safe to call more than once.
func stop() -> void:
	_stop = true
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null
	if _audio != null and is_instance_valid(_audio):
		_audio.stop()
	set_process(false)


func close() -> void:      # alias so callers that expect GoZen's close() work too
	stop()


func _exit_tree() -> void:
	stop()

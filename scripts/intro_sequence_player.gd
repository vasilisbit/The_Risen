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

var _threads: Array[Thread] = []   # several decode workers so decode keeps up at 24fps under load
var _next := 0                # next frame index a worker will claim (guarded by _mutex)
var _mutex: Mutex = Mutex.new()
var _buf: Dictionary = {}     # frame_index -> Image (guarded by _mutex)
var _want := 0                # frame the main thread currently needs (workers stay ahead of this)
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
	# Black backing behind the video (only visible for the first frame before the texture exists;
	# with the cover fill below it is otherwise hidden - it just prevents any menu flash at t=0).
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_rect = TextureRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# COVER the whole window (fills any non-16:9 window edge-to-edge, keeping aspect so nothing is
	# distorted - it crops a sliver off the long side instead of showing bars).
	_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists("res://shaders/intro_bw.gdshader"):
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/intro_bw.gdshader")
		_rect.material = mat
	add_child(_rect)

	_audio = AudioStreamPlayer.new()
	var apath := _resolve(audio_path)
	var stream: AudioStream = null
	# In the EDITOR, read the .ogg straight off disk rather than load()ing Godot's IMPORTED copy:
	# the import cache can lag behind a regenerated .ogg, and playing that stale copy (a differently
	# timed VO) desyncs the film from the mp4 even though the on-disk file is correct. Reading the
	# real bytes guarantees the game plays exactly what's on disk. In an exported build the imported
	# resource is rebuilt fresh at export time (and the raw .ogg may be absent), so load() is right.
	var disk := ProjectSettings.globalize_path(apath) if apath.begins_with("res://") else apath
	if OS.has_feature("editor") and apath.get_extension().to_lower() == "ogg" and FileAccess.file_exists(disk):
		stream = AudioStreamOggVorbis.load_from_file(disk)
	if stream == null and ResourceLoader.exists(apath):
		stream = load(apath) as AudioStream
	if stream == null and FileAccess.file_exists(disk):
		stream = AudioStreamOggVorbis.load_from_file(disk)
	if stream != null:
		_audio.stream = stream
	_audio.finished.connect(_on_audio_finished)
	add_child(_audio)
	return true


func play() -> void:
	if _started or _count == 0:
		return
	_started = true
	_stop = false
	# Several decode workers: a single thread can't always sustain 24fps WebP decode while the hub
	# scene is being threaded-preloaded in parallel, which would let the picture lag behind the
	# audio. A small pool keeps decode well ahead of playback even under that load.
	var n := clampi(OS.get_processor_count() / 2, 2, 4)
	for _w in n:
		var t := Thread.new()
		t.start(_worker)
		_threads.append(t)
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
		if img == null:
			# Exact frame not decoded yet - show the newest decoded frame at or before it, so a
			# brief decode stall never freezes the picture on a far-behind frame.
			var best := -1
			for k in _buf.keys():
				if k <= idx and k > best:
					best = k
			if best >= 0:
				img = _buf[best]
				idx = best
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


## Background worker (several run in parallel): claim the next frame index, decode it, and store it,
## staying within _LOOKAHEAD of playback and skipping frames already behind _want.
func _worker() -> void:
	var fa := FileAccess.open(_pack_path, FileAccess.READ)
	if fa == null:
		return
	while not _stop:
		_mutex.lock()
		var i := _next
		if i < _want:              # decode fell behind playback - jump forward to catch up
			i = _want
		if i >= _count:
			_mutex.unlock()
			break
		if i > _want + _LOOKAHEAD:  # far enough ahead; wait for playback to advance
			_mutex.unlock()
			OS.delay_msec(3)
			continue
		_next = i + 1
		_mutex.unlock()
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
	fa = null


func _on_audio_finished() -> void:
	if _ended:
		return
	_ended = true
	finished.emit()


## Stop playback and join the loader thread. Safe to call more than once.
func stop() -> void:
	_stop = true
	for t in _threads:
		if t != null and t.is_started():
			t.wait_to_finish()
	_threads.clear()
	if _audio != null and is_instance_valid(_audio):
		_audio.stop()
	set_process(false)


func close() -> void:      # alias so callers that expect GoZen's close() work too
	stop()


func _exit_tree() -> void:
	stop()

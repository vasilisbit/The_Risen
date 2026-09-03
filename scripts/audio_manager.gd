extends Node

## AudioManager autoload (T-0034). Owns the bus layout, the music director and
## the shared SFX synth.
##
## GDD §5.3 specifies Suno AI music and Freesound SFX. Every track and effect is
## also SYNTHESISED IN CODE as a fallback, so the game is playable with no audio
## files present. In practice the real audio is generated on fal.ai (Stable Audio
## music + ElevenLabs SFX, tools/gen_audio.py) and lives under
## assets/generated/audio/{music,sfx}; _build_music / _sfx / _load_*_file prefer a
## file over the synth loop, so a present clip wins and a missing one degrades to
## the synth. As of 2026-08-28 every director track (hub/earth_combat/mars_combat/
## boss/travel) and the gameplay SFX ship as generated files. The system is real -
## buses, crossfades, attenuation, volume persistence - regardless of the source.
##
## Music is picked from world state rather than pushed by each scene: the
## director decides once a second. Each planet has ONE continuous battle theme
## that plays for the whole mission (it must not drop back to the calm hub bed
## just because no enemy is momentarily nearby); a living boss anywhere overrides
## it with the boss track; the hub and main menu use the calm ambient bed. That
## keeps the rules in one place instead of scattering play_music() calls through
## every mission script.

signal track_changed(track: String)

const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"

const MUSIC_RATE := 22050          # plenty for pads and drums, half the data
const SFX_RATE := 22050
const LOOP_SECONDS := 8.0          # every music loop is one 8 s phrase
const CROSSFADE := 2.0             # s between tracks
const MUSIC_DB := -12.0            # music sits under the effects
const DIRECTOR_INTERVAL := 1.0     # s between track decisions

## Tracks, chosen by the director. "silent" is used before anything is playing.
const TRACK_HUB := "hub"
const TRACK_COMBAT_EARTH := "earth_combat"
const TRACK_COMBAT_MARS := "mars_combat"
const TRACK_COMBAT_VENUS := "venus_combat"
const TRACK_BOSS := "boss"               # generic boss cue (fallback off-planet)
const TRACK_BOSS_EARTH := "boss_earth"   # per-boss themes: Shielded Brute / Teleporting
const TRACK_BOSS_MARS := "boss_mars"     # Phantom / Ember Tyrant. File-backed (Suno + Lyria);
const TRACK_BOSS_VENUS := "boss_venus"   # each falls back to the generic boss synth.
const TRACK_TRAVEL := "travel"           # the Fold cutscene stinger (file-only)

## Real audio generated on fal.ai (ElevenLabs SFX + Stable Audio music). When a file
## exists it is used in place of the code-synthesised fallback, so the game degrades
## gracefully if a clip is missing. See tools/gen_audio.py.
const SFX_FILE := "res://assets/generated/audio/sfx/%s.mp3"
const MUSIC_FILE := "res://assets/generated/audio/music/%s.mp3"
const LOOP_SFX := ["engine", "wind"]     # SFX streams that should loop

var current_track: String = ""

## Looping planet/hub ambience bed (a generated wind/room tone), swapped by scene.
var _ambient: AudioStreamPlayer
var _ambient_id: String = ""

var _players: Array[AudioStreamPlayer] = []
var _active: int = 0
var _music_cache: Dictionary = {}
var _sfx_cache: Dictionary = {}
var _director_timer: float = 0.0
var _fade: Tween
## Music synthesis runs on a worker thread - the boss loop alone takes ~280 ms
## to generate, and it would otherwise be built the instant a boss spawns,
## hitching the exact moment the fight starts. SFX are 1-2 ms, so those stay
## lazy on the main thread.
var _music_mutex := Mutex.new()
var _warm_task: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = MUSIC_BUS
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)
	_ambient = AudioStreamPlayer.new()
	_ambient.bus = SFX_BUS
	_ambient.volume_db = -14.0
	add_child(_ambient)
	_load_volumes()
	_warm_task = WorkerThreadPool.add_task(_warm_music, true, "Synthesise music loops")


func _exit_tree() -> void:
	if _warm_task != -1:
		WorkerThreadPool.wait_for_task_completion(_warm_task)


## Build every loop up front, off the main thread. Until a track lands in the
## cache the director simply retries a second later, so nothing stalls.
func _warm_music() -> void:
	for track in [TRACK_HUB, TRACK_COMBAT_EARTH, TRACK_COMBAT_MARS, TRACK_COMBAT_VENUS, TRACK_BOSS, TRACK_BOSS_EARTH, TRACK_BOSS_MARS, TRACK_BOSS_VENUS, TRACK_TRAVEL]:
		var wav := _build_music(track)
		if wav == null:
			continue
		_music_mutex.lock()
		_music_cache[track] = wav
		_music_mutex.unlock()


func _process(delta: float) -> void:
	_director_timer -= delta
	if _director_timer <= 0.0:
		_director_timer = DIRECTOR_INTERVAL
		var wanted := _wanted_track()
		if wanted != "" and wanted != current_track:
			play_music(wanted)
		_update_ambient()


## Swap the looping ambience bed by scene: alien wind on the planets, nothing in the hub
## or menu (the calm music carries those). Only plays if a generated clip is present.
func _update_ambient() -> void:
	var tree := get_tree()
	var scene := String(tree.current_scene.name) if tree and tree.current_scene else ""
	var wanted := "wind" if scene in ["Earth", "Mars", "Venus"] else ""
	if wanted == _ambient_id:
		return
	_ambient_id = wanted
	if wanted == "":
		_ambient.stop()
		return
	var stream := _load_sfx_file(wanted)
	if stream:
		_ambient.stream = stream
		_ambient.play()
	else:
		_ambient.stop()


# --- buses ------------------------------------------------------------------

## Master / Music / SFX, created in code so there is no bus-layout resource to
## keep in sync. Idempotent - safe if the layout already defines them.
func _ensure_buses() -> void:
	for bus_name in [MUSIC_BUS, SFX_BUS]:
		if AudioServer.get_bus_index(bus_name) != -1:
			continue
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")


## Linear 0..1 volume for a bus name ("Master", "Music", "SFX").
func set_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	var v := clampf(linear, 0.0, 1.0)
	# Mute outright at zero: linear_to_db(0) is -inf and some drivers dislike it.
	AudioServer.set_bus_mute(idx, v <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.001)))
	# Persist to the global options file (GameSettings), not the per-slot save -
	# volume is a machine preference, not game progress.
	var gs := get_node_or_null("/root/GameSettings")
	if gs and gs.has_method("set_audio_volume"):
		gs.set_audio_volume(bus_name, v)


func get_volume(bus_name: String) -> float:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return 1.0
	if AudioServer.is_bus_mute(idx):
		return 0.0
	return clampf(db_to_linear(AudioServer.get_bus_volume_db(idx)), 0.0, 1.0)


func _load_volumes() -> void:
	# Global options file (GameSettings) is the source of truth for volumes.
	var gs := get_node_or_null("/root/GameSettings")
	for bus_name in ["Master", MUSIC_BUS, SFX_BUS]:
		var idx := AudioServer.get_bus_index(bus_name)
		if idx == -1:
			continue
		var v := float(gs.audio_volume(bus_name)) if gs else 1.0
		AudioServer.set_bus_mute(idx, v <= 0.001)
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.001)))


# --- music director ---------------------------------------------------------

## What should be playing right now, from what is actually in the world.
## Public so the transition rules can be asserted directly in tests.
func _wanted_track() -> String:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return ""
	var scene := String(tree.current_scene.name)
	if scene == "MainMenu":
		return TRACK_HUB          # the menu shares the calm ambient bed
	var player := tree.get_first_node_in_group("player")
	if player == null:
		return TRACK_HUB

	# A living boss anywhere in the level takes priority over everything. Each planet has its
	# own boss theme; off-planet falls back to the generic boss cue.
	for b in tree.get_nodes_in_group("boss"):
		if not is_instance_valid(b):
			continue
		match scene:
			"Earth":
				return TRACK_BOSS_EARTH
			"Mars":
				return TRACK_BOSS_MARS
			"Venus":
				return TRACK_BOSS_VENUS
		return TRACK_BOSS

	# On a planet the world's battle theme plays for the WHOLE mission - continuously,
	# not gated on an enemy being within range (that made the music cut out to the hub
	# bed whenever you cleared the immediate area). Boss above still overrides it.
	match scene:
		"Earth":
			return TRACK_COMBAT_EARTH
		"Mars":
			return TRACK_COMBAT_MARS
		"Venus":
			return TRACK_COMBAT_VENUS
	return TRACK_HUB


## Crossfade to `track`. Public so scenes can force a cue if they ever need to.
func play_music(track: String) -> void:
	if track == current_track:
		return
	var stream := _music(track)
	if stream == null:
		return
	current_track = track
	var incoming := _players[1 - _active]
	var outgoing := _players[_active]
	_active = 1 - _active

	incoming.stream = stream
	incoming.volume_db = -80.0
	incoming.play()
	if _fade and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.set_parallel(true)
	_fade.tween_property(incoming, "volume_db", MUSIC_DB, CROSSFADE)
	_fade.tween_property(outgoing, "volume_db", -80.0, CROSSFADE)
	_fade.chain().tween_callback(outgoing.stop)
	track_changed.emit(track)


func stop_music() -> void:
	current_track = ""
	for p in _players:
		p.stop()


# --- SFX --------------------------------------------------------------------

## Fire a positional effect. Falls back to non-positional if `at` is omitted,
## which is what the UI sounds use.
func play_sfx(id: String, at: Variant = null, pitch_jitter: float = 0.08) -> void:
	var stream := _sfx(id)
	if stream == null:
		return
	var host := get_tree().current_scene
	if host == null:
		host = self
	if at is Vector3:
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = SFX_BUS
		p3.stream = stream
		p3.unit_size = 12.0
		p3.max_distance = 70.0
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
		host.add_child(p3)
		p3.global_position = at
		p3.finished.connect(p3.queue_free)
		p3.play()
	else:
		var p2 := AudioStreamPlayer.new()
		p2.bus = SFX_BUS
		p2.stream = stream
		p2.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
		add_child(p2)
		p2.finished.connect(p2.queue_free)
		p2.play()


# --- synthesis --------------------------------------------------------------

## Cached loop for a track, or null if the warm-up thread has not reached it
## yet. Callers treat null as "not now" rather than blocking.
func _music(track: String) -> AudioStream:
	_music_mutex.lock()
	var cached: Variant = _music_cache.get(track)
	_music_mutex.unlock()
	return cached as AudioStream if cached != null else null


func _build_music(track: String) -> AudioStream:
	# Prefer a generated music file (Stable Audio); fall back to the synth loop.
	var file := _load_music_file(track)
	if file != null:
		return file
	var wav: AudioStreamWAV = null
	match track:
		TRACK_HUB:
			wav = _make_ambient()
		TRACK_COMBAT_EARTH:
			wav = _make_combat(120.0, 55.0, 0.35)
		TRACK_COMBAT_MARS:
			wav = _make_combat(140.0, 41.2, 0.55)
		TRACK_COMBAT_VENUS:
			wav = _make_combat(150.0, 36.7, 0.7)   # faster + lower + grittier: Venus is hell
		TRACK_BOSS, TRACK_BOSS_EARTH, TRACK_BOSS_MARS, TRACK_BOSS_VENUS:
			wav = _make_boss()
	if wav != null:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = wav.data.size() / 2
	return wav


## Load a generated music track as a looping stream, or null if there is no file.
func _load_music_file(track: String) -> AudioStream:
	var path := MUSIC_FILE % track
	if not ResourceLoader.exists(path):
		return null
	var s := load(path)
	if s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = true
	elif s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	return s as AudioStream


## Load a generated SFX file, looping the ids in LOOP_SFX (engine/wind), or null if none.
func _load_sfx_file(id: String) -> AudioStream:
	var path := SFX_FILE % id
	if not ResourceLoader.exists(path):
		return null
	var s := load(path)
	if id in LOOP_SFX and s is AudioStreamMP3:
		s = (s as AudioStreamMP3).duplicate()   # own copy so the loop flag is local
		(s as AudioStreamMP3).loop = true
	return s as AudioStream


## True once every music loop has been synthesised. Exposed for tests.
func music_ready() -> bool:
	_music_mutex.lock()
	var n := _music_cache.size()
	_music_mutex.unlock()
	return n >= 4


## Calm pad: a stack of fifths with a slow swell. Every frequency completes a
## whole number of cycles across the loop, so the seam is inaudible.
func _make_ambient() -> AudioStreamWAV:
	var n := int(MUSIC_RATE * LOOP_SECONDS)
	var buf := PackedByteArray()
	buf.resize(n * 2)
	var partials := [110.0, 165.0, 220.0, 330.0]
	var gains := [0.5, 0.32, 0.22, 0.10]
	for i in n:
		var t := float(i) / MUSIC_RATE
		var swell := 0.55 + 0.45 * sin(TAU * t / LOOP_SECONDS * 2.0)
		var s := 0.0
		for k in partials.size():
			s += sin(TAU * float(partials[k]) * t) * float(gains[k])
		s *= swell * 0.22
		buf.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	return _wav(buf, MUSIC_RATE)


## Driving loop: a pulsing bass note plus kick and hat on a grid.
func _make_combat(bpm: float, root: float, grit: float) -> AudioStreamWAV:
	var n := int(MUSIC_RATE * LOOP_SECONDS)
	var buf := PackedByteArray()
	buf.resize(n * 2)
	var beat := 60.0 / bpm
	for i in n:
		var t := float(i) / MUSIC_RATE
		var beat_pos := fmod(t, beat) / beat
		var beat_index := int(t / beat)
		var s := 0.0
		# Bass: eighth-note pulse, alternating root and fifth.
		var bass_freq: float = root if beat_index % 4 < 2 else root * 1.5
		var pulse := pow(1.0 - fmod(t, beat * 0.5) / (beat * 0.5), 2.0)
		var bass := sin(TAU * bass_freq * t)
		s += lerpf(bass, signf(bass), grit) * pulse * 0.45
		# Kick on every beat.
		if beat_pos < 0.18:
			var e := 1.0 - beat_pos / 0.18
			s += sin(TAU * lerpf(120.0, 45.0, 1.0 - e) * t) * e * e * 0.5
		# Hat on the off-beat.
		if beat_pos > 0.5 and beat_pos < 0.58:
			s += randf_range(-1.0, 1.0) * (1.0 - (beat_pos - 0.5) / 0.08) * 0.10
		buf.encode_s16(i * 2, int(clampf(s * 0.5, -1.0, 1.0) * 32767.0))
	return _wav(buf, MUSIC_RATE)


## Boss: a low drone with a rising fifth and slow war-drum hits.
func _make_boss() -> AudioStreamWAV:
	var n := int(MUSIC_RATE * LOOP_SECONDS)
	var buf := PackedByteArray()
	buf.resize(n * 2)
	for i in n:
		var t := float(i) / MUSIC_RATE
		var s := 0.0
		s += sin(TAU * 55.0 * t) * 0.40
		s += sin(TAU * 82.5 * t) * 0.22 * (0.5 + 0.5 * sin(TAU * t / LOOP_SECONDS))
		s += sin(TAU * 110.0 * t) * 0.12
		# Choir-ish shimmer, detuned so it beats slowly.
		s += sin(TAU * 440.5 * t) * 0.05 + sin(TAU * 441.5 * t) * 0.05
		# War drum every second.
		var d := fmod(t, 1.0)
		if d < 0.25:
			var e := 1.0 - d / 0.25
			s += sin(TAU * lerpf(90.0, 38.0, 1.0 - e) * t) * e * e * 0.55
		buf.encode_s16(i * 2, int(clampf(s * 0.55, -1.0, 1.0) * 32767.0))
	return _wav(buf, MUSIC_RATE)


func _sfx(id: String) -> AudioStream:
	if _sfx_cache.has(id):
		return _sfx_cache[id]
	# Prefer a generated SFX file (ElevenLabs); fall back to the synth effect.
	var file := _load_sfx_file(id)
	if file != null:
		_sfx_cache[id] = file
		return file
	var wav: AudioStreamWAV = null
	match id:
		# Weapons: same shape, different weight and pitch.
		"auto_rifle":
			wav = _make_shot(0.10, 900.0, 0.55)
		"shotgun":
			wav = _make_shot(0.26, 260.0, 1.0)
		"sniper":
			wav = _make_shot(0.34, 520.0, 0.9)
		"hand_cannon":
			wav = _make_shot(0.20, 380.0, 0.85)
		"explosion":
			wav = _make_explosion()
		"footstep":
			wav = _make_footstep()
		"enemy_hit":
			wav = _make_thud(0.09, 320.0)
		"player_hit":
			wav = _make_thud(0.16, 150.0)
		"ui_hover":
			wav = _make_beep(660.0, 0.05)
		"ui_click":
			wav = _make_beep(990.0, 0.09)
	if wav != null:
		_sfx_cache[id] = wav
	return wav


## Gunshot: a noise crack over a pitched-down body thump.
func _make_shot(dur: float, tone: float, body: float) -> AudioStreamWAV:
	var n := int(SFX_RATE * dur)
	var buf := PackedByteArray()
	buf.resize(n * 2)
	var prev := 0.0
	for i in n:
		var t := float(i) / SFX_RATE
		var e := pow(1.0 - float(i) / n, 3.0)
		var noise := randf_range(-1.0, 1.0)
		prev = lerpf(prev, noise, 0.55)          # cheap low-pass: less hiss
		var s := prev * e * 0.7
		s += sin(TAU * lerpf(tone, tone * 0.25, 1.0 - e) * t) * e * body * 0.5
		buf.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	return _wav(buf, SFX_RATE)


func _make_explosion() -> AudioStreamWAV:
	var n := int(SFX_RATE * 0.9)
	var buf := PackedByteArray()
	buf.resize(n * 2)
	var prev := 0.0
	for i in n:
		var t := float(i) / SFX_RATE
		var e := pow(1.0 - float(i) / n, 2.2)
		prev = lerpf(prev, randf_range(-1.0, 1.0), 0.22)     # heavier low-pass
		var s := prev * e * 0.85
		s += sin(TAU * lerpf(70.0, 26.0, t / 0.9) * t) * e * 0.55
		buf.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	return _wav(buf, SFX_RATE)


func _make_footstep() -> AudioStreamWAV:
	var n := int(SFX_RATE * 0.07)
	var buf := PackedByteArray()
	buf.resize(n * 2)
	var prev := 0.0
	for i in n:
		var e := pow(1.0 - float(i) / n, 4.0)
		prev = lerpf(prev, randf_range(-1.0, 1.0), 0.35)
		buf.encode_s16(i * 2, int(clampf(prev * e * 0.5, -1.0, 1.0) * 32767.0))
	return _wav(buf, SFX_RATE)


func _make_thud(dur: float, freq: float) -> AudioStreamWAV:
	var n := int(SFX_RATE * dur)
	var buf := PackedByteArray()
	buf.resize(n * 2)
	for i in n:
		var t := float(i) / SFX_RATE
		var e := pow(1.0 - float(i) / n, 3.0)
		var s := sin(TAU * lerpf(freq, freq * 0.4, 1.0 - e) * t) * e * 0.6
		s += randf_range(-1.0, 1.0) * e * e * 0.25
		buf.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	return _wav(buf, SFX_RATE)


## Shared with the older per-script beeps (exploder, vendor, weak point); those
## can drop their private copies and call play_sfx() when convenient.
func _make_beep(freq: float, dur: float) -> AudioStreamWAV:
	var n := int(SFX_RATE * dur)
	var buf := PackedByteArray()
	buf.resize(n * 2)
	for i in n:
		var t := float(i) / SFX_RATE
		var e := 1.0 - float(i) / n
		buf.encode_s16(i * 2, int(clampf(sin(TAU * freq * t) * e * 0.5, -1.0, 1.0) * 32767.0))
	return _wav(buf, SFX_RATE)


func _wav(buf: PackedByteArray, rate: int) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = buf
	return wav

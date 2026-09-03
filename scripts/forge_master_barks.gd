extends Node3D
## Forge Master idle barks (T-0029 follow-on). Added as a child of the hub-bay clerk
## (hub_structure._build_vendor_stall) ONLY - not the vendor-screen backdrop - so the
## armourer occasionally says a random line when the player is standing near him in the
## hub. Positional (AudioStreamPlayer3D on the SFX bus) so it comes from his direction.
##
## MUST be a Node3D (not a plain Node): the voice is a Node3D child, and a plain-Node
## parent would leave it un-parented in the spatial tree, emitting from the world origin
## (right by the hologram table) instead of the Forge Master - the reported bug.
##
## Default (pausable) process_mode: while the shop screen is open the tree is paused, so
## he goes quiet then - the greeting/interaction lines cover that context instead.

const NEAR := 9.0                  # m: player must be at least this close to bark
const MIN_GAP := 14.0              # s: min quiet time between barks
const MAX_GAP := 26.0              # s: max quiet time between barks
const VOICE_PATH := "res://assets/generated/audio/vendor/%s.mp3"
const HEAD_Y := 1.6                # emit from ~head height

var _player: Node3D
var _voice: AudioStreamPlayer3D
var _lines: AudioStreamRandomizer
var _cooldown: float = 6.0         # first possible bark shortly after entering the hub


func _ready() -> void:
	_lines = AudioStreamRandomizer.new()   # default playback_mode is random-no-repeat
	_lines.random_pitch = 1.04
	_lines.random_volume_offset_db = 1.5
	for id in ["bark_1", "bark_2", "bark_3"]:
		var path := VOICE_PATH % id
		if ResourceLoader.exists(path):
			var s := load(path)
			if s != null:
				_lines.add_stream(-1, s)
	if _lines.get_streams_count() == 0:
		set_process(false)             # nothing to say - stay silent
		return
	_voice = AudioStreamPlayer3D.new()
	_voice.bus = "SFX" if AudioServer.get_bus_index("SFX") != -1 else "Master"
	_voice.stream = _lines
	_voice.unit_size = 8.0
	_voice.max_distance = 22.0
	_voice.position = Vector3(0, HEAD_Y, 0)
	add_child(_voice)


func _process(delta: float) -> void:
	if _voice == null:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	_cooldown -= delta
	if _cooldown > 0.0 or _voice.playing:
		return
	var here := (get_parent() as Node3D)
	if here == null:
		return
	if here.global_position.distance_to(_player.global_position) <= NEAR:
		_voice.play()
		_cooldown = randf_range(MIN_GAP, MAX_GAP)
	else:
		_cooldown = 2.0                # out of range - re-check again soon

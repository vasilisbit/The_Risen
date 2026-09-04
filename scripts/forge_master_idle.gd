extends Node
## Drives the Forge Master vendor's rigged idle. Added as a child of the instanced
## forge_master.glb (the custom Meshy-rigged armourer robot, T-0043) in BOTH places
## the vendor appears: the hub bay (hub_structure) and the vendor screen backdrop
## (vendor_shop). Finds the GLB's AnimationPlayer, loops its "idle" clip (glTF import
## leaves clips non-looping) and plays it - the same pattern guardian_preview uses.
##
## PROCESS_MODE_ALWAYS so the idle keeps playing while the vendor screen pauses the
## tree. Falls back to a subtle procedural breathing bob if the GLB ships no idle
## clip, so the vendor is never a frozen statue.

const BOB := 0.02         # metres of vertical breathing (fallback only)
const SWAY := 0.025       # radians of gentle lean (fallback only)

var _t: float = 0.0
var _base_pos: Vector3
var _base_rot: Vector3
var _fallback: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var p := get_parent() as Node3D
	if p == null:
		return
	_base_pos = p.position
	_base_rot = p.rotation
	var ap := _find_anim_player(p)
	if ap != null:
		var clip := _idle_clip(ap)
		if clip != "":
			var anim := ap.get_animation(clip)
			if anim:
				anim.loop_mode = Animation.LOOP_LINEAR
			# Slow the Meshy idle a touch - the raw clip sways a bit much for a
			# shopkeeper; ~0.65x reads as a calm, dignified stance.
			ap.speed_scale = 0.65
			ap.play(clip)
			return
	# No usable clip - keep the vendor subtly alive procedurally.
	_fallback = true


func _find_anim_player(root: Node) -> AnimationPlayer:
	var aps := root.find_children("*", "AnimationPlayer", true, false)
	return aps[0] as AnimationPlayer if not aps.is_empty() else null


func _idle_clip(ap: AnimationPlayer) -> String:
	for anim in ap.get_animation_list():
		if String(anim).to_lower().contains("idle"):
			return anim
	var list := ap.get_animation_list()
	return String(list[0]) if not list.is_empty() else ""


func _process(delta: float) -> void:
	if not _fallback:
		return
	var p := get_parent() as Node3D
	if p == null:
		return
	_t += delta
	p.position.y = _base_pos.y + sin(_t) * BOB
	p.rotation.y = _base_rot.y + sin(_t * 0.55) * SWAY

extends Node
## Subtle "alive" idle for the Forge Master robot, which ships with no animation
## clips. A slow breathing bob plus a gentle sway, applied to the parent robot
## each frame on top of its rest transform. Added as a child of the robot in both
## the hub (hub_structure) and the vendor screen (vendor_shop).
##
## PROCESS_MODE_ALWAYS so it keeps idling while the vendor screen pauses the tree.

const BOB := 0.022        # metres of vertical breathing
const SWAY := 0.03        # radians of gentle lean
const SPEED := 1.0

var _base_pos: Vector3
var _base_rot: Vector3
var _t: float = 0.0
var _ready_ok: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var p := get_parent() as Node3D
	if p == null:
		return
	_base_pos = p.position
	_base_rot = p.rotation
	_ready_ok = true


func _process(delta: float) -> void:
	if not _ready_ok:
		return
	var p := get_parent() as Node3D
	if p == null:
		return
	_t += delta * SPEED
	p.position.y = _base_pos.y + sin(_t) * BOB
	p.rotation.y = _base_rot.y + sin(_t * 0.55) * SWAY
	p.rotation.x = _base_rot.x + sin(_t * 0.8) * SWAY * 0.4

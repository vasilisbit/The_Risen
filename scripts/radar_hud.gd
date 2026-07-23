extends Control
## Top-left motion tracker. Plots enemies around the player on a circular scope
## rotated so the player's forward always points up; red blips are enemies, the
## centre marker is the player. Purely a HUD reader - it finds the player and the
## "enemy" group each frame and draws, holding no game state.

const SIZE := 128.0
const RANGE := 45.0          # metres from player to the scope's edge
const PAD := 20.0            # inset from the screen corner

const RING_COL := Color(0.40, 0.90, 1.0, 0.55)
const RING_DIM := Color(0.40, 0.90, 1.0, 0.18)
const BG_COL := Color(0.03, 0.06, 0.09, 0.55)
const BLIP_COL := Color(1.0, 0.28, 0.24)
const BOSS_COL := Color(1.0, 0.62, 0.15)
const PLAYER_COL := Color(0.55, 0.95, 1.0)

var _sweep: float = 0.0


func _ready() -> void:
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 0.0
	anchor_bottom = 0.0
	offset_left = PAD
	offset_top = PAD
	offset_right = PAD + SIZE
	offset_bottom = PAD + SIZE
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	var p := get_tree().get_first_node_in_group("player")
	# Show only in combat scenes (the hub holsters everything and has no enemies).
	var show_radar: bool = p != null and (not ("combat_enabled" in p) or p.combat_enabled)
	visible = show_radar
	if show_radar:
		_sweep = fmod(_sweep + delta * 1.6, TAU)
		queue_redraw()


func _draw() -> void:
	var c := Vector2(SIZE, SIZE) * 0.5
	var r := SIZE * 0.5 - 5.0

	# scope face
	draw_circle(c, r, BG_COL)
	draw_arc(c, r, 0.0, TAU, 56, RING_COL, 2.0, true)
	draw_arc(c, r * 0.66, 0.0, TAU, 44, RING_DIM, 1.0, true)
	draw_arc(c, r * 0.33, 0.0, TAU, 32, RING_DIM, 1.0, true)
	draw_line(c - Vector2(r, 0), c + Vector2(r, 0), RING_DIM, 1.0)
	draw_line(c - Vector2(0, r), c + Vector2(0, r), RING_DIM, 1.0)

	# radial sweep line
	var sweep_dir := Vector2(sin(_sweep), -cos(_sweep))
	draw_line(c, c + sweep_dir * r, RING_COL.lerp(Color(0, 0, 0, 0), 0.3), 1.5)

	# player marker: a small triangle pointing up (forward)
	var tri := PackedVector2Array([
		c + Vector2(0, -7), c + Vector2(-5, 5), c + Vector2(5, 5)])
	draw_colored_polygon(tri, PLAYER_COL)

	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null:
		return
	var ppos := p.global_position
	var yaw := p.global_rotation.y
	var s := sin(yaw)
	var co := cos(yaw)
	var scale := r / RANGE

	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node3D):
			continue
		var off: Vector3 = (e as Node3D).global_position - ppos
		var dist := Vector2(off.x, off.z).length()
		if dist > RANGE:
			continue
		# Rotate the world offset into the player's forward-up frame.
		# forward = (-sin, -cos), right = (cos, -sin).
		var fwd := -(off.x * s + off.z * co)      # + = ahead
		var rgt := off.x * co - off.z * s         # + = to the right
		var blip := c + Vector2(rgt, -fwd) * scale
		var is_boss: bool = e.is_in_group("boss")
		var col := BOSS_COL if is_boss else BLIP_COL
		# fade slightly with distance so near threats read stronger
		col.a = lerpf(1.0, 0.55, clampf(dist / RANGE, 0.0, 1.0))
		draw_circle(blip, 5.0 if is_boss else 3.5, col)

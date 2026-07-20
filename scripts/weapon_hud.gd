extends Control

## Destiny-style weapon panel (restyle of the old ammo label). Bottom-right:
## the equipped weapon as a big magazine count with its reserve beside it, and
## the other three weapons stacked below as dim rows with a coloured slot
## accent down the right edge.
##
## Reserves read "INF" because the game has no reserve ammo — weapons reload
## from an unlimited pool (TDD §4.2 lists reserves, but nothing tracks them).
## Showing infinity is honest rather than inventing a number.

const MARGIN := Vector2(34, 30)
const PANEL := Vector2(330, 152)
const ROW_HEIGHT := 28.0
const ACCENT_WIDTH := 4.0
## Height of the equipped-weapon block. Tall enough for the name to sit above
## the magazine count instead of colliding with it.
const HEAD_HEIGHT := PANEL.y - ROW_HEIGHT * 3.0 - 6.0

const EMPTY := Color(0.10, 0.11, 0.13, 0.85)
const FRAME := Color(0.62, 0.66, 0.74, 0.45)
const DIM := Color(0.62, 0.65, 0.72)

## Slot accents, matching the loot rarity palette the game already uses.
const SLOT_COLORS := [
	Color(0.85, 0.88, 0.95),      # Auto Rifle
	Color(0.40, 0.85, 0.55),      # Shotgun
	Color(0.55, 0.45, 1.00),      # Sniper
	Color(1.00, 0.72, 0.25),      # Hand Cannon
]

var weapon_manager: Node

var _name_label: Label
var _ammo_label: Label
var _reserve_label: Label
var _rows: Array[Label] = []


func _ready() -> void:
	anchor_left = 1.0
	anchor_top = 1.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = -(PANEL.x + MARGIN.x)
	offset_top = -(PANEL.y + MARGIN.y)
	offset_right = -MARGIN.x
	offset_bottom = -MARGIN.y
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_labels()


func _process(_delta: float) -> void:
	_sync()
	queue_redraw()


func _weapons() -> Array:
	if weapon_manager == null or not is_instance_valid(weapon_manager):
		return []
	if not ("_weapons" in weapon_manager):
		return []
	return weapon_manager._weapons


func _active_index() -> int:
	if weapon_manager and ("_active" in weapon_manager):
		return int(weapon_manager._active)
	return 0


func _draw() -> void:
	var weapons := _weapons()
	if weapons.is_empty():
		return
	var active := _active_index()

	# Equipped weapon: a tall bar across the top of the panel.
	var head := Rect2(Vector2(0, 0), Vector2(PANEL.x, HEAD_HEIGHT))
	draw_rect(head, EMPTY)
	draw_rect(head, FRAME, false, 2.0)
	var accent: Color = SLOT_COLORS[active % SLOT_COLORS.size()]
	draw_rect(Rect2(Vector2(head.end.x - ACCENT_WIDTH, head.position.y),
		Vector2(ACCENT_WIDTH, head.size.y)), accent)
	# Divider between magazine and reserve, as in the reference.
	var divider := head.end.x - 62.0
	draw_line(Vector2(divider, head.position.y + 24.0),
		Vector2(divider, head.end.y - 6.0), FRAME, 1.5)
	_draw_weapon_glyph(Vector2(38, head.position.y + head.size.y * 0.62), accent, 1.0)

	# The other three weapons, dimmed.
	var slot := 0
	for i in weapons.size():
		if i == active:
			continue
		var y := head.end.y + 6.0 + float(slot) * ROW_HEIGHT
		var row := Rect2(Vector2(56, y), Vector2(PANEL.x - 56, ROW_HEIGHT - 4.0))
		draw_rect(row, EMPTY)
		draw_rect(Rect2(Vector2(row.end.x - ACCENT_WIDTH, row.position.y),
			Vector2(ACCENT_WIDTH, row.size.y)),
			SLOT_COLORS[i % SLOT_COLORS.size()].darkened(0.25))
		_draw_weapon_glyph(Vector2(30, y + row.size.y * 0.5), DIM, 0.62)
		slot += 1


## Simple side-on rifle silhouette: body, barrel, magazine, stock.
func _draw_weapon_glyph(c: Vector2, col: Color, scale: float) -> void:
	var w := 34.0 * scale
	var h := 7.0 * scale
	draw_rect(Rect2(c + Vector2(-w * 0.5, -h * 0.5), Vector2(w, h)), col)
	draw_rect(Rect2(c + Vector2(w * 0.35, -h * 0.22), Vector2(w * 0.4, h * 0.45)), col)
	draw_rect(Rect2(c + Vector2(-w * 0.12, h * 0.4), Vector2(h * 0.9, h * 1.5)), col)
	draw_rect(Rect2(c + Vector2(-w * 0.62, -h * 0.1), Vector2(w * 0.2, h * 0.8)), col)


func _build_labels() -> void:
	_name_label = _make_label(14, HORIZONTAL_ALIGNMENT_LEFT)
	_name_label.modulate = DIM
	add_child(_name_label)
	_ammo_label = _make_label(40, HORIZONTAL_ALIGNMENT_RIGHT)
	add_child(_ammo_label)
	_reserve_label = _make_label(18, HORIZONTAL_ALIGNMENT_CENTER)
	_reserve_label.modulate = DIM
	add_child(_reserve_label)
	for i in 3:
		var l := _make_label(16, HORIZONTAL_ALIGNMENT_RIGHT)
		l.modulate = DIM
		add_child(l)
		_rows.append(l)


func _make_label(font_size: int, align: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


func _sync() -> void:
	var weapons := _weapons()
	if weapons.is_empty():
		return
	var active := _active_index()
	var w: Weapon = weapons[active]
	var head_h := HEAD_HEIGHT

	# Name on its own line at the top, count below — they collided when the
	# head block was short enough for both to want the vertical centre.
	_name_label.position = Vector2(14, 5)
	_name_label.size = Vector2(PANEL.x - 30, 18)
	_name_label.text = "%s%s" % [w.weapon_name.to_upper(),
		"   RELOADING" if w.is_reloading() else ""]

	_ammo_label.position = Vector2(PANEL.x - 210, head_h * 0.5 - 12)
	_ammo_label.size = Vector2(140, 48)
	_ammo_label.text = str(w.ammo)
	# Flash the count red when the magazine is empty.
	_ammo_label.modulate = Color(1.0, 0.45, 0.4) if w.ammo <= 0 else Color(1, 1, 1)

	_reserve_label.position = Vector2(PANEL.x - 62, head_h * 0.5 - 2)
	_reserve_label.size = Vector2(56, 26)
	_reserve_label.text = "INF"

	var slot := 0
	for i in weapons.size():
		if i == active or slot >= _rows.size():
			continue
		var other: Weapon = weapons[i]
		var y := head_h + 6.0 + float(slot) * ROW_HEIGHT
		_rows[slot].position = Vector2(PANEL.x - 120, y)
		_rows[slot].size = Vector2(104, ROW_HEIGHT - 4.0)
		_rows[slot].text = str(other.ammo)
		slot += 1

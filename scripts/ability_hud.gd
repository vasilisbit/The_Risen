extends Control

## Destiny-style ability cluster (T-0023..25, restyled). Bottom-left of the
## HUD: a diamond for the super with a long energy bar running off it, and a
## row of squares for the grenade and melee charges beneath.
##
## Everything is drawn with draw_polygon / draw_rect so it needs no textures -
## the glyphs are simple vector shapes built in code, same approach as the rest
## of the game's placeholder art.
##
## Each element fills bottom-to-top as its cooldown recovers and lights up when
## it is ready, so "can I use this" reads at a glance without reading a number.

const MARGIN := Vector2(34, 30)
const DIAMOND_HALF := Vector2(46, 46)
const TILE := Vector2(58, 58)
const TILE_GAP := 8.0
const BAR_HEIGHT := 5.0
const BAR_LENGTH := 300.0
const PIP_HEIGHT := 4.0

const EMPTY := Color(0.10, 0.11, 0.13, 0.85)
const FRAME := Color(0.62, 0.66, 0.74, 0.55)
const CHARGING := Color(0.32, 0.35, 0.40)

## Filled in by the Guardian when it builds the class kit. The super gets the
## diamond; the grenade and melee become tiles, left to right.
var super_ability: Ability
var grenade_ability: Ability
var melee_ability: Ability


## The two tiles, in draw order. Read fresh each frame so a class change is
## picked up without the Guardian having to poke the HUD twice.
func tiles() -> Array:
	return [grenade_ability, melee_ability]

var _labels: Array[Label] = []
var _super_label: Label


func _ready() -> void:
	anchor_left = 0.0
	anchor_top = 1.0
	anchor_right = 0.0
	anchor_bottom = 1.0
	var width := DIAMOND_HALF.x * 2.0 + BAR_LENGTH
	var height := DIAMOND_HALF.y * 2.0 + TILE.y + 30.0
	offset_left = MARGIN.x
	offset_top = -(height + MARGIN.y)
	offset_right = MARGIN.x + width
	offset_bottom = -MARGIN.y
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_labels()


func _process(_delta: float) -> void:
	_sync_labels()
	queue_redraw()


# --- geometry ---------------------------------------------------------------

func _diamond_centre() -> Vector2:
	return Vector2(DIAMOND_HALF.x, size.y - DIAMOND_HALF.y - 6.0)


func _tile_rect(index: int) -> Rect2:
	var start := _diamond_centre().x + DIAMOND_HALF.x + 18.0
	return Rect2(Vector2(start + float(index) * (TILE.x + TILE_GAP),
		size.y - TILE.y - 6.0), TILE)


func _draw() -> void:
	_draw_super()
	var list := tiles()
	for i in list.size():
		_draw_tile(i, list[i])


# --- super diamond ----------------------------------------------------------

func _draw_super() -> void:
	var c := _diamond_centre()
	var pts := _diamond_points(c, DIAMOND_HALF)
	var ready_now := super_ability != null and super_ability.is_ready()
	var tint: Color = super_ability.ability_color if super_ability else Color.WHITE

	# A charging super is tinted rather than left near-black, so the diamond
	# still reads as the super slot when it is completely empty.
	draw_colored_polygon(pts, EMPTY if ready_now else Color(tint.darkened(0.78), 0.9))
	# Charge fills the diamond from the bottom up.
	var frac := super_ability.cooldown_fraction() if super_ability else 0.0
	if frac > 0.0:
		var line := c.y + DIAMOND_HALF.y - DIAMOND_HALF.y * 2.0 * clampf(frac, 0.0, 1.0)
		var filled := _clip_below(pts, line)
		if filled.size() >= 3:
			draw_colored_polygon(filled, tint if ready_now else tint.darkened(0.45))
	_draw_outline(pts, tint if ready_now else FRAME, 3.0 if ready_now else 2.0)
	# A charged super gets a second, larger outline as a "ready" flare.
	if ready_now:
		_draw_outline(_diamond_points(c, DIAMOND_HALF + Vector2(6, 6)), Color(tint, 0.35), 2.0)
	_draw_super_glyph(c, tint if ready_now else tint.darkened(0.25))

	# Energy bar running right off the diamond, D2's super meter.
	var bar_x := c.x + DIAMOND_HALF.x + 4.0
	var bar_y := c.y - DIAMOND_HALF.y + 2.0
	var track := Rect2(Vector2(bar_x, bar_y), Vector2(BAR_LENGTH, BAR_HEIGHT))
	draw_rect(track, EMPTY)
	if frac > 0.0:
		# Fades along its length so it reads as energy rather than a plain bar.
		var lit := BAR_LENGTH * clampf(frac, 0.0, 1.0)
		var steps := 24
		for i in steps:
			var t0 := float(i) / float(steps)
			var seg := lit / float(steps)
			if t0 * BAR_LENGTH >= lit:
				break
			var col := tint.lerp(tint.darkened(0.55), t0)
			draw_rect(Rect2(Vector2(bar_x + t0 * lit, bar_y), Vector2(seg + 1.0, BAR_HEIGHT)),
				col if ready_now else col.darkened(0.35))


## Six-armed swirl, echoing the super glyph in the reference.
func _draw_super_glyph(c: Vector2, col: Color) -> void:
	var arms := 6
	for i in arms:
		var a := TAU * float(i) / float(arms)
		var inner := c + Vector2(cos(a), sin(a)) * 7.0
		var mid := c + Vector2(cos(a + 0.5), sin(a + 0.5)) * 15.0
		var outer := c + Vector2(cos(a + 1.0), sin(a + 1.0)) * 21.0
		draw_polyline([inner, mid, outer], col, 2.5, true)


# --- ability tiles ----------------------------------------------------------

func _draw_tile(index: int, ability: Ability) -> void:
	var r := _tile_rect(index)
	var ready_now := ability != null and ability.is_ready()
	var tint: Color = ability.ability_color if ability else Color.WHITE

	draw_rect(r, EMPTY)
	var frac := ability.cooldown_fraction() if ability else 0.0
	if frac > 0.0:
		var h := r.size.y * clampf(frac, 0.0, 1.0)
		draw_rect(Rect2(Vector2(r.position.x, r.position.y + r.size.y - h),
			Vector2(r.size.x, h)), tint if ready_now else tint.darkened(0.5))
	draw_rect(r, tint if ready_now else FRAME, false, 2.0)
	_draw_tile_glyph(index, r, Color(0.06, 0.07, 0.09) if ready_now else CHARGING)

	# Charge pip under the tile: solid when the ability is available.
	var pip := Rect2(Vector2(r.position.x, r.position.y + r.size.y + 5.0),
		Vector2(r.size.x, PIP_HEIGHT))
	draw_rect(pip, EMPTY)
	if ready_now:
		draw_rect(pip, tint)
	else:
		draw_rect(Rect2(pip.position, Vector2(pip.size.x * frac, PIP_HEIGHT)), tint.darkened(0.5))


## Tile 0 is the grenade (a lobbed arc), tile 1 the melee (a strike).
func _draw_tile_glyph(index: int, r: Rect2, col: Color) -> void:
	var c := r.position + r.size * 0.5
	if index == 0:
		# Grenade: a body with an arcing throw line over it.
		draw_circle(c + Vector2(0, 5), 8.0, col)
		var arc := PackedVector2Array()
		for i in 9:
			var t := float(i) / 8.0
			arc.append(c + Vector2(lerpf(-16.0, 8.0, t), -6.0 - sin(t * PI) * 9.0))
		draw_polyline(arc, col, 2.5, true)
	else:
		# Melee: a slash with a fist behind it.
		draw_rect(Rect2(c + Vector2(-13, -4), Vector2(12, 11)), col)
		draw_line(c + Vector2(-4, 10), c + Vector2(15, -11), col, 3.5, true)
		draw_line(c + Vector2(1, 12), c + Vector2(17, -4), col, 2.0, true)


# --- polygon helpers --------------------------------------------------------

func _diamond_points(c: Vector2, half: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		c + Vector2(0, -half.y), c + Vector2(half.x, 0),
		c + Vector2(0, half.y), c + Vector2(-half.x, 0)])


func _draw_outline(pts: PackedVector2Array, col: Color, w: float) -> void:
	var loop := PackedVector2Array(pts)
	loop.append(pts[0])
	draw_polyline(loop, col, w, true)


## Sutherland-Hodgman against the single half-plane y >= line - the portion of
## a convex polygon below a horizontal cut, used to fill the diamond partway.
func _clip_below(pts: PackedVector2Array, line: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var a_in := a.y >= line
		var b_in := b.y >= line
		if a_in:
			out.append(a)
		if a_in != b_in and not is_equal_approx(a.y, b.y):
			var t := (line - a.y) / (b.y - a.y)
			out.append(a + (b - a) * t)
	return out


# --- labels -----------------------------------------------------------------

func _build_labels() -> void:
	_super_label = _make_label(16)
	add_child(_super_label)
	for i in 2:
		var l := _make_label(15)
		add_child(l)
		_labels.append(l)


func _make_label(font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


## Ready abilities show their key prompt; charging ones show seconds left.
func _sync_labels() -> void:
	var c := _diamond_centre()
	_super_label.size = Vector2(DIAMOND_HALF.x * 2.0, 20)
	_super_label.position = Vector2(c.x - DIAMOND_HALF.x, c.y + DIAMOND_HALF.y - 22.0)
	_apply(_super_label, super_ability)
	var list := tiles()
	for i in _labels.size():
		var r := _tile_rect(i)
		_labels[i].size = Vector2(r.size.x, 18)
		_labels[i].position = Vector2(r.position.x, r.position.y + r.size.y - 20.0)
		_apply(_labels[i], list[i] if i < list.size() else null)


func _apply(label: Label, ability: Ability) -> void:
	if ability == null or not is_instance_valid(ability):
		label.text = ""
		return
	if ability.is_ready():
		label.text = ability.input_prompt
		label.modulate = Color(1, 1, 1)
	else:
		label.text = str(int(ceil(ability.cooldown_left())))
		label.modulate = Color(0.78, 0.80, 0.86)

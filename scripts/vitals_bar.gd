extends Control
## Top-centre vitals readout (Destiny-style): a thin shield bar sitting over a
## health bar, centred at the top of the screen. Decoupled from the Guardian
## class - it finds the player by group and follows its health_changed /
## shield_changed signals, so it can live under any HUD CanvasLayer.

const BAR_W := 440.0          # bar width in px
const HEALTH_H := 12.0
const SHIELD_H := 8.0
const GAP := 4.0              # space between the two bars
const SEGMENTS := 24         # tick marks across the bar for the segmented look

const SHIELD_COL := Color(0.45, 0.85, 1.0)      # cyan
const HEALTH_COL := Color(0.92, 0.94, 0.98)     # near-white
const HEALTH_LOW := Color(0.95, 0.35, 0.30)     # red when hurt
const TRACK_COL := Color(0.05, 0.07, 0.10, 0.65)
const EDGE_COL := Color(0.55, 0.75, 0.95, 0.45)

var _hp: float = 1.0
var _hp_max: float = 1.0
var _sh: float = 1.0
var _sh_max: float = 1.0


func _ready() -> void:
	# Anchor the control to the top-centre and size it to the bar.
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -BAR_W * 0.5
	offset_right = BAR_W * 0.5
	offset_top = 18.0
	offset_bottom = 18.0 + HEALTH_H + SHIELD_H + GAP + 4.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var p := get_tree().get_first_node_in_group("player")
	if p and p.has_signal("health_changed"):
		p.health_changed.connect(_on_health)
		p.shield_changed.connect(_on_shield)
		# Prime with current values (the player also emits on spawn).
		_hp = p.health
		_hp_max = maxf(1.0, p.max_hp())
		_sh = p.shield
		_sh_max = maxf(1.0, p.MAX_SHIELD)
	queue_redraw()


func _process(_delta: float) -> void:
	# Hidden in non-combat scenes (the hub), like the radar and crosshair-less HUD.
	var p := get_tree().get_first_node_in_group("player")
	visible = p != null and (not ("combat_enabled" in p) or p.combat_enabled)


func _on_health(current: float, maximum: float) -> void:
	_hp = current
	_hp_max = maxf(1.0, maximum)
	queue_redraw()


func _on_shield(current: float, maximum: float) -> void:
	_sh = current
	_sh_max = maxf(1.0, maximum)
	queue_redraw()


func _draw() -> void:
	# Shield bar (top), slightly inset; health bar (below), full width.
	var sh_x := (BAR_W - BAR_W) * 0.5
	_draw_bar(Vector2(0, 0), BAR_W, SHIELD_H, _sh / _sh_max, SHIELD_COL)
	var hp_col := HEALTH_COL.lerp(HEALTH_LOW, clampf(1.0 - _hp / _hp_max, 0.0, 1.0) * 0.85)
	_draw_bar(Vector2(0, SHIELD_H + GAP), BAR_W, HEALTH_H, _hp / _hp_max, hp_col)
	# sh_x kept for symmetry / future inset tuning
	sh_x = sh_x
	# Emblem caps just left of the bars (generated icons; nothing drawn if absent).
	UiIcons.blit_centered(self, "shield", Vector2(-15, SHIELD_H * 0.5), 16.0, SHIELD_COL)
	UiIcons.blit_centered(self, "health", Vector2(-15, SHIELD_H + GAP + HEALTH_H * 0.5), 16.0, hp_col)


## One bar: dark track, coloured fill, segment ticks, and a bright top edge.
func _draw_bar(pos: Vector2, w: float, h: float, frac: float, col: Color) -> void:
	frac = clampf(frac, 0.0, 1.0)
	var track := Rect2(pos, Vector2(w, h))
	draw_rect(track, TRACK_COL, true)
	if frac > 0.0:
		draw_rect(Rect2(pos, Vector2(w * frac, h)), col, true)
		# a brighter 2px cap at the leading edge
		draw_rect(Rect2(pos + Vector2(maxf(0.0, w * frac - 2.0), 0), Vector2(2, h)),
			col.lightened(0.4), true)
	# segment ticks
	for i in range(1, SEGMENTS):
		var x := pos.x + w * float(i) / float(SEGMENTS)
		draw_line(Vector2(x, pos.y), Vector2(x, pos.y + h), TRACK_COL.lightened(0.15), 1.0)
	# outline
	draw_rect(track, EDGE_COL, false, 1.0)

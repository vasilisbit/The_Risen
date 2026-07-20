extends Control

## Radial super-ability cooldown indicator (T-0023). Bottom-right of the HUD:
## a ring that fills clockwise as the 60 s cooldown elapses, the remaining
## seconds in the middle, and a "Q" prompt that lights up when the super is
## ready. Drawn with draw_arc so it needs no textures.

const RADIUS := 34.0
const THICKNESS := 7.0
const MARGIN := Vector2(28, 28)
const DIM := Color(0.25, 0.26, 0.30)

var ability: Ability

var _centre: Label
var _name_label: Label


func _ready() -> void:
	# Pin to the bottom-right corner. Anchors + explicit offsets, NOT `position`:
	# on an anchored Control `position` is parent-space, so setting it to a
	# negative value put the whole ring off the top-left of the screen.
	anchor_left = 1.0
	anchor_top = 1.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = -(RADIUS * 2.0 + MARGIN.x)
	offset_top = -(RADIUS * 2.0 + MARGIN.y)
	offset_right = -MARGIN.x
	offset_bottom = -MARGIN.y
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_labels()


func _process(_delta: float) -> void:
	if ability == null or not is_instance_valid(ability):
		visible = false
		return
	visible = true
	# One centre label: the "Q" prompt when the super is usable, otherwise the
	# seconds remaining. Showing both at once just made them overlap.
	var ready_now := ability.is_ready()
	_centre.text = "Q" if ready_now else str(int(ceil(ability.cooldown_left())))
	_centre.modulate = ability.ability_color if ready_now else DIM
	_name_label.text = ability.ability_name
	queue_redraw()


func _draw() -> void:
	if ability == null or not is_instance_valid(ability):
		return
	var center := Vector2(RADIUS, RADIUS)
	# Track.
	draw_arc(center, RADIUS, 0.0, TAU, 48, DIM, THICKNESS, true)
	# Fill, clockwise from 12 o'clock.
	var frac := clampf(ability.cooldown_fraction(), 0.0, 1.0)
	if frac > 0.0:
		var start := -PI * 0.5
		var col: Color = ability.ability_color if ability.is_ready() else ability.ability_color.darkened(0.35)
		draw_arc(center, RADIUS, start, start + TAU * frac, 48, col, THICKNESS, true)
	# A brighter inner ring once it is ready, so "usable" reads at a glance.
	if ability.is_ready():
		draw_arc(center, RADIUS - THICKNESS, 0.0, TAU, 40,
			Color(ability.ability_color, 0.35), 2.0, true)


func _build_labels() -> void:
	_centre = Label.new()
	_centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	_centre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_centre.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_centre.add_theme_font_size_override("font_size", 22)
	_centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_centre)

	_name_label = Label.new()
	_name_label.position = Vector2(-40, RADIUS * 2.0 + 2)
	_name_label.custom_minimum_size = Vector2(RADIUS * 2.0 + 80, 0)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 12)
	_name_label.modulate = Color(0.75, 0.78, 0.85)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_label)

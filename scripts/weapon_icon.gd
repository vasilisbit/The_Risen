class_name LootIcon
extends Control

## A boxed loot icon for the inventory: a rounded panel filled with the item's
## rarity colour, a matching border, and a silhouette of the item drawn on top
## (a side-on gun for weapons, an armour piece for armour). Everything is drawn
## in code so there are no image assets. Set `kind`, `rarity` and `is_armor`
## before it is shown, or call configure().

## Rarity fill colours, matching loot_drop.gd / the rest of the game's palette.
const RARITY_COLORS := {
	"Common": Color(0.55, 0.58, 0.64),
	"Rare": Color(0.20, 0.45, 0.95),
	"Epic": Color(0.55, 0.28, 0.95),
	"Exotic": Color(0.95, 0.72, 0.15),
}

var kind: String = "Auto Rifle"
var rarity: String = "Common"
var is_armor: bool = false


func configure(kind_: String, rarity_: String, armor: bool) -> void:
	kind = kind_
	rarity = rarity_
	is_armor = armor
	queue_redraw()


func _ready() -> void:
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(56, 56)
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var base: Color = RARITY_COLORS.get(rarity, RARITY_COLORS["Common"])
	# Rarity-tinted box: a dark version fills it, the pure rarity colour frames
	# it, so the silhouette stays legible against the fill.
	draw_rect(rect, base.darkened(0.55))
	draw_rect(rect, base, false, 2.0)
	var c := size * 0.5
	var col := base.lightened(0.35)
	if is_armor:
		_draw_armor_glyph(kind, c, col)
	else:
		_draw_weapon_glyph(kind, c, col)


## Side-on weapon silhouette, barrel pointing left. Mirrors the weapon-HUD
## glyphs so a gun reads the same in the inventory as it does on the HUD.
func _draw_weapon_glyph(kind_: String, c: Vector2, col: Color) -> void:
	var s := minf(size.x, size.y) / 56.0
	var w := 40.0 * s
	var h := 9.0 * s
	match kind_:
		"Shotgun":
			draw_rect(Rect2(c + Vector2(-w * 0.25, -h * 0.6), Vector2(w * 0.55, h * 1.2)), col)
			draw_rect(Rect2(c + Vector2(-w * 0.62, -h * 0.55), Vector2(w * 0.4, h * 0.5)), col)
			draw_rect(Rect2(c + Vector2(-w * 0.62, h * 0.05), Vector2(w * 0.4, h * 0.4)), col)
			draw_rect(Rect2(c + Vector2(-w * 0.45, h * 0.5), Vector2(w * 0.22, h * 0.5)), col)
		"Sniper":
			draw_rect(Rect2(c + Vector2(-w * 0.15, -h * 0.35), Vector2(w * 0.5, h * 0.8)), col)
			draw_rect(Rect2(c + Vector2(-w * 0.75, -h * 0.12), Vector2(w * 0.62, h * 0.3)), col)
			draw_rect(Rect2(c + Vector2(-w * 0.1, -h * 0.95), Vector2(w * 0.36, h * 0.4)), col)
			draw_rect(Rect2(c + Vector2(w * 0.3, -h * 0.4), Vector2(w * 0.2, h * 0.9)), col)
		"Hand Cannon":
			draw_rect(Rect2(c + Vector2(-w * 0.1, -h * 0.45), Vector2(w * 0.34, h * 0.9)), col)
			draw_rect(Rect2(c + Vector2(-w * 0.44, -h * 0.2), Vector2(w * 0.36, h * 0.4)), col)
			draw_circle(c + Vector2(w * 0.02, h * 0.05), h * 0.62, col)
			draw_rect(Rect2(c + Vector2(w * 0.14, h * 0.3), Vector2(w * 0.16, h * 1.2)), col)
		_:
			draw_rect(Rect2(c + Vector2(-w * 0.2, -h * 0.5), Vector2(w * 0.55, h)), col)
			draw_rect(Rect2(c + Vector2(-w * 0.66, -h * 0.18), Vector2(w * 0.5, h * 0.36)), col)
			draw_rect(Rect2(c + Vector2(-w * 0.05, h * 0.4), Vector2(h * 0.85, h * 1.5)), col)
			draw_rect(Rect2(c + Vector2(w * 0.3, -h * 0.35), Vector2(w * 0.18, h * 0.8)), col)


## Simple armour-piece silhouettes for the three slots.
func _draw_armor_glyph(kind_: String, c: Vector2, col: Color) -> void:
	var s := minf(size.x, size.y) / 56.0
	var u := 13.0 * s
	match kind_:
		"Helmet":
			# Domed top with a visor slit.
			draw_circle(c + Vector2(0, -u * 0.15), u * 0.9, col)
			draw_rect(Rect2(c + Vector2(-u * 0.9, -u * 0.1), Vector2(u * 1.8, u * 0.55)), col)
			draw_rect(Rect2(c + Vector2(-u * 0.7, -u * 0.05), Vector2(u * 1.4, u * 0.18)),
				col.darkened(0.6))
		"Gauntlets":
			# A blocky forearm guard with knuckle plates.
			draw_rect(Rect2(c + Vector2(-u * 0.5, -u * 0.9), Vector2(u, u * 1.5)), col)
			draw_rect(Rect2(c + Vector2(-u * 0.7, u * 0.6), Vector2(u * 1.4, u * 0.5)), col)
			for i in 3:
				draw_rect(Rect2(c + Vector2(-u * 0.55 + i * u * 0.45, -u * 1.05),
					Vector2(u * 0.3, u * 0.3)), col)
		_:
			# Chest Plate: a rounded breastplate.
			draw_rect(Rect2(c + Vector2(-u, -u * 0.8), Vector2(u * 2.0, u * 1.5)), col)
			draw_rect(Rect2(c + Vector2(-u * 1.2, -u * 0.8), Vector2(u * 0.5, u * 0.9)), col)
			draw_rect(Rect2(c + Vector2(u * 0.7, -u * 0.8), Vector2(u * 0.5, u * 0.9)), col)
			draw_line(c + Vector2(0, -u * 0.6), c + Vector2(0, u * 0.6), col.darkened(0.5), 2.0)

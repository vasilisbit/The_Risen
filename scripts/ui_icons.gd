class_name UiIcons
extends Object

## Shared loader for the generated HUD icon set (T-0045). The icons are flat
## WHITE monochrome glyphs with a clean alpha channel in
## res://assets/generated/ui/<key>.png; each HUD blits them with draw_texture_rect
## and tints them per-context (ability colour, weapon-slot / rarity gold, shield
## cyan, ...). get_icon() caches loaded textures and returns null when a sheet is
## missing, so every caller keeps its procedural glyph as a safe fallback.

const DIR := "res://assets/generated/ui/"

static var _cache := {}

static func get_icon(key: String) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	var path := DIR + key + ".png"
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_cache[key] = tex
	return tex


## Blit a monochrome icon centered in `box` (a Rect2), tinted `col`, preserving
## the icon's square aspect. Returns false if the icon is missing so the caller
## can draw its fallback glyph instead.
static func blit(canvas: CanvasItem, key: String, box: Rect2, col: Color) -> bool:
	var tex := get_icon(key)
	if tex == null:
		return false
	var side := minf(box.size.x, box.size.y)
	var pos := box.position + (box.size - Vector2(side, side)) * 0.5
	canvas.draw_texture_rect(tex, Rect2(pos, Vector2(side, side)), false, col)
	return true


## Convenience: blit centered on a point with a square edge length.
static func blit_centered(canvas: CanvasItem, key: String, center: Vector2, edge: float, col: Color) -> bool:
	return blit(canvas, key, Rect2(center - Vector2(edge, edge) * 0.5, Vector2(edge, edge)), col)


## Icon key for a weapon type, shared by the weapon HUD and the loot icons.
static func weapon_key(kind: String) -> String:
	match kind:
		"Shotgun": return "wpn_shotgun"
		"Sniper": return "wpn_sniper"
		"Hand Cannon": return "wpn_hand_cannon"
		_: return "wpn_auto_rifle"


## Icon key for an armour slot.
static func armor_key(kind: String) -> String:
	match kind:
		"Helmet": return "armor_helmet"
		"Gauntlets": return "armor_gauntlets"
		_: return "armor_chest"

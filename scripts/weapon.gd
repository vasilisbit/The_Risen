class_name Weapon
extends Node3D

## Base hitscan weapon (T-0010). One script, four configured scenes. Stats are
## @export per TDD §4.2 and match GDD §2.6. Firing raycasts from a supplied
## origin/direction (the player camera) via PhysicsRayQueryParameters3D; hitting
## a node with take_damage() applies damage, doubled on a headshot (is_headshot).

@export var weapon_name: String = "Weapon"
@export var damage: float = 20.0          # total per trigger pull (split over pellets)
@export var rpm: float = 600.0
@export var mag_size: int = 30
@export var reload_time: float = 2.0
@export var effective_range: float = 30.0
@export var pellets: int = 1
@export var spread_degrees: float = 0.0
@export var headshot_mult: float = 1.0
@export var automatic: bool = false

## Rarity multipliers on the scene's base stats (GDD §2.7: rarity is the roll
## that makes one drop worth keeping over another). A better roll hits harder,
## reloads faster, kicks less and - from Epic up - holds a bigger magazine.
## Applied once by apply_rarity() at build time, so the four scene defaults stay
## the Common baseline.
const RARITY_MODS := {
	"Common": {"dmg": 1.00, "reload": 1.00, "recoil": 1.00, "mag": 1.00},
	"Rare":   {"dmg": 1.15, "reload": 0.92, "recoil": 0.90, "mag": 1.00},
	"Epic":   {"dmg": 1.30, "reload": 0.85, "recoil": 0.80, "mag": 1.15},
	"Exotic": {"dmg": 1.50, "reload": 0.75, "recoil": 0.65, "mag": 1.30},
}

## Per-stat rarity bands [worst_roll, best_roll] as multipliers on the base
## stat. Two drops of the same weapon and rarity differ within the band (a random
## roll 0..1 picks a point on it), but the bands step up with rarity so a better
## rarity is always at least as good - a bad Exotic still beats a good Rare. For
## reload and recoil the "better" end is the lower number.
const STAT_BANDS := {
	"damage": {"Common": [0.95, 1.05], "Rare": [1.08, 1.22], "Epic": [1.22, 1.40], "Exotic": [1.42, 1.62]},
	"reload": {"Common": [1.05, 0.97], "Rare": [0.97, 0.88], "Epic": [0.88, 0.80], "Exotic": [0.80, 0.70]},
	"recoil": {"Common": [1.05, 0.95], "Rare": [0.94, 0.85], "Epic": [0.84, 0.74], "Exotic": [0.72, 0.58]},
	"mag":    {"Common": [1.00, 1.02], "Rare": [1.02, 1.08], "Epic": [1.10, 1.20], "Exotic": [1.22, 1.36]},
}

## The rarity this instance was rolled/built at, kept for the HUD and inventory.
var rarity: String = "Common"
## Scales the camera recoil the WeaponManager applies (rarer = steadier). Set by
## apply_rarity; 1.0 leaves the per-weapon recoil untouched.
var recoil_mult: float = 1.0

## Damage element (GDD §2.6). Kinetic is the neutral default; an Elemental mod
## sets Solar/Arc/Void, which then does bonus damage to a matching elemental
## shield and chip damage to a mismatched one (GDD §2.8).
const ELEMENTS := ["Kinetic", "Solar", "Arc", "Void"]
var element: String = "Kinetic"

## Craftable weapon mods (GDD §2.6). Each installed mod is applied once by
## apply_mod() at build time. Element mods are mutually exclusive (a weapon has
## one element); the other mods stack. Flux cost matches the GDD (100 each);
## blueprints are deferred, so mods are crafted straight from Flux in the
## inventory rather than from a dropped blueprint.
const MODS := {
	"rpm":   {"name": "Fire-Rate Coil",  "desc": "+20% rate of fire",     "cost": 100},
	"mag":   {"name": "Extended Mag",    "desc": "+50% magazine",         "cost": 100},
	"solar": {"name": "Solar Injector",  "desc": "Solar element",         "cost": 100, "element": "Solar"},
	"arc":   {"name": "Arc Injector",    "desc": "Arc element",           "cost": 100, "element": "Arc"},
	"void":  {"name": "Void Injector",   "desc": "Void element",          "cost": 100, "element": "Void"},
}
## Mod slots per rarity (GDD §2.7: Epic +1, Exotic +2). Levels 5/8 gate slots in
## the GDD, but XP/levels are unimplemented (M6), so slots come from rarity - the
## progression axis the game actually has.
const MOD_SLOTS := {"Common": 0, "Rare": 1, "Epic": 2, "Exotic": 2}

## Element colours for HUD/inventory tinting.
const ELEMENT_COLORS := {
	"Kinetic": Color(0.85, 0.88, 0.95),
	"Solar": Color(1.00, 0.55, 0.18),
	"Arc": Color(0.35, 0.80, 1.00),
	"Void": Color(0.70, 0.40, 1.00),
}

## Hitscan collision mask: world geometry (layer 1) so shots stop on walls, plus
## the enemy layer (5) that EnemyBase now occupies. Enemies were moved off layer 1
## so the player no longer physically collides with them (EnemyBase.ENEMY_LAYER);
## the gun must mask that layer explicitly or its raycast passes straight through.
const HIT_MASK := 1 | (1 << 4)             # world + enemy layer

signal state_changed                       # ammo / reload changed
signal reload_started(duration: float)     # a reload just BEGAN (manual R or auto-on-empty)

## Scales outgoing damage - Mars wave buffs raise this (e.g. +20% -> 1.2).
## Buff picks SET this rather than stacking it, hence the separate class field.
var damage_multiplier: float = 1.0
## Class passive damage bonus (Assault: 1.1). Kept apart from
## damage_multiplier so a mission buff overwriting that one can't silently
## erase the player's class passive.
var class_multiplier: float = 1.0

var ammo: int = 0
var _cooldown: float = 0.0
var _reloading: bool = false
var _reload_left: float = 0.0


func _ready() -> void:
	ammo = mag_size


## One point on a stat's rarity band, chosen by a 0..1 roll (0.5 = middle).
static func stat_band(stat: String, rarity_: String, roll: float) -> float:
	var by_rarity: Dictionary = STAT_BANDS.get(stat, {})
	var band: Array = by_rarity.get(rarity_, by_rarity.get("Common", [1.0, 1.0]))
	return lerpf(float(band[0]), float(band[1]), clampf(roll, 0.0, 1.0))


## A fresh random roll per stat, stored on the owned item so the weapon rebuilds
## identically every time. Generated once at drop / purchase.
static func roll_stats() -> Dictionary:
	return {"damage": randf(), "reload": randf(), "recoil": randf(), "mag": randf()}


## Scale this weapon's base stats for its rarity and its stored rolls. Call it
## BEFORE the node enters the tree (before _ready fills the magazine), so the
## rolled magazine size is reflected in the starting ammo. Missing rolls default
## to the middle of the band, so old saves stay stable.
func apply_stats(rarity_: String, rolls: Dictionary) -> void:
	rarity = rarity_ if STAT_BANDS["damage"].has(rarity_) else "Common"
	damage *= stat_band("damage", rarity, float(rolls.get("damage", 0.5)))
	reload_time *= stat_band("reload", rarity, float(rolls.get("reload", 0.5)))
	recoil_mult = stat_band("recoil", rarity, float(rolls.get("recoil", 0.5)))
	mag_size = int(round(mag_size * stat_band("mag", rarity, float(rolls.get("mag", 0.5)))))
	ammo = mag_size


## Back-compat: rarity only, middle-of-band rolls.
func apply_rarity(rarity_: String) -> void:
	apply_stats(rarity_, {})


## Apply one installed mod's effect. Called by the WeaponManager after
## apply_rarity and before the node enters the tree, so a magazine mod is
## reflected in the starting ammo. Unknown ids are ignored.
func apply_mod(mod_id: String) -> void:
	var m: Dictionary = MODS.get(mod_id, {})
	if m.is_empty():
		return
	if m.has("element"):
		element = String(m["element"])
	match mod_id:
		"rpm":
			rpm *= 1.2
		"mag":
			mag_size = int(round(mag_size * 1.5))
			ammo = mag_size


func tick(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta
	if _reloading:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_reloading = false
			ammo = mag_size
			state_changed.emit()
	elif ammo <= 0:
		# Empty magazines reload themselves: dry-firing and waiting for the
		# player to press R does nothing useful. Manual reload still works
		# early, and this lives in tick() so any Weapon user gets it.
		start_reload()


func is_reloading() -> bool:
	return _reloading


func can_fire() -> bool:
	return not _reloading and _cooldown <= 0.0 and ammo > 0


## Fire one shot (all pellets). Returns the list of {collider, headshot, damage}
## for hits. Applies damage to anything with take_damage().
func fire(origin: Vector3, direction: Vector3, world: World3D, exclude: Array = []) -> Array:
	if not can_fire():
		return []
	ammo -= 1
	_cooldown = 60.0 / rpm
	# Fired at the muzzle so it attenuates with distance for anyone else nearby
	# (T-0034). The sfx id is derived from the weapon name, so the four
	# configured scenes each get their own report with no extra @export.
	_play_shot(origin)
	var per_pellet := damage * damage_multiplier * class_multiplier / float(max(1, pellets))
	var results: Array = []
	var space := world.direct_space_state
	for i in pellets:
		var dir := _apply_spread(direction)
		var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * effective_range, HIT_MASK)
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var collider: Object = hit["collider"]
		# Bullet-impact sparks where the shot lands (world or enemy), sized per gun and
		# tinted by the weapon's energy element. A temporary bullet-hole decal is left
		# only on static world geometry (not on a moving enemy, where it would detach).
		var host := get_tree().current_scene
		if host != null:
			var ecol: Color = ELEMENT_COLORS.get(element, Color(1.0, 0.9, 0.7))
			var world_hit := collider == null or not collider.has_method("take_damage")
			VfxKit.impact(host, hit["position"], hit.get("normal", Vector3.UP), ecol, weapon_name, world_hit)
		if collider != null and collider.has_method("take_damage"):
			var dmg := per_pellet
			var head := false
			if collider.has_method("is_headshot") and collider.is_headshot(hit["position"]):
				dmg *= headshot_mult
				head = true
			# Attribute before the hit: a lethal shot frees the node. The element
			# rides along here so a matching elemental shield (Heroic/Legendary)
			# takes bonus damage - no extra argument on take_damage needed.
			if collider.has_method("mark_damage_source"):
				collider.mark_damage_source(weapon_name, head, element)
			collider.take_damage(dmg)
			results.append({"collider": collider, "headshot": head, "damage": dmg})
	state_changed.emit()
	return results


func _play_shot(origin: Vector3) -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio == null:
		return
	audio.play_sfx(weapon_name.to_lower().replace(" ", "_"), origin)


func start_reload() -> void:
	if _reloading or ammo >= mag_size:
		return
	_reloading = true
	_reload_left = reload_time
	reload_started.emit(reload_time)         # drives the FP reload animation (manual OR auto-empty)
	state_changed.emit()


func cancel_reload() -> void:
	if _reloading:
		_reloading = false
		state_changed.emit()


func _apply_spread(direction: Vector3) -> Vector3:
	if spread_degrees <= 0.0:
		return direction
	var half := deg_to_rad(spread_degrees) * 0.5
	# Random tilt within a cone around `direction`.
	var cone_basis := Basis.looking_at(direction, Vector3.UP)
	var ang := randf() * TAU
	var mag := randf() * half
	var local := Vector3(sin(mag) * cos(ang), sin(mag) * sin(ang), -cos(mag))
	return (cone_basis * local).normalized()

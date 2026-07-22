class_name EnemyBase
extends CharacterBody3D

## Shared enemy plumbing (T-0007/T-0008/T-0009): health, damage intake, death
## signal, loot drop, player lookup, gravity, headshot test. Subclasses set
## `max_health` in _init() and implement their own _physics_process guarding on
## `_dead`.

signal died(where: Vector3)

## Loot spawned on death. If unset, the shared loot_drop.tscn (T-0011) is used.
@export var loot_scene: PackedScene

## Local height (from the body origin at the feet) at/above which a hit counts
## as a headshot - matches the 1.8 m capsule (top hemisphere).
const HEAD_MIN_LOCAL_Y := 1.4
const LOOT_SCENE_PATH := "res://scenes/weapons/loot_drop.tscn"
const NAMEPLATE_SCENE_PATH := "res://scripts/enemy_nameplate.gd"

## Display names for the floating nameplate, keyed by the subclass class_name.
const NAMES := {
	"Rusher": "Risen Rusher",
	"Shooter": "Risen Shooter",
	"Exploder": "Volatile Exploder",
	"ShieldedBrute": "Shielded Brute",
	"Phantom": "Teleporting Phantom",
	"EmberTyrant": "Ember Tyrant",
}

## Whether this enemy shows a floating nameplate. On by default; a subclass can
## suppress it (e.g. if it drives its own dedicated boss UI).
var show_nameplate: bool = true

## Mission-wide enemy modifiers set by the Mars debuff picks (T-0018). Static so
## they apply to every enemy, including ones spawned later. Reset per mission.
static var speed_scale: float = 1.0          # -10% speed pick -> 0.9
static var accuracy_penalty: float = 0.0     # -5% accuracy pick -> 0.05


static func reset_modifiers() -> void:
	speed_scale = 1.0
	accuracy_penalty = 0.0

## Force a loot rarity on death (e.g. a boss guaranteeing an Epic). Empty = roll.
var loot_rarity_override: String = ""
## Probability this enemy drops anything at all (GDD §2.7: loot is a chance, not
## a guarantee, so the floor doesn't carpet with pickups). Bosses/minibosses set
## this to 1.0, and a forced rarity always drops regardless.
var loot_chance: float = 0.3
## Probability a drop is armour rather than a weapon. Armour is the rarer find.
var armor_drop_chance: float = 0.18

var max_health: float = 100.0
var health: float = 100.0
## Flux awarded on death. Subclasses raise it in _init(); bosses pay far more.
## GDD 2.5 estimates ~200 Flux for Earth, which these values roughly hit. Mars
## pays considerably more than its ~500 estimate because it actually contains
## about 210 enemies, not the ~50 that estimate implies.
var flux_value: int = 3
## Seconds of stun left; while > 0 the enemy takes no actions.
var stun_left: float = 0.0

## Heroic/Legendary shield pool (T-0027), absorbed before health. GDD §2.8: an
## elemental shield takes BONUS damage from a matching-element weapon and only
## chip damage from a mismatched one. shield_element is the element that counters
## it; "Kinetic" means a plain (non-elemental) shield that any damage breaks.
var elemental_shield: float = 0.0
var max_elemental_shield: float = 0.0
var shield_element: String = "Kinetic"
## Element of the shot currently being absorbed, stamped by mark_damage_source
## just before take_damage (which weapons always call). Consumed - and reset to
## Kinetic - by absorb_shield, so each shield hit uses its own shot's element.
var incoming_element: String = "Kinetic"

## Shield damage multipliers vs an elemental shield (GDD §2.8).
const SHIELD_MATCH_MULT := 2.0     # matching element: breaks the shield fast
const SHIELD_MISMATCH_MULT := 0.35 # off-element / Kinetic: chip damage only

## Knockback displacement budget (Ground Slam), spent over PUSH_TIME seconds.
const PUSH_TIME := 0.3
var _push_velocity: Vector3 = Vector3.ZERO
var _push_time_left: float = 0.0
var _dead: bool = false
var _player: Node3D = null
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)


func _ready() -> void:
	add_to_group("enemy")
	_apply_difficulty()
	health = max_health
	_player = _find_player()
	_apply_external_model()
	if show_nameplate:
		_build_nameplate()


## Swap the primitive capsule for a real model if one has been dropped in at
## `assets/thirdparty/characters/<type>.{glb,gltf,tscn,scn}` (type = the scene
## basename, e.g. `rusher`, `shielded_brute`). The imported model must face -Z
## (forward) and stand ~1.8 m; pre-orient it in the import if not. The capsule
## collision is untouched - the model is visual only. Dormant until a file
## exists, so nothing changes today (mirrors the weapon pipeline).
func _apply_external_model() -> void:
	var base := "res://assets/thirdparty/characters/" + _to_snake(_enemy_type_name())
	for ext in ["glb", "gltf", "tscn", "scn"]:
		var path := "%s.%s" % [base, ext]
		if ResourceLoader.exists(path):
			var res := load(path)
			if res is PackedScene:
				add_child((res as PackedScene).instantiate())
				var placeholder := get_node_or_null("Mesh")
				if placeholder is Node3D:
					(placeholder as Node3D).visible = false
				return


## "ShieldedBrute" -> "shielded_brute", matching the scene file names.
func _to_snake(s: String) -> String:
	var out := ""
	for i in s.length():
		var c := s[i]
		if c >= "A" and c <= "Z":
			if i > 0:
				out += "_"
			out += c.to_lower()
		else:
			out += c
	return out


## Attach the floating name + health bar (and, for a shielded enemy, the shield
## bar + elemental shell). Runs after _apply_difficulty so the shield stats and
## element are already set.
func _build_nameplate() -> void:
	var plate := Node3D.new()
	plate.set_script(load(NAMEPLATE_SCENE_PATH))
	plate.setup(self)
	add_child(plate)


# --- nameplate data (overridable by subclasses) -----------------------------

## Human-readable name shown on the nameplate.
func display_name() -> String:
	return String(NAMES.get(_enemy_type_name(), _enemy_type_name()))


## "normal" or "boss" - bosses get a larger, gold nameplate.
func nameplate_tier() -> String:
	return "boss" if is_in_group("boss") else "normal"


## Local height the nameplate floats at (above the ~1.8 m capsule). Taller
## bosses override this so the plate clears their head.
func nameplate_head_y() -> float:
	return 2.15


## Radius of the elemental shield shell around the body. Bosses override it.
func nameplate_shell_radius() -> float:
	return 0.72


## Current / max shield shown on the nameplate. Defaults to the elemental pool;
## a boss with its own gate shield (the Shielded Brute) overrides these.
func nameplate_shield() -> float:
	return elemental_shield


func nameplate_shield_max() -> float:
	return max_elemental_shield


## Colour of the shield segment / shell: the element's colour for an elemental
## shield, a neutral shield-blue for a plain one.
func nameplate_shield_color() -> Color:
	if shield_element != "Kinetic":
		return Weapon.ELEMENT_COLORS.get(shield_element, Color(0.55, 0.75, 1.0))
	return Color(0.55, 0.75, 1.0)


## Scale this enemy for the selected difficulty tier (T-0027). Applied at
## spawn, before health is filled, so a Heroic Rusher is 225/225 rather than
## 150/225. Enemies spawned mid-mission get it too, since every one runs this.
func _apply_difficulty() -> void:
	var diff := get_node_or_null("/root/Difficulty")
	if diff == null:
		return
	max_health *= float(diff.enemy_health_mult())
	var fraction: float = diff.enemy_shield_fraction()
	if fraction > 0.0:
		elemental_shield = max_health * fraction
		max_elemental_shield = elemental_shield
		# Randomise which element counters this shield, so a single-element
		# loadout can't trivially melt every shielded enemy (GDD §2.8).
		shield_element = ["Solar", "Arc", "Void"][randi() % 3]


func _find_player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


## Re-resolve the player if it was freed; returns true when a target exists.
func _ensure_player() -> bool:
	if _player == null or not is_instance_valid(_player):
		_player = _find_player()
	return _player != null


func _halt_horizontal() -> void:
	velocity.x = 0.0
	velocity.z = 0.0


## Blind/stun this enemy (Flashbang T-0024, EMP Punch T-0025). Takes the longer
## of the current and new duration so a second application can't cut an
## existing one short.
func stun(seconds: float) -> void:
	stun_left = maxf(stun_left, seconds)


func is_stunned() -> bool:
	return stun_left > 0.0


## Shove this enemy a precise distance (Ground Slam, T-0025). Mirrors
## Guardian.apply_push(): a displacement budget spent over PUSH_TIME and
## applied with move_and_collide, so the travel is exactly offset.length()
## regardless of frame rate, and walls still stop it.
func apply_push(offset: Vector3) -> void:
	if _dead or offset == Vector3.ZERO:
		return
	_push_velocity = offset / PUSH_TIME
	_push_time_left = PUSH_TIME


func is_pushed() -> bool:
	return _push_time_left > 0.0


## Advance stun/knockback and hold the enemy while either is active. Returns
## true while the caller should skip the rest of its _physics_process -
## subclasses call this right after their `_dead` guard. Gravity still applies,
## so an affected enemy falls instead of hanging in mid-air.
func _tick_status(delta: float) -> bool:
	if stun_left <= 0.0 and _push_time_left <= 0.0:
		return false
	stun_left = maxf(0.0, stun_left - delta)
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_halt_horizontal()
	move_and_slide()
	if _push_time_left > 0.0:
		var push_dt: float = minf(delta, _push_time_left)
		move_and_collide(_push_velocity * push_dt)
		_push_time_left -= push_dt
	return true


## Horizontal steering direction toward a NavigationAgent3D waypoint. The
## navmesh sits slightly above the floor, so once the agent is horizontally on
## top of a waypoint the flattened delta collapses to ~0 and the enemy would
## stall every time it reached one. Fall back to heading straight at the final
## target in that case.
func _nav_dir(next: Vector3, fallback_target: Vector3) -> Vector3:
	var dir := next - global_position
	dir.y = 0.0
	if dir.length() < 0.15:
		dir = fallback_target - global_position
		dir.y = 0.0
	return dir


func _face(target: Vector3) -> void:
	var flat := Vector3(target.x, global_position.y, target.z)
	if global_position.distance_to(flat) > 0.05:
		look_at(flat, Vector3.UP)


## True when a world-space hit point lands in this enemy's head zone.
func is_headshot(world_point: Vector3) -> bool:
	return (world_point.y - global_position.y) >= HEAD_MIN_LOCAL_Y


## Incoming damage (from weapons T-0010). Dies + drops loot at 0 HP.
func take_damage(amount: float) -> void:
	if _dead:
		return
	amount = absorb_shield(amount)
	if amount <= 0.0:
		play_sfx("enemy_hit")
		return
	health = maxf(0.0, health - amount)
	play_sfx("enemy_hit")
	if health <= 0.0:
		_die()


## Spend the Heroic/Legendary shield pool first and return what gets through.
## Subclasses with their own damage handling (the bosses) call this too.
##
## Element (GDD §2.8): a matching-element shot does SHIELD_MATCH_MULT damage to
## the shield, a mismatched one only SHIELD_MISMATCH_MULT, so the raw damage a
## shot spends breaking the shield differs from the shield HP it removes. Any
## damage left after the shield breaks carries over to health at the normal 1x
## rate. A plain shield (shield_element Kinetic) uses 1x and behaves as before.
func absorb_shield(amount: float) -> float:
	if elemental_shield <= 0.0 or amount <= 0.0:
		incoming_element = "Kinetic"
		return amount
	var mult := 1.0
	if shield_element != "Kinetic":
		mult = SHIELD_MATCH_MULT if incoming_element == shield_element else SHIELD_MISMATCH_MULT
	incoming_element = "Kinetic"                 # consume this shot's element
	var shield_dmg := amount * mult
	var removed := minf(elemental_shield, shield_dmg)
	elemental_shield -= removed
	var raw_spent := removed / mult              # portion of `amount` used on the shield
	return maxf(0.0, amount - raw_spent)         # remainder passes to health at 1x


## Positional effect at this enemy (T-0034). No-ops without the autoload, so
## enemies stay testable in isolation.
func play_sfx(id: String) -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.play_sfx(id, global_position)


## What last damaged this enemy, for the EnemyKilled telemetry event (T-0026).
## Recorded on the enemy rather than logged by the weapon so that delayed
## deaths (the Ember Tyrant's 3 s sequence) and indirect kills (explosions,
## the Exploder taking itself out) still attribute correctly.
var last_hit_by: String = "Unknown"
var last_hit_headshot: bool = false


func mark_damage_source(source: String, headshot: bool = false, element: String = "Kinetic") -> void:
	last_hit_by = source
	last_hit_headshot = headshot
	incoming_element = element


func _die() -> void:
	_dead = true
	var where := global_position
	_log_kill()
	died.emit(where)
	_drop_loot(where)
	queue_free()


## Subclasses that override _die() (Exploder, Ember Tyrant) call this too.
func _log_kill() -> void:
	var tel := get_node_or_null("/root/Telemetry")
	if tel:
		tel.enemy_killed(_enemy_type_name(), last_hit_by, last_hit_headshot)
	var sm := get_node_or_null("/root/SaveManager")
	if sm and sm.has_method("add_flux"):
		sm.add_flux(flux_value)


## The subclass's class_name ("Rusher", "EmberTyrant", ...) for telemetry.
func _enemy_type_name() -> String:
	var script: Script = get_script() as Script
	if script == null:
		return "Enemy"
	var global_name := String(script.get_global_name())
	return global_name if global_name != "" else "Enemy"


## Spawn loot at the death position + a random offset within a 1 m radius
## (GDD §2.7). Uses `loot_scene` if set, else the shared loot_drop.tscn.
func _drop_loot(where: Vector3) -> void:
	# Not every kill drops. A forced rarity (boss guarantee) always does; a
	# regular enemy rolls against loot_chance so pickups stay meaningful.
	if loot_rarity_override == "" and randf() > loot_chance:
		return
	var drop: Node3D = null
	if loot_scene != null:
		drop = loot_scene.instantiate() as Node3D
	else:
		var packed := load(LOOT_SCENE_PATH)
		if packed != null:
			drop = packed.instantiate() as Node3D
	if drop == null:
		drop = _placeholder_loot()
	# Force rarity (e.g. boss Epic) before the drop enters the tree and rolls.
	if loot_rarity_override != "" and ("forced_rarity" in drop):
		drop.forced_rarity = loot_rarity_override
	# A minority of drops are armour instead of a weapon (unless the scene fixes
	# the category itself, e.g. a boss's guaranteed armour reward).
	if ("category" in drop) and drop.category == "weapon" and randf() < armor_drop_chance:
		drop.category = "armor"
	# Parent to the scene (not self - we are about to free) so the drop persists.
	var host := get_tree().current_scene
	if host == null:
		host = get_tree().root
	host.add_child(drop)
	var offset := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	if offset.length() > 1.0:
		offset = offset.normalized()
	drop.global_position = where + Vector3(0.0, 0.4, 0.0) + offset


## Fallback marker if the loot scene fails to load.
func _placeholder_loot() -> Node3D:
	var mi := MeshInstance3D.new()
	mi.name = "LootDropPlaceholder"
	mi.add_to_group("loot")
	var sphere := SphereMesh.new()
	sphere.radius = 0.2
	sphere.height = 0.4
	mi.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1)
	mat.emission_enabled = true
	mat.emission = Color(1, 1, 1)
	mat.emission_energy_multiplier = 2.0
	mi.material_override = mat
	return mi

extends Node

## Difficulty autoload (T-0027). Owns the modifier table, the current
## selection (persisted in SaveManager) and the queries the rest of the game
## makes at mission load.
##
## Tiers STACK: Legendary is Heroic plus a time limit and no shield regen. The
## card lists their modifiers separately, but a harder tier that dropped the
## easier tier's handicaps would be strictly easier in places, which no one
## would expect from a name like Legendary.
##
## GDD §7 restricts modifiers to missions 1 and 3 (Earth, Venus). Mars is left
## alone because its wave buff/debuff picks are already a difficulty dial and
## stacking the two would compound in ways neither system was balanced for.

signal difficulty_changed(id: String)

const NORMAL := "Normal"
const HEROIC := "Heroic"
const LEGENDARY := "Legendary"

## Legendary runs are limited to this many deaths; the run fails on the next one.
## Applies to every mission played on Legendary (see death_limit); 0 = unlimited.
const LEGENDARY_DEATH_LIMIT := 5

## The three missions, for the "cleared all on Legendary -> credits" check.
const ALL_MISSIONS := ["Earth", "Venus", "Mars"]

## Missions the FULL modifier set (enemy health, time limit, no shield regen)
## applies to (GDD §7: "Apply to Mission 1 & 3 only").
const APPLIES_TO := ["Earth", "Venus"]

## Missions where enemies gain the Heroic/Legendary SHIELD. Broader than
## APPLIES_TO: Mars fields shielded enemies too, but WITHOUT the +50% health -
## its wave buff/debuff picker is already its toughness dial, so only the shield
## is opted in (the health boost would compound with the wave picks). See
## enemy_shield_fraction.
const SHIELD_APPLIES_TO := ["Earth", "Venus", "Mars"]

const TIERS: Array[Dictionary] = [
	{
		"id": NORMAL,
		"title": "NORMAL",
		"blurb": "The intended experience.",
		"details": "No modifiers.",
		"health_mult": 1.0,
		"shield_fraction": 0.0,
		"time_limit": 0.0,
		"no_shield_regen": false,
		"color": Color(0.65, 0.72, 0.85),
	},
	{
		"id": HEROIC,
		"title": "HEROIC",
		"blurb": "Enemies are tougher and carry shields.",
		"details": "+50% enemy health.\nEnemies gain a shield worth 25% of their health,\nwhich absorbs damage before it reaches them.",
		"health_mult": 1.5,
		"shield_fraction": 0.25,
		"time_limit": 0.0,
		"no_shield_regen": false,
		"color": Color(1.0, 0.72, 0.30),
	},
	{
		"id": LEGENDARY,
		"title": "LEGENDARY",
		"blurb": "Heroic, against the clock, with no second wind.",
		"details": "Everything in Heroic.\n10 minute time limit - the mission fails at zero.\nYour shield never recharges.",
		"health_mult": 1.5,
		"shield_fraction": 0.25,
		"time_limit": 600.0,
		"no_shield_regen": true,
		"color": Color(1.0, 0.42, 0.38),
	},
]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


# --- selection --------------------------------------------------------------

## The selected tier, clamped DOWN to the best tier actually unlocked for
## `mission_id` (Legendary is per-mission now), so a stale/higher pick can't leak in.
func current(mission_id: String = "") -> String:
	if mission_id == "":
		mission_id = current_mission()
	var sm := get_node_or_null("/root/SaveManager")
	var id := String(sm.data.get("selected_difficulty", NORMAL)) if sm else NORMAL
	var order := [NORMAL, HEROIC, LEGENDARY]
	for r in range(order.find(id), -1, -1):
		if is_unlocked(order[r], mission_id):
			return order[r]
	return NORMAL


func select(id: String, mission_id: String = "") -> bool:
	if mission_id == "":
		mission_id = current_mission()
	if not is_unlocked(id, mission_id) or tier_of(id).is_empty():
		return false
	var sm := get_node_or_null("/root/SaveManager")
	if sm:
		sm.data["selected_difficulty"] = id
		sm.save_game()
	difficulty_changed.emit(id)
	return true


## NORMAL: always. HEROIC: global - unlocked once Venus is cleared (any difficulty).
## LEGENDARY: PER-MISSION - unlocked once THAT mission has been beaten on Heroic.
func is_unlocked(id: String, mission_id: String = "") -> bool:
	if id == NORMAL:
		return true
	var sm := get_node_or_null("/root/SaveManager")
	if sm == null:
		return false
	if id == HEROIC:
		var unlocks: Dictionary = sm.data.get("difficulty_unlocks", {})
		return bool(unlocks.get(HEROIC, false))
	if id == LEGENDARY:
		if mission_id == "":
			mission_id = current_mission()
		return mission_heroic_cleared(mission_id)
	return false


## True once `mission_id` has been completed on Heroic (or Legendary).
func mission_heroic_cleared(mission_id: String) -> bool:
	var sm := get_node_or_null("/root/SaveManager")
	if sm == null:
		return false
	var hc: Dictionary = sm.data.get("heroic_cleared", {})
	return bool(hc.get(mission_id, false))


func tier_of(id: String) -> Dictionary:
	for t in TIERS:
		if String(t["id"]) == id:
			return t
	return {}


## The tier actually in force for `mission_id` - Normal outside Earth/Venus.
func active_tier(mission_id: String) -> Dictionary:
	if not APPLIES_TO.has(mission_id):
		return tier_of(NORMAL)
	return tier_of(current(mission_id))


# --- queries used at mission load ------------------------------------------

## Mission the enemies/player belong to. Read from whichever mission driver is
## in the scene, so a single enemy doesn't need to be told.
func current_mission() -> String:
	var scene := _scene_mission()
	return scene if APPLIES_TO.has(scene) else ""


## Raw scene/mission name, unfiltered by APPLIES_TO (used by the shield query,
## which opts in a wider set of missions - see SHIELD_APPLIES_TO).
func _scene_mission() -> String:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return ""
	return String(tree.current_scene.name)


func enemy_health_mult() -> float:
	return float(active_tier(current_mission()).get("health_mult", 1.0))


## Shield fraction for the CURRENT scene. Unlike the other queries this uses
## SHIELD_APPLIES_TO, so Mars enemies shield up on Heroic/Legendary even though
## the mission takes none of the tier's other modifiers (its health stays base).
func enemy_shield_fraction() -> float:
	var scene := _scene_mission()
	if not SHIELD_APPLIES_TO.has(scene):
		return 0.0
	return float(tier_of(current(scene)).get("shield_fraction", 0.0))


func time_limit() -> float:
	return float(active_tier(current_mission()).get("time_limit", 0.0))


## Time limit (s) for the CURRENT scene's effective tier, for ANY of the three
## missions - unlike time_limit(), which is APPLIES_TO-gated (Earth/Venus). Lets
## Mars carry the Legendary clock WITHOUT the tier's other modifiers (its health
## stays base). Legendary = the tier default (600 s); 0 otherwise. mission_timer
## caps it per-scene (all three missions = 5 min via time_limit_override).
func scene_time_limit() -> float:
	var scene := _scene_mission()
	if not ALL_MISSIONS.has(scene):
		return 0.0
	return float(tier_of(current(scene)).get("time_limit", 0.0))


## Whether the PLAYER's shield is barred from recharging (Legendary "no second
## wind"). Scene-based like scene_time_limit, so it applies on ALL three missions -
## Legendary Mars stops shield regen too, without taking the tier's other modifiers.
## (time_limit()-style APPLIES_TO gating left Mars regenerating on Legendary - the
## same class of bug as the Mars shields / Mars timer.)
func no_shield_regen() -> bool:
	var scene := _scene_mission()
	if not ALL_MISSIONS.has(scene):
		return false
	return bool(tier_of(current(scene)).get("no_shield_regen", false))


## Max deaths allowed on the CURRENT mission before the run fails; 0 = unlimited.
## Legendary only, and on any of the three missions (uses the raw scene name, so
## it covers Mars). The Guardian counts deaths per run and calls this each death.
func death_limit() -> int:
	var scene := _scene_mission()
	if not ALL_MISSIONS.has(scene):
		return 0
	return LEGENDARY_DEATH_LIMIT if current(scene) == LEGENDARY else 0


## Effective tier for the CURRENT scene, regardless of APPLIES_TO - Normal in the
## hub / anywhere that isn't one of the three missions. Used by systems that scale
## with the tier the mission is actually being played on (e.g. loot rarity).
func scene_tier() -> String:
	var scene := _scene_mission()
	if not ALL_MISSIONS.has(scene):
		return NORMAL
	return current(scene)


## Whether RANDOM loot may roll the gold Exotic in the current mission. Bosses'
## guaranteed Exotic drops are separate and always happen (see boss_exotic_count):
##   Normal    - never (on Normal the ONLY Exotic is the Venus boss's guaranteed one);
##   Heroic    - Mars and Venus only;
##   Legendary - all three missions.
func exotic_loot_allowed() -> bool:
	var scene := _scene_mission()
	if not ALL_MISSIONS.has(scene):
		return false
	match current(scene):
		LEGENDARY:
			return true
		HEROIC:
			return scene == "Mars" or scene == "Venus"
		_:
			return false


## How many Exotic weapons the CURRENT mission's boss drops, gated by the same
## mission+tier rule as exotic_loot_allowed and scaled by difficulty (0 = this
## boss drops no Exotic at this tier):
##   Normal    - Venus boss only, 1;
##   Heroic    - Mars and Venus bosses, 2 each;
##   Legendary - all three bosses, 3 each.
func boss_exotic_count() -> int:
	var scene := _scene_mission()
	if not ALL_MISSIONS.has(scene):
		return 0
	match current(scene):
		LEGENDARY:
			return 3
		HEROIC:
			return 2 if (scene == "Mars" or scene == "Venus") else 0
		_:
			return 1 if scene == "Venus" else 0


## True once Earth, Venus AND Mars have each been beaten on Legendary. Drives the
## end-game credits roll (the last of the three to fall triggers it, in any order).
func all_missions_legendary_cleared() -> bool:
	var sm := get_node_or_null("/root/SaveManager")
	if sm == null:
		return false
	var lc: Dictionary = sm.data.get("legendary_cleared", {})
	for m in ALL_MISSIONS:
		if not bool(lc.get(m, false)):
			return false
	return true


## Called when a mission completes, to record progression toward the tier unlocks:
##  - clearing a mission on Heroic/Legendary unlocks THAT mission's Legendary;
##  - clearing a mission on Legendary records it for the all-three credits roll;
##  - clearing Venus (on ANY difficulty) opens Heroic on every mission.
func unlock_after(mission_id: String) -> void:
	var sm := get_node_or_null("/root/SaveManager")
	if sm == null:
		return
	# The tier this mission was actually played on. Gate on SHIELD_APPLIES_TO, not
	# APPLIES_TO: Mars runs a real Heroic (shielded enemies) even though it takes
	# none of the tier's other modifiers, so a Heroic Mars clear must still unlock
	# Mars Legendary. (This was the bug: Mars fell into the NORMAL branch here, so
	# beating it on Heroic never recorded the clear.)
	var played := current(mission_id) if SHIELD_APPLIES_TO.has(mission_id) else NORMAL
	if played == HEROIC or played == LEGENDARY:
		var hc: Dictionary = sm.data.get("heroic_cleared", {})
		hc[mission_id] = true
		sm.data["heroic_cleared"] = hc
	if played == LEGENDARY:
		var lc: Dictionary = sm.data.get("legendary_cleared", {})
		lc[mission_id] = true
		sm.data["legendary_cleared"] = lc
	if mission_id == "Venus":
		var unlocks: Dictionary = sm.data.get("difficulty_unlocks", {})
		unlocks[HEROIC] = true
		sm.data["difficulty_unlocks"] = unlocks
	sm.save_game()

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

## Missions the modifiers apply to (GDD §7: "Apply to Mission 1 & 3 only").
const APPLIES_TO := ["Earth", "Venus"]

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

func current() -> String:
	var sm := get_node_or_null("/root/SaveManager")
	var id := String(sm.data.get("selected_difficulty", NORMAL)) if sm else NORMAL
	# A save that was made while a tier was unlocked, then reset, must not keep
	# that tier selected.
	return id if is_unlocked(id) else NORMAL


func select(id: String) -> bool:
	if not is_unlocked(id) or tier_of(id).is_empty():
		return false
	var sm := get_node_or_null("/root/SaveManager")
	if sm:
		sm.data["selected_difficulty"] = id
		sm.save_game()
	difficulty_changed.emit(id)
	return true


## Heroic and Legendary unlock once Venus is complete (GDD §7).
func is_unlocked(id: String) -> bool:
	if id == NORMAL:
		return true
	var sm := get_node_or_null("/root/SaveManager")
	if sm == null:
		return false
	var unlocks: Dictionary = sm.data.get("difficulty_unlocks", {})
	return bool(unlocks.get(id, false))


func tier_of(id: String) -> Dictionary:
	for t in TIERS:
		if String(t["id"]) == id:
			return t
	return {}


## The tier actually in force for `mission_id` - Normal outside Earth/Venus.
func active_tier(mission_id: String) -> Dictionary:
	if not APPLIES_TO.has(mission_id):
		return tier_of(NORMAL)
	return tier_of(current())


# --- queries used at mission load ------------------------------------------

## Mission the enemies/player belong to. Read from whichever mission driver is
## in the scene, so a single enemy doesn't need to be told.
func current_mission() -> String:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return ""
	var scene := String(tree.current_scene.name)
	return scene if APPLIES_TO.has(scene) else ""


func enemy_health_mult() -> float:
	return float(active_tier(current_mission()).get("health_mult", 1.0))


func enemy_shield_fraction() -> float:
	return float(active_tier(current_mission()).get("shield_fraction", 0.0))


func time_limit() -> float:
	return float(active_tier(current_mission()).get("time_limit", 0.0))


func no_shield_regen() -> bool:
	return bool(active_tier(current_mission()).get("no_shield_regen", false))


## Called when a mission completes, to open the tiers up after Venus.
func unlock_after(mission_id: String) -> void:
	if mission_id != "Venus":
		return
	var sm := get_node_or_null("/root/SaveManager")
	if sm == null:
		return
	var unlocks: Dictionary = sm.data.get("difficulty_unlocks", {})
	unlocks[HEROIC] = true
	unlocks[LEGENDARY] = true
	sm.data["difficulty_unlocks"] = unlocks
	sm.save_game()

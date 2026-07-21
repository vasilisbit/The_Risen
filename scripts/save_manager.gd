extends Node
## SaveManager (autoload): JSON persistence for The Risen.
## Schema is aligned verbatim with TDD v2.0 §4.7 (= GDD §6.3).
## File: user://risen_save_01.json (FileAccess + JSON).

const SAVE_PATH := "user://risen_save_01.json"

## Mission order for unlock gating - each unlocks when the previous completes.
const MISSION_ORDER: Array[String] = ["Earth", "Mars", "Venus"]

## Flux paid for finishing a mission, on top of per-kill rewards. Tuned so a
## clean Earth run lands near the ~200 Flux GDD 2.5 expects, which is roughly
## two vendor upgrades.
const COMPLETION_FLUX := {"Earth": 60, "Mars": 100, "Venus": 150}

## The one weapon a new Guardian starts with. Everything else is earned from
## loot or bought - you no longer begin holding all four (see equipped_weapons).
const STARTER_WEAPON := {"id": "starter_ar", "name": "Auto Rifle", "rarity": "Common"}
## How many weapons can be carried into a mission at once (weapon_1..weapon_3).
const MAX_EQUIPPED_WEAPONS := 3
## The three armour slots, keyed by the item name the loot roller produces.
const ARMOR_SLOTS := ["Helmet", "Chest Plate", "Gauntlets"]
## Passive damage reduction granted by an equipped piece, by rarity. Summed
## across the three slots and clamped in take_damage - all-Exotic is ~21%.
const ARMOR_REDUCTION := {"Common": 0.02, "Rare": 0.035, "Epic": 0.05, "Exotic": 0.07}

signal game_loaded
signal game_saved
## Emitted whenever Flux is earned, so HUDs can update without polling.
signal flux_changed(total: int)
## Emitted whenever the equipped weapons or armour change, so the WeaponManager
## can rebuild and the Guardian can refresh its armour bonus.
signal loadout_changed

var data: Dictionary = {}


func _ready() -> void:
	# Autoload runs before the hub scene, so this covers "load on hub start".
	load_game()


## A fresh default save (first launch). Field names match TDD §4.7 exactly.
func _default_data() -> Dictionary:
	return {
		"player_level": 1,
		"current_xp": 0,
		"selected_class": "Assault",
		# False until the player picks on the class-selection screen (T-0022).
		# selected_class already has a value, so this is what marks it a default
		# rather than a real choice. Backfilled into older saves on load.
		"class_chosen": false,
		# You start with one weapon; the rest are earned from loot or the vendor.
		"owned_weapons": [STARTER_WEAPON.duplicate()],
		"owned_armor": [],
		# Ids from owned_weapons that are carried into a mission (weapon slots 1-3).
		"equipped_weapons": [STARTER_WEAPON["id"]],
		# Slot name -> owned_armor id. Empty until the player equips a piece.
		"equipped_armor": {},
		"flux_currency": 0,
		"mission_completion_flags": {"Earth": false, "Mars": false, "Venus": false},
		"difficulty_unlocks": {"Heroic": false, "Legendary": false},
		# Selected modifier tier (T-0027); unlocks after Venus.
		"selected_difficulty": "Normal",
		# Most recent mission deployed to - drives the hub window planet (T-0028).
		"last_mission": "Earth",
		"total_kills": 0,
		"total_deaths": 0,
		"total_playtime": 0.0,
		# Linear 0..1 per audio bus (T-0034). Backfilled into older saves.
		"audio_volumes": {"Master": 1.0, "Music": 1.0, "SFX": 1.0},
	}


## Load the save, or create defaults on first launch / unreadable / corrupt file.
## Missing keys are backfilled from defaults so older saves stay compatible.
func load_game() -> void:
	var defaults := _default_data()
	if not FileAccess.file_exists(SAVE_PATH):
		data = defaults
		save_game()
		game_loaded.emit()
		return

	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		push_warning("SaveManager: cannot open save; using defaults.")
		data = defaults
		game_loaded.emit()
		return
	var text := f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SaveManager: corrupt save; using defaults.")
		data = defaults
		game_loaded.emit()
		return

	data = defaults
	for key in (parsed as Dictionary):
		data[key] = (parsed as Dictionary)[key]
	_normalize_loadout()
	game_loaded.emit()


## Repair the loadout after a load so it is always playable: at least one owned
## weapon, every equipped id actually owned, and never zero equipped. Older saves
## (pre-loadout) and hand-edited files pass through here too.
func _normalize_loadout() -> void:
	var owned: Array = data.get("owned_weapons", [])
	if owned.is_empty():
		owned = [STARTER_WEAPON.duplicate()]
	data["owned_weapons"] = owned
	var owned_ids := {}
	for w in owned:
		if typeof(w) == TYPE_DICTIONARY:
			owned_ids[w.get("id", "")] = true
			# Backfill the mods array so pre-mod saves are managed uniformly.
			if not w.has("mods"):
				w["mods"] = []
	var equipped: Array = data.get("equipped_weapons", [])
	var clean: Array = []
	for id in equipped:
		if owned_ids.has(id) and not clean.has(id) and clean.size() < MAX_EQUIPPED_WEAPONS:
			clean.append(id)
	if clean.is_empty():
		clean.append(owned[0].get("id", ""))
	data["equipped_weapons"] = clean
	# Drop any equipped-armour reference whose item is no longer owned.
	var armor_ids := {}
	for a in data.get("owned_armor", []):
		if typeof(a) == TYPE_DICTIONARY:
			armor_ids[a.get("id", "")] = true
	var eq_armor: Dictionary = data.get("equipped_armor", {})
	for slot in eq_armor.keys():
		if not armor_ids.has(eq_armor[slot]):
			eq_armor.erase(slot)
	data["equipped_armor"] = eq_armor


## Write the current data to disk as pretty JSON. Returns true on success.
func save_game() -> bool:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("SaveManager: cannot write save to %s" % SAVE_PATH)
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	game_saved.emit()
	return true


## Award Flux. Returns the new balance. Kills and mission completions are the
## only sources - before this, flux_currency was spent by the vendor but never
## earned, so the shop was unusable on a fresh save.
func add_flux(amount: int) -> int:
	if amount <= 0:
		return int(data.get("flux_currency", 0))
	var total := int(data.get("flux_currency", 0)) + amount
	data["flux_currency"] = total
	flux_changed.emit(total)
	return total


## Mark a mission complete and auto-save (called on return to the hub).
func complete_mission(mission: String) -> void:
	var flags: Dictionary = data.get("mission_completion_flags", {})
	flags[mission] = true
	data["mission_completion_flags"] = flags
	add_flux(int(COMPLETION_FLUX.get(mission, 0)))
	save_game()
	# Clearing Venus opens the Heroic/Legendary modifiers (T-0027, GDD §7).
	var diff := get_node_or_null("/root/Difficulty")
	if diff and diff.has_method("unlock_after"):
		diff.unlock_after(mission)


## True if a mission is playable: the first one, or the previous is complete.
func is_mission_unlocked(mission: String) -> bool:
	var idx := MISSION_ORDER.find(mission)
	if idx <= 0:
		return true
	var prev: String = MISSION_ORDER[idx - 1]
	var flags: Dictionary = data.get("mission_completion_flags", {})
	return bool(flags.get(prev, false))


## Record the player's class choice (T-0022) and persist it.
func select_class(class_name_: String) -> void:
	data["selected_class"] = class_name_
	data["class_chosen"] = true
	save_game()


## True once the player has actually been through the class picker.
func has_chosen_class() -> bool:
	return bool(data.get("class_chosen", false))


## Start a brand-new save (defaults) and persist it.
func reset() -> void:
	data = _default_data()
	save_game()


# --- loadout -----------------------------------------------------------------

func weapon_by_id(id: String) -> Dictionary:
	for w in data.get("owned_weapons", []):
		if typeof(w) == TYPE_DICTIONARY and w.get("id", "") == id:
			return w
	return {}


func armor_by_id(id: String) -> Dictionary:
	for a in data.get("owned_armor", []):
		if typeof(a) == TYPE_DICTIONARY and a.get("id", "") == id:
			return a
	return {}


func is_weapon_equipped(id: String) -> bool:
	return (data.get("equipped_weapons", []) as Array).has(id)


## The full item dicts (not just ids) for the carried weapons, in slot order.
func equipped_weapon_items() -> Array:
	var items: Array = []
	for id in data.get("equipped_weapons", []):
		var w := weapon_by_id(id)
		if not w.is_empty():
			items.append(w)
	return items


## Equip an owned weapon into a free slot. When all three slots are full the
## oldest is dropped, so equipping always succeeds and feels responsive.
## Returns true if the loadout changed.
func equip_weapon(id: String) -> bool:
	if weapon_by_id(id).is_empty() or is_weapon_equipped(id):
		return false
	var equipped: Array = data.get("equipped_weapons", [])
	if equipped.size() >= MAX_EQUIPPED_WEAPONS:
		equipped.pop_front()
	equipped.append(id)
	data["equipped_weapons"] = equipped
	save_game()
	loadout_changed.emit()
	return true


## Unequip a weapon, unless it is the last one - the Guardian always carries at
## least one. Returns true if the loadout changed.
func unequip_weapon(id: String) -> bool:
	var equipped: Array = data.get("equipped_weapons", [])
	if not equipped.has(id) or equipped.size() <= 1:
		return false
	equipped.erase(id)
	data["equipped_weapons"] = equipped
	save_game()
	loadout_changed.emit()
	return true


## Equip an armour piece into its slot (Helmet/Chest Plate/Gauntlets), replacing
## whatever occupied it. Returns true if the loadout changed.
func equip_armor(id: String) -> bool:
	var item := armor_by_id(id)
	if item.is_empty():
		return false
	var slot := String(item.get("name", ""))
	if not ARMOR_SLOTS.has(slot):
		return false
	var eq: Dictionary = data.get("equipped_armor", {})
	if eq.get(slot, "") == id:
		return false
	eq[slot] = id
	data["equipped_armor"] = eq
	save_game()
	loadout_changed.emit()
	return true


func unequip_armor(slot: String) -> bool:
	var eq: Dictionary = data.get("equipped_armor", {})
	if not eq.has(slot):
		return false
	eq.erase(slot)
	data["equipped_armor"] = eq
	save_game()
	loadout_changed.emit()
	return true


func is_armor_equipped(id: String) -> bool:
	return id in (data.get("equipped_armor", {}) as Dictionary).values()


# --- weapon mods -------------------------------------------------------------

## Number of mod slots a weapon has, from its rarity (Weapon.MOD_SLOTS).
func weapon_mod_slots(id: String) -> int:
	var w := weapon_by_id(id)
	if w.is_empty():
		return 0
	return int(Weapon.MOD_SLOTS.get(String(w.get("rarity", "Common")), 0))


## Install a mod on a weapon, paying its Flux cost. Enforces the slot count, one
## element mod per weapon, and no duplicates. Returns a status string (also shown
## in the inventory). Crafting-from-Flux stands in for the GDD's blueprint craft
## until blueprints exist.
func install_mod(weapon_id: String, mod_id: String) -> String:
	var w := weapon_by_id(weapon_id)
	if w.is_empty():
		return "Unknown weapon"
	var mod: Dictionary = Weapon.MODS.get(mod_id, {})
	if mod.is_empty():
		return "Unknown mod"
	var mods: Array = w.get("mods", [])
	if mods.has(mod_id):
		return "Already installed"
	if mods.size() >= weapon_mod_slots(weapon_id):
		return "No free mod slot"
	if mod.has("element") and _has_element_mod(mods):
		return "One element mod per weapon"
	var cost := int(mod.get("cost", 0))
	if int(data.get("flux_currency", 0)) < cost:
		return "Need %d Flux" % cost
	data["flux_currency"] = int(data.get("flux_currency", 0)) - cost
	mods.append(mod_id)
	w["mods"] = mods
	save_game()
	flux_changed.emit(int(data.get("flux_currency", 0)))
	loadout_changed.emit()
	return "Installed %s" % String(mod.get("name", mod_id))


## Remove an installed mod (no Flux refund). Returns true if it changed.
func remove_mod(weapon_id: String, mod_id: String) -> bool:
	var w := weapon_by_id(weapon_id)
	if w.is_empty():
		return false
	var mods: Array = w.get("mods", [])
	if not mods.has(mod_id):
		return false
	mods.erase(mod_id)
	w["mods"] = mods
	save_game()
	loadout_changed.emit()
	return true


func _has_element_mod(mods: Array) -> bool:
	for id in mods:
		if Weapon.MODS.get(id, {}).has("element"):
			return true
	return false


## Total passive damage reduction from the currently equipped armour, summed
## across slots. The Guardian folds this into take_damage.
func armor_reduction_total() -> float:
	var total := 0.0
	var eq: Dictionary = data.get("equipped_armor", {})
	for slot in eq:
		var item := armor_by_id(String(eq[slot]))
		if not item.is_empty():
			total += float(ARMOR_REDUCTION.get(String(item.get("rarity", "Common")), 0.0))
	return total

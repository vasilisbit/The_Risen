class_name LootDrop
extends Area3D

## Loot drop (T-0011). Rolls a rarity on spawn (GDD §2.7: Common 50 / Rare 35 /
## Epic 15 / Exotic 0 for MVP), shows a rarity-coloured spinning pickup with a
## 2 m proximity Area3D and a "Press E" prompt, and on interact adds the item to
## SaveManager.owned_weapons and frees itself. Guarded against double-pickup.

const RARITY_COLORS := {
	"Common": Color(1.0, 1.0, 1.0),
	"Rare": Color(0.2, 0.5, 1.0),
	"Epic": Color(0.6, 0.25, 1.0),
	"Exotic": Color(1.0, 0.8, 0.1),
}
const WEAPON_KINDS := ["Auto Rifle", "Shotgun", "Sniper", "Hand Cannon"]
## Armour slots (GDD §3.4 boss reward: chest, helmet, gloves).
const ARMOR_KINDS := ["Chest Plate", "Helmet", "Gauntlets"]
const PICKUP_RADIUS := 2.0

## When non-empty (and a known rarity), skips the roll and forces this rarity -
## used for guaranteed boss drops. Set before the node enters the tree.
@export var forced_rarity: String = ""
## "weapon" (default) or "armor" - decides the kind pool and which SaveManager
## inventory the pickup lands in. Set before the node enters the tree.
@export var category: String = "weapon"
## Force one specific item name instead of rolling one. Set before tree entry.
@export var forced_kind: String = ""

var rarity: String = "Common"
var kind: String = "Auto Rifle"

var _player_in_range: bool = false
var _picked: bool = false
var _visual: Node3D
var _prompt: Label3D
var _spin: float = 0.0

const CHEST_PATH := "res://assets/thirdparty/Sci-Fi Essentials Kit[Standard]/glTF/Prop_Chest.gltf"
## Generated weapon models (T-0041) - a weapon drop shows the actual gun spinning
## on its rarity beacon instead of a chest.
const WEAPON_MODEL_DIR := "res://assets/generated/weapons/"
## Generated armour models (T-0042) - an armour drop now shows the actual plate
## (chest/helmet/gauntlets) instead of the loot chest. Kind -> GLB basename.
const ARMOR_MODEL_DIR := "res://assets/generated/armor/"
const ARMOR_FILE := {"Chest Plate": "chest", "Helmet": "helmet", "Gauntlets": "gauntlets"}


func _ready() -> void:
	add_to_group("loot")
	collision_mask = 1                     # detect the player (world layer 1)
	roll_rarity()
	_build_visual()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


## Rarity weights per difficulty tier (GDD §2.7, extended for T-0027). The gold
## Exotic is the payoff for playing harder: near-absent on Normal, uncommon on
## Heroic, and genuinely likely on Legendary. Weights per tier need not sum to 100.
## Weights (relative, per tier - they need not sum to 100). Epic climbs with the
## tier so harder runs feel richer, but the gold Exotic from a NORMAL ENEMY is
## deliberately a lottery: ~0.1 % on Heroic, ~0.2 % on Legendary (and gated to the
## eligible missions - see _tier_weights). Exotic is really meant to come from
## bosses; a trash-mob Exotic is a rare thrill, not a farm. Normal never rolls one.
const RARITY_WEIGHTS := {
	"Normal":    {"Common": 550, "Rare": 330, "Epic": 120, "Exotic": 0},
	"Heroic":    {"Common": 430, "Rare": 330, "Epic": 240, "Exotic": 1},
	"Legendary": {"Common": 300, "Rare": 340, "Epic": 358, "Exotic": 2},
}
const RARITY_ORDER := ["Common", "Rare", "Epic", "Exotic"]


## Roll rarity from the weight table for the tier the mission is being played on
## (Normal in the hub / unknown). A forced rarity (boss drops) skips the roll.
func roll_rarity() -> void:
	if forced_rarity != "" and RARITY_COLORS.has(forced_rarity):
		rarity = forced_rarity
		kind = _roll_kind()
		return
	rarity = _roll_weighted(_tier_weights())
	kind = _roll_kind()


## Weight table for the current difficulty tier, defaulting to Normal. The gold
## Exotic is additionally gated by mission+tier: it is dropped to weight 0 unless
## Difficulty says random Exotics are allowed here (Normal: nowhere - the Venus
## boss's guaranteed Exotic is the only Normal one; Heroic: Mars/Venus; Legendary:
## all three). Boss-forced drops bypass this whole roll (forced_rarity).
func _tier_weights() -> Dictionary:
	var tier := "Normal"
	var exotic_ok := false
	var diff := get_node_or_null("/root/Difficulty")
	if diff:
		if diff.has_method("scene_tier"):
			tier = String(diff.scene_tier())
		if diff.has_method("exotic_loot_allowed"):
			exotic_ok = bool(diff.exotic_loot_allowed())
	var w: Dictionary = (RARITY_WEIGHTS.get(tier, RARITY_WEIGHTS["Normal"]) as Dictionary).duplicate()
	if not exotic_ok:
		w["Exotic"] = 0
	return w


## Pick a rarity from a {rarity: weight} table.
func _roll_weighted(weights: Dictionary) -> String:
	var total := 0
	for k in weights:
		total += int(weights[k])
	var r := randi_range(1, maxi(1, total))
	var acc := 0
	for k in RARITY_ORDER:
		acc += int(weights.get(k, 0))
		if r <= acc:
			return k
	return "Common"


func _roll_kind() -> String:
	if forced_kind != "":
		return forced_kind
	var pool: Array = ARMOR_KINDS if category == "armor" else WEAPON_KINDS
	return pool[randi() % pool.size()]


func _build_visual() -> void:
	var c: Color = RARITY_COLORS.get(rarity, Color.WHITE)
	# A drop shows its ACTUAL generated model - the gun for weapons (T-0041), the
	# armour plate for armour (T-0042). A missing model falls back to the loot chest,
	# then to a coloured box.
	var model := _load_weapon_model() if category != "armor" else _load_armor_model()
	if model != null:
		_visual = model
		if category == "armor":
			_fit_to(_visual, 0.55)                    # armour pieces vary in size - normalise
		else:
			_visual.scale = Vector3.ONE * 0.9
		_visual.rotation = Vector3(0.35, 0.0, 0.25)   # cant it so it reads in the air
		_visual.position = Vector3(0, 0.55, 0)
	else:
		var scene := load(CHEST_PATH)
		if scene is PackedScene:
			_visual = (scene as PackedScene).instantiate() as Node3D
			_visual.scale = Vector3.ONE * 0.5
		else:
			var mi := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.35, 0.35, 0.35)
			mi.mesh = box
			var mat := StandardMaterial3D.new()
			mat.albedo_color = c
			mat.emission_enabled = true
			mat.emission = c
			mat.emission_energy_multiplier = 2.5
			mi.material_override = mat
			_visual = mi
		_visual.position = Vector3(0, 0.28, 0)
	add_child(_visual)

	# Rarity beacon so drops read at range: a coloured point light and a glowing
	# disc on the ground under the chest.
	var light := OmniLight3D.new()
	light.light_color = c
	light.light_energy = 2.2
	light.omni_range = 3.0
	light.position = Vector3(0, 0.6, 0)
	add_child(light)
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.4
	cyl.bottom_radius = 0.4
	cyl.height = 0.02
	disc.mesh = cyl
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(c.r, c.g, c.b, 0.5)
	dm.emission_enabled = true
	dm.emission = c
	dm.emission_energy_multiplier = 2.0
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc.material_override = dm
	disc.position = Vector3(0, 0.02, 0)
	add_child(disc)

	# Collision is provided by the scene (loot_drop.tscn -> PickupShape). If this
	# is instantiated as a bare Area3D, create the pickup shape as a fallback so
	# it can still detect the player.
	if get_node_or_null("PickupShape") == null:
		var col := CollisionShape3D.new()
		col.name = "PickupShape"
		var sph := SphereShape3D.new()
		sph.radius = PICKUP_RADIUS
		col.shape = sph
		add_child(col)

	_prompt = Label3D.new()
	_prompt.text = "Press E  [%s]" % rarity
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.position = Vector3(0, 1.0, 0)
	_prompt.visible = false
	add_child(_prompt)


## Load the generated GLB for this weapon kind, or null if it isn't present yet.
func _load_weapon_model() -> Node3D:
	var file := kind.to_lower().replace(" ", "_")
	var path := "%s%s.glb" % [WEAPON_MODEL_DIR, file]
	if not ResourceLoader.exists(path):
		return null
	var res := load(path)
	return (res as PackedScene).instantiate() as Node3D if res is PackedScene else null


## Load the generated GLB for this armour kind (chest/helmet/gauntlets), or null.
func _load_armor_model() -> Node3D:
	var file: String = ARMOR_FILE.get(kind, "")
	if file == "":
		return null
	var path := "%s%s.glb" % [ARMOR_MODEL_DIR, file]
	if not ResourceLoader.exists(path):
		return null
	var res := load(path)
	return (res as PackedScene).instantiate() as Node3D if res is PackedScene else null


## Uniformly scale `node` so its largest mesh dimension is `target` metres, so
## differently-sized armour pieces all read at a consistent pickup size.
func _fit_to(node: Node3D, target: float) -> void:
	var acc := AABB()
	var first := true
	for n in node.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var a: AABB = mi.transform * mi.get_aabb()
		if first:
			acc = a; first = false
		else:
			acc = acc.merge(a)
	if first:
		return
	var m: float = maxf(acc.size.x, maxf(acc.size.y, acc.size.z))
	if m > 0.001:
		node.scale = Vector3.ONE * (target / m)


func _process(delta: float) -> void:
	if _visual:
		_spin += delta
		_visual.rotation.y = _spin * 1.5


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		if _prompt:
			_prompt.visible = true


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		if _prompt:
			_prompt.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if _player_in_range and not _picked and event.is_action_pressed("interact"):
		pickup()


## Add to inventory + free. Idempotent (double-E spam picks up once).
func pickup() -> void:
	if _picked:
		return
	_picked = true
	var sm := get_node_or_null("/root/SaveManager")
	if sm:
		var slot := "owned_armor" if category == "armor" else "owned_weapons"
		var owned: Array = sm.data.get(slot, [])
		var item := {"id": "loot_%d" % Time.get_ticks_usec(), "name": kind, "rarity": rarity}
		# Weapons roll individual stats within their rarity band, so two of the
		# same weapon and rarity still differ.
		if category != "armor":
			item["mods"] = []
			item["rolls"] = Weapon.roll_stats()
		owned.append(item)
		sm.data[slot] = owned
		sm.save_game()
	var tel := get_node_or_null("/root/Telemetry")
	if tel:
		tel.loot_picked(kind, rarity)
	queue_free()

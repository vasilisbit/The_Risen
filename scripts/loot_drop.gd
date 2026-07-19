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
const PICKUP_RADIUS := 2.0

## When non-empty (and a known rarity), skips the roll and forces this rarity —
## used for guaranteed boss drops. Set before the node enters the tree.
@export var forced_rarity: String = ""

var rarity: String = "Common"
var kind: String = "Auto Rifle"

var _player_in_range: bool = false
var _picked: bool = false
var _mesh: MeshInstance3D
var _prompt: Label3D
var _spin: float = 0.0


func _ready() -> void:
	add_to_group("loot")
	collision_mask = 1                     # detect the player (world layer 1)
	roll_rarity()
	_build_visual()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


## Roll rarity 1-100 per GDD §2.7 (Exotic folded into Epic for the MVP).
func roll_rarity() -> void:
	if forced_rarity != "" and RARITY_COLORS.has(forced_rarity):
		rarity = forced_rarity
		kind = WEAPON_KINDS[randi() % WEAPON_KINDS.size()]
		return
	var r := randi_range(1, 100)
	if r <= 50:
		rarity = "Common"
	elif r <= 85:
		rarity = "Rare"
	else:
		rarity = "Epic"
	kind = WEAPON_KINDS[randi() % WEAPON_KINDS.size()]


func _build_visual() -> void:
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.35, 0.35, 0.35)
	_mesh.mesh = box
	var mat := StandardMaterial3D.new()
	var c: Color = RARITY_COLORS.get(rarity, Color.WHITE)
	mat.albedo_color = c
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = 2.5
	_mesh.material_override = mat
	_mesh.position = Vector3(0, 0.35, 0)
	add_child(_mesh)

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


func _process(delta: float) -> void:
	if _mesh:
		_spin += delta
		_mesh.rotation.y = _spin * 1.5


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
		var owned: Array = sm.data.get("owned_weapons", [])
		owned.append({"id": "loot_%d" % Time.get_ticks_usec(), "name": kind, "rarity": rarity})
		sm.data["owned_weapons"] = owned
		sm.save_game()
	queue_free()

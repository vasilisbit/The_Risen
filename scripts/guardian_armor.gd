extends Node
class_name GuardianArmor
## T-0042 (b): attaches the equipped armour PLATES onto a Guardian skeleton, layered
## over the base body via BoneAttachment3D and tinted by the piece's rarity. Shared by
## the 3rd-person body (hub mirror, guardian.gd) and the inventory preview
## (guardian_preview.gd) so the same loadout shows in both.
##
## The base Guardian is already armoured, so an equipped piece is heavier OVER-armour
## (a chest rig, an upgraded helmet, gauntlet plates) that reads as gear on top.

const PLATE_DIR := "res://assets/generated/armor/"

## Per slot: which mesh attaches to which bone, plus a shared placement (position/
## rotation in the bone's local space + uniform scale). Tuned in-engine. Gauntlets
## attach one split half to each forearm.
## Placement is in the bone's local space (which carries the rig's ~100x internal
## scale, so scale ~3-5 and positions in the same units). rot -90 X stands the Tripo
## plate upright to face forward. Tuned in-engine on the inventory preview / mirror.
const PLACEMENT := {
	"Helmet": {
		"attach": [{"bone": "Head", "file": "helmet.glb"}],
		"pos": Vector3(0, 1.0, 0.5), "rot": Vector3(-90, 0, 0), "scale": 3.0,
	},
	"Chest Plate": {
		"attach": [{"bone": "Spine", "file": "chest.glb"}],
		"pos": Vector3(0, 1.5, 1.2), "rot": Vector3(-90, 0, 0), "scale": 4.5,
	},
	"Gauntlets": {
		"attach": [{"bone": "LeftForeArm", "file": "gauntlet_l.glb"},
				   {"bone": "RightForeArm", "file": "gauntlet_r.glb"}],
		"pos": Vector3(0, -2.0, 0), "rot": Vector3(-90, 0, 0), "scale": 2.2,
	},
}

## Rarity accent (the game's loot colours). Common stays neutral; higher rarities
## take a subtle hue so the loadout reads at a glance, like the character screen.
const RARITY_TINT := {
	"Common": Color(1, 1, 1), "Rare": Color(0.2, 0.5, 1.0),
	"Epic": Color(0.6, 0.25, 1.0), "Exotic": Color(1.0, 0.8, 0.1),
}


## Rebuild every equipped plate under `skeleton`. `equipped` = {slot: item_id};
## `sm` is the SaveManager (for rarity lookup). Idempotent - clears the old plates.
static func refresh(skeleton: Skeleton3D, equipped: Dictionary, sm: Node) -> void:
	if skeleton == null:
		return
	for c in skeleton.get_children():
		if String(c.name).begins_with("ArmorPlate"):
			c.queue_free()
	for slot in equipped:
		if not PLACEMENT.has(slot):
			continue
		var rarity := "Common"
		if sm and sm.has_method("armor_by_id"):
			var item: Dictionary = sm.armor_by_id(equipped[slot])
			rarity = String(item.get("rarity", "Common"))
		var pl: Dictionary = PLACEMENT[slot]
		var tint: Color = RARITY_TINT.get(rarity, Color.WHITE)
		var i := 0
		for a in pl["attach"]:
			var path := PLATE_DIR + String(a["file"])
			if not ResourceLoader.exists(path):
				i += 1
				continue
			var scene: Resource = load(path)
			if not (scene is PackedScene):
				i += 1
				continue
			var bi := skeleton.find_bone(String(a["bone"]))
			if bi < 0:
				i += 1
				continue
			var att := BoneAttachment3D.new()
			att.name = "ArmorPlate_%s_%d" % [slot, i]
			att.bone_name = String(a["bone"])
			skeleton.add_child(att)
			var mesh := (scene as PackedScene).instantiate() as Node3D
			att.add_child(mesh)
			mesh.position = pl["pos"]
			mesh.rotation_degrees = pl["rot"]
			mesh.scale = Vector3.ONE * float(pl["scale"])
			_finish(mesh, tint)
			i += 1


## Punch the metal (Tripo ORM ships dull) and apply the subtle rarity albedo hue.
static func _finish(model: Node3D, tint: Color) -> void:
	var hue := Color.WHITE.lerp(tint, 0.35)   # Common -> neutral; higher rarities hued
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var base := mi.get_active_material(s)
			if not (base is BaseMaterial3D):
				continue
			var mat: BaseMaterial3D = base.duplicate()
			mat.albedo_color = hue
			mat.metallic = 0.6
			mat.roughness = clampf(mat.roughness * 0.8, 0.15, 1.0)
			mat.metallic_specular = 0.55
			mi.set_surface_override_material(s, mat)
		# Same render layer as the body: the main first-person camera skips it, the
		# hub mirror shows it. (Ignored by the inventory preview's isolated world.)
		mi.layers = 1 << 18

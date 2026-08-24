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

## Per slot: which mesh attaches to which bone, plus placement (position/rotation in
## the bone's LOCAL space + uniform scale). Gauntlets attach one split half to each
## forearm, and each half carries its OWN pos/rot/scale (the left/right forearm bones
## are mirrored, so a shared offset lands the two halves in different places).
##
## IMPORTANT scale note: the Meshy auto-rig's armature scale is ~0.0117 (a ~85x
## shrink), and a BoneAttachment3D inherits that scale, so a plate mesh needs a big
## local scale (~20-55) or it renders as an invisible ~3 cm speck. The bone-local
## positions are in that same shrunk space (~85 local units per world metre), so the
## offsets read large too. rot -90 X stands the upright Tripo plate to face forward;
## the chest adds -90 Y to turn its opening toward the front. All tuned in-engine on
## the inventory preview, then read back as bone-local values (pose-invariant, so they
## hold on the mission body + hub mirror too).
const PLACEMENT := {
	"Helmet": {
		"attach": [{"bone": "Head", "file": "helmet.glb"}],
		"pos": Vector3(-14.74, -9.6, -5.96), "rot": Vector3(-90, 0, 0), "scale": 20.0,
	},
	"Chest Plate": {
		"attach": [{"bone": "Spine", "file": "chest.glb"}],
		"pos": Vector3(-1.46, -15.02, -6.59), "rot": Vector3(-90, -90, 0), "scale": 52.0,
	},
	"Gauntlets": {
		"attach": [
			{"bone": "LeftForeArm", "file": "gauntlet_l.glb",
				"pos": Vector3(0, 16.02, 0), "rot": Vector3(-90, 5, 0), "scale": 33.0},
			{"bone": "RightForeArm", "file": "gauntlet_r.glb",
				"pos": Vector3(0, 15.83, 0), "rot": Vector3(-90, 21.1, 0), "scale": 33.0},
		],
		"pos": Vector3(0, 16.0, 0), "rot": Vector3(-90, 0, 0), "scale": 33.0,
	},
}

## Rarity overlay, meant to read at a glance (not a subtle hue): Common stays a
## neutral gunmetal grey with no overlay; Rare gets a clear BLUE wash + glow; Epic
## and Exotic (the "legendary" tier) both get a clear PURPLE wash + glow.
## `mix` = how far the albedo is pushed toward `col`; `emit` = emission energy.
const RARITY_STYLE := {
	"Common": {"col": Color(0.74, 0.76, 0.80), "mix": 0.25, "emit": 0.0},
	"Rare":   {"col": Color(0.15, 0.45, 1.0),  "mix": 0.72, "emit": 0.55},
	"Epic":   {"col": Color(0.60, 0.18, 1.0),  "mix": 0.72, "emit": 0.60},
	"Exotic": {"col": Color(0.60, 0.18, 1.0),  "mix": 0.72, "emit": 0.60},
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
		var style: Dictionary = RARITY_STYLE.get(rarity, RARITY_STYLE["Common"])
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
			# Per-attach placement overrides the slot default (needed for the mirrored
			# left/right gauntlet halves), falling back to the slot's shared values.
			mesh.position = a.get("pos", pl["pos"])
			mesh.rotation_degrees = a.get("rot", pl["rot"])
			mesh.scale = Vector3.ONE * float(a.get("scale", pl["scale"]))
			_finish(mesh, style)
			i += 1


## Punch the metal (Tripo ORM ships dull) and apply the rarity overlay: push the
## albedo toward the rarity colour and add a matching emission glow so Rare (blue)
## and Epic/Exotic (purple) read at a glance, while Common stays neutral gunmetal.
static func _finish(model: Node3D, style: Dictionary) -> void:
	var col: Color = style.get("col", Color(0.74, 0.76, 0.80))
	var mix: float = float(style.get("mix", 0.25))
	var emit: float = float(style.get("emit", 0.0))
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var base := mi.get_active_material(s)
			if not (base is BaseMaterial3D):
				continue
			var mat: BaseMaterial3D = base.duplicate()
			mat.albedo_color = Color(0.55, 0.57, 0.6).lerp(col, mix)
			mat.metallic = 0.6
			mat.roughness = clampf(mat.roughness * 0.8, 0.15, 1.0)
			mat.metallic_specular = 0.55
			if emit > 0.0:
				mat.emission_enabled = true
				mat.emission = col
				mat.emission_energy_multiplier = emit
			mi.set_surface_override_material(s, mat)
		# Same render layer as the body: the main first-person camera skips it, the
		# hub mirror shows it. (Ignored by the inventory preview's isolated world.)
		mi.layers = 1 << 18

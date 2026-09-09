extends Node
class_name GuardianArmor
## Equipped armour is STAT-ONLY now (damage reduction) - it no longer shows as visual
## plates on the Guardian. The generated over-armour meshes never fit the Meshy rig
## cleanly across the body / hub mirror / inventory preview (each poses the same rig
## differently), so the plate display was removed on 2026-08-26; the Guardian shows as
## its own (already-armoured) self everywhere.
##
## refresh() is kept so guardian.gd / guardian_preview.gd can still call it: it just
## strips any "ArmorPlate*" nodes a previous build may have attached, leaving the plain
## Guardian. The armour GLBs under assets/generated/armor/ and tools/gen_armor.py are
## now unused (kept in case the plate idea is revisited with body-fitted meshes).

## Clear any equipped-armour plate nodes under `skeleton`. `_equipped` / `_sm` are
## accepted (and ignored) so the call sites need no change. Idempotent.
static func refresh(skeleton: Skeleton3D, _equipped: Dictionary, _sm: Node) -> void:
	if skeleton == null:
		return
	for c in skeleton.get_children():
		if String(c.name).begins_with("ArmorPlate"):
			c.queue_free()

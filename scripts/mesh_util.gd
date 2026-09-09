class_name MeshUtil
extends Object

## Runtime helper for dropping a generated GLB prop into a scene without a
## Blender normalise step: instance it under a Node3D holder, then (once the
## holder is in the tree) AABB-fit it to a target size and recenter its origin,
## so a projectile/hazard mesh of arbitrary export scale sits where the old
## primitive did. Returns null when the GLB is missing so callers keep a
## code-built fallback mesh.

## Instance `path` under a fresh Node3D holder. The holder is returned NOT yet
## in the tree; add it, then call fit() so global AABB is valid.
static func load_prop(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var inst := scene.instantiate()
	if inst == null:
		return null
	var holder := Node3D.new()
	holder.add_child(inst)
	return holder


## Scale the holder's child so its longest axis == `target` metres, and shift it
## so the mesh is centred on the holder's origin. Call AFTER add_child(holder).
static func fit(holder: Node3D, target: float) -> void:
	if holder.get_child_count() == 0:
		return
	var inst := holder.get_child(0) as Node3D
	if inst == null:
		return
	var aabb := _local_aabb(holder)
	var longest := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	if longest < 0.0001:
		return
	inst.scale *= target / longest
	# Recompute after scaling and recentre so the origin is the mesh centre.
	inst.position -= _local_aabb(holder).get_center()


## Merged AABB of every VisualInstance3D under `holder`, expressed in the
## holder's local space (holder must be in the tree for global_transform).
static func _local_aabb(holder: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var inv := holder.global_transform.affine_inverse()
	for vi in holder.find_children("*", "VisualInstance3D", true, false):
		var v := vi as VisualInstance3D
		var world := inv * v.global_transform * v.get_aabb()
		if first:
			out = world
			first = false
		else:
			out = out.merge(world)
	return out

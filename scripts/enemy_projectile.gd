class_name EnemyProjectile
extends Node3D

## Linear enemy projectile (T-0008, retuned). Fired straight toward where the
## player's chest was when the shot left the muzzle - no homing, so it travels in
## a straight line and can be dodged by strafing. Raycasts each step for wall and
## player hits (allies are excluded so bolts pass through other enemies).

const SPEED := 18.0            # m/s
const LIFETIME := 5.0          # s
const TARGET_CHEST := Vector3(0.0, 1.0, 0.0)

var damage: float = 60.0       # default (Shooter); bosses set their own. Was 100.
## Bolt tint - set before the node enters the tree (the Phantom fires purple).
var bolt_color: Color = Color(1.0, 0.55, 0.1)
## Who fired it, for PlayerDeath attribution (T-0026). Set by the shooter.
var source_name: String = "Projectile"
## Optional design-matched bolt model (the Shooter sets this to its generated glb). When unset
## or missing, the bolt falls back to the small emissive sphere (bosses / the Phantom).
var model_path: String = ""
const BOLT_LEN := 0.5          # metres, longest axis the model is fitted to
var _dir: Vector3 = Vector3.FORWARD
var _shooter_rid: RID
var _life: float = 0.0
var _visual: Node3D = null
var _oriented: bool = false


func setup(from: Vector3, target: Node3D, shooter_rid: RID) -> void:
	_shooter_rid = shooter_rid
	position = from
	if target != null:
		_dir = (target.global_position + TARGET_CHEST - from).normalized()


func _ready() -> void:
	# Prefer the design-matched bolt model (the Shooter's, generated from its own art); fall back
	# to a small emissive bolt for bosses / the Phantom / when the asset isn't present.
	if model_path != "" and ResourceLoader.exists(model_path):
		var holder := MeshUtil.load_prop(model_path)
		if holder != null:
			add_child(holder)
			MeshUtil.fit(holder, BOLT_LEN)
			# The mesh's long axis is Z with the tip at +Z; look_at() aims the node's -Z down the
			# flight path, so spin the model 180 deg about Y to put the tip on -Z (leading the shot).
			holder.rotate_y(PI)
			_visual = holder
	if _visual == null:
		var mi := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.12
		sphere.height = 0.24
		mi.mesh = sphere
		var mat := StandardMaterial3D.new()
		mat.albedo_color = bolt_color
		mat.emission_enabled = true
		mat.emission = bolt_color
		mat.emission_energy_multiplier = 2.5
		mi.material_override = mat
		add_child(mi)
	# Soft glow so the bolt reads at speed and keeps its emissive soulfire look in motion.
	var glow := OmniLight3D.new()
	glow.light_color = bolt_color
	glow.omni_range = 3.0
	glow.light_energy = 1.4
	add_child(glow)


func _physics_process(delta: float) -> void:
	_life += delta
	if _life > LIFETIME:
		queue_free()
		return

	# Orient the model down its flight path once _dir is known (skip near-vertical shots).
	if _visual != null and not _oriented and _dir.length() > 0.01 and absf(_dir.dot(Vector3.UP)) < 0.99:
		look_at(global_position + _dir, Vector3.UP)
		_oriented = true

	# Straight-line step (no steering).
	var step := _dir * SPEED * delta

	# Wall/player check along this step (world layer 1). Enemies are excluded so
	# bolts pass allies; hitting the player body counts as a hit.
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + step, 1)
	var excludes: Array[RID] = [_shooter_rid]
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is CollisionObject3D:
			excludes.append(e.get_rid())
	query.exclude = excludes
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		var collider: Object = hit["collider"]
		if collider is Node and (collider as Node).is_in_group("player"):
			_hit_player(collider as Node)
		else:
			queue_free()          # wall / prop
		return

	global_position += step


func _hit_player(node: Node) -> void:
	if node.has_method("take_damage"):
		node.take_damage(damage, source_name)
	queue_free()

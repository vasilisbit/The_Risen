extends Area3D
## Venus magma bomb (T-0020). The summit volcano hurls these glowing rocks down the
## exterior ascent: each flies a ballistic arc to a target point on the slope, hits the
## player directly on contact (or splashes nearby on impact), then bursts in a molten
## flash. Purely a hazard - not on the navmesh, no groups the AI reads. Spawned by
## venus_level._spawn_magma_bomb.

const GRAVITY := 16.0             # arc gravity (independent of the player's physics)
const DIRECT_DAMAGE := 34.0       # a direct hit
const SPLASH_DAMAGE := 20.0       # anyone caught in the impact radius
const SPLASH_RADIUS := 3.5
const LIFETIME := 9.0             # safety cap so a stray bomb can't live forever

const MOLTEN_ROCK_GLB := "res://assets/generated/venus/molten_rock.glb"
const ROCK_SIZE := 1.1            # metres, longest axis (was a 1.0 m sphere)

var _vel: Vector3 = Vector3.ZERO
var _life: float = 0.0
var _target_y: float = 0.0
var _done: bool = false
var _mesh: Node3D                 # the tumbling visual (generated rock GLB or a sphere)


func _ready() -> void:
	collision_layer = 0               # nothing collides WITH the bomb...
	collision_mask = 1                # ...but it detects the player (layer 1)
	monitoring = true
	var col := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.5
	col.shape = s
	add_child(col)
	_build_visual()
	body_entered.connect(_on_body)


## Aim from the crater to a target point, solving the launch velocity for a lobbed arc.
func setup(from: Vector3, to: Vector3) -> void:
	global_position = from
	_target_y = to.y
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var dist := flat.length()
	var t: float = clampf(dist / 22.0, 1.2, 3.4)          # flight time -> higher = loftier arc
	_vel = flat / t
	_vel.y = (to.y - from.y) / t + 0.5 * GRAVITY * t


func _physics_process(delta: float) -> void:
	if _done:
		return
	_life += delta
	_vel.y -= GRAVITY * delta
	global_position += _vel * delta
	if _mesh:
		_mesh.rotate_x(delta * 5.0)
		_mesh.rotate_y(delta * 3.0)
	# Impact when it falls to (or past) the target slope height, or on the safety cap.
	if (_vel.y < 0.0 and global_position.y <= _target_y) or _life > LIFETIME:
		_impact()


func _on_body(body: Node) -> void:
	if _done:
		return
	if body.is_in_group("player"):
		if body.has_method("take_damage"):
			body.take_damage(DIRECT_DAMAGE, "a magma bomb")
		_impact()


func _impact() -> void:
	if _done:
		return
	_done = true
	# Splash: catch any player standing right where it lands.
	for p in get_tree().get_nodes_in_group("player"):
		if p is Node3D and p.has_method("take_damage"):
			if p.global_position.distance_to(global_position) <= SPLASH_RADIUS:
				p.take_damage(SPLASH_DAMAGE, "a magma bomb")
	var host := get_tree().current_scene
	if host == null:
		host = get_tree().root
	# Molten fireball + sparks + smoke + shockwave + scorch + flash (VfxKit "fire").
	VfxKit.explosion(host, global_position, Color(1.0, 0.5, 0.15), SPLASH_RADIUS, "fire")
	queue_free()


func _build_visual() -> void:
	# Prefer the generated molten-rock GLB (charred basalt crust + glowing lava
	# cracks); fall back to the emissive low-poly sphere when it is missing.
	var glb := MeshUtil.load_prop(MOLTEN_ROCK_GLB)
	if glb != null:
		_mesh = glb
		add_child(_mesh)
		MeshUtil.fit(_mesh, ROCK_SIZE)
	else:
		var mi := MeshInstance3D.new()
		var rock := SphereMesh.new()
		rock.radius = 0.5
		rock.height = 1.0
		rock.radial_segments = 8
		rock.rings = 5
		mi.mesh = rock
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.14, 0.05, 0.03)              # charred crust
		m.emission_enabled = true
		m.emission = Color(1.0, 0.4, 0.08)                    # molten glow
		m.emission_energy_multiplier = 3.2
		mi.material_override = m
		_mesh = mi
		add_child(_mesh)
	# Light so it visibly streaks over the slope as it flies.
	var light := OmniLight3D.new()
	light.omni_range = 9.0
	light.light_energy = 2.4
	light.light_color = Color(1.0, 0.5, 0.15)
	add_child(light)

extends Node3D
## FPS weapon viewmodels, built from primitives (no external assets, no
## licensing). Sits under the camera in the lower-right; kick() adds a recoil
## impulse that decays each frame, so firing reads on screen.
##
## Each of the four weapon types gets its own silhouette and recoil weight —
## a shotgun should not look or kick like a sniper. set_weapon() rebuilds when
## the player switches, and the WeaponManager calls it on every switch.

const REST_POS := Vector3(0.32, -0.26, -0.7)
const RECOVER := 14.0        # recovery speed

## Per-weapon recoil, so the heavy guns shove harder.
const KICK := {
	"Auto Rifle": {"back": 0.07, "up": 0.045},
	"Shotgun": {"back": 0.16, "up": 0.10},
	"Sniper": {"back": 0.14, "up": 0.09},
	"Hand Cannon": {"back": 0.11, "up": 0.075},
}

var weapon_name: String = "Auto Rifle"

var _kick: float = 0.0
var _rise: float = 0.0
var _model: Node3D


func _ready() -> void:
	position = REST_POS
	set_weapon(weapon_name)


## Rebuild the viewmodel for `name_`. Cheap enough to do on every switch —
## these are a handful of boxes and cylinders.
func set_weapon(name_: String) -> void:
	weapon_name = name_
	if _model and is_instance_valid(_model):
		_model.queue_free()
	_model = Node3D.new()
	add_child(_model)
	match name_:
		"Shotgun":
			_build_shotgun()
		"Sniper":
			_build_sniper()
		"Hand Cannon":
			_build_hand_cannon()
		_:
			_build_auto_rifle()


func kick() -> void:
	var k: Dictionary = KICK.get(weapon_name, KICK["Auto Rifle"])
	_kick = float(k["back"])
	_rise = float(k["up"])


func _process(delta: float) -> void:
	var t := clampf(RECOVER * delta, 0.0, 1.0)
	_kick = lerpf(_kick, 0.0, t)
	_rise = lerpf(_rise, 0.0, t)
	position = REST_POS + Vector3(0.0, _rise * 0.25, _kick)
	rotation.x = _rise


# --- the four silhouettes ---------------------------------------------------

## Boxy receiver, long thin barrel, tall magazine, blue accents.
func _build_auto_rifle() -> void:
	var metal := _mat(Color(0.11, 0.11, 0.13), 0.7, 0.4)
	var accent := _mat(Color(0.15, 0.35, 0.7), 0.2, 0.5, true, Color(0.12, 0.32, 0.85), 1.0)
	_box(Vector3(0, 0, 0), Vector3(0.12, 0.14, 0.42), metal)
	_cyl(Vector3(0, 0.03, -0.36), 0.024, 0.34, metal)
	_box(Vector3(0, 0.10, -0.06), Vector3(0.03, 0.03, 0.16), accent)
	_grip(metal)
	var mag := _box(Vector3(0, -0.16, -0.02), Vector3(0.06, 0.16, 0.09), accent)
	mag.rotation.x = 0.08


## Short, fat, twin-tube with a pump under the barrel. Green accents.
func _build_shotgun() -> void:
	var metal := _mat(Color(0.13, 0.12, 0.11), 0.6, 0.5)
	var wood := _mat(Color(0.28, 0.16, 0.08), 0.0, 0.7)
	var accent := _mat(Color(0.20, 0.60, 0.32), 0.2, 0.5, true, Color(0.15, 0.75, 0.35), 1.0)
	_box(Vector3(0, 0, 0.02), Vector3(0.14, 0.15, 0.34), metal)
	_cyl(Vector3(0, 0.035, -0.30), 0.038, 0.32, metal)          # wide bore
	_cyl(Vector3(0, -0.02, -0.28), 0.030, 0.26, metal)          # under-tube
	var pump := _box(Vector3(0, -0.02, -0.22), Vector3(0.09, 0.07, 0.14), wood)
	pump.rotation.z = 0.02
	_box(Vector3(0, 0.09, 0.0), Vector3(0.02, 0.02, 0.10), accent)
	_grip(wood)


## Very long barrel, big scope, bipod stubs. Purple accents.
func _build_sniper() -> void:
	var metal := _mat(Color(0.10, 0.10, 0.12), 0.75, 0.35)
	var accent := _mat(Color(0.42, 0.28, 0.75), 0.2, 0.5, true, Color(0.45, 0.25, 0.95), 1.2)
	_box(Vector3(0, 0, 0.04), Vector3(0.10, 0.12, 0.40), metal)
	_cyl(Vector3(0, 0.02, -0.48), 0.020, 0.62, metal)           # long barrel
	_cyl(Vector3(0, 0.115, -0.06), 0.035, 0.24, metal)          # scope tube
	_cyl(Vector3(0, 0.115, -0.19), 0.045, 0.04, accent)         # objective lens
	_box(Vector3(0, 0.055, -0.02), Vector3(0.02, 0.05, 0.05), metal)
	_box(Vector3(0, 0.055, -0.14), Vector3(0.02, 0.05, 0.05), metal)
	var bipod := _box(Vector3(0, -0.07, -0.40), Vector3(0.02, 0.10, 0.02), metal)
	bipod.rotation.x = 0.35
	_grip(metal)
	var stock := _box(Vector3(0, -0.02, 0.26), Vector3(0.07, 0.11, 0.14), metal)
	stock.rotation.x = -0.05


## Stubby revolver: short barrel, fat cylinder, no magazine. Gold accents.
func _build_hand_cannon() -> void:
	var metal := _mat(Color(0.16, 0.15, 0.14), 0.8, 0.3)
	var accent := _mat(Color(0.75, 0.55, 0.18), 0.6, 0.35, true, Color(1.0, 0.72, 0.25), 1.0)
	_box(Vector3(0, 0, 0.02), Vector3(0.08, 0.10, 0.20), metal)
	_cyl(Vector3(0, 0.015, -0.19), 0.022, 0.22, metal)          # short barrel
	var cylinder := _cyl(Vector3(0, -0.005, -0.02), 0.045, 0.09, accent)
	cylinder.rotation.z = 1.5708                                 # lie it across the frame
	_box(Vector3(0, 0.065, -0.06), Vector3(0.015, 0.02, 0.10), accent)
	var grip := _box(Vector3(0, -0.13, 0.08), Vector3(0.07, 0.17, 0.09), metal)
	grip.rotation.x = 0.42                                       # steeper revolver grip


func _grip(mat: StandardMaterial3D) -> void:
	var grip := _box(Vector3(0, -0.13, 0.13), Vector3(0.08, 0.18, 0.1), mat)
	grip.rotation.x = 0.3


# --- primitives -------------------------------------------------------------

func _box(center: Vector3, size: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = mat
	mesh.position = center
	_model.add_child(mesh)
	return mesh


func _cyl(center: Vector3, radius: float, length: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = length
	cm.radial_segments = 12
	mesh.mesh = cm
	mesh.material_override = mat
	mesh.position = center
	mesh.rotation.x = 1.5707963            # cylinders default to +Y; lie along -Z
	_model.add_child(mesh)
	return mesh


func _mat(color: Color, metallic: float, roughness: float, emission := false, em := Color.BLACK, em_energy := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	if emission:
		m.emission_enabled = true
		m.emission = em
		m.emission_energy_multiplier = em_energy
	return m

extends Node3D
## Placeholder FPS weapon viewmodel (built from primitives — no external assets,
## no licensing). Sits under the camera in the lower-right; kick() adds a recoil
## impulse that decays each frame, so firing reads on screen.

const REST_POS := Vector3(0.32, -0.26, -0.7)
const KICK_BACK := 0.09      # metres pushed toward the camera (+Z)
const KICK_UP := 0.06        # radians of muzzle rise
const RECOVER := 14.0        # recovery speed

var _kick: float = 0.0
var _rise: float = 0.0


func _ready() -> void:
	position = REST_POS
	_build()


func _build() -> void:
	var metal := _mat(Color(0.11, 0.11, 0.13), 0.7, 0.4)
	var accent := _mat(Color(0.15, 0.35, 0.7), 0.2, 0.5, true, Color(0.12, 0.32, 0.85), 1.0)
	_box(Vector3(0.0, 0.0, 0.0), Vector3(0.12, 0.14, 0.42), metal)          # receiver
	_box(Vector3(0.0, 0.03, -0.36), Vector3(0.05, 0.05, 0.34), metal)       # barrel
	_box(Vector3(0.0, 0.10, -0.06), Vector3(0.03, 0.03, 0.16), accent)      # top sight
	var grip := _box(Vector3(0.0, -0.13, 0.13), Vector3(0.08, 0.18, 0.1), metal)
	grip.rotation.x = 0.3                                                    # grip angled back
	var mag := _box(Vector3(0.0, -0.16, -0.02), Vector3(0.06, 0.16, 0.09), accent)
	mag.rotation.x = 0.08


func kick() -> void:
	_kick = KICK_BACK
	_rise = KICK_UP


func _process(delta: float) -> void:
	var t := clampf(RECOVER * delta, 0.0, 1.0)
	_kick = lerpf(_kick, 0.0, t)
	_rise = lerpf(_rise, 0.0, t)
	position = REST_POS + Vector3(0.0, _rise * 0.25, _kick)
	rotation.x = _rise


func _box(center: Vector3, size: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = mat
	mesh.position = center
	add_child(mesh)
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

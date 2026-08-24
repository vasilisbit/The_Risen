extends Node
## First-person weapon viewmodel. Renders a dedicated ARMS+GUN mesh (two armoured
## gauntlets modelled already gripping the weapon - T-0042, tools/gen_viewmodel.py)
## in its own isolated SubViewport, composited on top of the main view.
##
## Why a bespoke mesh and not the player body rig: the Meshy-rigged Guardian can't
## hold a gun two-handed - the arms are too short to reach the handguard and the
## auto-rig hands are a single fingerless bone, so a support hand only splays open.
## Real FPS viewmodels are purpose-built arm+gun meshes, which is what this shows.
## The world/inventory keep the T-0041 gun models (separate view vs world models).

const VM_DIR := "res://assets/generated/viewmodels/"
## Fallback: the bare world gun (no arms) if a weapon has no viewmodel mesh yet.
const WEAPON_DIR := "res://assets/generated/weapons/"

## Where the viewmodel camera sits and looks (fixed; the mesh is placed in front of
## it, lower-right, barrel forward). The mesh transform per weapon does the framing.
@export var cam_position: Vector3 = Vector3(0, 0, 0)
@export var cam_look_at: Vector3 = Vector3(0, 0, -1)
@export var cam_fov: float = 55.0
## The viewmodel dips/rises a touch with the look pitch.
@export var pitch_follow: float = 0.04

## Per-weapon viewmodel placement in the holder's space: position (m), rotation
## (deg) and uniform scale, so the gun sits lower-right with the barrel pointing
## forward (-Z), arms coming up from the bottom - the reference viewmodel look.
## Tuned in-engine; the auto rifle is the baseline (others reuse it until tuned).
const VM_BASE := {"pos": Vector3(0.14, -0.24, -0.60), "rot": Vector3(2, 6, -8), "scale": 0.47}
## NOTE on per-weapon rotation: each Tripo mesh keeps its own native barrel axis.
## Auto Rifle / Shotgun / Sniper already model the barrel along -Z, so their rot is
## a small cosmetic cant. The Hand Cannon mesh models the barrel along +X, so it
## needs a ~+90 deg Y turn (barrel +X -> -Z) or it points back at the player.
const VM_XFORM := {
	"Auto Rifle": {"pos": Vector3(0.14, -0.24, -0.60), "rot": Vector3(2, 6, -8), "scale": 0.47},
	"Shotgun": {"pos": Vector3(0.13, -0.18, -0.55), "rot": Vector3(3, 8, -7), "scale": 0.53},
	"Sniper": {"pos": Vector3(0.14, -0.21, -0.62), "rot": Vector3(2, 6, -8), "scale": 0.46},
	"Hand Cannon": {"pos": Vector3(0.14, -0.25, -0.53), "rot": Vector3(5, 101, 6), "scale": 0.55},
}
const VM_FILE := {
	"Auto Rifle": "auto_rifle_vm.glb", "Shotgun": "shotgun_vm.glb",
	"Sniper": "sniper_vm.glb", "Hand Cannon": "hand_cannon_vm.glb",
}

## Per-weapon recoil impulse (metres back/up + radians of muzzle rise).
const KICK := {
	"Auto Rifle": {"back": 0.03, "up": 0.018, "rot": 0.05},
	"Shotgun": {"back": 0.075, "up": 0.045, "rot": 0.11},
	"Sniper": {"back": 0.065, "up": 0.04, "rot": 0.10},
	"Hand Cannon": {"back": 0.05, "up": 0.03, "rot": 0.08},
}
const RECOIL_RECOVER := 12.0

var _viewport: SubViewport
var _cam: Camera3D
var _holder: Node3D           # recoil/dip move this; the VM mesh hangs under it
var _model: Node3D
var _layer: CanvasLayer
var _tex: TextureRect
var _pitch: float = 0.0
var _recoil: Vector3 = Vector3.ZERO
var _recoil_rot: float = 0.0
var _reload_left: float = 0.0
var _reload_dur: float = 1.0
var _base_pos: Vector3 = Vector3.ZERO      # current weapon's rest holder position


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_2X
	add_child(_viewport)

	_build_lighting()

	_cam = Camera3D.new()
	_cam.fov = cam_fov
	_cam.near = 0.02
	_viewport.add_child(_cam)
	_aim_camera()

	_holder = Node3D.new()
	_viewport.add_child(_holder)

	_build_overlay()


## Key + fill so the dark gauntlets read, plus a little ambient. The isolated world
## is otherwise pitch black.
func _build_lighting() -> void:
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-45), deg_to_rad(30), 0)
	key.light_energy = 1.2
	_viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-10), deg_to_rad(-140), 0)
	fill.light_energy = 0.5
	fill.light_color = Color(0.75, 0.82, 1.0)
	_viewport.add_child(fill)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.46, 0.55)
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)


func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 1
	add_child(_layer)
	_tex = TextureRect.new()
	_tex.texture = _viewport.get_texture()
	_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_tex)


func _process(delta: float) -> void:
	var win := get_window().size
	if _viewport.size != win:
		_viewport.size = win
	# Ease the recoil back to rest.
	var t := clampf(RECOIL_RECOVER * delta, 0.0, 1.0)
	_recoil = _recoil.lerp(Vector3.ZERO, t)
	_recoil_rot = lerpf(_recoil_rot, 0.0, t)
	# Reload dip: the viewmodel lowers + cants over reload_time, then rises back.
	var dip := 0.0
	if _reload_left > 0.0:
		_reload_left -= delta
		var pr := clampf(1.0 - _reload_left / maxf(_reload_dur, 0.05), 0.0, 1.0)
		dip = sin(pr * PI)
	if _holder:
		var lift := _pitch * pitch_follow
		_holder.position = _base_pos + _recoil + Vector3(0.0, lift - 0.06 * dip, 0.03 * dip)
		_holder.rotation = Vector3(-_recoil_rot - 0.45 * dip, 0.0, 0.5 * dip)
	_aim_camera()


func _aim_camera() -> void:
	if _cam == null:
		return
	_cam.fov = cam_fov
	_cam.position = cam_position
	_cam.look_at(cam_look_at, Vector3.UP)


## Match the equipped weapon: load its arms+gun viewmodel mesh (mirrors the naming,
## e.g. "Auto Rifle" -> viewmodels/auto_rifle_vm.glb).
func set_weapon(name_: String) -> void:
	if _holder == null:
		return
	if _model and is_instance_valid(_model):
		_model.queue_free()
		_model = null
	var xf: Dictionary = VM_XFORM.get(name_, VM_BASE)
	_base_pos = xf["pos"]
	var vm_path := VM_DIR + String(VM_FILE.get(name_, ""))
	var scene: Resource = null
	if ResourceLoader.exists(vm_path):
		scene = load(vm_path)
	if scene is PackedScene:
		_model = (scene as PackedScene).instantiate() as Node3D
		_holder.add_child(_model)
		_model.position = Vector3.ZERO
		_model.rotation_degrees = xf["rot"]
		_model.scale = Vector3.ONE * float(xf["scale"])
		_metalize(_model, false)
	else:
		_fallback_weapon(name_)


## No viewmodel mesh yet: show the bare world gun (no arms) so something is drawn.
func _fallback_weapon(name_: String) -> void:
	var file := name_.to_lower().replace(" ", "_")
	var path := "%s%s.glb" % [WEAPON_DIR, file]
	if not ResourceLoader.exists(path):
		return
	var scene: Resource = load(path)
	if scene is PackedScene:
		_model = (scene as PackedScene).instantiate() as Node3D
		_holder.add_child(_model)
		_model.rotation_degrees = Vector3(0, 90, 0)
		_model.position = Vector3(0.12, -0.2, -0.5)
		_metalize(_model, true)


## Punch the metal a touch (Tripo ORM ships dull). The full arms+gun mesh keeps its
## generated Color/Normal; the bare fallback gun gets a stronger metal punch.
func _metalize(model: Node3D, hard: bool) -> void:
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var base := mi.get_active_material(s)
			if not (base is BaseMaterial3D):
				continue
			var mat: BaseMaterial3D = base.duplicate()
			mat.metallic = 1.0 if hard else 0.5
			mat.roughness = clampf(mat.roughness * (0.7 if hard else 0.85), 0.1, 1.0)
			mat.metallic_specular = 0.6 if hard else 0.5
			mi.set_surface_override_material(s, mat)


func set_pitch(pitch: float) -> void:
	_pitch = pitch


func kick(weapon_name := "Auto Rifle") -> void:
	var k: Dictionary = KICK.get(weapon_name, KICK["Auto Rifle"])
	_recoil = Vector3(0.0, float(k["up"]), float(k["back"]))
	_recoil_rot = float(k["rot"])


## Reload feedback: dip the viewmodel down/back for `duration` seconds (see _process).
func play_reload(duration: float) -> void:
	_reload_dur = maxf(duration, 0.05)
	_reload_left = _reload_dur


func set_shown(shown: bool) -> void:
	if _layer:
		_layer.visible = shown

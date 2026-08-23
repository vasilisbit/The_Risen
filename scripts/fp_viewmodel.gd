extends Node
## First-person weapon viewmodel, the way an FPS actually does it: the arms and
## gun are rendered in their OWN isolated SubViewport and composited on top of the
## main view. The real body can't serve as the viewmodel because the gun rides on
## the chest, ~8 cm from an eye-level camera, so it fills the screen and bobs; in
## an isolated viewport the arms+gun are placed at a comfortable distance in the
## lower-right and never clip into the world.
##
## The rig is a second copy of the same PlayerCharacter (same mannequin + rifle
## idle + weapon socket), so it holds whatever weapon is equipped, in the same
## hands, for free. A dedicated viewmodel camera frames just the arms and gun.

const CHARACTER := "res://scripts/player_character.gd"

## Where the viewmodel camera sits and looks, in the rig's space. The rig stands
## at origin facing -Z. The camera sits BEHIND the body looking level along -Z, so
## the gun's barrel (which points -Z) reads parallel to the ground; the near plane
## then clips away the neck/torso between the camera and the gun, leaving just the
## forearm and gun in the lower-right. Tuned in-engine.
@export var cam_position: Vector3 = Vector3(-0.06, 1.60, 0.62)
@export var cam_look_at: Vector3 = Vector3(-0.19, 1.42, -0.9)
@export var cam_fov: float = 55.0
## Near plane. The torso is now removed by the arms-only vertex mask (no hard
## cut), so this only needs to stay off the very closest geometry.
@export var cam_near: float = 0.05
## Aim: the viewmodel dips/rises a touch with the look pitch. Small - too much and
## looking down slides the clipped body edge into view.
@export var pitch_follow: float = 0.05

## Per-weapon viewmodel framing (camera pos/look/fov in the rig's space), tuned
## in-engine so each gun frames right - barrel forward, both hands on it, sensible
## scale. The auto rifle is the baseline; the shotgun rides a touch higher and
## level, the long sniper is pulled back to fit, and the one-handed hand cannon is
## brought in closer so it isn't lost in the corner. Applied by set_weapon().
## The generated T-0041 guns are all canonicalised to the same grip, so the
## baseline framing carries over unchanged.
## Re-tuned for the Meshy Guardian's frozen gun_idle hold. All four canonicalised
## guns share the grip and this framing (look direction fixed so the one grip keeps
## every barrel on the crosshair); longer guns just sit a touch further back.
const FRAMING := {
	"Auto Rifle":  {"pos": Vector3(-0.06, 1.60, 0.70), "look": Vector3(-0.19, 1.42, -0.9), "fov": 55.0},
	"Shotgun":     {"pos": Vector3(-0.06, 1.60, 0.66), "look": Vector3(-0.19, 1.42, -0.9), "fov": 55.0},
	"Sniper":      {"pos": Vector3(-0.06, 1.60, 0.80), "look": Vector3(-0.19, 1.42, -0.9), "fov": 53.0},
	"Hand Cannon": {"pos": Vector3(-0.06, 1.60, 0.62), "look": Vector3(-0.19, 1.42, -0.9), "fov": 55.0},
}

## Per-weapon recoil impulse (metres back/up + radians of muzzle rise). The rig
## snaps by this when fired and eases back, so the gun kicks toward you and up -
## the heavy guns shove harder.
const KICK := {
	"Auto Rifle": {"back": 0.03, "up": 0.018, "rot": 0.05},
	"Shotgun": {"back": 0.075, "up": 0.045, "rot": 0.11},
	"Sniper": {"back": 0.065, "up": 0.04, "rot": 0.10},
	"Hand Cannon": {"back": 0.05, "up": 0.03, "rot": 0.08},
}
const RECOIL_RECOVER := 12.0        # how fast the kick eases back to rest

var _viewport: SubViewport
var _cam: Camera3D
var _rig: Node3D
var _layer: CanvasLayer
var _tex: TextureRect
var _pitch: float = 0.0
var _recoil: Vector3 = Vector3.ZERO     # current rig offset (back/up) from recoil
var _recoil_rot: float = 0.0            # current muzzle rise from recoil


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true                      # isolated from the level
	_viewport.transparent_bg = true                    # composite over the game
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_2X
	add_child(_viewport)

	_build_lighting()

	var scene: Resource = load(CHARACTER)
	if scene is GDScript:
		_rig = Node3D.new()
		_rig.set_script(scene)
		_rig.set("arms_only", true)                     # show only the forearms+hands
		_rig.rotation.y = PI                            # face -Z like the real body
		_viewport.add_child(_rig)

	_cam = Camera3D.new()
	_cam.fov = cam_fov
	_cam.near = cam_near
	_viewport.add_child(_cam)
	_aim_camera()

	_build_overlay()


## A key light and fill so the dark suit arms read, plus a little ambient. The
## isolated world is otherwise pitch black.
func _build_lighting() -> void:
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-50), deg_to_rad(35), 0)
	key.light_energy = 1.0
	_viewport.add_child(key)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.46, 0.55)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)


## Full-screen overlay that draws the viewmodel render on top of the world. On a
## CanvasLayer below the HUD's own layers so HUD text stays on top of the gun.
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
	# Ease the recoil back to rest. The kick itself is an instant snap; this is the
	# recovery, so the gun jumps then settles.
	var t := clampf(RECOIL_RECOVER * delta, 0.0, 1.0)
	_recoil = _recoil.lerp(Vector3.ZERO, t)
	_recoil_rot = lerpf(_recoil_rot, 0.0, t)
	if _rig:
		# Back (+Z toward the camera) and up (+Y); rotate the muzzle up.
		_rig.position = _recoil
		_rig.rotation = Vector3(-_recoil_rot, PI, 0.0)
	_aim_camera()


func _aim_camera() -> void:
	if _cam == null:
		return
	_cam.near = cam_near
	_cam.fov = cam_fov
	var lift := _pitch * pitch_follow
	_cam.position = cam_position + Vector3(0, lift, 0)
	_cam.look_at(cam_look_at + Vector3(0, lift, 0), Vector3.UP)


## Match the equipped weapon (mirrors WeaponManager naming, e.g. "Auto Rifle").
func set_weapon(name_: String) -> void:
	if _rig and _rig.has_method("set_weapon"):
		_rig.set_weapon(name_)
		if _rig.has_method("set_weapon_visible"):
			_rig.set_weapon_visible(true)
	_apply_framing(name_)


## Reframe the viewmodel camera for the equipped weapon (see FRAMING); unknown
## weapons fall back to the auto-rifle baseline.
func _apply_framing(name_: String) -> void:
	var f: Dictionary = FRAMING.get(name_, FRAMING["Auto Rifle"])
	cam_position = f["pos"]
	cam_look_at = f["look"]
	cam_fov = f["fov"]
	_aim_camera()


func set_pitch(pitch: float) -> void:
	_pitch = pitch


## Recoil impulse on fire: snap the gun back and up, then _process eases it home.
func kick(weapon_name := "Auto Rifle") -> void:
	var k: Dictionary = KICK.get(weapon_name, KICK["Auto Rifle"])
	_recoil = Vector3(0.0, float(k["up"]), float(k["back"]))
	_recoil_rot = float(k["rot"])


func set_shown(shown: bool) -> void:
	if _layer:
		_layer.visible = shown

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
## at origin facing -Z; the camera sits in front of and above the hands looking
## back at them so the gun reads in the lower-right. Tuned in-engine.
@export var cam_position: Vector3 = Vector3(-0.04, 1.66, 0.1)
@export var cam_look_at: Vector3 = Vector3(0.2, 1.3, -0.7)
@export var cam_fov: float = 55.0
## Aim: the viewmodel tilts a little with the look pitch (a viewmodel dips/rises
## as you aim), a fraction of the real pitch so it stays on screen.
@export var pitch_follow: float = 0.15

var _viewport: SubViewport
var _cam: Camera3D
var _rig: Node3D
var _layer: CanvasLayer
var _tex: TextureRect
var _pitch: float = 0.0


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
		_rig.rotation.y = PI                            # face -Z like the real body
		_viewport.add_child(_rig)

	_cam = Camera3D.new()
	_cam.fov = cam_fov
	_viewport.add_child(_cam)
	_aim_camera()

	_build_overlay()


## A key light and fill so the dark suit arms read, plus a little ambient. The
## isolated world is otherwise pitch black.
func _build_lighting() -> void:
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-45), deg_to_rad(35), 0)
	key.light_energy = 1.3
	_viewport.add_child(key)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.72)
	env.ambient_light_energy = 0.7
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


func _process(_delta: float) -> void:
	var win := get_window().size
	if _viewport.size != win:
		_viewport.size = win
	_aim_camera()


func _aim_camera() -> void:
	if _cam == null:
		return
	var lift := _pitch * pitch_follow
	_cam.position = cam_position + Vector3(0, lift, 0)
	_cam.look_at(cam_look_at + Vector3(0, lift, 0), Vector3.UP)


## Match the equipped weapon (mirrors WeaponManager naming, e.g. "Auto Rifle").
func set_weapon(name_: String) -> void:
	if _rig and _rig.has_method("set_weapon"):
		_rig.set_weapon(name_)
		if _rig.has_method("set_weapon_visible"):
			_rig.set_weapon_visible(true)


func set_pitch(pitch: float) -> void:
	_pitch = pitch


func set_shown(shown: bool) -> void:
	if _layer:
		_layer.visible = shown

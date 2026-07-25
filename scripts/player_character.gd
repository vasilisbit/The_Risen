extends Node3D
## The Guardian's real body, seen from a TRUE first-person camera (Phase 3):
## look down and you see your chest, hips and legs, and the gun is held in the
## character's own hands rather than floating in front of the camera.
##
## Model: Quaternius Superhero (CC0, 65-bone UE rig).
## Animation: the Fab "Pistol and Rifle Locomotion" rifle loops, which pose the
## arms around a rifle. That pack rigs a UEFN mannequin (88 bones), but Godot
## animates bones BY NAME - 51 of its 75 animated bones exist on the Superhero
## and the misses are only IK helpers (ik_foot_*, ik_hand_gun) and twist bones,
## so the clips drive this body correctly. Their track paths are
## "Skeleton3D:<bone>", so the AnimationPlayer's root_node is the Armature.
##
## The head bone is scaled to nothing every frame, because the camera sits inside
## the head - otherwise you would be looking at the inside of the skull.

## The UEFN mannequin ships INSIDE the rifle-animation pack, so its rig is the
## exact one those clips animate - every bone matches, unlike the Quaternius
## Superhero (65 bones, only a partial match) which also had no clothing.
const MODEL := "res://assets/thirdparty/fab/Pistol and Rifle Locomotion Animations 1700/Characters/UEFN_Mannequin/Meshes/SKM_UEFN_Mannequin.FBX"
const RIFLE_DIR := "res://assets/thirdparty/fab/Pistol and Rifle Locomotion Animations 1700/_FixedRifle/"
## state -> clip file. Each FBX holds a single animation called "Unreal Take".
const CLIPS := {
	"idle": "Idle/M_Neutral_Stand_Idle_Loop_Rifle.FBX",
	"walk": "Walk/M_Neutral_Walk_Loop_F_Rifle.FBX",
	"walk_back": "Walk/M_Neutral_Walk_Loop_B_Rifle.FBX",
	"walk_left": "Walk/M_Neutral_Walk_Loop_LL_Rifle.FBX",
	"walk_right": "Walk/M_Neutral_Walk_Loop_RR_Rifle.FBX",
	"run": "Run/M_Neutral_Run_Loop_F_Rifle.FBX",
	"run_back": "Run/M_Neutral_Run_Loop_B_Rifle.FBX",
	"sprint": "Sprint/M_Neutral_Sprint_Loop_F_Rifle.FBX",
	"jump": "Jump/M_Neutral_Jump_Loop_Fall_Rifle.FBX",
}
const WEAPON_DIR := "res://assets/thirdparty/weapons/"

const WALK_SPEED := 0.4      # above this = walk
const RUN_SPEED := 4.8       # above this = sprint

## Bones we drive directly. The Superhero rig capitalises the head ("Head") while
## the hands are lower-case, so the head is looked up case-insensitively.
## Head AND neck are collapsed: with only the head hidden, looking down put the
## Guardian's own neck stub in the middle of the view. Hiding both leaves the
## chest, belly and legs, which is what you should see looking down.
const HEAD_BONE := "Head"
const NECK_BONES := ["neck_01", "neck_02"]
## The UEFN rig carries a dedicated weapon socket bone, already placed and
## oriented in the grip - far better than hanging the gun off hand_r by eye.
const HAND_BONE := "weapon_r"
## Upper-spine bones the aim offset is spread across, so the chest (and with it
## the arms and the gun) tilts toward wherever the camera is looking. Without
## this the body stays level and the rifle sits below the screen.
const AIM_BONES := ["spine_02", "spine_03"]
## How much of the look pitch the torso takes. Below 1.0 the spine leans toward
## the aim without the chest trying to match the camera exactly.
const AIM_STRENGTH := 0.85

## Where the gun sits in the right hand (tuned so the grip meets the palm).
## Per-weapon grip in the socket. The wrappers were authored for the camera
## viewmodel and face along X, so they all need a quarter turn to look down the
## barrel; beyond that each gun's grip sits differently in the palm, so they get
## their own offset and size rather than sharing one guessed transform.
const GRIP_DEFAULT := {"pos": Vector3.ZERO, "rot": Vector3(0, -90, 0), "scale": 1.0}
const GRIPS := {
	"Auto Rifle": {"pos": Vector3(0.0, 0.0, -0.06), "rot": Vector3(0, -90, 0), "scale": 1.0},
	"Shotgun": {"pos": Vector3(0.0, 0.0, -0.04), "rot": Vector3(0, -90, 0), "scale": 0.9},
	"Sniper": {"pos": Vector3(0.0, 0.0, -0.10), "rot": Vector3(0, -90, 0), "scale": 0.85},
	"Hand Cannon": {"pos": Vector3(0.0, 0.0, -0.02), "rot": Vector3(0, -90, 0), "scale": 1.1},
}

## Put the gun in the character's hand instead of drawing the camera viewmodel.
## Needs a per-weapon grip transform first - see set_weapon().
@export var hand_weapon_enabled: bool = true
## Whether the held weapon is drawn (false in the hub - see set_weapon_visible).
var weapon_drawn: bool = true

var _anim: AnimationPlayer
var _skeleton: Skeleton3D
var _head_bone: int = -1
var _neck_bones: Array[int] = []
var _hand_attach: BoneAttachment3D
var _weapon_model: Node3D
var _current: String = ""
var _aim_bones: Array[int] = []
var _aim_pitch: float = 0.0


func _ready() -> void:
	# Run after the AnimationPlayer each frame so the head-hiding scale below is
	# written on top of the animated pose rather than being overwritten by it.
	process_priority = 100

	var hero_scene: Resource = load(MODEL)
	if not (hero_scene is PackedScene):
		return
	var hero := (hero_scene as PackedScene).instantiate() as Node3D
	add_child(hero)
	_apply_suit(hero)

	var skels := hero.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return
	_skeleton = skels[0] as Skeleton3D
	_head_bone = _find_bone_ci(HEAD_BONE)
	for b in NECK_BONES:
		var n := _find_bone_ci(String(b))
		if n >= 0:
			_neck_bones.append(n)
	for b in AIM_BONES:
		var idx := _find_bone_ci(String(b))
		if idx >= 0:
			_aim_bones.append(idx)

	_build_animation(_skeleton.get_parent())
	_build_hand_attachment()
	_play("idle")


## The CC0 base character is an UNCLOTHED body in a single skin tone, which from
## inside the first-person camera reads as indistinguishable flesh-coloured
## shapes. Painting it a dark suit at least gives the limbs a readable silhouette
## until a properly clothed/armoured character model replaces it.
func _apply_suit(hero: Node3D) -> void:
	var suit := StandardMaterial3D.new()
	suit.albedo_color = Color(0.13, 0.15, 0.20)
	suit.metallic = 0.35
	suit.roughness = 0.55
	for m in hero.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).material_override = suit


## Bone lookup that tolerates the rig's inconsistent capitalisation.
func _find_bone_ci(bone: String) -> int:
	var idx := _skeleton.find_bone(bone)
	if idx >= 0:
		return idx
	var want := bone.to_lower()
	for i in _skeleton.get_bone_count():
		if _skeleton.get_bone_name(i).to_lower() == want:
			return i
	return -1


## Collect the rifle loops into one library on an AnimationPlayer whose root is
## the Armature, so the clips' "Skeleton3D:<bone>" tracks resolve.
func _build_animation(armature: Node) -> void:
	var lib := AnimationLibrary.new()
	for state in CLIPS:
		var scene: Resource = load(RIFLE_DIR + String(CLIPS[state]))
		if not (scene is PackedScene):
			continue
		var inst := (scene as PackedScene).instantiate()
		var aps := inst.find_children("*", "AnimationPlayer", true, false)
		if not aps.is_empty():
			var src := aps[0] as AnimationPlayer
			var names := src.get_animation_list()
			if names.size() > 0:
				var clip: Animation = src.get_animation(names[0]).duplicate()
				clip.loop_mode = Animation.LOOP_LINEAR
				lib.add_animation(state, clip)
		inst.queue_free()
	if lib.get_animation_list().is_empty():
		return
	_anim = AnimationPlayer.new()
	armature.add_child(_anim)
	_anim.root_node = NodePath("..")          # the Armature; "Skeleton3D:bone" resolves
	_anim.add_animation_library("loco", lib)


## Hang the equipped weapon off the right hand, so the arms actually hold it.
func _build_hand_attachment() -> void:
	if _skeleton == null or _skeleton.find_bone(HAND_BONE) < 0:
		return
	_hand_attach = BoneAttachment3D.new()
	_hand_attach.bone_name = HAND_BONE
	_skeleton.add_child(_hand_attach)
	_hand_attach.set_use_external_skeleton(false)


## Show the weapon `name_` in the character's hand (mirrors the viewmodel's
## naming: "Auto Rifle" -> weapons/auto_rifle.tscn).
func set_weapon(name_: String) -> void:
	# Off by default: the weapon wrappers are built and sized for the camera
	# viewmodel, so dropping one straight onto the hand bone put the gun through
	# the Guardian's torso and pointing at his own head. Until each weapon has a
	# proper per-weapon grip transform, the camera viewmodel draws the gun.
	if not hand_weapon_enabled or _hand_attach == null:
		return
	if _weapon_model and is_instance_valid(_weapon_model):
		_weapon_model.queue_free()
		_weapon_model = null
	var file := name_.to_lower().replace(" ", "_")
	for ext in ["tscn", "glb", "gltf", "scn"]:
		var path := "%s%s.%s" % [WEAPON_DIR, file, ext]
		if not ResourceLoader.exists(path):
			continue
		var scene: Resource = load(path)
		if scene is PackedScene:
			_weapon_model = (scene as PackedScene).instantiate() as Node3D
			_hand_attach.add_child(_weapon_model)
			var grip: Dictionary = GRIPS.get(name_, GRIP_DEFAULT)
			_weapon_model.position = grip["pos"]
			_weapon_model.rotation_degrees = grip["rot"]
			_weapon_model.scale = Vector3.ONE * float(grip["scale"])
			_weapon_model.visible = weapon_drawn
		return


## Holster/draw the held weapon (the Guardian is unarmed in the hub).
func set_weapon_visible(shown: bool) -> void:
	weapon_drawn = shown
	if _weapon_model and is_instance_valid(_weapon_model):
		_weapon_model.visible = shown


func _play(state: String) -> void:
	if _anim == null:
		return
	var key := "loco/" + state
	if _current != key and _anim.has_animation(key):
		_anim.play(key, 0.18)                  # short cross-fade between states
		_current = key


## Kept for the Guardian's call site. The earlier version rewrote the spine bones
## from their REST pose every frame, which threw away the animation's own torso
## rotation and mangled the upper body - so the aim offset is off until it can be
## done properly (additively, on top of the animated pose).
func set_aim_pitch(pitch: float) -> void:
	_aim_pitch = pitch


func _process(_delta: float) -> void:
	if _skeleton == null:
		return
	# The camera lives inside the head, so shrink the head bone away. This runs
	# after the AnimationPlayer (process_priority above) so it isn't overwritten.
	# Scaled rather than zeroed: an exact zero collapses the head vertices into a
	# degenerate spike of triangles right in front of the camera.
	if _head_bone >= 0:
		_skeleton.set_bone_pose_scale(_head_bone, Vector3.ONE * 0.01)
	# The neck is deliberately left alone - hiding it took away part of the body
	# you should see when you look down.

	# Aim offset, applied ADDITIVELY: the animated pose rotation is kept and the
	# look pitch is layered on top of it. (The first attempt built the rotation
	# from the bone's REST pose, which threw the animation away and mangled the
	# torso.) Spreading it over the upper spine carries the chest, arms and the
	# gun they hold with the camera, so the weapon points where you look instead
	# of hanging down.
	if not _aim_bones.is_empty():
		var per := -_aim_pitch * AIM_STRENGTH / float(_aim_bones.size())
		for idx in _aim_bones:
			var posed := _skeleton.get_bone_pose_rotation(idx)
			_skeleton.set_bone_pose_rotation(idx, posed * Quaternion(Vector3.RIGHT, per))


## Drive the locomotion state from the Guardian's movement. `local_dir` is the
## travel direction in the body's own space (x = right, z = forward is -z), so
## strafing and backing up play their own clips instead of a forward walk.
func set_speed(speed: float, local_dir := Vector2.ZERO, airborne := false) -> void:
	if airborne and _anim and _anim.has_animation("loco/jump"):
		_play("jump")
		return
	if speed < WALK_SPEED:
		_play("idle")
		return
	var running: bool = speed >= RUN_SPEED
	# Sideways only when it clearly dominates the forward component.
	if absf(local_dir.x) > absf(local_dir.y) * 1.4:
		_play("walk_right" if local_dir.x > 0.0 else "walk_left")
	elif local_dir.y > 0.35:                       # travelling backwards
		_play("run_back" if running else "walk_back")
	else:
		_play("sprint" if running else "walk")

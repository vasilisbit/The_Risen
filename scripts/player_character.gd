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

const MODEL := "res://assets/thirdparty/Universal Base Characters[Standard]/Base Characters/Godot - UE/Superhero_Male_FullBody.gltf"
const RIFLE_DIR := "res://assets/thirdparty/fab/Pistol and Rifle Locomotion Animations 1700/_FixedRifle/"
## state -> clip file. Each FBX holds a single animation called "Unreal Take".
const CLIPS := {
	"idle": "Idle/M_Neutral_Stand_Idle_Loop_Rifle.FBX",
	"walk": "Walk/M_Neutral_Walk_Loop_F_Rifle.FBX",
	"run": "Run/M_Neutral_Run_Loop_F_Rifle.FBX",
	"sprint": "Sprint/M_Neutral_Sprint_Loop_F_Rifle.FBX",
}
const WEAPON_DIR := "res://assets/thirdparty/weapons/"

const WALK_SPEED := 0.4      # above this = walk
const RUN_SPEED := 4.8       # above this = sprint

## Bones we drive directly. The Superhero rig capitalises the head ("Head") while
## the hands are lower-case, so the head is looked up case-insensitively.
const HEAD_BONE := "Head"
const HAND_BONE := "hand_r"
## Upper-spine bones the aim offset is spread across, so the chest (and with it
## the arms and the gun) tilts toward wherever the camera is looking. Without
## this the body stays level and the rifle sits below the screen.
const AIM_BONES := ["spine_02", "spine_03"]

## Where the gun sits in the right hand (tuned so the grip meets the palm).
const HAND_WEAPON_POS := Vector3(0.0, 0.03, 0.02)
const HAND_WEAPON_ROT := Vector3(0.0, 90.0, 0.0)
const HAND_WEAPON_SCALE := 1.0

var _anim: AnimationPlayer
var _skeleton: Skeleton3D
var _head_bone: int = -1
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

	var skels := hero.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return
	_skeleton = skels[0] as Skeleton3D
	_head_bone = _find_bone_ci(HEAD_BONE)
	for b in AIM_BONES:
		var idx := _find_bone_ci(String(b))
		if idx >= 0:
			_aim_bones.append(idx)

	_build_animation(_skeleton.get_parent())
	_build_hand_attachment()
	_play("idle")


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
	if _hand_attach == null:
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
			_weapon_model.position = HAND_WEAPON_POS
			_weapon_model.rotation_degrees = HAND_WEAPON_ROT
			_weapon_model.scale = Vector3.ONE * HAND_WEAPON_SCALE
		return


func _play(state: String) -> void:
	if _anim == null:
		return
	var key := "loco/" + state
	if _current != key and _anim.has_animation(key):
		_anim.play(key, 0.18)                  # short cross-fade between states
		_current = key


## Tilt the upper body toward where the camera is looking (radians; negative is
## up in the Guardian's pitch convention). Called by the Guardian each frame.
func set_aim_pitch(pitch: float) -> void:
	_aim_pitch = pitch


func _process(_delta: float) -> void:
	if _skeleton == null:
		return
	# The camera lives inside the head, so collapse the head bone - this runs
	# after the AnimationPlayer (process_priority above), so it isn't overwritten.
	if _head_bone >= 0:
		_skeleton.set_bone_pose_scale(_head_bone, Vector3.ONE * 0.001)
	# Spread the aim pitch across the upper spine so the chest, arms and the gun
	# they hold follow the camera instead of staying level.
	if not _aim_bones.is_empty():
		var per := -_aim_pitch / float(_aim_bones.size())
		for idx in _aim_bones:
			var rest := _skeleton.get_bone_rest(idx)
			_skeleton.set_bone_pose_rotation(idx,
				rest.basis.get_rotation_quaternion() * Quaternion(Vector3.RIGHT, per))


## Drive the locomotion state from the Guardian's horizontal speed.
func set_speed(speed: float) -> void:
	if speed < WALK_SPEED:
		_play("idle")
	elif speed < RUN_SPEED:
		_play("walk")
	else:
		_play("sprint")

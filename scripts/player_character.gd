extends Node3D
## The Guardian's real body, seen from a TRUE first-person camera (Phase 3):
## look down and you see your chest, hips and legs, and the gun is held in the
## character's own hands rather than floating in front of the camera.
##
## Model (T-0042): a CUSTOM Guardian generated on the fal.ai pipeline and rigged
## with Meshy (route 2 - docs/FAL_PIPELINE.md 6/9A/10). It replaces the placeholder
## UEFN mannequin. The rig is a 24-bone Mixamo-style humanoid; the GLB ships its own
## AnimationPlayer with idle/walk/run (Meshy's basic set + the idle preset, root
## motion stripped so the loops play in place - tools/gen_guardian.py + a Blender
## merge). We drive that shipped mixer in MANUAL mode and advance it at the top of
## _process, so the additive aim offset below lands on top of the animated pose
## instead of being overwritten by it.
##
## The head bone is scaled to nothing every frame, because the camera sits inside
## the head - otherwise you would be looking at the inside of the skull.

## The custom Guardian GLB (mesh + Meshy rig + idle/walk/run), built by
## tools/gen_guardian.py -> Blender merge. Its AnimationPlayer is used as-is.
const MODEL := "res://assets/generated/guardian/guardian.glb"
## The Meshy rig ships a small generic locomotion set (idle/walk/run). Every game
## locomotion state maps onto the nearest available clip until a fuller moveset is
## baked (Meshy multi-animation, docs/FAL_PIPELINE 6.1). Strafe/back reuse walk,
## sprint/jump reuse run, turn-in-place reuses idle.
const STATE_MAP := {
	"idle": "idle", "gun_idle": "gun_idle",
	"walk": "walk", "walk_back": "walk", "walk_left": "walk", "walk_right": "walk",
	"run": "run", "run_back": "run", "sprint": "run", "jump": "run",
	"turn_left": "idle", "turn_right": "idle",
}
const WEAPON_DIR := "res://assets/generated/weapons/"

const WALK_SPEED := 0.4      # above this = walk
const RUN_SPEED := 4.8       # above this = sprint

## Bones we drive directly, on the Meshy humanoid rig (24 bones). The head is
## collapsed (the camera sits inside it); the single "neck" bone is left alone so
## looking down still shows the upper chest.
const HEAD_BONE := "Head"
const NECK_BONES := ["neck"]
## The Meshy rig has no dedicated weapon socket, so the gun hangs off the right
## HAND bone; the grip transform (GRIPS) seats it in the palm.
const HAND_BONE := "RightHand"
## Upper-spine bones the aim offset is spread across, so the chest (and with it the
## arms and the gun) tilts toward wherever the camera is looking. On this rig the
## chain runs Hips -> Spine02 -> Spine01 -> Spine, so the UPPER two (nearest the
## shoulders) are Spine and Spine01.
const AIM_BONES := ["Spine", "Spine01"]
## How much of the look pitch the torso takes (spread across the aim bones).
@export var aim_strength: float = 1.0
## Constant upper-body lean added on top of the pitch tracking (see the old note:
## the natural pose already reads as a viewmodel, so kept 0 by default).
@export var aim_base_lift: float = 0.0
## The aim lean axis in SKELETON space, converted into each bone's local frame every
## frame. Skeleton +X is the character's left-right, so a rotation about it leans the
## torso forward/back. Sign/axis tuned live per rig.
@export var aim_axis: Vector3 = Vector3(1, 0, 0)
## Optional shoulder-raise (swing both upper arms up). Kept 0 by default.
const ARM_BONES := ["LeftArm", "RightArm"]
@export var arm_lift: float = 0.0

## Left (support) arm bones, swung DOWN off the gun for weapons that need the
## support hand adjusted. Amount per weapon in SUPPORT_LOWER (set in set_weapon).
const LEFT_ARM_BONES := ["LeftArm", "LeftForeArm"]
## Per-weapon support-hand lower (radians about the skeleton left-right axis).
const SUPPORT_LOWER := {}
## Weapons held in ONE hand: the whole left arm is collapsed to nothing (its root
## bone scaled to ~0), so no support arm shows at all.
const HIDE_LEFT_ARM := {"Hand Cannon": true}
const LEFT_ARM_ROOT := "LeftShoulder"

## Render layer the real body sits on so the main camera can exclude it (true
## first person - no own neck/back) while the mirror camera still shows it.
const BODY_LAYER := 1 << 18

## Dedicated first-person arms: when true this instance shows ONLY the forearms and
## hands (armoured gauntlets) - the torso/legs/head are discarded per-vertex, so the
## viewmodel needs no near-plane clip and has no hard cut. Set on the viewmodel rig.
@export var arms_only: bool = false
## Bone-name fragments whose vertices are KEPT for arms_only; everything weighted
## mainly to any other bone is discarded. The Meshy rig names the lower arms
## LeftForeArm/RightForeArm and the hands LeftHand/RightHand (no finger bones - the
## gauntlets are rigid), so "forearm" + "hand" keep exactly the forearms + gauntlets.
const ARM_KEEP := ["forearm", "hand"]

## Grip transform for the weapon on the RightHand bone. The Meshy hand bone's axes
## differ from the old UEFN weapon socket, so this is re-derived for this rig. The
## generated guns (T-0041) are canonicalised (barrel -X, sight +Y, origin at the
## grip, metres) by tools/orient_weapons.py, so they share ONE grip orientation.
## GRIP_SCALE counters the Meshy armature's 0.01 scale (the BoneAttachment inherits
## it, so an unscaled weapon would render 100x too small).
const GRIP_SCALE := 100.0
## Solved in-engine against the frozen gun_idle hand pose so the barrel (-X) points
## down the FP camera's forward and the sight (+Y) points up (lower-right framing).
const GRIP_ROT := Vector3(-29.7, 119.5, -108.2)
const GRIP_DEFAULT := {"pos": Vector3.ZERO, "rot": GRIP_ROT, "scale": GRIP_SCALE}
const GRIPS := {
	"Auto Rifle": {"pos": Vector3.ZERO, "rot": GRIP_ROT, "scale": GRIP_SCALE},
	"Shotgun": {"pos": Vector3.ZERO, "rot": GRIP_ROT, "scale": GRIP_SCALE},
	"Sniper": {"pos": Vector3.ZERO, "rot": GRIP_ROT, "scale": GRIP_SCALE},
	"Hand Cannon": {"pos": Vector3.ZERO, "rot": GRIP_ROT, "scale": GRIP_SCALE},
}

## The first-person arms hold a STATIC gun pose (the gun_idle clip animates the
## hand, which would swing the weapon), frozen at this normalised time so the grip
## stays put. fp_viewmodel adds the recoil/sway on top.
const FP_POSE_T := 0.5

## Put the gun in the character's hand instead of drawing the camera viewmodel.
@export var hand_weapon_enabled: bool = true
## Whether the held weapon is drawn (false in the hub - see set_weapon_visible).
var weapon_drawn: bool = true

## Body material tuning: the gen ships one StandardMaterial3D (albedo texture only,
## metallic=1/roughness=1). Meshy lightened the albedo vs the dark concept, so tint
## it hard back toward near-black gunmetal; keep metalness modest + roughness high
## so it doesn't blow out bright under the hub lights / in the mirror.
const BODY_METALLIC := 0.15
const BODY_ROUGHNESS := 0.7
const BODY_TINT := Color(0.19, 0.2, 0.25)

var _anim: AnimationPlayer
var _skeleton: Skeleton3D
var _head_bone: int = -1
var _neck_bones: Array[int] = []
var _hand_attach: BoneAttachment3D
var _weapon_model: Node3D
var _current: String = ""
var _aim_bones: Array[int] = []
var _arm_bones: Array[int] = []
var _left_arm_bones: Array[int] = []
var _left_arm_root: int = -1        # LeftShoulder, collapsed for one-handed weapons
var _support_lower: float = 0.0     # how far to drop the support arm (per weapon)
var _hide_left_arm: bool = false    # true for one-handed weapons (Hand Cannon)
var _aim_pitch: float = 0.0
var _frozen: bool = false           # FP arms: hold a single frozen gun pose


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
	for b in NECK_BONES:
		var n := _find_bone_ci(String(b))
		if n >= 0:
			_neck_bones.append(n)
	for b in AIM_BONES:
		var idx := _find_bone_ci(String(b))
		if idx >= 0:
			_aim_bones.append(idx)
	for b in ARM_BONES:
		var idx := _find_bone_ci(String(b))
		if idx >= 0:
			_arm_bones.append(idx)
	for b in LEFT_ARM_BONES:
		var idx := _find_bone_ci(String(b))
		if idx >= 0:
			_left_arm_bones.append(idx)
	_left_arm_root = _find_bone_ci(LEFT_ARM_ROOT)

	if arms_only:
		_mask_to_arms(hero)
	else:
		_prep_body(hero)

	_setup_animation(hero)
	_build_hand_attachment()
	# The first-person arms rig holds the gun (a rifle-hold pose); the full body
	# in the hub is unarmed, so it idles. The FP hold is FROZEN at one frame so the
	# grip stays steady (the clip turns the hand otherwise).
	_play("gun_idle" if arms_only else "idle")
	if arms_only and _anim and _anim.has_animation("gun_idle"):
		_frozen = true
		_anim.seek(_anim.get_animation("gun_idle").length * FP_POSE_T, true)


## Keep the generated Guardian textures, but put the body on its own render layer
## (so the main first-person camera skips it while the hub mirror still shows it)
## and punch the flat gen material toward armoured plate. Runs on the real body,
## not the arms-only viewmodel (which uses the discard mask below).
func _prep_body(hero: Node3D) -> void:
	for m in hero.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		mi.layers = BODY_LAYER
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var base := mi.get_active_material(s)
			if not (base is BaseMaterial3D):
				continue
			var mat: BaseMaterial3D = base.duplicate()
			mat.albedo_color = BODY_TINT          # multiplies the (too-light) gen texture
			mat.metallic = BODY_METALLIC
			mat.roughness = BODY_ROUGHNESS
			mat.metallic_specular = 0.55
			mi.set_surface_override_material(s, mat)


## Turn the full Guardian into an arms-only viewmodel mesh WITHOUT losing the
## gauntlet textures: bake a per-vertex keep/drop mask into vertex colours (a
## vertex is "arm" when its dominant skin bone is a forearm/hand bone) and swap in
## a shader that samples the original albedo texture and discards dropped fragments.
## The skin (bones + weights) is preserved, so the gauntlets still animate.
func _mask_to_arms(hero: Node3D) -> void:
	var keep := {}
	for i in _skeleton.get_bone_count():
		var nm := _skeleton.get_bone_name(i).to_lower()
		for frag in ARM_KEEP:
			if nm.contains(frag):
				keep[i] = true
				break
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec3 tint = vec3(0.19, 0.2, 0.25);
uniform float metallic_v = 0.15;
uniform float roughness_v = 0.7;
void fragment() {
	if (COLOR.r < 0.5) { discard; }
	ALBEDO = texture(albedo_tex, UV).rgb * tint;
	METALLIC = metallic_v;
	ROUGHNESS = roughness_v;
}
"""
	for m in hero.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var mesh := mi.mesh
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		# Pull the generated albedo texture off the imported material so the
		# gauntlets read with their real armour texture (falls back to flat).
		var albedo_tex: Texture2D = null
		var src := mi.get_active_material(0)
		if src is BaseMaterial3D:
			albedo_tex = (src as BaseMaterial3D).albedo_texture
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("albedo_tex", albedo_tex)
		mat.set_shader_parameter("tint", Vector3(BODY_TINT.r, BODY_TINT.g, BODY_TINT.b))
		mat.set_shader_parameter("metallic_v", BODY_METALLIC)
		mat.set_shader_parameter("roughness_v", BODY_ROUGHNESS)

		var new_mesh := ArrayMesh.new()
		for s in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(s)
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var vcount: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			if bones.is_empty() or vcount == 0:
				new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				continue
			var per := bones.size() / vcount          # 4 or 8 bone influences per vertex
			var colors := PackedColorArray()
			colors.resize(vcount)
			for v in vcount:
				var best_w := -1.0
				var best_b := 0
				for k in per:
					var w := weights[v * per + k]
					if w > best_w:
						best_w = w
						best_b = bones[v * per + k]
				colors[v] = Color.WHITE if keep.has(best_b) else Color(0, 0, 0, 1)
			arrays[Mesh.ARRAY_COLOR] = colors
			new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mi.mesh = new_mesh
		mi.material_override = mat


## Bone lookup that tolerates inconsistent capitalisation across rigs.
func _find_bone_ci(bone: String) -> int:
	var idx := _skeleton.find_bone(bone)
	if idx >= 0:
		return idx
	var want := bone.to_lower()
	for i in _skeleton.get_bone_count():
		if _skeleton.get_bone_name(i).to_lower() == want:
			return i
	return -1


## Use the AnimationPlayer that ships inside the imported Guardian GLB (its tracks
## and root_node are already wired to the rig). Driven manually and advanced at the
## top of _process so the additive aim offset survives.
func _setup_animation(hero: Node3D) -> void:
	var aps := hero.find_children("*", "AnimationPlayer", true, false)
	if aps.is_empty():
		return
	_anim = aps[0] as AnimationPlayer
	_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	# glTF import leaves animations non-looping, so the cyclic states would play once
	# and freeze. Loop the locomotion + hold clips (reload/shoot stay one-shot).
	for a in ["idle", "walk", "run", "gun_idle"]:
		if _anim.has_animation(a):
			_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR


## Hang the equipped weapon off the right hand, so the arms actually hold it.
func _build_hand_attachment() -> void:
	if _skeleton == null or _find_bone_ci(HAND_BONE) < 0:
		return
	_hand_attach = BoneAttachment3D.new()
	_hand_attach.bone_name = _skeleton.get_bone_name(_find_bone_ci(HAND_BONE))
	_skeleton.add_child(_hand_attach)
	_hand_attach.set_use_external_skeleton(false)


## Show the weapon `name_` in the character's hand (mirrors the viewmodel's
## naming: "Auto Rifle" -> weapons/auto_rifle.glb).
func set_weapon(name_: String) -> void:
	if not hand_weapon_enabled or _hand_attach == null:
		return
	_support_lower = float(SUPPORT_LOWER.get(name_, 0.0))
	_hide_left_arm = HIDE_LEFT_ARM.has(name_)
	if _weapon_model and is_instance_valid(_weapon_model):
		_weapon_model.queue_free()
		_weapon_model = null
	var file := name_.to_lower().replace(" ", "_")
	for ext in ["glb", "gltf", "tscn", "scn"]:
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
			_metalize_weapon(_weapon_model)
		return


## Punch the metal on a generated weapon (T-0041 / FAL_PIPELINE 10.3: the raw
## roughness/metalness a 3D gen ships is weak). Keeps the generated Color/Normal
## textures but drives metallic to full and trims roughness, via a per-surface
## override so the shared imported material isn't mutated for every instance.
func _metalize_weapon(model: Node3D) -> void:
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var base := mi.get_active_material(s)
			if not (base is BaseMaterial3D):
				continue
			var mat: BaseMaterial3D = base.duplicate()
			mat.metallic = 1.0
			mat.roughness = clampf(mat.roughness * 0.7, 0.08, 1.0)
			mat.metallic_specular = 0.6
			mi.set_surface_override_material(s, mat)


## Holster/draw the held weapon (the Guardian is unarmed in the hub).
func set_weapon_visible(shown: bool) -> void:
	weapon_drawn = shown
	if _weapon_model and is_instance_valid(_weapon_model):
		_weapon_model.visible = shown


## Resolve a game locomotion state to a clip the Meshy rig actually ships. Falls
## back to idle if the mapped clip isn't present (e.g. gun_idle before the moveset
## is merged in).
func _resolve(state: String) -> String:
	var clip := String(STATE_MAP.get(state, "idle"))
	if _anim and not _anim.has_animation(clip):
		return "idle"
	return clip


func _play(state: String) -> void:
	if _anim == null:
		return
	var clip := _resolve(state)
	if _current != clip and _anim.has_animation(clip):
		_anim.play(clip, 0.18)                  # short cross-fade between states
		_current = clip


## Kept for the Guardian's call site.
func set_aim_pitch(pitch: float) -> void:
	_aim_pitch = pitch


func _process(_delta: float) -> void:
	if _skeleton == null:
		return
	# Advance the (manual-mode) mixer first, so everything below layers on top of
	# the freshly written animated pose rather than being overwritten by it. The FP
	# arms normally hold a frozen pose (seeked once in _ready); a reload temporarily
	# unfreezes and plays the reload clip (time-scaled to the weapon's reload_time),
	# then returns to the frozen hold.
	if _anim and not _frozen:
		_anim.advance(_delta)
	# NOTE: the head is NOT collapsed here. The main first-person camera already skips
	# the body's render layer (guardian.gd), so the head is never in the player's own
	# view - and collapsing it left the hub MIRROR reflection headless. The FP arms
	# rig discards the head via the arms-only mask, so it needs no collapse either.

	# Aim offset, applied ADDITIVELY on top of the animated pose. Spreading it over
	# the upper spine carries the chest, arms and gun with the camera.
	var sk_axis := aim_axis.normalized()
	if not _aim_bones.is_empty():
		var per := (-_aim_pitch * aim_strength + aim_base_lift) / float(_aim_bones.size())
		for idx in _aim_bones:
			var b := _skeleton.get_bone_global_pose(idx).basis.orthonormalized()
			var local_axis := (b.transposed() * sk_axis).normalized()
			var posed := _skeleton.get_bone_pose_rotation(idx)
			_skeleton.set_bone_pose_rotation(idx, posed * Quaternion(local_axis, per))

	# Shoulder lift (optional): swing both upper arms up. Only while the weapon is
	# drawn - in the hub it is holstered.
	if arm_lift != 0.0 and weapon_drawn and not _arm_bones.is_empty():
		for idx in _arm_bones:
			var b := _skeleton.get_bone_global_pose(idx).basis.orthonormalized()
			var local_axis := (b.transposed() * sk_axis).normalized()
			var posed := _skeleton.get_bone_pose_rotation(idx)
			_skeleton.set_bone_pose_rotation(idx, posed * Quaternion(local_axis, arm_lift))

	# One-handed weapons (Hand Cannon) collapse the whole left arm so no support arm
	# is drawn; every other weapon must RESTORE the scale to 1 each frame (the clips
	# carry no scale track, so a leftover collapse would strip later weapons' hands).
	# The FP arms viewmodel ALWAYS collapses the left arm: the Meshy gun-hold pose
	# leaves the left hand back off the gun (and there are no finger bones to grip a
	# foregrip), so a lone right hand + gun reads as a clean FPS viewmodel. The
	# third-person body (arms_only=false, seen in the mirror) keeps both arms.
	if _left_arm_root >= 0:
		var hide_left := _hide_left_arm or arms_only
		var arm_scale := 0.01 if (hide_left and weapon_drawn) else 1.0
		_skeleton.set_bone_pose_scale(_left_arm_root, Vector3.ONE * arm_scale)
	# Optional per-weapon support-hand nudge (only while the support arm is shown).
	if not _hide_left_arm and _support_lower != 0.0 and weapon_drawn and not _left_arm_bones.is_empty():
		for idx in _left_arm_bones:
			var b := _skeleton.get_bone_global_pose(idx).basis.orthonormalized()
			var local_axis := (b.transposed() * sk_axis).normalized()
			var posed := _skeleton.get_bone_pose_rotation(idx)
			_skeleton.set_bone_pose_rotation(idx, posed * Quaternion(local_axis, _support_lower))


## Above this yaw rate (rad/s) while standing still, the feet step round with a
## turn-in-place clip instead of the whole body pivoting under a static idle.
const TURN_RATE := 1.2

## Drive the locomotion state from the Guardian's movement. `local_dir` is the
## travel direction in the body's own space (x = right, z = forward is -z), so
## strafing and backing up play their own clips. `yaw_rate` (rad/s) drives
## turn-in-place while stationary.
func set_speed(speed: float, local_dir := Vector2.ZERO, airborne := false,
		yaw_rate := 0.0) -> void:
	if airborne and _anim and _anim.has_animation(_resolve("jump")):
		_play("jump")
		return
	if speed < WALK_SPEED:
		if absf(yaw_rate) > TURN_RATE:
			_play("turn_left" if yaw_rate > 0.0 else "turn_right")
		else:
			_play("idle")
		return
	var running: bool = speed >= RUN_SPEED
	if absf(local_dir.x) > absf(local_dir.y) * 1.4:
		_play("walk_right" if local_dir.x > 0.0 else "walk_left")
	elif local_dir.y > 0.35:                       # travelling backwards
		_play("run_back" if running else "walk_back")
	else:
		_play("sprint" if running else "walk")

extends Node3D
## Animated third-person Guardian body (Phase 3). The Quaternius Superhero mesh
## driven by the Universal Animation Library - both share the same 65-bone
## "Armature/Skeleton3D" rig, so the UAL clips retarget onto the hero with no
## bone mapping (just add the library and point root_node at the hero). Plays
## idle / walk / run off the horizontal speed the Guardian feeds it each frame.

const MODEL := "res://assets/thirdparty/Universal Base Characters[Standard]/Base Characters/Godot - UE/Superhero_Male_FullBody.gltf"
const ANIMS := "res://assets/thirdparty/Universal Animation Library[Standard]/Unreal-Godot/UAL1_Standard.glb"

const WALK_SPEED := 0.4      # above this = walk
const RUN_SPEED := 4.8       # above this = sprint

var _anim: AnimationPlayer
var _current: String = ""


func _ready() -> void:
	var hero_scene: Resource = load(MODEL)
	if not (hero_scene is PackedScene):
		return
	var hero := (hero_scene as PackedScene).instantiate() as Node3D
	add_child(hero)

	# Pull the UAL animation library and drive the hero's skeleton with it.
	var ual_scene: Resource = load(ANIMS)
	if ual_scene is PackedScene:
		var ual := (ual_scene as PackedScene).instantiate()
		var ual_aps := ual.find_children("*", "AnimationPlayer", true, false)
		if not ual_aps.is_empty():
			var lib: AnimationLibrary = (ual_aps[0] as AnimationPlayer).get_animation_library("")
			_anim = AnimationPlayer.new()
			hero.add_child(_anim)
			_anim.root_node = NodePath("..")          # -> hero root; Armature/Skeleton3D resolves
			_anim.add_animation_library("ual", lib)
			for n in ["Idle", "Walk", "Sprint"]:
				if lib.has_animation(n):
					lib.get_animation(n).loop_mode = Animation.LOOP_LINEAR
			_play("Idle")
		ual.queue_free()


func _play(anim: String) -> void:
	if _anim == null:
		return
	var key := "ual/" + anim
	if _current != key and _anim.has_animation(key):
		_anim.play(key, 0.15)                          # short cross-fade between states
		_current = key


## Drive the locomotion state from the Guardian's horizontal speed.
func set_speed(speed: float) -> void:
	if speed < WALK_SPEED:
		_play("Idle")
	elif speed < RUN_SPEED:
		_play("Walk")
	else:
		_play("Sprint")

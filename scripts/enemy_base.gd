class_name EnemyBase
extends CharacterBody3D

## Shared enemy plumbing (T-0007/T-0008/T-0009): health, damage intake, death
## signal, loot drop, player lookup, gravity, headshot test. Subclasses set
## `max_health` in _init() and implement their own _physics_process guarding on
## `_dead`.

signal died(where: Vector3)

## Loot spawned on death. If unset, the shared loot_drop.tscn (T-0011) is used.
@export var loot_scene: PackedScene

## Local height (from the body origin at the feet) at/above which a hit counts
## as a headshot - matches the 1.8 m capsule (top hemisphere).
const HEAD_MIN_LOCAL_Y := 1.4
const LOOT_SCENE_PATH := "res://scenes/weapons/loot_drop.tscn"
const NAMEPLATE_SCENE_PATH := "res://scripts/enemy_nameplate.gd"

## Physics layers. Enemies occupy their OWN layer, NOT the world/player layer 1,
## so the PLAYER (layer 1, default mask) never physically collides with them: a
## crowd can no longer pin you or stand on your head. Enemies still collide with
## the world (layer 1) to walk the floor, and with EACH OTHER (ENEMY_LAYER) so a
## wave doesn't spawn stacked on one spot. The player's hitscan masks both layers
## explicitly (see Weapon.HIT_MASK) since enemies are no longer on layer 1.
const WORLD_LAYER := 1
const ENEMY_LAYER := 1 << 4        # physics layer 5 (value 16)

## Display names for the floating nameplate, keyed by the subclass class_name.
const NAMES := {
	"Rusher": "Risen Rusher",
	"Shooter": "Risen Shooter",
	"Exploder": "Volatile Exploder",
	"ShieldedBrute": "Shielded Brute",
	"Phantom": "Teleporting Phantom",
	"EmberTyrant": "Ember Tyrant",
}

## Whether this enemy shows a floating nameplate. On by default; a subclass can
## suppress it (e.g. if it drives its own dedicated boss UI).
var show_nameplate: bool = true

## Mission-wide enemy modifiers set by the Mars debuff picks (T-0018). Static so
## they apply to every enemy, including ones spawned later. Reset per mission.
static var speed_scale: float = 1.0          # -10% speed pick -> 0.9
static var accuracy_penalty: float = 0.0     # -5% accuracy pick -> 0.05


static func reset_modifiers() -> void:
	speed_scale = 1.0
	accuracy_penalty = 0.0

## Force a loot rarity on death (e.g. a boss guaranteeing an Epic). Empty = roll.
var loot_rarity_override: String = ""
## Probability this enemy drops anything at all (GDD §2.7: loot is a chance, not
## a guarantee, so the floor doesn't carpet with pickups). Bosses/minibosses set
## this to 1.0, and a forced rarity always drops regardless.
var loot_chance: float = 0.3
## Probability a drop is armour rather than a weapon. Armour is the rarer find.
var armor_drop_chance: float = 0.18

var max_health: float = 100.0
var health: float = 100.0
## Flux awarded on death. Subclasses raise it in _init(); bosses pay far more.
## GDD 2.5 estimates ~200 Flux for Earth, which these values roughly hit. Mars
## pays considerably more than its ~500 estimate because it actually contains
## about 210 enemies, not the ~50 that estimate implies.
var flux_value: int = 3
## Seconds of stun left; while > 0 the enemy takes no actions.
var stun_left: float = 0.0

## Heroic/Legendary shield pool (T-0027), absorbed before health. GDD §2.8: an
## elemental shield takes BONUS damage from a matching-element weapon and only
## chip damage from a mismatched one. shield_element is the element that counters
## it; "Kinetic" means a plain (non-elemental) shield that any damage breaks.
var elemental_shield: float = 0.0
var max_elemental_shield: float = 0.0
var shield_element: String = "Kinetic"
## Element of the shot currently being absorbed, stamped by mark_damage_source
## just before take_damage (which weapons always call). Consumed - and reset to
## Kinetic - by absorb_shield, so each shield hit uses its own shot's element.
var incoming_element: String = "Kinetic"

## Shield damage multipliers vs an elemental shield (GDD §2.8).
const SHIELD_MATCH_MULT := 2.0     # matching element: breaks the shield fast
const SHIELD_MISMATCH_MULT := 0.1  # off-element / Kinetic: chip only, little bleed-through

## Shield regeneration: a shielded enemy that avoids ALL damage (to shield or
## health) for SHIELD_REGEN_DELAY seconds starts recharging its shield, refilling
## from empty to full over SHIELD_REGEN_TIME. Any hit resets the wait (see
## take_damage / absorb_shield). Ticked in _process so it runs even while stunned.
## Only enemies that spawned with a shield (Heroic/Legendary) ever regen.
const SHIELD_REGEN_DELAY := 5.0    # s without damage before regen begins
const SHIELD_REGEN_TIME := 3.0     # s to refill from empty to full
var _shield_regen_wait: float = 0.0   # s since the last damage taken

## Knockback displacement budget (Ground Slam), spent over PUSH_TIME seconds.
const PUSH_TIME := 0.3
var _push_velocity: Vector3 = Vector3.ZERO
var _push_time_left: float = 0.0
var _dead: bool = false
var _player: Node3D = null

## Enemy vocalization (Destiny-2 Hive inspired): each subclass returns its SFX id from
## _enemy_voice(). Played once shortly after spawn (staggered) then at random intervals
## while alive, positionally, so a nearby creature snarls/laughs/roars now and then.
const VOICE_MIN := 8.0
const VOICE_MAX := 18.0
var _voice_id: String = ""
var _voice_left: float = -1.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)


func _ready() -> void:
	add_to_group("enemy")
	# Move off the shared world/player layer so the player can't be pinned or
	# stood on; still collide with the world and with other enemies.
	collision_layer = ENEMY_LAYER
	collision_mask = WORLD_LAYER | ENEMY_LAYER
	_apply_difficulty()
	health = max_health
	_player = _find_player()
	_last_pos = global_position
	_last_grounded_y = global_position.y
	_apply_external_model()
	if show_nameplate:
		_build_nameplate()
	# Spawn cry shortly after appearing (0.3-0.9 s stagger so a wave doesn't shout in unison).
	_voice_id = _enemy_voice()
	if _voice_id != "":
		_voice_left = randf_range(0.3, 0.9)


## Subclass hook: the enemy's vocalization SFX id (in assets/generated/audio/sfx/).
## Empty = silent. Overridden per creature (rusher/shooter/exploder + the three bosses).
func _enemy_voice() -> String:
	return ""


## Play the vocalization on spawn then at random VOICE_MIN..VOICE_MAX intervals while alive.
func _tick_voice(delta: float) -> void:
	if _voice_id == "" or _dead:
		return
	_voice_left -= delta
	if _voice_left <= 0.0:
		play_sfx(_voice_id)
		_voice_left = randf_range(VOICE_MIN, VOICE_MAX)


## Enemy traversal jump (T-fix): crates break the navmesh, so an enemy that
## spawns on one - or wants to reach the player over/onto one - would just press
## against it. When a chasing enemy is grounded and blocked by a low ledge in its
## move direction (or the player is above and close), hop up; walking off the far
## edge afterwards drops it back to the floor under gravity. Enemies call this
## from their movement each frame with the direction they want to travel.
const JUMP_SPEED := 6.5           # clears a ~2 m crate
const JUMP_COOLDOWN := 0.7
const LEDGE_REACH := 0.9          # how far ahead to look for a ledge
const LEDGE_MAX_HEIGHT := 2.2     # tallest ledge the enemy will try to mount
var _jump_cd: float = 0.0
## No-progress detector for the unstick logic (see _nav_dir): how long we have
## wanted to move but barely have, and where we were last frame.
var _stuck_time: float = 0.0
var _last_pos: Vector3 = Vector3.ZERO
## An enemy that drops this far below the last floor it stood on has fallen off the
## map - it is culled (counted as killed) so a stray body in the void can't leave a
## "kill everything" objective unclearable. Tracked from the real grounded height
## (updated each frame it's on the floor), so it adapts to any level's layout.
const FALL_DISTANCE := 40.0
var _last_grounded_y: float = 0.0


func _tick_jump(desired_dir: Vector3, delta: float) -> void:
	if _jump_cd > 0.0:
		_jump_cd -= delta
	if not is_on_floor() or _jump_cd > 0.0:
		return
	var flat := Vector3(desired_dir.x, 0.0, desired_dir.z)
	if flat.length() < 0.1:
		return
	flat = flat.normalized()
	var space := get_world_3d().direct_space_state
	# Only real WORLD geometry counts as a ledge - never the player or another
	# enemy. Masking to WORLD_LAYER drops other enemies (now on ENEMY_LAYER), and
	# excluding the player's body by RID stops an enemy "climbing" the player and
	# ending up perched on their head - the reported can't-move bug.
	var skip: Array[RID] = [get_rid()]
	if _player is CollisionObject3D:
		skip.append((_player as CollisionObject3D).get_rid())
	# 1) Is something blocking us right ahead at foot/shin height?
	var low_from := global_position + Vector3.UP * 0.35
	var low_q := PhysicsRayQueryParameters3D.create(low_from, low_from + flat * LEDGE_REACH)
	low_q.exclude = skip
	low_q.collision_mask = WORLD_LAYER
	if space.intersect_ray(low_q).is_empty():
		return                                        # clear path, no need to jump
	# 2) Is it low enough to mount? Above LEDGE_MAX_HEIGHT there must be open air.
	var high_from := global_position + Vector3.UP * LEDGE_MAX_HEIGHT
	var high_q := PhysicsRayQueryParameters3D.create(high_from, high_from + flat * LEDGE_REACH)
	high_q.exclude = skip
	high_q.collision_mask = WORLD_LAYER
	if not space.intersect_ray(high_q).is_empty():
		return                                        # too tall (a wall), don't bother
	velocity.y = JUMP_SPEED
	_jump_cd = JUMP_COOLDOWN


## Swap the primitive capsule for a real model if one has been dropped in at
## `assets/thirdparty/characters/<type>.{glb,gltf,tscn,scn}` (type = the scene
## basename, e.g. `rusher`, `shielded_brute`). The imported model must face -Z
## (forward) and stand ~1.8 m; pre-orient it in the import if not. The capsule
## collision is untouched - the model is visual only. Dormant until a file
## exists, so nothing changes today (mirrors the weapon pipeline).
## The loaded external model root (null if the capsule placeholder is used).
## The nameplate reads this to build the shield outline around the real shape.
var model_root: Node3D
var _model_anim: AnimationPlayer
var _walk_anim: String = ""
var _idle_anim: String = ""


func _apply_external_model() -> void:
	var base := "res://assets/thirdparty/characters/" + _to_snake(_enemy_type_name())
	for ext in ["glb", "gltf", "tscn", "scn"]:
		var path := "%s.%s" % [base, ext]
		if ResourceLoader.exists(path):
			var res := load(path)
			if res is PackedScene:
				var inst := (res as PackedScene).instantiate() as Node3D
				add_child(inst)
				model_root = inst
				var placeholder := get_node_or_null("Mesh")
				if placeholder is Node3D:
					(placeholder as Node3D).visible = false
				_apply_model_tint(inst)
				_wire_model_animation(inst)
				_apply_lod(inst)
				return


## LOD (T-0031): fade distant enemies out so a full 20-enemy wave doesn't pay the
## full skinned-vertex cost across the whole level. The generated GLBs already carry
## auto-generated mesh LODs (`meshes/generate_lods` on import) that shed triangles
## with distance; this adds a FAR CULL with a dithered self-fade so an enemy well
## out of engagement range costs nothing to draw, with no hard pop-in (the mesh
## dissolves over the margin band). The cull distance is per-enemy so a large
## arena boss stays visible far longer than a rusher (see `_lod_cull_distance`).
func _apply_lod(inst: Node3D) -> void:
	var cull := _lod_cull_distance()
	if cull <= 0.0:
		return  # boss / never-cull
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		mi.visibility_range_end = cull
		mi.visibility_range_end_margin = cull * 0.18   # dither-fade band before the cull
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


## Distance (m) at which this enemy fades out. 0 disables culling (arena bosses).
## Regular enemies use 75 m — beyond effective engagement range for these weapons,
## so it never hides something you could meaningfully fight. Subclasses override.
func _lod_cull_distance() -> float:
	return 75.0


## Some models (Fab FBX) ship without their textures and render flat white; a
## subclass can return a material to paint them so they read intentionally
## (e.g. the Ember Tyrant charred, the Phantom spectral). Default: keep the
## model's own materials (the Quaternius kit is textured).
func external_model_tint() -> Material:
	return null


func _apply_model_tint(inst: Node3D) -> void:
	var mat := external_model_tint()
	if mat == null:
		return
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).material_override = mat


## Phase 1.5: drive the model's own walk/idle clips off the enemy's movement. The
## animation names vary per kit, so match them case-insensitively; enemies whose
## model has no AnimationPlayer (or no matching clip) just stay in their pose.
func _wire_model_animation(inst: Node3D) -> void:
	var players := inst.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	_model_anim = players[0] as AnimationPlayer
	for anim_name in _model_anim.get_animation_list():
		var l := anim_name.to_lower()
		if _walk_anim == "" and (l.contains("walk") or l.contains("run") or l.contains("move")):
			_walk_anim = anim_name
		if _idle_anim == "" and l.contains("idle"):
			_idle_anim = anim_name
	for n in [_walk_anim, _idle_anim]:
		if n != "" and _model_anim.has_animation(n):
			_model_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	var start := _idle_anim if _idle_anim != "" else _walk_anim
	if start != "":
		_model_anim.play(start)


func _process(_delta: float) -> void:
	_tick_shield_regen(_delta)
	_tick_voice(_delta)
	# Off-the-map failsafe: an enemy knocked into the void (off a ledge, through a
	# gap) would otherwise stay alive-but-unreachable and block a "kill everything"
	# objective (the reported Earth exploder). Track the last floor it stood on and,
	# once it has dropped FALL_DISTANCE below that, count it as killed. Bosses are
	# exempt - they live in sealed arenas and drive their own outcome, so a physics
	# glitch mustn't hand a free win.
	if not _dead and not is_in_group("boss"):
		if is_on_floor():
			_last_grounded_y = global_position.y
		elif global_position.y < _last_grounded_y - FALL_DISTANCE:
			_die()
			return
	if _model_anim == null:
		return
	# Don't interrupt a one-shot clip (e.g. an attack) that is still playing.
	var cur := _model_anim.current_animation
	if cur != "" and cur != _walk_anim and cur != _idle_anim and _model_anim.is_playing():
		return
	var moving := Vector2(velocity.x, velocity.z).length() > 0.6
	var want := _walk_anim if (moving and _walk_anim != "") else _idle_anim
	if want == "":
		want = _walk_anim
	if want != "" and _model_anim.current_animation != want:
		_model_anim.play(want)


## Attack clips are ~2 s of mocap; play them faster so the swing is snappy and its
## contact lands near MELEE_WINDUP (below) rather than seconds later.
const ATTACK_ANIM_SPEED := 1.8
## Delay between starting the swing and landing the hit, so the damage reads as
## connecting WITH the animation instead of a frame before it starts (the reported
## "I take damage, then the melee shows" bug). Roughly the clip's wind-up-to-contact.
const MELEE_WINDUP := 0.4


## Play a one-shot attack clip if the model has one (returns to walk/idle after).
## Enemies call this when they strike; a no-op if there's no attack animation.
func play_attack_animation() -> void:
	if _model_anim == null:
		return
	for anim_name in _model_anim.get_animation_list():
		var l := anim_name.to_lower()
		if l.contains("attack") or l.contains("hit") or l.contains("bite") \
				or l.contains("punch") or l.contains("slash"):
			_model_anim.play(anim_name, -1, ATTACK_ANIM_SPEED)
			return


## Play the attack swing, then land the hit after a wind-up so the damage is
## synced to the animation's contact (fixes damage arriving before the swing shows).
## The hit only lands if the enemy is alive and the player is still within
## `max_range` at contact - a dodge out of range whiffs, which reads as fair.
func melee_strike(damage: float, source: String, max_range: float,
		windup: float = MELEE_WINDUP) -> void:
	play_attack_animation()
	await get_tree().create_timer(windup).timeout
	if _dead or not is_instance_valid(_player):
		return
	if _player.global_position.distance_to(global_position) <= max_range \
			and _player.has_method("take_damage"):
		_player.take_damage(damage, source)


## "ShieldedBrute" -> "shielded_brute", matching the scene file names.
func _to_snake(s: String) -> String:
	var out := ""
	for i in s.length():
		var c := s[i]
		if c >= "A" and c <= "Z":
			if i > 0:
				out += "_"
			out += c.to_lower()
		else:
			out += c
	return out


## Attach the floating name + health bar (and, for a shielded enemy, the shield
## bar + elemental shell). Runs after _apply_difficulty so the shield stats and
## element are already set.
func _build_nameplate() -> void:
	var plate := Node3D.new()
	plate.set_script(load(NAMEPLATE_SCENE_PATH))
	plate.setup(self)
	add_child(plate)


# --- nameplate data (overridable by subclasses) -----------------------------

## Human-readable name shown on the nameplate.
func display_name() -> String:
	return String(NAMES.get(_enemy_type_name(), _enemy_type_name()))


## "normal" or "boss" - bosses get a larger, gold nameplate.
func nameplate_tier() -> String:
	return "boss" if is_in_group("boss") else "normal"


## Local height the nameplate floats at (above the ~1.8 m capsule). Taller
## bosses override this so the plate clears their head.
func nameplate_head_y() -> float:
	return 2.15


## Radius of the elemental shield shell around the body. Bosses override it.
func nameplate_shell_radius() -> float:
	return 0.72


## Current / max shield shown on the nameplate. Defaults to the elemental pool;
## a boss with its own gate shield (the Shielded Brute) overrides these.
func nameplate_shield() -> float:
	return elemental_shield


func nameplate_shield_max() -> float:
	return max_elemental_shield


## Colour of the shield segment / shell: the element's colour for an elemental
## shield, a neutral shield-blue for a plain one.
func nameplate_shield_color() -> Color:
	if shield_element != "Kinetic":
		return Weapon.ELEMENT_COLORS.get(shield_element, Color(0.55, 0.75, 1.0))
	return Color(0.55, 0.75, 1.0)


## Scale this enemy for the selected difficulty tier (T-0027). Applied at
## spawn, before health is filled, so a Heroic Rusher is 225/225 rather than
## 150/225. Enemies spawned mid-mission get it too, since every one runs this.
func _apply_difficulty() -> void:
	var diff := get_node_or_null("/root/Difficulty")
	if diff == null:
		return
	max_health *= float(diff.enemy_health_mult())
	var fraction: float = diff.enemy_shield_fraction()
	if fraction > 0.0:
		elemental_shield = max_health * fraction
		max_elemental_shield = elemental_shield
		# Randomise which element counters this shield, so a single-element
		# loadout can't trivially melt every shielded enemy (GDD §2.8).
		shield_element = ["Solar", "Arc", "Void"][randi() % 3]


func _find_player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


## Re-resolve the player if it was freed; returns true when a target exists.
func _ensure_player() -> bool:
	if _player == null or not is_instance_valid(_player):
		_player = _find_player()
	return _player != null


func _halt_horizontal() -> void:
	velocity.x = 0.0
	velocity.z = 0.0


## Blind/stun this enemy (Flashbang T-0024, EMP Punch T-0025). Takes the longer
## of the current and new duration so a second application can't cut an
## existing one short.
func stun(seconds: float) -> void:
	stun_left = maxf(stun_left, seconds)


func is_stunned() -> bool:
	return stun_left > 0.0


## Shove this enemy a precise distance (Ground Slam, T-0025). Mirrors
## Guardian.apply_push(): a displacement budget spent over PUSH_TIME and
## applied with move_and_collide, so the travel is exactly offset.length()
## regardless of frame rate, and walls still stop it.
func apply_push(offset: Vector3) -> void:
	if _dead or offset == Vector3.ZERO:
		return
	_push_velocity = offset / PUSH_TIME
	_push_time_left = PUSH_TIME


func is_pushed() -> bool:
	return _push_time_left > 0.0


## Advance stun/knockback and hold the enemy while either is active. Returns
## true while the caller should skip the rest of its _physics_process -
## subclasses call this right after their `_dead` guard. Gravity still applies,
## so an affected enemy falls instead of hanging in mid-air.
func _tick_status(delta: float) -> bool:
	if stun_left <= 0.0 and _push_time_left <= 0.0:
		return false
	stun_left = maxf(0.0, stun_left - delta)
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_halt_horizontal()
	move_and_slide()
	if _push_time_left > 0.0:
		var push_dt: float = minf(delta, _push_time_left)
		move_and_collide(_push_velocity * push_dt)
		_push_time_left -= push_dt
	return true


## Horizontal steering toward `target`. Normally follows the NavigationAgent
## path, but crates break navigation two ways: an enemy standing on a crate whose
## top the navmesh doesn't cover is fully OFF the mesh, while a crate top baked as
## its own disconnected navmesh island leaves the enemy technically ON the mesh
## with NO path to a player on the floor. Both used to strand the enemy. We now
## detect no-progress generally - off-mesh, a finished-but-far path, or simply
## wanting to move while barely moving - and in that case steer STRAIGHT at the
## player. That walks the enemy to the crate edge so gravity drops it onto the
## floor, and _tick_jump mounts a low crate on the way in. Returns a horizontal
## (y=0) vector; the caller normalises. Pass the agent and frame delta.
func _nav_dir(agent: NavigationAgent3D, target: Vector3, delta: float) -> Vector3:
	agent.target_position = target
	var to_target := target - global_position
	to_target.y = 0.0

	# --- progress / stuck tracking (horizontal) -------------------------------
	var moved := global_position - _last_pos
	moved.y = 0.0
	_last_pos = global_position
	if to_target.length() > 1.2 and moved.length() < 0.5 * delta:  # <0.5 m/s = stalled
		_stuck_time += delta
	else:
		_stuck_time = maxf(0.0, _stuck_time - delta * 3.0)

	# Standing on a crate/ledge ABOVE the player, fully off the navmesh, or simply
	# stalled: navigation can't route us DOWN a ledge (a crate top bakes as its own
	# disconnected navmesh island, so the path leads nowhere useful), so head
	# straight at the player to reach an edge and let gravity drop us onto the
	# floor. Keying on height beats trusting is_navigation_finished(), which flips
	# frame to frame. Climbing UP onto a low crate toward a player above us is
	# handled separately by _tick_jump.
	var above := global_position.y - target.y > 0.8
	var edge := _off_mesh_edge()
	if above or edge != Vector3.ZERO or _stuck_time > 0.35:
		if to_target.length() > 0.8:
			return to_target
		if edge != Vector3.ZERO:
			return edge                                 # player ~straight below
		return -global_transform.basis.z

	# --- normal navmesh follow ------------------------------------------------
	var dir := agent.get_next_path_position() - global_position
	dir.y = 0.0
	if dir.length() < 0.15:
		dir = to_target
	return dir


## If the enemy is off the navmesh (on a crate the navmesh doesn't cover), returns
## a horizontal heading toward the nearest navigable ground (so it walks to an edge
## and falls back down); Vector3.ZERO when the enemy is on the navmesh. A last-
## resort forward nudge covers being dead-centre on a crate with ground straight
## below.
func _off_mesh_edge() -> Vector3:
	var map := get_world_3d().navigation_map
	if not map.is_valid():
		return Vector3.ZERO
	var closest := NavigationServer3D.map_get_closest_point(map, global_position)
	if closest == Vector3.ZERO or global_position.distance_to(closest) <= 1.0:
		return Vector3.ZERO
	var edge := closest - global_position
	edge.y = 0.0
	if edge.length() < 0.2:
		edge = -global_transform.basis.z    # ground is straight down: walk forward off
	return edge


func _face(target: Vector3) -> void:
	var flat := Vector3(target.x, global_position.y, target.z)
	if global_position.distance_to(flat) > 0.05:
		look_at(flat, Vector3.UP)


## True when a world-space hit point lands in this enemy's head zone.
func is_headshot(world_point: Vector3) -> bool:
	return (world_point.y - global_position.y) >= HEAD_MIN_LOCAL_Y


## Incoming damage (from weapons T-0010). Dies + drops loot at 0 HP.
func take_damage(amount: float) -> void:
	if _dead:
		return
	if amount > 0.0:
		_shield_regen_wait = 0.0          # any hit delays shield regen
	amount = absorb_shield(amount)
	if amount <= 0.0:
		play_sfx("enemy_hit")
		return
	health = maxf(0.0, health - amount)
	play_sfx("enemy_hit")
	if health <= 0.0:
		_die()


## Spend the Heroic/Legendary shield pool first and return what gets through.
## Subclasses with their own damage handling (the bosses) call this too.
##
## Element (GDD §2.8): a matching-element shot does SHIELD_MATCH_MULT damage to
## the shield, a mismatched one only SHIELD_MISMATCH_MULT, so the raw damage a
## shot spends breaking the shield differs from the shield HP it removes. Any
## damage left after the shield breaks carries over to health at the normal 1x
## rate. A plain shield (shield_element Kinetic) uses 1x and behaves as before.
func absorb_shield(amount: float) -> float:
	if amount > 0.0:
		_shield_regen_wait = 0.0          # bosses call this directly - reset here too
	if elemental_shield <= 0.0 or amount <= 0.0:
		incoming_element = "Kinetic"
		return amount
	var matched := shield_element != "Kinetic" and incoming_element == shield_element
	var plain := shield_element == "Kinetic"
	incoming_element = "Kinetic"                 # consume this shot's element

	if plain:
		var rem_p := minf(elemental_shield, amount)
		elemental_shield -= rem_p
		return maxf(0.0, amount - rem_p)

	if matched:
		# Right element: burns the shield fast, remainder passes to health at 1x.
		var sd := amount * SHIELD_MATCH_MULT
		var rem := minf(elemental_shield, sd)
		elemental_shield -= rem
		return maxf(0.0, amount - rem / SHIELD_MATCH_MULT)

	# Wrong element / Kinetic on an elemental shield: it only chips the shield,
	# and even when the shield finally breaks most of the shot is wasted, so it
	# can't one-shot a shielded enemy through its shield - you need the element.
	var sd_m := amount * SHIELD_MISMATCH_MULT
	var rem_m := minf(elemental_shield, sd_m)
	elemental_shield -= rem_m
	if elemental_shield > 0.0:
		return 0.0                               # fully absorbed, shield still up
	var overflow := maxf(0.0, amount - rem_m / SHIELD_MISMATCH_MULT)
	return overflow * SHIELD_MISMATCH_MULT       # heavily reduced bleed-through


## Recharge the elemental shield once the enemy has gone SHIELD_REGEN_DELAY
## seconds without taking any damage (the wait is reset on every hit). No-op for
## enemies that never had a shield, once it is already full, or while dead.
func _tick_shield_regen(delta: float) -> void:
	if _dead or max_elemental_shield <= 0.0 or elemental_shield >= max_elemental_shield:
		return
	_shield_regen_wait += delta
	if _shield_regen_wait < SHIELD_REGEN_DELAY:
		return
	var rate := max_elemental_shield / SHIELD_REGEN_TIME
	elemental_shield = minf(max_elemental_shield, elemental_shield + rate * delta)


## Positional effect at this enemy (T-0034). No-ops without the autoload, so
## enemies stay testable in isolation.
func play_sfx(id: String) -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.play_sfx(id, global_position)


## What last damaged this enemy, for the EnemyKilled telemetry event (T-0026).
## Recorded on the enemy rather than logged by the weapon so that delayed
## deaths (the Ember Tyrant's 3 s sequence) and indirect kills (explosions,
## the Exploder taking itself out) still attribute correctly.
var last_hit_by: String = "Unknown"
var last_hit_headshot: bool = false


func mark_damage_source(source: String, headshot: bool = false, element: String = "Kinetic") -> void:
	last_hit_by = source
	last_hit_headshot = headshot
	incoming_element = element


func _die() -> void:
	_dead = true
	var where := global_position
	_log_kill()
	died.emit(where)
	_drop_loot(where)
	queue_free()


## Subclasses that override _die() (Exploder, Ember Tyrant) call this too.
func _log_kill() -> void:
	var tel := get_node_or_null("/root/Telemetry")
	if tel:
		tel.enemy_killed(_enemy_type_name(), last_hit_by, last_hit_headshot)
	var sm := get_node_or_null("/root/SaveManager")
	if sm and sm.has_method("add_flux"):
		sm.add_flux(flux_value)


## The subclass's class_name ("Rusher", "EmberTyrant", ...) for telemetry.
func _enemy_type_name() -> String:
	var script: Script = get_script() as Script
	if script == null:
		return "Enemy"
	var global_name := String(script.get_global_name())
	return global_name if global_name != "" else "Enemy"


## Spawn loot at the death position + a random offset within a 1 m radius
## (GDD §2.7). Uses `loot_scene` if set, else the shared loot_drop.tscn.
func _drop_loot(where: Vector3) -> void:
	# Not every kill drops. A forced rarity (boss guarantee) always does; a
	# regular enemy rolls against loot_chance so pickups stay meaningful.
	if loot_rarity_override == "" and randf() > loot_chance:
		return
	var drop: Node3D = null
	if loot_scene != null:
		drop = loot_scene.instantiate() as Node3D
	else:
		var packed := load(LOOT_SCENE_PATH)
		if packed != null:
			drop = packed.instantiate() as Node3D
	if drop == null:
		drop = _placeholder_loot()
	# Force rarity (e.g. boss Epic) before the drop enters the tree and rolls.
	if loot_rarity_override != "" and ("forced_rarity" in drop):
		drop.forced_rarity = loot_rarity_override
	# A minority of drops are armour instead of a weapon (unless the scene fixes
	# the category itself, e.g. a boss's guaranteed armour reward).
	if ("category" in drop) and drop.category == "weapon" and randf() < armor_drop_chance:
		drop.category = "armor"
	# Parent to the scene (not self - we are about to free) so the drop persists.
	var host := get_tree().current_scene
	if host == null:
		host = get_tree().root
	host.add_child(drop)
	var offset := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	if offset.length() > 1.0:
		offset = offset.normalized()
	drop.global_position = where + Vector3(0.0, 0.4, 0.0) + offset


## Fallback marker if the loot scene fails to load.
func _placeholder_loot() -> Node3D:
	var mi := MeshInstance3D.new()
	mi.name = "LootDropPlaceholder"
	mi.add_to_group("loot")
	var sphere := SphereMesh.new()
	sphere.radius = 0.2
	sphere.height = 0.4
	mi.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1)
	mat.emission_enabled = true
	mat.emission = Color(1, 1, 1)
	mat.emission_energy_multiplier = 2.0
	mi.material_override = mat
	return mi

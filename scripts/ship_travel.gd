extends CanvasLayer
## ShipTravel autoload (P1) - the public entry point for the Fold cinematic and the
## keeper of the white "atmospheric entry" flash + the actual scene swap.
##
## The verb is: from the helm (or the hologram table) you pick a world and confirm a
## difficulty; that funnels here. `begin()` drops a `travel_cutscene` into the live
## scene, which flies the hero ship to the planet and lands (see travel_cutscene.gd).
## When the descent finishes the cutscene emits `handoff`; THIS node then flashes the
## screen white, swaps to the mission scene, and clears the white - so the surface
## "washes in" out of a bright cloud, exactly like the reference.
##
## It is an autoload (not scene-scoped) for two reasons: the public API reads cleanly
## as `ShipTravel.begin(...)`, and the white flash must survive the scene change that
## frees the cutscene, so it lives on this persistent CanvasLayer.
##
## SAFE FALLBACK: if the ship asset or the cutscene scene is missing, `begin()` returns
## false and the caller does its existing plain fade instead - the Fold never dead-ends.

enum State { IDLE, FOLD, APPROACH, DESCENT, HANDOFF }

const CUTSCENE_SCENE := "res://scenes/hub/travel_cutscene.tscn"
const SHIP_GLB := "res://assets/generated/ship/hero_ship.glb"

## Mission planet -> level scene (same map the helm/table interactors keep locally).
const MISSION_SCENES := {
	"Earth": "res://scenes/missions/earth/earth.tscn",
	"Mars": "res://scenes/missions/mars/mars.tscn",
	"Venus": "res://scenes/missions/venus/venus.tscn",
}

## Observable current beat (mirrors the cutscene's state machine), exposed for tests.
var state: int = State.IDLE

var _running: bool = false
var _cutscene: Node3D = null
var _white: ColorRect


func _ready() -> void:
	layer = 140                       # above GameState's fade (128) and HUDs
	process_mode = Node.PROCESS_MODE_ALWAYS
	_white = ColorRect.new()
	_white.color = Color(1, 1, 1, 0)
	_white.set_anchors_preset(Control.PRESET_FULL_RECT)
	_white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_white)


## Start the Fold cinematic to `mission`. `planet_node` is the aimed world (helm
## billboard / mission sphere) - accepted per the design API, used only as a hint;
## the cutscene builds its own framed pocket of space. Returns true if the cinematic
## was launched, false if assets are missing (caller should fall back to a plain fade).
func begin(mission: String, _planet_node: Node3D = null) -> bool:
	if _running:
		return true
	if not MISSION_SCENES.has(mission):
		return false
	if not _assets_ready():
		return false
	var packed := load(CUTSCENE_SCENE)
	if not (packed is PackedScene):
		return false
	var scene := get_tree().current_scene
	if scene == null:
		return false

	_cutscene = (packed as PackedScene).instantiate() as Node3D
	if _cutscene == null:
		return false
	scene.add_child(_cutscene)
	_running = true
	state = State.FOLD

	# Freeze the walking player so its camera/input can't fight the cinematic; it is
	# discarded on the scene swap, so no restore is needed.
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player:
		player.visible = false
		player.process_mode = Node.PROCESS_MODE_DISABLED

	if _cutscene.has_signal("state_changed"):
		_cutscene.state_changed.connect(func(s: int) -> void: state = s)
	if _cutscene.has_signal("handoff"):
		_cutscene.handoff.connect(_on_handoff)
	if _cutscene.has_method("play"):
		_cutscene.play(mission)
	return true


## Both the ship model and the cutscene scene must load, else we can't fly anything.
func _assets_ready() -> bool:
	return ResourceLoader.exists(SHIP_GLB) and ResourceLoader.exists(CUTSCENE_SCENE)


## Descent done: flash white, swap to the mission, then clear the white so the surface
## reveals through the fading brightness.
func _on_handoff(mission: String) -> void:
	state = State.HANDOFF
	var path: String = MISSION_SCENES.get(mission, "")
	if path == "":
		_running = false
		return
	var tw := create_tween()
	tw.tween_property(_white, "color:a", 1.0, 0.45)
	tw.tween_callback(func() -> void: _swap(path))
	tw.tween_interval(0.2)
	tw.tween_property(_white, "color:a", 0.0, 0.7)
	tw.tween_callback(_reset)


func _swap(path: String) -> void:
	_cutscene = null                  # freed with the old scene by change_scene_to_file
	get_tree().change_scene_to_file(path)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _reset() -> void:
	_running = false
	state = State.IDLE

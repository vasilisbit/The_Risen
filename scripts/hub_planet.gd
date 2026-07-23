extends Node3D

## Planet seen through the hub's cockpit window (T-0028, Phase 5). A real
## generated planet from the naejimer 3D planet generator addon, showing the
## world you were LAST DEPLOYED TO (the ship is parked in its orbit) - Earth
## before your first mission.
##
## `last_mission` is written by the mission drivers when a mission starts, so
## this reflects where you actually went rather than what the save flags say.
##
## The planet is lit by a dedicated directional "sun" restricted to the planet's
## own render layer (via light_cull_mask), so it does not spill light into the
## ship interior. The node spins slowly for rotation.

## Mission -> generated planet scene.
const PLANET_SCENES := {
	"Earth": "res://addons/naejimer_3d_planet_generator/scenes/planet_terrestrial.tscn",
	"Mars": "res://addons/naejimer_3d_planet_generator/scenes/planet_sand.tscn",
	"Venus": "res://addons/naejimer_3d_planet_generator/scenes/planet_lava.tscn",
}
## Out through the cockpit window (opening is 5x3 at z = -5, centred x = 0).
const OFFSET := Vector3(0.0, 3.0, -24.0)
const PLANET_SCALE := 12.0                 # addon planets are ~0.5 m radius
const SPIN := TAU / 60.0                    # 1 revolution / 60 s
const PLANET_LAYER := 1 << 1                # render layer 2, lit only by our sun

## Which planet is currently shown - exposed for tests.
var shown: String = "Earth"

var _planet: Node3D
var _sun: DirectionalLight3D


func _ready() -> void:
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-24.0, 212.0, 0.0)
	_sun.light_energy = 1.5
	_sun.light_cull_mask = PLANET_LAYER      # only lights the planet, not the ship
	add_child(_sun)
	refresh()


## Re-read progress and rebuild the planet. The hub is reloaded on return from a
## mission so _ready covers the normal path; this also serves tests.
func refresh() -> void:
	shown = _last_visited()
	if _planet and is_instance_valid(_planet):
		_planet.queue_free()
		_planet = null
	var scene: Resource = load(PLANET_SCENES.get(shown, PLANET_SCENES["Earth"]))
	if scene is PackedScene:
		_planet = (scene as PackedScene).instantiate() as Node3D
		_planet.position = OFFSET
		_planet.scale = Vector3.ONE * PLANET_SCALE
		# Put every visual on the planet layer (so the culled sun lights it) and
		# give a generous cull margin so the interior geometry can't clip it out.
		for vi in _planet.find_children("*", "VisualInstance3D", true, false):
			(vi as VisualInstance3D).layers = PLANET_LAYER
			(vi as VisualInstance3D).extra_cull_margin = PLANET_SCALE * 2.0
		add_child(_planet)


## The mission most recently deployed to, defaulting to Earth before the first.
func _last_visited() -> String:
	var sm := get_node_or_null("/root/SaveManager")
	if sm == null:
		return "Earth"
	var last := String(sm.data.get("last_mission", "Earth"))
	return last if PLANET_SCENES.has(last) else "Earth"


func _process(delta: float) -> void:
	if _planet and is_instance_valid(_planet):
		_planet.rotate_y(SPIN * delta)

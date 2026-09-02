extends Node
## TEMPORARY trailer/IGF area-capture autoload. Forces the window to 1920x1080 and
## saves the composited frame (3D + HUD) to assets/generated/trailer/frames/area_N.png
## when F12 is pressed. Registered as autoload "AreaShot" only while capturing the
## environment frames; REMOVE it from project.godot afterwards (it must not ship).
var _n := 0
const DIR := "res://assets/generated/trailer/frames/"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	# Give the scene a moment, then force capture resolution.
	await get_tree().process_frame
	DisplayServer.window_set_size(Vector2i(1920, 1080))

func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F12:
		_cap()

func _cap() -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var base := "area"
	var cs := get_tree().current_scene
	if cs != null and cs.scene_file_path != "":
		base = cs.scene_file_path.get_file().get_basename()
	var p := ProjectSettings.globalize_path(DIR + "%s_%d.png" % [base, _n])
	img.save_png(p)
	print("AREA_SHOT %s %dx%d -> %s" % [base, img.get_width(), img.get_height(), p])
	_n += 1

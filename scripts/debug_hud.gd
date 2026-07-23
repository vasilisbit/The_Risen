extends CanvasLayer
## Player HUD host. Builds the top-centre vitals bar (HP + shield) and the
## top-left enemy radar in code, so the scene only needs this bare CanvasLayer
## plus the crosshair. Both children find the player by group and drive
## themselves, keeping this node decoupled from the Guardian class.


func _ready() -> void:
	var vitals := Control.new()
	vitals.name = "Vitals"
	vitals.set_script(load("res://scripts/vitals_bar.gd"))
	add_child(vitals)

	var radar := Control.new()
	radar.name = "Radar"
	radar.set_script(load("res://scripts/radar_hud.gd"))
	add_child(radar)

	# Interaction prompt, just below the crosshair. The mission_interactor shows
	# it while you are looking at the Forge Master or the hologram table.
	var prompt := Label.new()
	prompt.name = "InteractPrompt"
	prompt.add_to_group("interact_prompt")
	prompt.anchor_left = 0.5
	prompt.anchor_right = 0.5
	prompt.anchor_top = 0.5
	prompt.anchor_bottom = 0.5
	prompt.offset_left = -220.0
	prompt.offset_right = 220.0
	prompt.offset_top = 28.0
	prompt.offset_bottom = 58.0
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 18)
	prompt.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
	prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	prompt.add_theme_constant_override("outline_size", 6)
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt.visible = false
	add_child(prompt)

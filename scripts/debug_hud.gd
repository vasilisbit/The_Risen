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

	# Interaction prompt. Pinned at the same fixed centre-bottom spot as every other
	# world prompt (the helm "Take the Helm" and the landed-ship "Board / Lift off"),
	# rather than floating under the crosshair, so they all appear in one place. The
	# mission_interactor shows it while you look at the Forge Master or hologram table.
	var prompt := Label.new()
	prompt.name = "InteractPrompt"
	prompt.add_to_group("interact_prompt")
	prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.anchor_left = 0.5
	prompt.anchor_right = 0.5
	prompt.position = Vector2(-220.0, -115.0)
	prompt.custom_minimum_size = Vector2(440.0, 0.0)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Shared interaction-prompt style (gold), kept identical across every "[E]…"
	# world prompt: hub interact/deploy (here), the helm, and the landed ship.
	prompt.add_theme_font_size_override("font_size", 22)
	prompt.add_theme_color_override("font_color", Color(1.0, 0.82, 0.34))
	prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	prompt.add_theme_constant_override("outline_size", 6)
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt.visible = false
	add_child(prompt)

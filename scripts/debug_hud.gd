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

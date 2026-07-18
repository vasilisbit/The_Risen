extends CanvasLayer
## T-0002 debug HUD: live HP / Shield bars driven by the parent Guardian's
## signals. Duck-typed on purpose so this stays decoupled from the Guardian
## class and can be dropped under any node exposing the same signals.

@onready var _health_bar: ProgressBar = $Root/Bars/HealthBar
@onready var _shield_bar: ProgressBar = $Root/Bars/ShieldBar
@onready var _health_label: Label = $Root/Bars/HealthLabel
@onready var _shield_label: Label = $Root/Bars/ShieldLabel


func _ready() -> void:
	var source := get_parent()
	if source == null or not source.has_signal("health_changed"):
		push_warning("debug_hud: parent has no Guardian signals; bars stay static.")
		return
	source.health_changed.connect(_on_health_changed)
	source.shield_changed.connect(_on_shield_changed)
	# Prime the bars with current values.
	_on_health_changed(source.health, source.MAX_HEALTH)
	_on_shield_changed(source.shield, source.MAX_SHIELD)


func _on_health_changed(current: float, maximum: float) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current
	_health_label.text = "HP  %d / %d" % [roundi(current), roundi(maximum)]


func _on_shield_changed(current: float, maximum: float) -> void:
	_shield_bar.max_value = maximum
	_shield_bar.value = current
	_shield_label.text = "Shield  %d / %d" % [roundi(current), roundi(maximum)]

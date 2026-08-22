extends Node
## GameSettings (autoload): global player preferences - audio, graphics, controls.
##
## Unlike SaveManager (which stores per-slot game PROGRESS), these are machine /
## player preferences that apply across every save slot, so they live in their own
## config file: user://risen_config.json. Keeping them out of the save means
## switching slots never changes your volume or sensitivity, and a fresh New Game
## keeps the options you already set.
##
## Audio is applied by AudioManager (it owns the buses) - this node is just the
## persisted source of truth it reads on boot and writes back to when a slider
## moves. Graphics + controls are applied here directly.

const CONFIG_PATH := "user://risen_config.json"

## Look sensitivity bounds for the Controls slider (radians per pixel of mouse
## motion). The old hard-coded Guardian constant (0.003) sits mid-range, so the
## default feel is unchanged until the player touches the slider.
const SENS_MIN := 0.0008
const SENS_MAX := 0.0072
const SENS_DEFAULT := 0.003

## Emitted whenever a setting changes, so live listeners (the Guardian's look) can
## refresh without polling.
signal changed

var _audio := {"Master": 1.0, "Music": 1.0, "SFX": 1.0}
var _graphics := {"fullscreen": false, "vsync": true}
var _controls := {"mouse_sensitivity": SENS_DEFAULT, "invert_y": false}


func _ready() -> void:
	_load()
	# Graphics apply here; audio is pulled by AudioManager on its own _ready (it is
	# autoloaded after this node), so we don't push into it here.
	_apply_graphics()


# --- audio (persisted here, applied by AudioManager) -------------------------

func audio_volume(bus_name: String) -> float:
	return float(_audio.get(bus_name, 1.0))


## Persist a bus volume. Called by AudioManager.set_volume after it applies the
## change to the bus, so this file is the durable copy.
func set_audio_volume(bus_name: String, linear: float) -> void:
	_audio[bus_name] = clampf(linear, 0.0, 1.0)
	save_config()


# --- graphics ----------------------------------------------------------------

func is_fullscreen() -> bool:
	return bool(_graphics.get("fullscreen", false))


func set_fullscreen(on: bool) -> void:
	_graphics["fullscreen"] = on
	_apply_graphics()
	save_config()
	changed.emit()


func is_vsync() -> bool:
	return bool(_graphics.get("vsync", true))


func set_vsync(on: bool) -> void:
	_graphics["vsync"] = on
	_apply_graphics()
	save_config()
	changed.emit()


# --- controls ----------------------------------------------------------------

func mouse_sensitivity() -> float:
	return clampf(float(_controls.get("mouse_sensitivity", SENS_DEFAULT)), SENS_MIN, SENS_MAX)


func set_mouse_sensitivity(v: float) -> void:
	_controls["mouse_sensitivity"] = clampf(v, SENS_MIN, SENS_MAX)
	save_config()
	changed.emit()


## 0..1 slider position mapped onto [SENS_MIN, SENS_MAX], for the settings UI.
func sensitivity_fraction() -> float:
	return clampf((mouse_sensitivity() - SENS_MIN) / (SENS_MAX - SENS_MIN), 0.0, 1.0)


func set_sensitivity_fraction(frac: float) -> void:
	set_mouse_sensitivity(lerpf(SENS_MIN, SENS_MAX, clampf(frac, 0.0, 1.0)))


func invert_y() -> bool:
	return bool(_controls.get("invert_y", false))


func set_invert_y(on: bool) -> void:
	_controls["invert_y"] = on
	save_config()
	changed.emit()


# --- apply -------------------------------------------------------------------

func _apply_graphics() -> void:
	var mode := (DisplayServer.WINDOW_MODE_FULLSCREEN if is_fullscreen()
		else DisplayServer.WINDOW_MODE_WINDOWED)
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if is_vsync() else DisplayServer.VSYNC_DISABLED)


# --- persistence -------------------------------------------------------------

func _load() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		# First run of the settings system: adopt whatever audio levels the old
		# in-save `audio_volumes` held so the player's volumes carry over, then
		# write the config once.
		_migrate_from_save()
		save_config()
		return
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f == null:
		push_warning("GameSettings: cannot open config; using defaults.")
		return
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("GameSettings: corrupt config; using defaults.")
		return
	var d := parsed as Dictionary
	_merge(_audio, d.get("audio"))
	_merge(_graphics, d.get("graphics"))
	_merge(_controls, d.get("controls"))


func _migrate_from_save() -> void:
	var sm := get_node_or_null("/root/SaveManager")
	if sm == null:
		return
	var vols: Dictionary = sm.data.get("audio_volumes", {}) if sm.data else {}
	for bus_name in _audio.keys():
		if vols.has(bus_name):
			_audio[bus_name] = float(vols[bus_name])


## Copy only the keys we already know about, so a hand-edited or older config can
## never inject stray fields and every default stays present.
func _merge(target: Dictionary, src: Variant) -> void:
	if typeof(src) != TYPE_DICTIONARY:
		return
	for k in target.keys():
		if (src as Dictionary).has(k):
			target[k] = (src as Dictionary)[k]


func save_config() -> void:
	var f := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if f == null:
		push_error("GameSettings: cannot write config to %s" % CONFIG_PATH)
		return
	f.store_string(JSON.stringify(
		{"audio": _audio, "graphics": _graphics, "controls": _controls}, "\t"))
	f.close()

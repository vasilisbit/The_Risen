extends Node3D
## Player weapon manager (T-0010). Holds the four weapon scenes, handles switch
## (1-4), reload (R), and fire (LMB — full-auto for the Auto Rifle, semi for the
## rest), raycasting from the player camera. Updates the ammo HUD label.

const WEAPON_PATHS := [
	"res://scenes/weapons/auto_rifle.tscn",
	"res://scenes/weapons/shotgun.tscn",
	"res://scenes/weapons/sniper.tscn",
	"res://scenes/weapons/hand_cannon.tscn",
]

## Per-shot camera kick, in radians. `pitch` climbs the aim permanently (so
## sustained fire walks upward and has to be pulled back down); `shake` is the
## decaying jitter on top. Roughly tracks each weapon's damage per shot.
const CAMERA_RECOIL := {
	"Auto Rifle": {"pitch": 0.006, "shake": 0.004},
	"Shotgun": {"pitch": 0.045, "shake": 0.030},
	"Sniper": {"pitch": 0.055, "shake": 0.022},
	"Hand Cannon": {"pitch": 0.028, "shake": 0.016},
}

var _weapons: Array[Weapon] = []
var _active: int = 0
var _camera: Camera3D
var _body: CollisionObject3D
var _ammo_label: Label
var _viewmodel: Node3D


func _ready() -> void:
	var player := get_parent()
	_camera = player.get_node("SpringArm3D/Camera3D") as Camera3D
	_body = player as CollisionObject3D
	_ammo_label = player.get_node_or_null("DebugHUD/Ammo") as Label
	_viewmodel = _camera.get_node_or_null("WeaponViewmodel") as Node3D
	for path in WEAPON_PATHS:
		var w := load(path).instantiate() as Weapon
		add_child(w)
		w.state_changed.connect(_update_hud)
		_weapons.append(w)
	# Give the viewmodel the starting weapon's silhouette.
	if _viewmodel and _viewmodel.has_method("set_weapon") and not _weapons.is_empty():
		_viewmodel.set_weapon(_weapons[_active].weapon_name)
	_update_hud()


func active_weapon() -> Weapon:
	return _weapons[_active] if _active < _weapons.size() else null


func _process(delta: float) -> void:
	var w := active_weapon()
	if w == null:
		return
	w.tick(delta)

	if Input.is_action_just_pressed("weapon_1"):
		_switch(0)
	elif Input.is_action_just_pressed("weapon_2"):
		_switch(1)
	elif Input.is_action_just_pressed("weapon_3"):
		_switch(2)
	elif Input.is_action_just_pressed("weapon_4"):
		_switch(3)

	if Input.is_action_just_pressed("reload"):
		w.start_reload()

	var wants_fire := Input.is_action_pressed("fire") if w.automatic else Input.is_action_just_pressed("fire")
	if wants_fire:
		_fire()


func _switch(index: int) -> void:
	if index == _active or index >= _weapons.size():
		return
	active_weapon().cancel_reload()      # switching cancels an in-progress reload
	_active = index
	if _viewmodel and _viewmodel.has_method("set_weapon"):
		_viewmodel.set_weapon(active_weapon().weapon_name)
	_update_hud()


func _fire() -> void:
	var w := active_weapon()
	if w == null or _camera == null:
		return
	# Guard the action, not just the input polling: disabling _process stops the
	# player firing, but any other caller would still have gone through.
	var owner_body := get_parent()
	if owner_body and ("combat_enabled" in owner_body) and not owner_body.combat_enabled:
		return
	if not w.can_fire():
		return
	var origin := _camera.global_position
	var dir := -_camera.global_transform.basis.z
	var exclude: Array[RID] = []
	if _body != null:
		exclude.append(_body.get_rid())
	w.fire(origin, dir, get_world_3d(), exclude)
	if _viewmodel != null:
		_viewmodel.kick()                # recoil the on-screen viewmodel
	# Camera recoil, weighted per weapon so the shotgun throws the view and the
	# auto rifle only nudges it.
	var player := get_parent()
	if player and player.has_method("add_recoil"):
		var r: Dictionary = CAMERA_RECOIL.get(w.weapon_name, CAMERA_RECOIL["Auto Rifle"])
		player.add_recoil(float(r["pitch"]), float(r["shake"]))


func _update_hud() -> void:
	if _ammo_label == null:
		return
	var w := active_weapon()
	if w == null:
		return
	var suffix := "  RELOADING" if w.is_reloading() else ""
	_ammo_label.text = "%s   %d / %d%s" % [w.weapon_name, w.ammo, w.mag_size, suffix]

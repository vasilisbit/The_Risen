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
	_update_hud()


func _fire() -> void:
	var w := active_weapon()
	if w == null or _camera == null:
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


func _update_hud() -> void:
	if _ammo_label == null:
		return
	var w := active_weapon()
	if w == null:
		return
	var suffix := "  RELOADING" if w.is_reloading() else ""
	_ammo_label.text = "%s   %d / %d%s" % [w.weapon_name, w.ammo, w.mag_size, suffix]

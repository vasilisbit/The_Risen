extends Node3D
## Player weapon manager (T-0010). Holds the four weapon scenes, handles switch
## (1-4), reload (R), and fire (LMB - full-auto for the Auto Rifle, semi for the
## rest), raycasting from the player camera. Updates the ammo HUD label.

## Weapon scene per kind name. The active loadout no longer holds all four - it
## is built from the weapons the player has earned and equipped (SaveManager),
## so a fresh Guardian carries just the starting Auto Rifle.
const KIND_SCENES := {
	"Auto Rifle": "res://scenes/weapons/auto_rifle.tscn",
	"Shotgun": "res://scenes/weapons/shotgun.tscn",
	"Sniper": "res://scenes/weapons/sniper.tscn",
	"Hand Cannon": "res://scenes/weapons/hand_cannon.tscn",
}

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
	var sm := get_node_or_null("/root/SaveManager")
	if sm and sm.has_signal("loadout_changed"):
		sm.loadout_changed.connect(rebuild)
	rebuild()


## (Re)build the active weapons from the equipped loadout, applying each item's
## rarity to its stats. Called on ready and whenever the player changes their
## loadout in the inventory, so an equip is reflected immediately.
func rebuild() -> void:
	for w in _weapons:
		w.queue_free()
	_weapons.clear()
	_active = 0
	var sm := get_node_or_null("/root/SaveManager")
	var items: Array = sm.equipped_weapon_items() if sm and sm.has_method("equipped_weapon_items") else []
	for item in items:
		var kind := String(item.get("name", "Auto Rifle"))
		var path: String = KIND_SCENES.get(kind, KIND_SCENES["Auto Rifle"])
		var w := load(path).instantiate() as Weapon
		# Rarity + this item's stored stat rolls, before add_child so ammo fills
		# the rolled magazine.
		w.apply_stats(String(item.get("rarity", "Common")), item.get("rolls", {}))
		for mod_id in item.get("mods", []):                    # installed mods: element + stat tweaks
			w.apply_mod(String(mod_id))
		add_child(w)
		w.state_changed.connect(_update_hud)
		# Play the FP reload animation whenever a reload BEGINS - manual (R) or the
		# automatic reload weapon.tick() starts when the mag runs dry.
		w.reload_started.connect(_on_reload_started)
		_weapons.append(w)
	# Give the viewmodel the starting weapon's silhouette.
	if not _weapons.is_empty():
		_show_weapon(_weapons[_active].weapon_name)
	_update_hud()


func active_weapon() -> Weapon:
	return _weapons[_active] if _active < _weapons.size() else null


## Top every weapon back up instantly (used on respawn) - no reload wait, any
## in-progress reload cancelled. You come back ready to fight, not mid-reload.
func reset_all_ammo() -> void:
	for w in _weapons:
		w.cancel_reload()
		w.ammo = w.mag_size
		w.state_changed.emit()


func _process(delta: float) -> void:
	var w := active_weapon()
	if w == null:
		return
	w.tick(delta)               # reloads in progress keep ticking even while paused-in-menu

	# The inventory no longer freezes the world (so a jump finishes), but the player
	# should not fire/switch/reload while browsing it - a click on a panel item
	# would otherwise also pull the trigger.
	var inv := get_tree().get_first_node_in_group("inventory_screen")
	if inv and inv.visible:
		return

	if Input.is_action_just_pressed("weapon_1"):
		_switch(0)
	elif Input.is_action_just_pressed("weapon_2"):
		_switch(1)
	elif Input.is_action_just_pressed("weapon_3"):
		_switch(2)
	elif Input.is_action_just_pressed("weapon_4"):
		_switch(3)
	elif Input.is_action_just_pressed("weapon_next"):
		_cycle(1)                          # scroll wheel down -> next weapon
	elif Input.is_action_just_pressed("weapon_prev"):
		_cycle(-1)                         # scroll wheel up -> previous weapon

	if Input.is_action_just_pressed("reload"):
		w.start_reload()                     # the reload_started signal plays the FP animation

	var wants_fire := Input.is_action_pressed("fire") if w.automatic else Input.is_action_just_pressed("fire")
	if wants_fire:
		_fire()


## Cycle the active weapon by `dir` (+1 next, -1 previous), wrapping around the
## equipped set. Bound to the mouse wheel; no-op with 0 or 1 weapons.
func _cycle(dir: int) -> void:
	var n := _weapons.size()
	if n <= 1:
		return
	_switch((_active + dir + n) % n)


func _switch(index: int) -> void:
	if index == _active or index >= _weapons.size():
		return
	active_weapon().cancel_reload()      # switching cancels an in-progress reload
	_active = index
	_show_weapon(active_weapon().weapon_name)
	_update_hud()


## Play the first-person arms reload animation for a reload that just began (from
## the weapon's reload_started signal, so manual R and auto-on-empty both animate).
func _on_reload_started(duration: float) -> void:
	var fpvm := get_parent().get_node_or_null("FPViewmodel")
	if fpvm and fpvm.has_method("play_reload"):
		fpvm.play_reload(duration)


## Re-push the equipped weapon into the viewmodel and the character's hand.
## Called by the Guardian once its character body exists (this node's _ready runs
## first, so the hand attachment does not exist yet at that point).
func refresh_weapon_visual() -> void:
	if not _weapons.is_empty():
		_show_weapon(active_weapon().weapon_name)


## Point both the camera viewmodel and the character's hand at this weapon, so
## whichever one is being drawn shows the right gun.
func _show_weapon(name_: String) -> void:
	if _viewmodel and _viewmodel.has_method("set_weapon"):
		_viewmodel.set_weapon(name_)
	var character := get_parent().get_node_or_null("PlayerCharacter")
	if character and character.has_method("set_weapon"):
		character.set_weapon(name_)
	# The first-person viewmodel (arms+gun composited on top) in combat.
	var fpvm := get_parent().get_node_or_null("FPViewmodel")
	if fpvm and fpvm.has_method("set_weapon"):
		fpvm.set_weapon(name_)


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
		_viewmodel.kick()                # recoil the (legacy) camera viewmodel
	var fpvm := get_parent().get_node_or_null("FPViewmodel")
	if fpvm and fpvm.has_method("kick"):
		fpvm.kick(w.weapon_name)         # recoil the first-person arms viewmodel
	if fpvm and fpvm.has_method("muzzle_flash"):
		# Per-gun-type flash, tinted by the weapon's energy element (Solar/Arc/Void).
		var ecol: Color = Weapon.ELEMENT_COLORS.get(w.element, Color(1.0, 0.9, 0.7))
		fpvm.muzzle_flash(w.weapon_name, ecol)
	# Camera recoil, weighted per weapon so the shotgun throws the view and the
	# auto rifle only nudges it.
	var player := get_parent()
	if player and player.has_method("add_recoil"):
		var r: Dictionary = CAMERA_RECOIL.get(w.weapon_name, CAMERA_RECOIL["Auto Rifle"])
		# A rarer roll kicks less (recoil_mult < 1 from Rare up).
		player.add_recoil(float(r["pitch"]) * w.recoil_mult, float(r["shake"]) * w.recoil_mult)


func _update_hud() -> void:
	if _ammo_label == null:
		return
	var w := active_weapon()
	if w == null:
		return
	var suffix := "  RELOADING" if w.is_reloading() else ""
	_ammo_label.text = "%s   %d / %d%s" % [w.weapon_name, w.ammo, w.mag_size, suffix]

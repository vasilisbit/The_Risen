class_name EnemyNameplate
extends Node3D

## Destiny-style floating nameplate above an enemy: its name, a health bar, and
## - for a shielded enemy - a shield segment tinted by the shield's element. On
## an elemental (Heroic/Legendary) shield it also raises a matching-coloured
## energy shell around the body, so the player can SEE which element the shield
## needs (the telegraph) rather than guessing.
##
## Built entirely from 3D primitives (Label3D + quads + a sphere), no image
## assets and no per-enemy SubViewport, so a Mars room full of enemies stays
## cheap. The whole plate is billboarded by copying the camera basis each frame.

const BAR_W := 0.92
const BAR_H := 0.085
const SHIELD_H := 0.05
const HEAD_Y := 2.15                 # local height above the enemy origin (head ~1.8)
const NORMAL_COLOR := Color(0.90, 0.92, 0.96)
const BOSS_COLOR := Color(1.00, 0.80, 0.32)
const HP_COLOR := Color(0.86, 0.22, 0.20)
const BOSS_HP_COLOR := Color(0.95, 0.70, 0.22)

var _enemy: Node
var _hp_fill: MeshInstance3D
var _shield_bg: MeshInstance3D
var _shield_fill: MeshInstance3D
var _shell: MeshInstance3D
var _has_shield: bool = false
var _elemental: bool = false
var _pulse: float = 0.0


## Wire the enemy before adding to the tree, so _ready can read its stats.
func setup(enemy: Node) -> void:
	_enemy = enemy


func _ready() -> void:
	if _enemy == null:
		return
	var head_y: float = _enemy.nameplate_head_y() if _enemy.has_method("nameplate_head_y") else HEAD_Y
	position = Vector3(0, head_y, 0)
	var is_boss: bool = _enemy.has_method("nameplate_tier") and _enemy.nameplate_tier() == "boss"
	_build_name(is_boss)
	_build_health_bar(is_boss)
	_build_shield_bar()
	_build_shell()


func _build_name(is_boss: bool) -> void:
	var label := Label3D.new()
	label.text = _enemy.display_name() if _enemy.has_method("display_name") else "Enemy"
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED   # the root billboards us
	label.double_sided = true
	label.no_depth_test = false
	label.pixel_size = 0.0045 if is_boss else 0.0038
	label.modulate = BOSS_COLOR if is_boss else NORMAL_COLOR
	label.outline_modulate = Color(0, 0, 0, 0.85)
	label.outline_size = 14
	label.position = Vector3(0, 0.15 if not _has_shield else 0.20, 0)
	add_child(label)


func _build_health_bar(is_boss: bool) -> void:
	var w := BAR_W * (1.25 if is_boss else 1.0)
	add_child(_quad(w + 0.03, BAR_H + 0.03, Color(0, 0, 0, 0.75), 0))   # frame
	_hp_fill = _quad(w, BAR_H, BOSS_HP_COLOR if is_boss else HP_COLOR, 2)
	_hp_fill.set_meta("full_w", w)
	add_child(_hp_fill)


func _build_shield_bar() -> void:
	if not _enemy.has_method("nameplate_shield_max") or _enemy.nameplate_shield_max() <= 0.0:
		return
	_has_shield = true
	_elemental = String(_enemy.get("shield_element")) != "Kinetic"
	var y := BAR_H * 0.5 + SHIELD_H * 0.5 + 0.02
	_shield_bg = _quad(BAR_W + 0.03, SHIELD_H + 0.02, Color(0, 0, 0, 0.75), 1)
	_shield_bg.position = Vector3(0, y, 0)
	add_child(_shield_bg)
	_shield_fill = _quad(BAR_W, SHIELD_H, _shield_color(), 3)
	_shield_fill.set_meta("full_w", BAR_W)
	_shield_fill.position = Vector3(0, y, 0)
	add_child(_shield_fill)


## A translucent element-coloured shell around the body - only for an elemental
## shield, so it doubles as the "bring this element" telegraph. The Shielded
## Brute's plain gate keeps its own VFX and gets no shell here.
func _build_shell() -> void:
	if not _has_shield or not _elemental or _enemy.get_parent() == null:
		return
	_shell = MeshInstance3D.new()
	var sph := SphereMesh.new()
	var r: float = _enemy.nameplate_shell_radius() if _enemy.has_method("nameplate_shell_radius") else 0.72
	sph.radius = r
	sph.height = r * 2.6
	_shell.mesh = sph
	var col := _shield_color()
	# A rim-lit shell: near-transparent front, brighter at grazing angles (via
	# a soft fresnel through rim), so it reads as an energy bubble rather than a
	# solid glowing ball when the enemy is close.
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mat.albedo_color = Color(col.r, col.g, col.b, 0.10)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 0.35
	mat.rim_enabled = true
	mat.rim = 1.0
	mat.rim_tint = 0.5
	_shell.material_override = mat
	# Body centre in enemy space (roughly half the head height).
	var head_y: float = _enemy.nameplate_head_y() if _enemy.has_method("nameplate_head_y") else HEAD_Y
	_shell.position = Vector3(0, head_y * 0.5, 0)
	_enemy.add_child(_shell)                        # sibling of us, on the body


func _process(delta: float) -> void:
	if _enemy == null or not is_instance_valid(_enemy):
		queue_free()
		return
	# Billboard: copy the camera's orientation, keep our world position.
	var cam := get_viewport().get_camera_3d()
	if cam:
		global_transform = Transform3D(cam.global_transform.basis, global_position)

	var max_hp: float = maxf(1.0, float(_enemy.get("max_health")))
	_anchor(_hp_fill, clampf(float(_enemy.get("health")) / max_hp, 0.0, 1.0))

	if _has_shield and _shield_fill:
		var smax: float = maxf(1.0, _enemy.nameplate_shield_max())
		var sfrac := clampf(_enemy.nameplate_shield() / smax, 0.0, 1.0)
		_anchor(_shield_fill, sfrac)
		var up := sfrac > 0.001
		_shield_fill.visible = up
		if _shield_bg:
			_shield_bg.visible = up
		if _shell:
			_shell.visible = up
			_pulse += delta
			var s := 1.0 + sin(_pulse * 4.0) * 0.03
			_shell.scale = Vector3(s, s, s)


## Scale a centred fill quad from its left edge to `frac` of its full width.
func _anchor(fill: MeshInstance3D, frac: float) -> void:
	if fill == null:
		return
	var full: float = float(fill.get_meta("full_w", BAR_W))
	fill.scale.x = maxf(frac, 0.0001)
	fill.position.x = -full * 0.5 + full * frac * 0.5


func _shield_color() -> Color:
	if _enemy and _enemy.has_method("nameplate_shield_color"):
		return _enemy.nameplate_shield_color()
	return Color(0.55, 0.75, 1.0)


## An unshaded, double-sided coloured quad. render_priority orders the coplanar
## fills over their frames (transparent surfaces don't write depth, so draw order
## decides what shows).
func _quad(w: float, h: float, color: Color, priority: int = 0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	mi.mesh = q
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.render_priority = priority
	mi.material_override = mat
	return mi

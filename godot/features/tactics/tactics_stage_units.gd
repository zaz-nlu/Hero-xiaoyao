extends Node3D

# 战旗 3D 演员层：为每个 TacticsUnit 建立像素立绘演员（脚下阴影由 CharacterSprite 提供），
# 并同步位置、朝向、血条、韧性点、星标与晕眩。只读战斗状态。

const CharacterSprite = preload("res://shared/scene/character_sprite.gd")
const TacticsTheme = preload("res://features/tactics/tactics_theme.gd")
const StageWeak = preload("res://features/tactics/tactics_stage_weak.gd")

const PLAYER_SPRITE := "ren_xiaoyao"
const WALK_STEP := 0.12
const SPRITE_PIXEL_SIZE := 1.0 / 12.8
const BAR_WIDTH := 2.0
const BAR_HEIGHT := 0.18
const BAR_Y := 4.05
const PIP_Y := 3.78
const PIP_MAX := 0.2
const BAR_BACK := Color(0.04, 0.03, 0.05, 0.9)
const BAR_PLAYER := Color(0.40, 0.88, 0.45)
const BAR_ENEMY := Color(0.92, 0.27, 0.24)
const RING_PLAYER := Color(0.36, 0.84, 1.0, 0.9)
const RING_ENEMY := Color(1.0, 0.34, 0.30, 0.9)
const RING_ACTIVE := Color(1.0, 0.82, 0.30, 0.95)
const STUN_COLOR := Color(0.65, 0.80, 1.0)
const TOUGH_ON := Color(0.95, 0.80, 0.35)
const TOUGH_OFF := Color(0.30, 0.28, 0.24)
const HIT_TINT := Color(1.0, 0.55, 0.55)

var tiles: Variant = null
var battle: Variant = null

var _actors: Dictionary = {}
var _dead: Dictionary = {}
var _time: float = 0.0


func build(p_battle, p_tiles) -> void:
	tiles = p_tiles
	battle = p_battle
	_clear()
	sync(p_battle)


func sync(p_battle) -> void:
	if p_battle == null:
		return
	if battle != p_battle:
		battle = p_battle
		_clear()
	for raw_unit in battle.units:
		if raw_unit == null:
			continue
		var uid := str(raw_unit.id)
		if not raw_unit.is_alive():
			_kill(uid)
			continue
		if _dead.has(uid):
			continue
		var entry = _actors.get(uid, null)
		if entry == null:
			entry = _create_actor(raw_unit)
			_actors[uid] = entry
		if entry["cell"] != raw_unit.pos:
			_walk_to(entry, raw_unit.pos)
		_update_facing(entry, raw_unit.facing)
		_update_bars(entry, raw_unit)


func actor(unit_id: String):
	var entry = _actors.get(unit_id, null)
	if entry == null:
		return null
	return entry.get("root", null)


func actor_count() -> int:
	return _actors.size()


func unit_world(unit_id: String) -> Vector3:
	var node = actor(unit_id)
	if node == null or not is_instance_valid(node):
		return Vector3.ZERO
	return node.position


func play_attack(attacker_id: String, target_cell: Vector2i) -> void:
	var entry = _actors.get(attacker_id, null)
	if entry == null:
		return
	var root: Node3D = entry.get("root", null)
	if root == null or not is_instance_valid(root):
		return
	var target := _cell_world(target_cell)
	var delta := target - root.position
	if delta.length() < 0.01:
		return
	var body = entry.get("body", null)
	if body != null:
		body.set_facing(_facing_name(Vector2i(int(signf(delta.x)), int(signf(delta.z)))))
	if not is_inside_tree():
		return
	var origin := root.position
	var direction := Vector3(delta.x, 0.0, delta.z).normalized()
	var tween := create_tween()
	tween.tween_property(
		root, "position", origin + direction * (TacticsTheme.CELL_SIZE * 0.3), 0.1)
	tween.tween_property(root, "position", origin, 0.12)


func flash_hit(unit_id: String) -> void:
	var entry = _actors.get(unit_id, null)
	if entry == null:
		return
	var sprite: Sprite3D = entry.get("sprite", null)
	var body = entry.get("body", null)
	if sprite != null and is_instance_valid(sprite):
		sprite.modulate = HIT_TINT
		if is_inside_tree():
			var tween := create_tween()
			tween.tween_interval(0.12)
			tween.tween_property(sprite, "modulate", Color.WHITE, 0.03)
		else:
			sprite.modulate = Color.WHITE
	if body != null and is_instance_valid(body):
		body.position = Vector3(0.0, body.position.y, 0.22)
		if is_inside_tree():
			var knock := create_tween()
			knock.tween_property(body, "position:z", 0.0, 0.15)


func _process(delta: float) -> void:
	_time += delta
	var actor_id := ""
	if battle != null:
		actor_id = str(battle.current_actor)
	for uid in _actors.keys():
		var entry = _actors[uid]
		var body = entry.get("body", null)
		var is_active := str(uid) == actor_id and not bool(entry.get("dead", false))
		if body != null and is_instance_valid(body):
			var bob := 0.0
			if is_active:
				bob = sin(_time * 3.2) * 0.06
			body.position = Vector3(0.0, bob, body.position.z)
		_update_ring(entry, is_active)


func _update_ring(entry: Dictionary, is_active: bool) -> void:
	var ring: MeshInstance3D = entry.get("ring", null)
	if ring == null or not is_instance_valid(ring):
		return
	var mat: Variant = entry.get("ring_mat", null)
	if is_active:
		var pulse := 1.04 + sin(_time * 4.0) * 0.05
		ring.scale = Vector3(pulse, 1.0, pulse)
		if mat is StandardMaterial3D:
			(mat as StandardMaterial3D).albedo_color = RING_ACTIVE
			(mat as StandardMaterial3D).emission = RING_ACTIVE
	else:
		ring.scale = Vector3.ONE
		if mat is StandardMaterial3D:
			var base: Color = entry.get("ring_color", RING_ENEMY)
			(mat as StandardMaterial3D).albedo_color = base
			(mat as StandardMaterial3D).emission = base


func _create_actor(unit) -> Dictionary:
	var root := Node3D.new()
	root.name = "Actor_%s" % str(unit.id)
	add_child(root)
	root.position = _cell_world(unit.pos)

	var body: Variant = CharacterSprite.new()
	body.name = "Body"
	body.setup(_sprite_id(unit))
	body.set_facing(_facing_name(unit.facing))
	root.add_child(body)
	var sprite: Sprite3D = body.get_node_or_null("Sprite")
	if sprite != null:
		sprite.pixel_size = SPRITE_PIXEL_SIZE
		sprite.shaded = false
	_tune_shadow(body)

	var fill_color := BAR_PLAYER if unit.side == "player" else BAR_ENEMY
	var back := _bar(root, Vector2(BAR_WIDTH, BAR_HEIGHT), BAR_BACK, BAR_Y)
	var fill := _bar(root, Vector2(BAR_WIDTH, BAR_HEIGHT), fill_color, BAR_Y)
	var pips: Array = []
	var toughness := int(unit.unit.toughness_max)
	var step := BAR_WIDTH / float(maxi(1, toughness))
	var pip_size := minf(PIP_MAX, step * 0.7)
	for i in range(toughness):
		var pip := _bar(
			root, Vector2(pip_size, pip_size), TOUGH_ON, PIP_Y)
		pip.position.x = -BAR_WIDTH * 0.5 + step * (float(i) + 0.5)
		pips.append(pip)

	var ring_color := RING_PLAYER if unit.side == "player" else RING_ENEMY
	var ring := _ring(root, ring_color)

	var star := _icon(root, "★", Color(1.0, 0.86, 0.32),
		Vector3(BAR_WIDTH * 0.5 + 0.22, BAR_Y, 0.0))
	var stun := _icon(root, "晕", STUN_COLOR,
		Vector3(-BAR_WIDTH * 0.5 - 0.22, BAR_Y, 0.0))
	var weak_icons: Variant = StageWeak.new()
	weak_icons.name = "WeaknessIcons"
	root.add_child(weak_icons)
	return {
		"root": root,
		"body": body,
		"sprite": sprite,
		"back": back,
		"fill": fill,
		"pips": pips,
		"ring": ring,
		"ring_mat": ring.material_override,
		"ring_color": ring_color,
		"star": star,
		"stun": stun,
		"weak_icons": weak_icons,
		"cell": unit.pos,
		"dead": false,
		"walk_tween": null,
	}


func _tune_shadow(body: Node3D) -> void:
	var shadow := body.get_node_or_null("BlobShadow")
	if not (shadow is MeshInstance3D):
		return
	var mat := (shadow as MeshInstance3D).material_override as StandardMaterial3D
	if mat == null:
		return
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.alpha_scissor_threshold = 0.0
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.35)


func _ring(parent: Node3D, color: Color) -> MeshInstance3D:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.72
	torus.outer_radius = 0.98
	torus.rings = 32
	torus.ring_segments = 8
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.45
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.metallic_specular = 0.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var node := MeshInstance3D.new()
	node.name = "FactionRing"
	node.mesh = torus
	node.material_override = mat
	node.position = Vector3(0.0, 0.03, 0.0)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node


func _bar(
	parent: Node3D, size: Vector2, color: Color, height: float
) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	var node := MeshInstance3D.new()
	node.mesh = quad
	node.material_override = mat
	node.position = Vector3(0.0, height, 0.0)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node


func _icon(parent: Node3D, text: String, color: Color, pos: Vector3) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 48
	label.outline_size = 8
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.8)
	label.modulate = color
	label.pixel_size = 0.008
	label.position = pos
	label.visible = false
	parent.add_child(label)
	return label


func _walk_to(entry: Dictionary, cell: Vector2i) -> void:
	var from: Vector2i = entry["cell"]
	entry["cell"] = cell
	var steps := _manhattan_steps(from, cell)
	if steps.is_empty():
		return
	var body = entry.get("body", null)
	var root: Node3D = entry.get("root", null)
	if body != null:
		var last: Vector2i = steps[steps.size() - 1]
		body.set_facing(_facing_name(last - from))
	if not is_inside_tree():
		if root != null and is_instance_valid(root):
			root.position = _cell_world(cell)
		if body != null:
			body.set_moving(false)
		return
	if root == null or not is_instance_valid(root):
		return
	var old = entry.get("walk_tween", null)
	if old != null and old is Tween and old.is_valid():
		old.kill()
	if body != null:
		body.set_moving(true)
	var tween := create_tween()
	entry["walk_tween"] = tween
	for step in steps:
		tween.tween_property(root, "position", _cell_world(step), WALK_STEP)
	if body != null:
		tween.tween_callback(Callable(body, "set_moving").bind(false))


func _update_facing(entry: Dictionary, facing: Vector2i) -> void:
	var body = entry.get("body", null)
	if body == null:
		return
	body.set_facing(_facing_name(facing))


func _update_bars(entry: Dictionary, unit) -> void:
	var fill: MeshInstance3D = entry.get("fill", null)
	if fill != null and is_instance_valid(fill):
		var quad := fill.mesh as QuadMesh
		if quad != null:
			var ratio := clampf(
				float(unit.unit.hp) / maxf(1.0, float(unit.unit.max_hp)), 0.0, 1.0)
			var size := quad.size
			size.x = BAR_WIDTH * ratio
			quad.size = size
			fill.position.x = -BAR_WIDTH * 0.5 + size.x * 0.5

	var pips: Array = entry.get("pips", [])
	var left := int(ceil(float(unit.unit.toughness_left)))
	for i in range(pips.size()):
		var pip = pips[i]
		if pip == null or not is_instance_valid(pip):
			continue
		var mat := pip.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_color = TOUGH_ON if i < left else TOUGH_OFF

	var star = entry.get("star", null)
	if star != null and is_instance_valid(star):
		star.visible = (
			unit.side == "enemy" and battle != null
			and str(battle.leader_id) != "" and str(unit.id) == str(battle.leader_id))
	var stun = entry.get("stun", null)
	if stun != null and is_instance_valid(stun):
		stun.visible = unit.unit.is_stunned()
	var weak_icons = entry.get("weak_icons", null)
	if weak_icons != null and is_instance_valid(weak_icons):
		weak_icons.sync(unit)


func _kill(unit_id: String) -> void:
	if _dead.has(unit_id):
		return
	_dead[unit_id] = true
	var entry = _actors.get(unit_id, null)
	if entry == null:
		return
	entry["dead"] = true
	var root: Node3D = entry.get("root", null)
	if root == null or not is_instance_valid(root):
		return
	if not is_inside_tree():
		root.visible = false
		return
	var sprite: Sprite3D = entry.get("sprite", null)
	if sprite == null or not is_instance_valid(sprite):
		root.visible = false
		return
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0, 0.0), 0.3)
	tween.tween_callback(Callable(root, "hide"))


func _clear() -> void:
	for key in _actors.keys():
		var entry = _actors[key]
		var root: Node3D = entry.get("root", null)
		if root == null or not is_instance_valid(root):
			continue
		if root.get_parent() == self:
			remove_child(root)
		if is_inside_tree():
			root.queue_free()
		else:
			root.free()
	_actors.clear()
	_dead.clear()


func _manhattan_steps(from: Vector2i, to: Vector2i) -> Array:
	var steps: Array = []
	var cursor := from
	while cursor.x != to.x:
		cursor.x += signi(to.x - cursor.x)
		steps.append(cursor)
	while cursor.y != to.y:
		cursor.y += signi(to.y - cursor.y)
		steps.append(cursor)
	return steps


func _facing_name(direction: Vector2i) -> String:
	if absi(direction.x) >= absi(direction.y) and direction.x != 0:
		return "right" if direction.x > 0 else "left"
	if direction.y > 0:
		return "down"
	if direction.y < 0:
		return "up"
	return "down"


func _sprite_id(unit) -> String:
	if unit.side == "player":
		return PLAYER_SPRITE
	if unit.unit != null and unit.unit.def != null:
		var sprite := str(unit.unit.def.sprite)
		if sprite != "":
			return sprite
	var fallback := str(unit.unit.id)
	return fallback if fallback != "" else "bandit"


func _cell_world(cell: Vector2i) -> Vector3:
	if tiles == null or cell.x < 0:
		return Vector3.ZERO
	return tiles.cell_center(cell)

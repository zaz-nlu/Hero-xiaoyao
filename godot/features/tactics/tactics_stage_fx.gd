extends Node3D

# 战旗 3D 特效层：把 core 事件翻译成 data/tactics_vfx.json 配置的 vfx 帧动画与伤害飘字。
# VFX 图集按 8 列切帧。

const TacticsTheme = preload("res://features/tactics/tactics_theme.gd")
const VfxTable = preload("res://features/tactics/tactics_vfx_table.gd")
const VfxTargeting = preload("res://features/tactics/tactics_vfx_targeting.gd")
const ImageCache = preload("res://shared/resources/image_cache.gd")

const VFX_DIR := "res://assets/vfx/"
const SHEET_COLS := 8
const DEFAULT_FPS := 16.0
const DEFAULT_SCALE := 1.6
# 特效高度 ≈ CELL_SIZE * 0.92 * 配置里的 scale。
const HEIGHT_PER_CELL := 0.92
const CHEST_HEIGHT := 1.4
const PROJECTILE_TIME := 0.3
const LINE_STEP_DELAY := 0.04
const DAMAGE_LIFE := 0.8
const DAMAGE_RISE := 1.7
const NORMAL_COLOR := Color(0.96, 0.96, 0.94)
const CRIT_COLOR := Color(1.0, 0.86, 0.30)
const COUNTER_COLOR := Color(0.42, 0.90, 0.95)
const HEAL_COLOR := Color(0.45, 0.95, 0.50)
const MISS_COLOR := Color(0.66, 0.66, 0.66)
const JIANYI_COLOR := Color(0.78, 0.55, 1.0)

static var _frame_cache: Dictionary = {}

var battle: Variant = null
var tiles: Variant = null
var units: Variant = null

var _effects: Array = []
var _pending: Array = []
var _popups: Array = []
var _last_attack: Dictionary = {}
var _targeting: Variant = null


func setup(p_battle, p_tiles, p_units) -> void:
	battle = p_battle
	tiles = p_tiles
	units = p_units


func set_battle(p_battle) -> void:
	battle = p_battle


func effect_count() -> int:
	return _effects.size() + _pending.size()


func popup_count() -> int:
	return _popups.size()


func show_events(events: Array, context: Dictionary = {}) -> void:
	for raw in events:
		if raw is Dictionary:
			show_event(raw, context)


func show_event(event: Dictionary, context: Dictionary = {}) -> void:
	match str(event.get("type", "")):
		"attack":
			_on_attack(event, context)
		"hit":
			_on_hit(event, context)
		"counter_hit":
			_on_counter(event, context)
		"jianyi":
			_on_jianyi(event, context)
		"stun":
			_on_stun(event, context)
		"dead":
			_on_dead(event, context)
		"heal":
			spawn_damage_number(
				_unit_world(str(event.get("unit", ""))), int(event.get("amount", 0)), "heal")
		"move":
			_on_move(event, context)


# 兼容旧调用：直接播放某张图集第 0 行。
func spawn_vfx(name: String, cell_or_pos: Variant, scale_value: float = 1.0) -> void:
	_spawn_effect(name, 0, _resolve_pos(cell_or_pos), scale_value, DEFAULT_FPS,
		Color.WHITE, 0.0)


# 播放一条配置：可以是单个步骤，也可以是依次出现的步骤数组。
func _play(spec: Variant, event: Dictionary, context: Dictionary, fallback: Vector2i,
		base_delay: float = 0.0) -> void:
	if spec is Array:
		var delay := base_delay
		for raw_step in spec:
			if not (raw_step is Dictionary):
				continue
			var step: Dictionary = raw_step
			_play_step(step, event, context, fallback, delay)
			delay += maxf(0.0, float(step.get("delay", 0.0)))
		return
	if spec is Dictionary:
		_play_step(spec, event, context, fallback, base_delay)


func _play_step(step: Dictionary, event: Dictionary, context: Dictionary,
		fallback: Vector2i, delay: float) -> void:
	var sheet := str(step.get("sheet", ""))
	if sheet == "":
		return
	var row := int(step.get("row", 0))
	var scale_value := float(step.get("scale", DEFAULT_SCALE))
	var fps := float(step.get("fps", DEFAULT_FPS))
	var tint := _tint(step.get("tint", "#ffffff"))
	var targeter = _targeter()
	match str(step.get("at", "target")):
		"projectile":
			var from: Vector3 = targeter.cell_center(
				targeter.attacker_cell(event, context))
			var to: Vector3 = targeter.cell_center(
				targeter.target_cell(event, context, fallback))
			var flight := maxf(0.05, float(step.get("flight", PROJECTILE_TIME)))
			_spawn_effect(sheet, row, from, scale_value, fps, tint, delay, to, flight)
		"line":
			var cells: Array = targeter.line_cells(event, context, fallback)
			var stagger := maxf(0.0, float(step.get("step_delay", LINE_STEP_DELAY)))
			for i in range(cells.size()):
				var cell: Vector2i = cells[i]
				_spawn_effect(sheet, row, targeter.cell_center(cell), scale_value,
					fps, tint, delay + stagger * float(i))
		_:
			var cell: Vector2i = targeter.cell_for_step(step, event, context, fallback)
			_spawn_effect(sheet, row, targeter.cell_center(cell), scale_value,
				fps, tint, delay)


func _spawn_effect(sheet: String, row: int, pos: Vector3, scale_value: float,
		fps: float, tint: Color, delay: float = 0.0,
		fly_to: Variant = null, fly_time: float = 0.0) -> void:
	var request: Dictionary = {
		"sheet": sheet, "row": row, "pos": pos, "scale": scale_value,
		"fps": fps, "tint": tint, "delay": maxf(0.0, delay),
	}
	if fly_to is Vector3:
		request["fly_to"] = fly_to
		request["fly_time"] = maxf(0.05, fly_time)
	if float(request["delay"]) > 0.0:
		_pending.append(request)
		return
	_create_effect(request)


func _create_effect(request: Dictionary) -> void:
	var sheet := str(request["sheet"])
	var frames := _frames(sheet, int(request["row"]))
	if frames.is_empty():
		return
	var pos: Vector3 = request["pos"]
	var scale_value := float(request["scale"])
	var tint: Color = request["tint"]
	var first: Texture2D = frames[0]
	var raw := first.get_size()
	if raw.y <= 0.0:
		return
	var height := TacticsTheme.CELL_SIZE * HEIGHT_PER_CELL * scale_value
	var width := height * raw.x / raw.y
	var quad := QuadMesh.new()
	quad.size = Vector2(width, height)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = first
	mat.albedo_color = tint
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.no_depth_test = true
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var node := MeshInstance3D.new()
	node.name = "Vfx_%s_%d" % [sheet, int(request["row"])]
	node.mesh = quad
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.position = pos + Vector3(0.0, CHEST_HEIGHT, 0.0)
	add_child(node)
	var entry: Dictionary = {
		"node": node, "mat": mat, "frames": frames, "age": 0.0,
		"fps": maxf(1.0, float(request["fps"])),
	}
	if request.has("fly_to"):
		var fly_to: Vector3 = request["fly_to"]
		entry["fly_from"] = node.position
		entry["fly_to"] = fly_to + Vector3(0.0, CHEST_HEIGHT, 0.0)
		entry["fly_time"] = float(request["fly_time"])
	_effects.append(entry)


func _spec_is_projectile(raw: Variant) -> bool:
	if raw is Dictionary:
		return str(raw.get("at", "")) == "projectile"
	if raw is Array:
		for step in raw:
			if _spec_is_projectile(step):
				return true
	return false


func _tint(raw: Variant) -> Color:
	if raw is Color:
		return raw
	var text := str(raw).strip_edges()
	if text.begins_with("#"):
		text = text.substr(1)
	if text.length() != 6 and text.length() != 8:
		return Color.WHITE
	return Color.html(text)


func spawn_damage_number(world_pos: Vector3, amount: int, kind: String = "normal") -> void:
	var text := str(amount)
	var color := NORMAL_COLOR
	match kind:
		"crit", "back":
			color = CRIT_COLOR
		"counter":
			color = COUNTER_COLOR
		"heal":
			color = HEAL_COLOR
			text = "+%d" % amount
		"jianyi":
			color = JIANYI_COLOR
		"miss":
			color = MISS_COLOR
		"react":
			color = MISS_COLOR
			text = "反制"
		"weak":
			color = CRIT_COLOR
			text = "弱点 -%d" % amount
	var label := Label3D.new()
	label.name = "DamageNumber"
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 76 if kind == "weak" else 64
	label.outline_size = 10
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	label.modulate = color
	label.pixel_size = 0.012
	label.position = world_pos + Vector3(0.0, 2.3, 0.0)
	add_child(label)
	_popups.append({
		"node": label, "age": 0.0, "base": label.position, "color": color,
	})


func advance(delta: float) -> void:
	var waiting: Array = []
	for request in _pending:
		request["delay"] = float(request["delay"]) - delta
		if float(request["delay"]) <= 0.0:
			_create_effect(request)
		else:
			waiting.append(request)
	_pending = waiting

	var kept: Array = []
	for entry in _effects:
		entry["age"] = float(entry["age"]) + delta
		var frames: Array = entry["frames"]
		var index := int(float(entry["age"]) * float(entry["fps"]))
		if index >= frames.size():
			_free_node(entry["node"])
			continue
		var mat = entry.get("mat", null)
		if mat != null:
			mat.albedo_texture = frames[index]
		_apply_flight(entry)
		kept.append(entry)
	_effects = kept

	var alive: Array = []
	for entry in _popups:
		entry["age"] = float(entry["age"]) + delta
		var age := float(entry["age"])
		var t := clampf(age / DAMAGE_LIFE, 0.0, 1.0)
		var label: Label3D = entry["node"]
		if label != null and is_instance_valid(label):
			var base: Vector3 = entry["base"]
			label.position = base + Vector3(0.0, DAMAGE_RISE * t, 0.0)
			var color: Color = entry["color"]
			color.a = 1.0 - t
			label.modulate = color
		if age >= DAMAGE_LIFE:
			_free_node(label)
			continue
		if label != null and is_instance_valid(label):
			alive.append(entry)
	_popups = alive


func _process(delta: float) -> void:
	advance(delta)


func _apply_flight(entry: Dictionary) -> void:
	if not entry.has("fly_to"):
		return
	var node = entry.get("node", null)
	if node == null or not is_instance_valid(node):
		return
	var from: Vector3 = entry["fly_from"]
	var to: Vector3 = entry["fly_to"]
	var t := clampf(
		float(entry["age"]) / maxf(0.01, float(entry["fly_time"])), 0.0, 1.0)
	node.position = from.lerp(to, t)


func _on_attack(event: Dictionary, context: Dictionary) -> void:
	var attacker_id := str(event.get("unit", ""))
	var martial_id := str(event.get("martial_id", ""))
	var targeter = _targeter()
	var target: Vector2i = targeter.target_cell(event, context, Vector2i(-1, -1))
	if units != null and target.x >= 0:
		units.play_attack(attacker_id, target)
	var spec: Variant
	if battle != null and battle.martials.has(martial_id):
		spec = VfxTable.cast_spec(martial_id)
	else:
		spec = VfxTable.enemy_cast(
			martial_id, targeter.enemy_move_type(attacker_id, martial_id))
	_last_attack = {
		"attacker": attacker_id, "martial_id": martial_id, "target": target,
		"projectile": _spec_is_projectile(spec),
	}
	_play(spec, event, context, target)


func _on_hit(event: Dictionary, context: Dictionary) -> void:
	var defender_id := str(event.get("defender", ""))
	var cell := _unit_cell(defender_id)
	if cell.x < 0:
		cell = _targeter().target_cell(event, context, cell)
	if cell.x < 0:
		return
	var martial_id := str(_last_attack.get("martial_id", ""))
	var attacker_id := str(_last_attack.get("attacker", ""))
	var spec: Variant
	if battle != null and battle.martials.has(martial_id):
		spec = VfxTable.hit_spec(martial_id)
	else:
		spec = VfxTable.enemy_hit(
			martial_id, _targeter().enemy_move_type(attacker_id, martial_id))
	var hit_delay := 0.0
	if bool(_last_attack.get("projectile", false)):
		hit_delay = PROJECTILE_TIME
	_play(spec, event, context, cell, hit_delay)
	var relation := str(event.get("relation", "front"))
	var kind := "weak" if bool(event.get("weak", false)) else (
		"crit" if relation == "back" else "normal")
	spawn_damage_number(_unit_world(defender_id), int(event.get("damage", 0)), kind)
	var reaction := str(event.get("reaction", ""))
	if reaction != "":
		_play(VfxTable.cast_spec(reaction), event, context, cell)
		var verdict := int(event.get("verdict", 0))
		var key := "counter_barely"
		if bool(event.get("perfect", false)):
			key = "counter_perfect"
		elif verdict >= 2:
			key = "counter_advantage"
		var counter_spec: Variant = VfxTable.event_spec(key)
		if counter_spec != null:
			_play(counter_spec, event, context, cell)
		if int(event.get("damage", 0)) == 0:
			spawn_damage_number(
				_unit_world(defender_id) + Vector3(0.0, 0.4, 0.0), 0, "react")
	if units != null:
		units.flash_hit(defender_id)


func _on_counter(event: Dictionary, context: Dictionary) -> void:
	var defender_id := str(event.get("defender", ""))
	var cell := _unit_cell(defender_id)
	if cell.x < 0:
		return
	var spec: Variant = VfxTable.event_spec("counter_advantage")
	if spec != null:
		_play(spec, event, context, cell)
	spawn_damage_number(
		_unit_world(defender_id), int(event.get("damage", 0)), "counter")
	if units != null:
		units.flash_hit(defender_id)


func _on_jianyi(event: Dictionary, context: Dictionary) -> void:
	var defender_id := str(event.get("defender", ""))
	var cell := _unit_cell(defender_id)
	if cell.x < 0:
		cell = _targeter().target_cell(event, context, cell)
	if cell.x < 0:
		return
	var spec: Variant = VfxTable.event_spec("jianyi")
	if spec != null:
		_play(spec, event, context, cell)
	spawn_damage_number(
		_unit_world(defender_id), int(event.get("damage", 0)), "jianyi")
	if units != null:
		units.flash_hit(defender_id)


func _on_stun(event: Dictionary, context: Dictionary) -> void:
	var cell := _unit_cell(str(event.get("unit", "")))
	if cell.x < 0:
		return
	var key := "stun_broken" if bool(event.get("broken", false)) else "stun"
	var spec: Variant = VfxTable.event_spec(key)
	if spec != null:
		_play(spec, event, context, cell)


func _on_dead(event: Dictionary, context: Dictionary) -> void:
	var cell := _unit_cell(str(event.get("unit", "")))
	if cell.x < 0:
		return
	var spec: Variant = VfxTable.event_spec("dead")
	if spec != null:
		_play(spec, event, context, cell)


func _on_move(event: Dictionary, context: Dictionary) -> void:
	var raw: Variant = event.get("to", null)
	if not (raw is Vector2i):
		return
	var cell: Vector2i = raw
	var spec: Variant = VfxTable.event_spec("move_dust")
	if spec != null:
		_play(spec, event, context, cell)


func _resolve_pos(cell_or_pos: Variant) -> Vector3:
	if cell_or_pos is Vector3:
		return cell_or_pos
	if cell_or_pos is Vector2i and tiles != null:
		return tiles.cell_center(cell_or_pos)
	return Vector3.ZERO


# 落点数学集中在 tactics_vfx_targeting，每次调用时同步最新的 battle/tiles。
func _targeter() -> Variant:
	if _targeting == null:
		_targeting = VfxTargeting.new()
	_targeting.setup(battle, tiles)
	return _targeting


func _unit_cell(unit_id: String) -> Vector2i:
	return _targeter().unit_cell(unit_id)


func _unit_world(unit_id: String) -> Vector3:
	var cell := _unit_cell(unit_id)
	if cell.x < 0 or tiles == null:
		return Vector3.ZERO
	return tiles.cell_center(cell)


func _free_node(node) -> void:
	if node == null or not is_instance_valid(node):
		return
	var target: Node = node
	if target.get_parent() == self:
		remove_child(target)
	if is_inside_tree():
		target.queue_free()
	else:
		target.free()


static func _frames(name: String, row: int) -> Array:
	var safe_row := maxi(0, row)
	var key := "%s|%d" % [name, safe_row]
	if _frame_cache.has(key):
		return _frame_cache[key]
	var out: Array = []
	var rows := VfxTable.sheet_rows(name)
	var path := VFX_DIR + name + ".png"
	if safe_row < rows:
		var image := ImageCache.image(path)
		if image != null and not image.is_empty():
			var cell_w := int(image.get_width() / SHEET_COLS)
			var cell_h := int(image.get_height() / rows)
			if cell_w > 0 and cell_h > 0:
				for i in range(SHEET_COLS):
					var region: Image = image.get_region(
						Rect2i(i * cell_w, safe_row * cell_h, cell_w, cell_h))
					out.append(ImageTexture.create_from_image(region))
	_frame_cache[key] = out
	return out

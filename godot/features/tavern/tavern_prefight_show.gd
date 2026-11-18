extends RefCounted

# 紫霞前戏演出：弹字、命中闪光、演员走位与 Boss 血条。
# 接受模拟结果与演员节点字典；结束时发 finished(result)。

signal finished(result: Dictionary)

const GameState = preload("res://core/game_state.gd")
const Prefight = preload("res://core/prefight.gd")

const PREFIGHT_DURATION := 4.5
const PREFIGHT_LUNGE := 0.4
const PREFIGHT_POPUP_LIFE := 1.0
const PREFIGHT_POPUP_RISE := 1.4
const BOSS_BAR_HEIGHT := 2.6
const BOSS_MAX_HP := 300.0
const DISCIPLE_IDS: Array[String] = ["disciple_1", "disciple_2", "disciple_3"]
const ZIXIA_IDS: Array[String] = ["zixia", "disciple_1", "disciple_2", "disciple_3"]
const FALLEN_COLOR := Color(0.45, 0.45, 0.5, 0.75)
const PREFIGHT_HIT_COLOR := Color(1.0, 0.35, 0.35, 1.0)

var active := false
var boss_bar: Node3D = null
var boss_bar_fill: Sprite3D = null

var _parent: Node3D = null
var _actors: Dictionary = {}
var _elapsed := 0.0
var _result: Dictionary = {}
var _base: Dictionary = {}
var _popups: Array = []
var _flashes: Array = []
var _popup_times: Array = []
var _popup_index := 0
var _fallen := 0
var _crouched := false


func setup(parent: Node3D) -> void:
	_parent = parent


func begin(result: Dictionary, actors: Dictionary) -> void:
	_result = result
	_actors = actors
	active = true
	_elapsed = 0.0
	_popup_index = 0
	_fallen = 0
	_crouched = false
	_base.clear()
	for id in ZIXIA_IDS:
		_cache_base(str(id))
	for id in _actors.keys():
		if str(id) == "ma_youwei" or str(id).begins_with("bandit_"):
			_cache_base(str(id))
	_build_popup_times()
	_face_prefight_sides()
	_ensure_boss_bar()
	_place_boss_bar()
	if boss_bar != null:
		boss_bar.visible = true
	_set_boss_bar_ratio(1.0)


func advance(delta: float) -> void:
	_elapsed += maxf(0.0, delta)
	var t: float = clampf(_elapsed / PREFIGHT_DURATION, 0.0, 1.0)
	_apply_motion(t)
	_spawn_due_popups()
	advance_popups(delta)
	_advance_flashes(delta)
	var damage: int = int(_result.get("boss_damage", 0))
	_set_boss_bar_ratio(1.0 - float(damage) * t / BOSS_MAX_HP)
	_place_boss_bar()
	# 最后半秒三名弟子依次倒下，师姐单膝半蹲。
	if t >= 0.78 and _fallen < 1:
		_fallen = 1
		_lay_down_disciple(0)
	if t >= 0.84 and _fallen < 2:
		_fallen = 2
		_lay_down_disciple(1)
	if t >= 0.90 and _fallen < 3:
		_fallen = 3
		_lay_down_disciple(2)
	if t >= 0.94 and not _crouched:
		_crouched = true
		_crouch_sister()
	if _elapsed >= PREFIGHT_DURATION:
		_finish()


# 演出结束后残留的飘字仍要继续淡出。
func advance_popups(delta: float) -> void:
	var kept: Array = []
	for entry_value in _popups:
		if not (entry_value is Dictionary):
			continue
		var entry: Dictionary = entry_value
		var node_value: Variant = entry.get("node", null)
		if not (node_value is Label3D):
			continue
		var label: Label3D = node_value
		entry["age"] = float(entry.get("age", 0.0)) + delta
		var age: float = float(entry["age"])
		var t: float = clampf(age / PREFIGHT_POPUP_LIFE, 0.0, 1.0)
		var base: Vector3 = entry.get("base", label.position)
		label.position = base + Vector3(0.0, PREFIGHT_POPUP_RISE * t, 0.0)
		var color: Color = entry.get("color", Color.WHITE)
		color.a = 1.0 - t
		label.modulate = color
		if age >= PREFIGHT_POPUP_LIFE:
			label.queue_free()
			continue
		kept.append(entry)
	_popups = kept


# brawl 重入时只恢复头子血条，不重放演出。
func sync_state(
	state: String, prefight_done: bool, bandit_count: int, skip_actors: bool = false
) -> void:
	if skip_actors or state != "brawl" or not prefight_done:
		if boss_bar != null:
			boss_bar.visible = false
		return
	_ensure_cache(bandit_count)
	_ensure_boss_bar()
	_place_boss_bar()
	if boss_bar != null:
		boss_bar.visible = true
	_set_boss_bar_ratio(
		(BOSS_MAX_HP - float(GameState.prefight_loss_cached)) / BOSS_MAX_HP
	)


func _finish() -> void:
	if not active:
		return
	active = false
	_restore_positions()
	for i in range(DISCIPLE_IDS.size()):
		_lay_down_disciple(i)
	_fallen = DISCIPLE_IDS.size()
	_crouch_sister()
	_crouched = true
	GameState.boss_hp_loss = int(_result.get("boss_damage", 0))
	GameState.prefight_loss_cached = GameState.boss_hp_loss
	GameState.set_flag("prefight_done")
	_face_brawl_enemies()
	_ensure_boss_bar()
	_place_boss_bar()
	if boss_bar != null:
		boss_bar.visible = true
	_set_boss_bar_ratio(
		(BOSS_MAX_HP - float(GameState.prefight_loss_cached)) / BOSS_MAX_HP
	)
	emit_signal("finished", _result)


func _cache_base(id: String) -> void:
	var node_value: Variant = _actors.get(id, null)
	if node_value is Node3D:
		_base[id] = (node_value as Node3D).position


# 每条日志对应一次飘字，均匀铺在演出前 82% 的时间里。
func _build_popup_times() -> void:
	_popup_times.clear()
	var log: Array = _result.get("log", [])
	if log.is_empty():
		return
	var span: float = PREFIGHT_DURATION * 0.82
	for i in range(log.size()):
		_popup_times.append(span * float(i) / float(log.size()))


func _face_prefight_sides() -> void:
	for id in ZIXIA_IDS:
		_face_npc(str(id), "right")
	for id in _actors.keys():
		if str(id) == "ma_youwei" or str(id).begins_with("bandit_"):
			_face_npc(str(id), "left")


func _face_brawl_enemies() -> void:
	for id in _actors.keys():
		if str(id) == "ma_youwei" or str(id).begins_with("bandit_"):
			_face_npc(str(id), "down")


func _face_npc(id: String, facing: String) -> void:
	var node_value: Variant = _actors.get(id, null)
	if node_value is Node:
		(node_value as Node).call("set_facing", facing)


# 双方小幅突进/后撤：正弦位移，两侧方向相反，每个单位相位错开。
func _apply_motion(t: float) -> void:
	var index := 0
	for raw_id in _base.keys():
		var id: String = str(raw_id)
		var node_value: Variant = _actors.get(id, null)
		if not (node_value is Node3D):
			continue
		var node: Node3D = node_value
		var base: Vector3 = _base[raw_id]
		var side: float = 1.0 if ZIXIA_IDS.has(id) else -1.0
		var phase: float = PI * 0.5 * float(index % 4)
		var offset: float = PREFIGHT_LUNGE * sin(TAU * t * 2.0 + phase)
		node.position = Vector3(base.x + side * offset, base.y, base.z)
		index += 1


func _spawn_due_popups() -> void:
	var log: Array = _result.get("log", [])
	while _popup_index < _popup_times.size() \
			and _popup_index < log.size() \
			and _elapsed >= float(_popup_times[_popup_index]):
		_spawn_popup(str(log[_popup_index]))
		_popup_index += 1


func _spawn_popup(line: String) -> void:
	var parsed: Dictionary = _parse_log(line)
	if parsed.is_empty():
		return
	var target_value: Variant = _actors.get(str(parsed.get("target", "")), null)
	if not (target_value is Node3D):
		return
	var target: Node3D = target_value
	var label := Label3D.new()
	label.text = "-%d" % int(parsed.get("amount", 0))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = false
	label.pixel_size = 0.012
	label.font_size = 48
	label.outline_size = 8
	label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	label.modulate = Color(0.95, 0.95, 0.95, 1.0)
	var base: Vector3 = target.position + Vector3(0.0, 2.2, 0.0)
	label.position = base
	_parent.add_child(label)
	_popups.append({
		"node": label,
		"age": 0.0,
		"base": base,
		"color": Color(0.95, 0.95, 0.95, 1.0),
	})
	_flash_target(target)


func _parse_log(line: String) -> Dictionary:
	var separator: int = line.rfind(":")
	if separator <= 0:
		return {}
	var pair: String = line.substr(0, separator)
	var arrow: int = pair.find(">")
	if arrow <= 0:
		return {}
	return {
		"target": pair.substr(arrow + 1),
		"amount": absi(int(line.substr(separator + 1))),
	}


func _flash_target(node: Node3D) -> void:
	var restore: Color = Color.WHITE
	var sprite_value: Variant = node.get_node_or_null("Sprite")
	if sprite_value is Sprite3D:
		restore = (sprite_value as Sprite3D).modulate
	_set_npc_tint(node, PREFIGHT_HIT_COLOR)
	var kept: Array = []
	for entry_value in _flashes:
		if not (entry_value is Dictionary):
			continue
		var entry: Dictionary = entry_value
		if entry.get("node", null) == node:
			continue
		kept.append(entry)
	_flashes = kept
	_flashes.append({"node": node, "time": 0.18, "restore": restore})


func _advance_flashes(delta: float) -> void:
	var kept: Array = []
	for entry_value in _flashes:
		if not (entry_value is Dictionary):
			continue
		var entry: Dictionary = entry_value
		var node_value: Variant = entry.get("node", null)
		if not (node_value is Node3D):
			continue
		entry["time"] = float(entry.get("time", 0.0)) - delta
		if float(entry["time"]) <= 0.0:
			_set_npc_tint(node_value as Node3D, entry.get("restore", Color.WHITE))
			continue
		kept.append(entry)
	_flashes = kept


func _set_npc_tint(node: Node3D, color: Color) -> void:
	var sprite_value: Variant = node.get_node_or_null("Sprite")
	if sprite_value is Sprite3D:
		(sprite_value as Sprite3D).modulate = color


func _lay_down_disciple(index: int) -> void:
	if index < 0 or index >= DISCIPLE_IDS.size():
		return
	var node_value: Variant = _actors.get(DISCIPLE_IDS[index], null)
	if not (node_value is Node3D):
		return
	var node: Node3D = node_value
	node.rotation.z = PI / 2.0
	_set_npc_tint(node, FALLEN_COLOR)


func _crouch_sister() -> void:
	var node_value: Variant = _actors.get("zixia", null)
	if not (node_value is Node3D):
		return
	(node_value as Node3D).scale = Vector3(1.0, 0.85, 1.0)


func _restore_positions() -> void:
	for raw_id in _base.keys():
		var node_value: Variant = _actors.get(str(raw_id), null)
		if node_value is Node3D:
			(node_value as Node3D).position = _base[raw_id]
	_base.clear()


func _ensure_cache(bandit_count: int) -> void:
	if GameState.prefight_loss_cached > 0:
		return
	if not GameState.has_flag("prefight_done"):
		return
	GameState.prefight_loss_cached = int(
		Prefight.simulate(bandit_count).get("boss_damage", 0)
	)


func _ensure_boss_bar() -> void:
	if boss_bar != null:
		return
	boss_bar = Node3D.new()
	boss_bar.name = "BossHpBar"
	_parent.add_child(boss_bar)
	var back := Sprite3D.new()
	back.name = "Back"
	back.texture = _bar_texture(Color(0.16, 0.05, 0.05, 0.95), 108, 12)
	back.pixel_size = 0.02
	back.centered = false
	back.position = Vector3(-1.08, -0.06, 0.0)
	back.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	back.no_depth_test = true
	back.shaded = false
	back.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	boss_bar.add_child(back)
	boss_bar_fill = Sprite3D.new()
	boss_bar_fill.name = "Fill"
	boss_bar_fill.texture = _bar_texture(Color(0.78, 0.12, 0.1, 1.0), 100, 6)
	boss_bar_fill.pixel_size = 0.02
	boss_bar_fill.centered = false
	boss_bar_fill.position = Vector3(-1.0, 0.0, 0.01)
	boss_bar_fill.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	boss_bar_fill.no_depth_test = true
	boss_bar_fill.shaded = false
	boss_bar_fill.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	boss_bar.add_child(boss_bar_fill)
	boss_bar.visible = false


func _bar_texture(color: Color, width: int, height: int) -> ImageTexture:
	var img: Image = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


func _place_boss_bar() -> void:
	if boss_bar == null:
		return
	var boss_value: Variant = _actors.get("ma_youwei", null)
	if not (boss_value is Node3D):
		boss_bar.visible = false
		return
	boss_bar.position = (boss_value as Node3D).position + Vector3(0.0, BOSS_BAR_HEIGHT, 0.0)


func _set_boss_bar_ratio(ratio: float) -> void:
	if boss_bar_fill == null:
		return
	boss_bar_fill.scale.x = clampf(ratio, 0.0, 1.0)

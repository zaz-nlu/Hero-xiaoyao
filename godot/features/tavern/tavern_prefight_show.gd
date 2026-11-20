extends RefCounted

# 紫霞派与马匪的酒馆混战演出（约 13 秒）：
#   A 混战：三名弟子各与一名马匪对砍，火花四溅；
#   B 弟子倒下，马匪退到场边围成一圈，师姐与头子走到场中；
#   C 对决：师姐与头子互放剑气，师姐 200→120，头子 200→（200 − 推演伤害）。
# 结果由 core/prefight.gd 的确定性推演给出（boss_damage），演出只负责画面。
# 结束时发 finished(result)。对外接口：begin / advance / advance_popups / sync_state。

signal finished(result: Dictionary)

const GameState = preload("res://core/game_state.gd")
const Prefight = preload("res://core/prefight.gd")
const HpBar = preload("res://features/tavern/tavern_hp_bar.gd")
const SheetVfx = preload("res://shared/scene/sheet_vfx.gd")

const ARC_SHEET := "res://assets/vfx/emperor_century_slash_arc_sequence.png"
const HIT_SHEET := "res://assets/vfx/vfx_hit.png"
const SHEET_COLS := 8

const T_BRAWL := 6.0
const T_FALL := 6.0
const T_RING := 7.5
const T_DUEL := 7.8
const DURATION := 13.8
const STRIKES := 8
const STRIKE_GAP := 0.75
const LUNGE := 0.6
const SPARK_GAP := 0.5
const SISTER_MAX_HP := 200.0
const SISTER_END_HP := 120.0
const BOSS_MAX_HP := 200.0
const BAR_HEIGHT := 2.6
const POPUP_LIFE := 1.0
const POPUP_RISE := 1.4
const MEET_X := 7.6
const PAIR_ROWS_Z := [-5.0, -2.2, 0.6]
const RING_SPOTS := [Vector3(-5.0, 0.0, 2.0), Vector3(5.0, 0.0, 2.0), Vector3(-4.6, 0.0, -3.2), Vector3(4.6, 0.0, -3.2), Vector3(0.0, 0.0, 3.8)]
const DUEL_HALF_GAP := 1.9
const DISCIPLE_IDS: Array[String] = ["disciple_1", "disciple_2", "disciple_3"]
const ZIXIA_IDS: Array[String] = ["zixia", "disciple_1", "disciple_2", "disciple_3"]
const FALLEN_COLOR := Color(0.45, 0.45, 0.5, 0.75)
const HIT_COLOR := Color(1.0, 0.35, 0.35, 1.0)
const SISTER_TINT := Color(0.85, 0.65, 1.0, 1.0)
const BOSS_TINT := Color(1.0, 0.5, 0.38, 1.0)

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
var _bandits: Array = []
var _pairs: Array = []
var _sparks_done: Dictionary = {}
var _strikes_done := 0
var _fallen := 0
var _crouched := false
var _sister_bar: Node3D = null
var _sister_fill: Sprite3D = null
var _boss_label: Label3D = null
var _sister_label: Label3D = null
var _center := Vector3.ZERO


func setup(parent: Node3D) -> void:
	_parent = parent


func begin(result: Dictionary, actors: Dictionary) -> void:
	_result = result
	_actors = actors
	active = true
	_elapsed = 0.0
	_strikes_done = 0
	_fallen = 0
	_crouched = false
	_sparks_done.clear()
	for node_value in _actors.values():
		if node_value is Node and (node_value as Node).has_meta("held"):
			(node_value as Node).remove_meta("held")
	_base.clear()
	_bandits.clear()
	_pairs.clear()
	for id in ZIXIA_IDS:
		_cache_base(str(id))
	_cache_base("ma_youwei")
	var bandit_ids: Array = []
	for id in _actors.keys():
		if str(id).begins_with("bandit_"):
			bandit_ids.append(str(id))
	bandit_ids.sort()
	_bandits = bandit_ids
	for id in _bandits:
		_cache_base(str(id))
	for i in range(DISCIPLE_IDS.size()):
		if _bandits.is_empty():
			break
		_pairs.append([DISCIPLE_IDS[i], str(_bandits[i % _bandits.size()])])
	_face_sides()
	_center = _duel_center()
	_ensure_bars()
	_update_bars(0.0, 0.0)
	_place_bars()


func advance(delta: float) -> void:
	_elapsed += maxf(0.0, delta)
	if _elapsed < T_BRAWL:
		_move_brawl(_elapsed)
	_spawn_sparks()
	_move_aftermath()
	_run_falls()
	_run_strikes()
	advance_popups(delta)
	_advance_flashes(delta)
	_place_bars()
	if _elapsed >= DURATION:
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
		var t: float = clampf(age / POPUP_LIFE, 0.0, 1.0)
		var base: Vector3 = entry.get("base", label.position)
		label.position = base + Vector3(0.0, POPUP_RISE * t, 0.0)
		var color: Color = entry.get("color", Color.WHITE)
		color.a = 1.0 - t
		label.modulate = color
		if age >= POPUP_LIFE:
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
	_ensure_bars()
	_place_bars()
	_update_bars(SISTER_MAX_HP - SISTER_END_HP, float(GameState.prefight_loss_cached))
	if _sister_bar != null:
		_sister_bar.visible = false
	if boss_bar != null:
		boss_bar.visible = true


# ---------------------------------------------------------------- choreography

# A：每对弟子与马匪在中点对砍，进场 1 秒后保持来回突进。
func _move_brawl(time: float) -> void:
	var approach: float = clampf(time / 1.0, 0.0, 1.0)
	var index := 0
	for raw_pair in _pairs:
		var pair: Array = raw_pair
		var disciple: Node3D = _node(str(pair[0]))
		var bandit: Node3D = _node(str(pair[1]))
		if disciple == null or bandit == null:
			continue
		var d_base: Vector3 = _base.get(str(pair[0]), disciple.position)
		var b_base: Vector3 = _base.get(str(pair[1]), bandit.position)
		var mid := Vector3(MEET_X, d_base.y, float(PAIR_ROWS_Z[index % PAIR_ROWS_Z.size()]))
		var dir := Vector3.RIGHT
		var swing: float = sin(TAU * (time * 1.3 + 0.27 * float(index)))
		var gap: float = 0.75 - 0.25 * swing
		disciple.position = d_base.lerp(mid - dir * gap, approach)
		bandit.position = b_base.lerp(mid + dir * gap, approach)
		index += 1


func _spawn_sparks() -> void:
	if _elapsed >= T_BRAWL:
		return
	var index := 0
	for raw_pair in _pairs:
		var pair: Array = raw_pair
		var step := int((_elapsed - 0.8 - 0.17 * float(index)) / SPARK_GAP)
		var key := "%s|%d" % [str(pair[0]), step]
		index += 1
		if step < 0 or _sparks_done.has(key):
			continue
		_sparks_done[key] = true
		var disciple: Node3D = _node(str(pair[0]))
		var bandit: Node3D = _node(str(pair[1]))
		if disciple == null or bandit == null:
			continue
		var at: Vector3 = (disciple.position + bandit.position) * 0.5 + Vector3(0.0, 1.3, 0.0)
		SheetVfx.spawn(_parent, HIT_SHEET, SHEET_COLS, 2, step % 2, at, 0.9, 20.0)
		_flash_target(bandit if step % 2 == 0 else disciple)


# B：弟子倒下，马匪退成一圈，师姐与头子走到场中。
func _move_aftermath() -> void:
	if _elapsed < T_FALL:
		return
	var ring: float = clampf((_elapsed - T_FALL) / (T_RING - T_FALL), 0.0, 1.0)
	for i in range(_bandits.size()):
		var bandit: Node3D = _node(str(_bandits[i]))
		if bandit == null:
			continue
		var spot: Vector3 = _center + RING_SPOTS[i % RING_SPOTS.size()]
		bandit.position = _held_position(str(_bandits[i])).lerp(spot, ring)
		_face_toward(bandit, _center)
	var sister: Node3D = _node("zixia")
	var boss: Node3D = _node("ma_youwei")
	if sister != null:
		sister.position = _held_position("zixia").lerp(_center + Vector3(-DUEL_HALF_GAP, 0.0, 0.0), ring)
	if boss != null:
		boss.position = _held_position("ma_youwei").lerp(_center + Vector3(DUEL_HALF_GAP, 0.0, 0.0), ring)


func _run_falls() -> void:
	var due := int((_elapsed - T_FALL) / 0.45) + 1 if _elapsed >= T_FALL else 0
	while _fallen < mini(due, DISCIPLE_IDS.size()):
		_lay_down_disciple(_fallen)
		_fallen += 1


# C：交替出剑气。偶数次师姐攻击头子，奇数次头子反击师姐。
func _run_strikes() -> void:
	if _elapsed < T_DUEL:
		return
	var due := mini(STRIKES, int((_elapsed - T_DUEL) / STRIKE_GAP) + 1)
	while _strikes_done < due:
		_strike(_strikes_done)
		_strikes_done += 1
	# 攻击方短暂前冲。
	var k: int = clampi(int((_elapsed - T_DUEL) / STRIKE_GAP), 0, STRIKES - 1)
	var local: float = (_elapsed - T_DUEL) - float(k) * STRIKE_GAP
	var sister: Node3D = _node("zixia")
	var boss: Node3D = _node("ma_youwei")
	if sister == null or boss == null:
		return
	var push: float = LUNGE * sin(clampf(local / 0.4, 0.0, 1.0) * PI)
	sister.position = _center + Vector3(-DUEL_HALF_GAP + (push if k % 2 == 0 else 0.0), 0.0, 0.0)
	boss.position = _center + Vector3(DUEL_HALF_GAP - (push if k % 2 == 1 else 0.0), 0.0, 0.0)


func _strike(k: int) -> void:
	var sister_attacks: bool = k % 2 == 0
	var defender: Node3D = _node("ma_youwei" if sister_attacks else "zixia")
	if defender == null:
		return
	var per_boss: float = float(_boss_damage()) / float(STRIKES / 2)
	var per_sister: float = (SISTER_MAX_HP - SISTER_END_HP) / float(STRIKES / 2)
	var amount: int = int(round(per_boss if sister_attacks else per_sister))
	var tint: Color = SISTER_TINT if sister_attacks else BOSS_TINT
	var at: Vector3 = defender.position + Vector3(0.0, 1.2, 0.0)
	SheetVfx.spawn(_parent, ARC_SHEET, SHEET_COLS, 1, 0, at, 2.6, 18.0, tint, not sister_attacks)
	SheetVfx.spawn(_parent, HIT_SHEET, SHEET_COLS, 2, 0, at, 1.0, 20.0, Color.WHITE)
	_spawn_popup(defender, amount)
	_flash_target(defender)
	var sister_hits: int = (k + 1) / 2
	var boss_hits: int = k / 2 + 1
	_update_bars(per_sister * float(sister_hits), per_boss * float(boss_hits))


func _boss_damage() -> int:
	return clampi(int(_result.get("boss_damage", 100)), 1, int(BOSS_MAX_HP) - 1)


func _finish() -> void:
	if not active:
		return
	active = false
	for id in _base.keys():
		var node: Node3D = _node(str(id))
		if node != null:
			node.position = _base[id]
	_base.clear()
	for i in range(DISCIPLE_IDS.size()):
		_lay_down_disciple(i)
	_fallen = DISCIPLE_IDS.size()
	_crouch_sister()
	_crouched = true
	GameState.boss_hp_loss = _boss_damage()
	GameState.prefight_loss_cached = GameState.boss_hp_loss
	GameState.set_flag("prefight_done")
	for id in _actors.keys():
		if str(id) == "ma_youwei" or str(id).begins_with("bandit_"):
			_face_npc(str(id), "down")
	_update_bars(SISTER_MAX_HP - SISTER_END_HP, float(_boss_damage()))
	_place_bars()
	if _sister_bar != null:
		_sister_bar.visible = false
	emit_signal("finished", _result)


# ---------------------------------------------------------------- helpers

func _node(id: String) -> Node3D:
	var value: Variant = _actors.get(id, null)
	return value as Node3D if value is Node3D else null


func _cache_base(id: String) -> void:
	var node: Node3D = _node(id)
	if node != null:
		_base[id] = node.position


# 阶段 B 起点：弟子对砍结束时的位置（对砍只持续到 T_BRAWL）。
func _held_position(id: String) -> Vector3:
	var node: Node3D = _node(id)
	if node == null:
		return Vector3.ZERO
	if not node.has_meta("held"):
		node.set_meta("held", node.position)
	return node.get_meta("held")


func _duel_center() -> Vector3:
	var boss: Vector3 = _base.get("ma_youwei", Vector3(11.0, 0.0, -3.0))
	return Vector3(11.0, boss.y, -2.2)


func _face_sides() -> void:
	for id in ZIXIA_IDS:
		_face_npc(str(id), "right")
	_face_npc("ma_youwei", "left")
	for id in _bandits:
		_face_npc(str(id), "left")


func _face_toward(node: Node3D, target: Vector3) -> void:
	node.call("set_facing", "right" if target.x > node.position.x else "left")


func _face_npc(id: String, facing: String) -> void:
	var node: Node3D = _node(id)
	if node != null:
		node.call("set_facing", facing)


func _spawn_popup(target: Node3D, amount: int) -> void:
	var label := Label3D.new()
	label.text = "-%d" % amount
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.012
	label.font_size = 56
	label.outline_size = 8
	label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	var base: Vector3 = target.position + Vector3(0.0, 2.2, 0.0)
	label.position = base
	_parent.add_child(label)
	_popups.append({"node": label, "age": 0.0, "base": base, "color": Color(1.0, 0.9, 0.55, 1.0)})


func _flash_target(node: Node3D) -> void:
	var restore: Color = Color.WHITE
	var sprite_value: Variant = node.get_node_or_null("Sprite")
	if sprite_value is Sprite3D:
		restore = (sprite_value as Sprite3D).modulate
	_set_npc_tint(node, HIT_COLOR)
	var kept: Array = []
	for entry_value in _flashes:
		if entry_value is Dictionary and entry_value.get("node", null) != node:
			kept.append(entry_value)
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
	var node: Node3D = _node(DISCIPLE_IDS[index]) if index >= 0 and index < DISCIPLE_IDS.size() else null
	if node == null:
		return
	node.rotation.z = PI / 2.0
	_set_npc_tint(node, FALLEN_COLOR)


func _crouch_sister() -> void:
	var node: Node3D = _node("zixia")
	if node != null:
		node.scale = Vector3(1.0, 0.85, 1.0)


func _ensure_cache(bandit_count: int) -> void:
	if GameState.prefight_loss_cached > 0 or not GameState.has_flag("prefight_done"):
		return
	GameState.prefight_loss_cached = int(Prefight.simulate(bandit_count).get("boss_damage", 0))


# ---------------------------------------------------------------- hp bars

func _ensure_bars() -> void:
	if boss_bar == null:
		var made: Array = HpBar.make(_parent, "BossHpBar", Color(0.78, 0.12, 0.1, 1.0))
		boss_bar = made[0]
		boss_bar_fill = made[1]
		_boss_label = made[2]
	if _sister_bar == null:
		var made2: Array = HpBar.make(_parent, "SisterHpBar", Color(0.62, 0.36, 0.86, 1.0))
		_sister_bar = made2[0]
		_sister_fill = made2[1]
		_sister_label = made2[2]


# sister_lost / boss_lost：已损失的血量（绝对值）。
func _update_bars(sister_lost: float, boss_lost: float) -> void:
	var sister_hp: float = clampf(SISTER_MAX_HP - sister_lost, 0.0, SISTER_MAX_HP)
	var boss_hp: float = clampf(BOSS_MAX_HP - boss_lost, 0.0, BOSS_MAX_HP)
	if _sister_fill != null:
		_sister_fill.scale.x = sister_hp / SISTER_MAX_HP
		_sister_label.text = "紫霞师姐 %d/%d" % [int(sister_hp), int(SISTER_MAX_HP)]
	if boss_bar_fill != null:
		boss_bar_fill.scale.x = boss_hp / BOSS_MAX_HP
		_boss_label.text = "马匪头子 %d/%d" % [int(boss_hp), int(BOSS_MAX_HP)]


func _place_bars() -> void:
	_place_bar(boss_bar, "ma_youwei")
	_place_bar(_sister_bar, "zixia")


func _place_bar(bar: Node3D, id: String) -> void:
	if bar == null:
		return
	var node: Node3D = _node(id)
	if node == null:
		bar.visible = false
		return
	bar.visible = active or bar == boss_bar
	var side: float = -0.9 if id == "zixia" else (0.9 if active else 0.0)
	bar.position = node.position + Vector3(side, BAR_HEIGHT, 0.0)

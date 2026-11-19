extends RefCounted

const INITIAL_POINTS := 3

static var flags: Dictionary = {}
static var town_return_pos: Variant = null
static var forest_return_pos: Variant = null
static var tavern_return_pos: Variant = null
static var pending_forest_encounter: Variant = null
# 混编敌人组：[{"id": 敌人 id, "count": 数量}]；BattleView.start 读取后立即清空。
static var encounter_group: Array = []
# 森林里已经打倒的马匪数量（bandit / bandit_scout），决定酒馆闯入的马匪人数。
static var forest_bandits_killed: int = 0
# 前戏里紫霞师姐对马匪头子造成的伤势：BattleView.start 只在这一场里扣掉，用完清零。
static var boss_hp_loss: int = 0
# 前戏结果的缓存：战败重来时套用同一份伤害，不重播前戏、也不重新计算。
static var prefight_loss_cached: int = 0
static var battle_backdrop: String = "town"
# 小镇昼夜时段；暂不存档，由剧情/调试设置。
static var town_phase: String = "day"
static var known_moves: Dictionary = {}
static var stat_bonus: Dictionary = {}
static var equipment: Dictionary = {}
static var inventory: Dictionary = {}
static var quests: Dictionary = {}
static var mastery_exp: Dictionary = {}
static var mastery_total: Dictionary = {}
static var unspent_points: int = INITIAL_POINTS
static var toasts: Array = []
static var dialogue_counters: Dictionary = {}
static var realm_id: String = "lianti"
static var realm_stage: int = 1
static var age: int = 9
static var playtime: float = 0.0
# 跨战斗携带的内力剩余；-1 表示未记录（视为满）。
static var neili_left: int = -1
# 最小日历：第几天与一天内的时段下标（0 早上 1 白天 2 晚上 3 深夜，见 data/calendar.json）。
static var day: int = 1
static var phase: int = 0


static func set_flag(key: String, value: bool = true) -> void:
	flags[key] = value


static func has_flag(key: String) -> bool:
	return bool(flags.get(key, false))


static func reset() -> void:
	flags.clear()
	town_return_pos = null
	forest_return_pos = null
	tavern_return_pos = null
	pending_forest_encounter = null
	encounter_group.clear()
	forest_bandits_killed = 0
	boss_hp_loss = 0
	prefight_loss_cached = 0
	battle_backdrop = "town"
	town_phase = "day"
	known_moves.clear()
	stat_bonus.clear()
	equipment.clear()
	inventory.clear()
	quests.clear()
	mastery_exp.clear()
	mastery_total.clear()
	unspent_points = INITIAL_POINTS
	toasts.clear()
	dialogue_counters.clear()
	realm_id = "lianti"
	realm_stage = 1
	age = 9
	playtime = 0.0
	neili_left = -1
	day = 1
	phase = 0


# ---------------------------------------------------------------- save / load
#
# Explicit field list, no reflection: only persistent state is written. Runtime
# bookkeeping (toasts, battle_backdrop, pending encounters and the per-scene return
# positions) is deliberately left out. Vector2/Vector3 are stored as tagged arrays
# so the result survives JSON.stringify() without engine-specific types.

static func to_dict() -> Dictionary:
	return {
		"flags": _encode(flags),
		"known_moves": _encode(known_moves),
		"stat_bonus": _encode(stat_bonus),
		"equipment": _encode(equipment),
		"inventory": _encode(inventory),
		"quests": _encode(quests),
		"mastery_exp": _encode(mastery_exp),
		"mastery_total": _encode(mastery_total),
		"unspent_points": unspent_points,
		"dialogue_counters": _encode(dialogue_counters),
		"realm_id": realm_id,
		"realm_stage": realm_stage,
		"age": age,
		"playtime": playtime,
		"neili_left": neili_left,
		"day": day,
		"phase": phase,
	}


static func from_dict(d: Dictionary) -> void:
	reset()
	_restore_dict(d, "flags", flags)
	_restore_dict(d, "known_moves", known_moves)
	_restore_dict(d, "stat_bonus", stat_bonus)
	_restore_dict(d, "equipment", equipment)
	_restore_dict(d, "inventory", inventory)
	_restore_dict(d, "quests", quests)
	_restore_dict(d, "mastery_exp", mastery_exp)
	_restore_dict(d, "mastery_total", mastery_total)
	_restore_dict(d, "dialogue_counters", dialogue_counters)
	var value: Variant = d.get("unspent_points", null)
	if value is int or value is float:
		unspent_points = maxi(0, int(value))
	value = d.get("realm_id", null)
	if value is String:
		realm_id = value
	value = d.get("realm_stage", null)
	if value is int or value is float:
		realm_stage = int(value)
	value = d.get("age", null)
	if value is int or value is float:
		age = int(value)
	value = d.get("playtime", null)
	if value is int or value is float:
		playtime = maxf(0.0, float(value))
	value = d.get("neili_left", null)
	if value is int or value is float:
		neili_left = maxi(-1, int(value))
	value = d.get("day", null)
	if value is int or value is float:
		day = maxi(1, int(value))
	value = d.get("phase", null)
	if value is int or value is float:
		phase = maxi(0, int(value))


static func _restore_dict(source: Dictionary, key: String, target: Dictionary) -> void:
	var value: Variant = source.get(key, null)
	if not (value is Dictionary):
		return
	var decoded: Variant = _decode(value)
	if not (decoded is Dictionary):
		return
	target.clear()
	var decoded_dict: Dictionary = decoded
	for entry_key in decoded_dict.keys():
		target[entry_key] = decoded_dict[entry_key]


static func _encode(value: Variant) -> Variant:
	if value is Dictionary:
		var out: Dictionary = {}
		var source: Dictionary = value
		for key in source.keys():
			out[str(key)] = _encode(source[key])
		return out
	if value is Array:
		var out_array: Array = []
		for item in (value as Array):
			out_array.append(_encode(item))
		return out_array
	if value is Vector2:
		var v2: Vector2 = value
		return ["@Vector2", v2.x, v2.y]
	if value is Vector3:
		var v3: Vector3 = value
		return ["@Vector3", v3.x, v3.y, v3.z]
	return value


static func _decode(value: Variant) -> Variant:
	if value is Dictionary:
		var dictionary: Dictionary = value
		var out: Dictionary = {}
		for key in dictionary.keys():
			out[str(key)] = _decode(dictionary[key])
		return out
	if value is Array:
		var array: Array = value
		if array.size() == 3 and str(array[0]) == "@Vector2":
			return Vector2(float(array[1]), float(array[2]))
		if array.size() == 4 and str(array[0]) == "@Vector3":
			return Vector3(float(array[1]), float(array[2]), float(array[3]))
		var out_array: Array = []
		for item in array:
			out_array.append(_decode(item))
		return out_array
	return value

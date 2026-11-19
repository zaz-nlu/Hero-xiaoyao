extends RefCounted

# 进攻侧弱点：颜色槽、命中判定与刷新。数值来自 data/tactics_rules.json 的
# weakness 段；这里只读写 TacticsUnit 上的弱点状态，不依赖场景类型。

const TacticsEnergy = preload("res://core/tactics/tactics_energy.gd")
const TacticsRuleData = preload("res://core/tactics/tactics_rule_data.gd")

const DEFAULT_COLORS: Array[String] = ["neili", "ziqi", "xianqi"]
const NONE := "none"


# 敌人弱点槽数量：显式 weakness_slots 优先，否则按 tier。
static func slot_count(unit) -> int:
	if unit == null or unit.side != "enemy" or unit.unit == null:
		return 0
	var def = unit.unit.def
	if def == null:
		return 0
	if int(def.weakness_slots) >= 0:
		return int(def.weakness_slots)
	var by_tier: Dictionary = _rules().get("slots_by_tier", {})
	return maxi(0, int(by_tier.get(str(def.tier), 0)))


static func colors() -> Array:
	var out: Array = []
	var raw = _rules().get("colors", [])
	if raw is Array:
		for value in raw:
			out.append(str(value))
	return out if not out.is_empty() else DEFAULT_COLORS.duplicate()


static func damage_pct() -> int:
	return int(_rules().get("weak_damage_pct", 125))


# 开战时按战斗种子给所有敌人抽弱点：只从玩家方仍有剩余、且已开放的能量里取。
static func initialize(battle) -> void:
	var available := available_colors(battle)
	for raw_unit in battle.units:
		var unit = raw_unit
		if unit.side != "enemy":
			continue
		_fill(unit, available, battle.rng)


static func available_colors(battle) -> Array:
	var out: Array = []
	for raw_unit in battle.units:
		var unit = raw_unit
		if unit.side != "player" or not unit.is_alive():
			continue
		for color in TacticsEnergy.colors():
			var energy := str(color)
			if TacticsEnergy.is_locked(energy) or out.has(energy):
				continue
			if int(unit.energy_left.get(energy, 0)) > 0:
				out.append(energy)
	return out


# 攻击方出招所用能量是否命中该敌人的弱点；命中返回颜色，否则空字符串。
static func weak_color(battle, attacker, defender, energy: String) -> String:
	if attacker == null or defender == null:
		return ""
	if attacker.side != "player" or defender.side != "enemy":
		return ""
	if defender.unit == null or defender.unit.is_stunned():
		return ""
	if energy == "" or energy == NONE or not colors().has(energy):
		return ""
	if not defender.weaknesses.has(energy):
		return ""
	return energy


# 弱点槽立即刷新：不等于刚命中的颜色，也不等于其他槽的颜色。
static func refresh(battle, unit, index: int) -> String:
	if index < 0 or index >= unit.weaknesses.size():
		return ""
	var used := str(unit.weaknesses[index])
	var available := available_colors(battle)
	var pool: Array = []
	for color in available:
		if color == used or _other_slots_have(unit, index, color):
			continue
		pool.append(color)
	var next := NONE
	if not pool.is_empty():
		next = str(pool[battle.rng.randi_range(0, pool.size() - 1)])
	unit.weaknesses[index] = next
	return next


# 眩晕结束时重新抽取：按当前可用颜色重新填槽。
static func refill(battle, unit) -> void:
	_fill(unit, available_colors(battle), battle.rng)


# 击破时弱点全部清空为中性。
static func clear(unit) -> void:
	for i in range(unit.weaknesses.size()):
		unit.weaknesses[i] = NONE


static func _fill(unit, available: Array, rng: RandomNumberGenerator) -> void:
	var slots := slot_count(unit)
	var out: Array = []
	var pool: Array = available.duplicate()
	while out.size() < slots and not pool.is_empty():
		var index := rng.randi_range(0, pool.size() - 1)
		out.append(str(pool[index]))
		pool.remove_at(index)
	while out.size() < slots:
		out.append(NONE)
	unit.weaknesses = out


static func _other_slots_have(unit, index: int, color: String) -> bool:
	for i in range(unit.weaknesses.size()):
		if i != index and str(unit.weaknesses[i]) == color:
			return true
	return false


static func _rules() -> Dictionary:
	var block = TacticsRuleData.weakness()
	return block if block is Dictionary else {}

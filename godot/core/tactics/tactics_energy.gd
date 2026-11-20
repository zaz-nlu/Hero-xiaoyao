extends RefCounted

# 能量模型：内力 / 紫气 / 仙气（剑意不走这里）。数值全部来自
# data/tactics_rules.json 的 energy 段；这里只做纯查询，不写战斗状态。

const TacticsRuleData = preload("res://core/tactics/tactics_rule_data.gd")

const DEFAULT_COLORS: Array[String] = ["neili", "ziqi", "xianqi"]
const DEFAULT_NAMES := {"neili": "内力", "ziqi": "紫气", "xianqi": "仙气"}


static func colors() -> Array:
	var out: Array = []
	for value in _block().get("colors", []):
		out.append(str(value))
	return out if not out.is_empty() else DEFAULT_COLORS.duplicate()


static func name_of(energy: String) -> String:
	var names: Dictionary = _block().get("names", {})
	var text := str(names.get(energy, ""))
	if text != "":
		return text
	return str(DEFAULT_NAMES.get(energy, energy))


static func is_color(energy: String) -> bool:
	return colors().has(energy)


static func is_locked(energy: String) -> bool:
	var locked: Array = _block().get("locked", [])
	return locked.has(energy)


static func initial_pools() -> Dictionary:
	var out := {}
	var initial: Dictionary = _block().get("initial", {})
	for color in colors():
		out[str(color)] = maxi(0, int(initial.get(str(color), 0)))
	return out


# 内力池上限的成长入口：目前返回 JSON 初值，后续再随境界变化。
@warning_ignore("unused_parameter")
static func max_neili_for(realm_id: String) -> int:
	var initial: Dictionary = _block().get("initial", {})
	return maxi(0, int(initial.get("neili", 0)))


# 战败后内力至少保留池上限的百分比（data/tactics_rules.json）。
static func defeat_neili_floor_pct() -> int:
	return maxi(0, int(_block().get("defeat_neili_floor_pct", 50)))


# 战后内力：胜利沿用剩余；战败取剩余与下限的较大值，且不超过上限。
static func neili_after_battle(left: int, max_value: int, defeated: bool) -> int:
	var cap := maxi(0, max_value)
	var remaining := clampi(left, 0, cap)
	if not defeated:
		return remaining
	var floor_value := ceili(float(cap) * float(defeat_neili_floor_pct()) / 100.0)
	return clampi(maxi(remaining, floor_value), 0, cap)


# 已构造好的玩家单位没有池子时补 JSON 初值（不覆盖已有覆盖值）。
static func apply_defaults(unit) -> void:
	if unit == null or unit.side != "player" or not unit.energy_max.is_empty():
		return
	unit.energy_max = initial_pools()
	unit.energy_left = unit.energy_max.duplicate()


static func grade_cost(grade: String) -> int:
	var costs: Dictionary = _block().get("grade_cost", {})
	return maxi(0, int(costs.get(grade, 1)))


# 一次出招要扣的次数；基础剑术等 free_martials 里的武学不耗池。
static func cost_for(martial) -> int:
	if martial == null:
		return 1
	var martial_id: Variant = _field(martial, "id")
	var free: Array = _block().get("free_martials", [])
	if free.has(str(martial_id)):
		return 0
	# 蓝条模式（东方阳等）：武学自带耗蓝，池子是体质决定的大数值；任逍遥仍是次数制。
	var mana = _field(martial, "mana_cost")
	if (mana is int or mana is float) and int(mana) >= 0:
		return int(mana)
	var grade = _field(martial, "grade")
	return grade_cost(str(grade) if grade != null else "")


static func damage_pct(energy: String) -> int:
	var pct: Dictionary = _block().get("damage_pct", {})
	return int(pct.get(energy, 100))


static func heal_ratio() -> float:
	return float(_block().get("ziqi_heal_ratio", 1.5))


static func heal_scale() -> int:
	return maxi(1, int(_block().get("ziqi_heal_scale", 100)))


# 紫气回复：造成伤害 × heal_ratio × (1 + (技巧 + 体质) / heal_scale)。
static func heal_for(damage: int, stats: Dictionary) -> int:
	if damage <= 0:
		return 0
	var bonus := float(int(stats.get("skill", 0)) + int(stats.get("constitution", 0))) \
			/ float(heal_scale())
	return maxi(0, floori(float(damage) * heal_ratio() * (1.0 + bonus)))


# 仙气元素效果的数据钩子；本阶段没有具体效果。
static func xianqi_effects() -> Array:
	var xianqi: Dictionary = _block().get("xianqi", {})
	var effects = xianqi.get("effects", [])
	return effects if effects is Array else []


static func _field(value, key: String) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).get(key, "")
	if value is Object:
		return value.get(key)
	return ""


static func _block() -> Dictionary:
	var block = TacticsRuleData.energy()
	return block if block is Dictionary else {}

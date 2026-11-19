extends RefCounted

# 进攻侧韧性：削韧、击破、眩晕结束回满与蓄势。数值来自
# data/tactics_rules.json 的 weakness 段，状态写在 TacticsUnit 上。

const TacticsRuleData = preload("res://core/tactics/tactics_rule_data.gd")
const TacticsWeakness = preload("res://core/tactics/tactics_weakness.gd")


# 一次玩家方进攻命中后的韧性结算；返回事件与结算后的韧性。
# 反击不会走到这里：攻击方为敌人时直接返回，不削韧也不触发弱点。
static func resolve_hit(battle, attacker, defender, weak_color: String) -> Dictionary:
	var out: Dictionary = {"events": [], "toughness_left": _left(defender)}
	if attacker == null or defender == null or defender.unit == null:
		return out
	if attacker.side != "player" or defender.side != "enemy":
		return out
	if int(defender.unit.toughness_max) <= 0 or defender.unit.is_dead():
		return out
	var weak := weak_color != ""
	var cost := _rule_int("toughness_weak" if weak else "toughness_hit", 2 if weak else 1)
	var broken: bool = defender.unit.apply_toughness(float(cost))
	if weak:
		defender.no_weak_turns = 0
		defender.empowered = false
		defender.last_weak_color = weak_color
	if broken:
		out["events"].append({"type": "stun", "unit": defender.id})
		TacticsWeakness.clear(defender)
		attacker.unit.jianyi_points = mini(
			int(attacker.unit.jianyi_max), int(attacker.unit.jianyi_points) + 1)
	else:
		var index: int = defender.weaknesses.find(weak_color) if weak else -1
		if index >= 0:
			TacticsWeakness.refresh(battle, defender, index)
	out["toughness_left"] = defender.unit.toughness_left
	return out


# 蓄势：敌人自己的回合结束时累计未被弱点命中的回合数。
static func end_turn(battle, uid: String) -> Array:
	var unit = battle.get_unit(uid)
	if unit == null or unit.side != "enemy" or not unit.is_alive() \
			or unit.weaknesses.is_empty():
		return []
	unit.no_weak_turns += 1
	if unit.no_weak_turns >= _rule_int("empower_after_turns", 3) and not unit.empowered:
		unit.empowered = true
		unit.no_weak_turns = 0
		return [{"type": "empowered", "unit": uid}]
	return []


# 攻击前取出蓄势加成并清除；没有蓄势时返回 1.0。
static func consume_empower(attacker) -> float:
	if attacker == null or attacker.side != "enemy" or not attacker.empowered:
		return 1.0
	attacker.empowered = false
	return float(_rule_int("empower_pct", 125)) / 100.0


# 眩晕回合开始：递减眩晕；结束时韧性回满并重抽弱点。
static func tick_stun(battle, unit) -> Array:
	if unit == null or unit.unit == null or unit.unit.stun_left <= 0:
		return []
	unit.unit.tick_stun()
	if unit.unit.stun_left <= 0:
		TacticsWeakness.refill(battle, unit)
	return []


static func _left(defender) -> float:
	if defender == null or defender.unit == null:
		return 0.0
	return float(defender.unit.toughness_left)


static func _rule_int(key: String, fallback: int) -> int:
	var block = TacticsRuleData.weakness()
	if block is Dictionary and block.has(key):
		return int(block[key])
	return fallback

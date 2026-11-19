extends RefCounted

const Counter = preload("res://core/counter.gd")
const StatsRules = preload("res://core/tactics/stats_rules.gd")
const TacticsCounterRules = preload("res://core/tactics/tactics_counter_rules.gd")
const TacticsEnergy = preload("res://core/tactics/tactics_energy.gd")
const TacticsRuleData = preload("res://core/tactics/tactics_rule_data.gd")


# 返回被攻击方可选的防守列表：能破招的武学 + 基础格挡（_block）。
# 资格全部满足才返回，否则空数组。
static func options(
	defender,
	attacker,
	move: Dictionary,
	martials: Dictionary,
	mastery,
	relation: String,
	battle_ctx: Dictionary = {}
) -> Array:
	var out: Array = []
	# 本阶段只有玩家方防守敌人。
	if defender.side != "player":
		return out
	if defender.reactions_left <= 0:
		return out
	if relation == "back":
		return out
	if defender.unit.is_dead() or defender.unit.is_stunned():
		return out
	if bool(move.get("unblockable", false)):
		return out
	for raw_id in defender.loadout:
		var martial_id := str(raw_id)
		var martial = martials.get(martial_id)
		if martial == null:
			continue
		if not defender.can_pay("neili", cost_of(martial_id, martials)):
			continue
		if defender.speed() + int(martial.initiative) < attacker.speed() - StatsRules.React_SLACK:
			continue
		var evaluated := TacticsCounterRules.evaluate(
			defender, attacker, move, martial, relation, battle_ctx)
		if str(evaluated["outcome"]) == "none":
			continue
		out.append(_option(martial_id, evaluated))
	var block := TacticsRuleData.basic_block()
	if not block.is_empty():
		var blocked := TacticsCounterRules.evaluate(
			defender, attacker, move, null, relation, battle_ctx)
		if str(blocked["outcome"]) != "none":
			out.append(_option(str(block["id"]), blocked))
	return out


# 按选中的武学（或 _block）重新判定；只计算数值，不改任何单位状态。
static func resolve(
	defender,
	attacker,
	move: Dictionary,
	martial_id: String,
	martials: Dictionary,
	mastery,
	relation: String,
	base_damage: int,
	battle_ctx: Dictionary = {}
) -> Dictionary:
	var block_id := str(TacticsRuleData.basic_block().get("id", ""))
	var is_block := block_id != "" and martial_id == block_id
	var evaluated: Dictionary
	if martial_id == "":
		evaluated = _none_result()
	elif is_block:
		evaluated = TacticsCounterRules.evaluate(
			defender, attacker, move, null, relation, battle_ctx)
	else:
		var martial = martials.get(martial_id)
		if martial == null:
			evaluated = _none_result()
		else:
			evaluated = TacticsCounterRules.evaluate(
				defender, attacker, move, martial, relation, battle_ctx)
	var outcome := str(evaluated["outcome"])
	var table := TacticsRuleData.result(outcome)
	return {
		"outcome": outcome,
		"verdict": int(evaluated.get("verdict", Counter.Verdict.IMPOSSIBLE)),
		"perfect": bool(evaluated.get("perfect", false)),
		"block": is_block,
		"damage": _scaled_damage(base_damage, int(table.get("damage_pct", 100))),
		"counter_pct": int(table.get("counter_pct", 0)),
		"jianyi": int(table.get("jianyi", 0)),
		# 战旗层反击不再削攻击者韧性；字段保留给旧调用点。
		"toughness_cost": 0.0,
		"counter_attack": int(table.get("counter_pct", 0)) > 0,
	}


# 反制武学自动使用内力池；基础格挡不耗池，返回 0。
static func cost_of(martial_id: String, martials: Dictionary) -> int:
	var block_id := str(TacticsRuleData.basic_block().get("id", ""))
	if martial_id == "" or martial_id == block_id:
		return 0
	return TacticsEnergy.cost_for(martials.get(martial_id))


static func _option(martial_id: String, evaluated: Dictionary) -> Dictionary:
	return {
		"id": martial_id,
		"verdict": int(evaluated["verdict"]),
		"perfect": bool(evaluated["perfect"]),
		"outcome": str(evaluated["outcome"]),
	}


static func _none_result() -> Dictionary:
	return {
		"outcome": "none",
		"verdict": int(Counter.Verdict.IMPOSSIBLE),
		"perfect": false,
	}


static func _scaled_damage(base_damage: int, damage_pct: int) -> int:
	if damage_pct <= 0 or base_damage <= 0:
		return 0
	return maxi(1, floori(float(base_damage) * float(damage_pct) / 100.0))

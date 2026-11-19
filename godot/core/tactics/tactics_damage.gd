extends RefCounted

const Balance = preload("res://core/balance.gd")
const Realms = preload("res://core/realms.gd")
const StatsRules = preload("res://core/tactics/stats_rules.gd")
const TacticsRules = preload("res://core/tactics/tactics_rules.gd")


# 玩家武学伤害；无副作用，不调用 take_damage。
static func martial_damage(
	attacker_stats: Dictionary,
	attacker_realm: String,
	power: int,
	mastery_mult: float,
	defender,
	relation: String,
	height_bonus: float
) -> int:
	var raw: float = (float(power) * mastery_mult + float(attacker_stats.get("power", 0))) \
			* Realms.scale(attacker_realm) \
			* (1.0 + StatsRules.facing_bonus(relation) + height_bonus)
	return _apply_defense(raw, defender)


# 敌方招式伤害；沿用旧战斗的"威力 × 境界 − 防御"骨架。
static func move_damage(
	move_power: int,
	attacker_realm: String,
	defender,
	relation: String,
	height_bonus: float
) -> int:
	var raw: float = float(move_power) * Realms.scale(attacker_realm) \
			* (1.0 + StatsRules.facing_bonus(relation) + height_bonus)
	return _apply_defense(raw, defender)


# 剑意真实伤害：无视防御，不可愈合伤。
static func jianyi_damage(
	attacker_stats: Dictionary,
	attacker_realm: String,
	power: int,
	mastery_mult: float
) -> int:
	var skill := int(attacker_stats.get("skill", 0))
	var raw: float = (float(power) * mastery_mult + float(attacker_stats.get("power", 0))) \
			* Realms.scale(attacker_realm) \
			* TacticsRules.jianyi_multiplier(skill)
	return maxi(1, floori(raw))


static func _apply_defense(raw: float, defender) -> int:
	var defense := 0
	if defender.is_stunned():
		raw *= Balance.CRIT_MULT
	else:
		defense = floori(int(defender.stats.get("defense", 0)) * Realms.scale(str(defender.realm)))
	return maxi(1, floori(raw) - defense)

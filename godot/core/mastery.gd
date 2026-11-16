extends RefCounted

const Balance = preload("res://core/balance.gd")

# 一个 Mastery 实例属于一个角色，记录该角色每门武学的累计经验。
var _exp: Dictionary = {}


@warning_ignore("integer_division")
static func exp_to_reach(level: int) -> int:
	return 5 * level * (level + 1) / 2


func level(id: String) -> int:
	var exp: int = _exp.get(id, 0)
	var result := 0
	for l in range(1, Balance.MAX_LEVEL + 1):
		if exp >= exp_to_reach(l):
			result = l
		else:
			break
	return result


func add_exp(id: String, amount: int) -> void:
	_exp[id] = _exp.get(id, 0) + amount


func learn(id: String) -> void:
	var needed := exp_to_reach(1)
	if _exp.get(id, 0) < needed:
		_exp[id] = needed


func damage_multiplier(id: String) -> float:
	return 1.0 + Balance.LEVEL_BONUS * level(id)

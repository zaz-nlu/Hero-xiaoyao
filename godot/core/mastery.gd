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


func exp_of(id: String) -> int:
	return int(_exp.get(id, 0))


func export_exp() -> Dictionary:
	return _exp.duplicate()


func import_exp(d: Dictionary) -> void:
	for key in d.keys():
		_exp[str(key)] = int(d[key])


static func progress_in_level(exp: int) -> Dictionary:
	var current := 0
	for l in range(1, Balance.MAX_LEVEL + 1):
		if exp >= exp_to_reach(l):
			current = l
		else:
			break
	if current >= Balance.MAX_LEVEL:
		return {
			"level": current,
			"into": maxi(0, exp - exp_to_reach(current)),
			"need": 0,
		}
	var start := exp_to_reach(current)
	var target := exp_to_reach(current + 1)
	return {
		"level": current,
		"into": maxi(0, exp - start),
		"need": target - start,
	}


func learn(id: String) -> void:
	var needed := exp_to_reach(1)
	if _exp.get(id, 0) < needed:
		_exp[id] = needed


func damage_multiplier(id: String) -> float:
	return 1.0 + Balance.LEVEL_BONUS * level(id)

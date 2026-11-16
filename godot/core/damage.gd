extends RefCounted

const Balance = preload("res://core/balance.gd")


static func hit(martial_power: int, multiplier: float, attacker_stats: Dictionary, defender) -> int:
	var raw: float = martial_power * multiplier + attacker_stats["power"]
	var defense := 0
	if defender.is_stunned():
		raw *= Balance.CRIT_MULT
	else:
		defense = int(defender.stats["defense"])
	var damage: int = maxi(1, floori(raw) - defense)
	defender.take_damage(damage)
	return damage

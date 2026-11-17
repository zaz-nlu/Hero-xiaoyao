extends RefCounted

const Balance = preload("res://core/balance.gd")
const Realms = preload("res://core/realms.gd")


static func hit(martial_power: int, multiplier: float, attacker_stats: Dictionary, defender, attacker_realm := "lianti") -> int:
	var raw: float = (martial_power * multiplier + attacker_stats["power"]) * Realms.scale(attacker_realm)
	var defense := 0
	if defender.is_stunned():
		raw *= Balance.CRIT_MULT
	else:
		defense = floori(int(defender.stats["defense"]) * Realms.scale(str(defender.realm)))
	var damage: int = maxi(1, floori(raw) - defense)
	defender.take_damage(damage)
	return damage

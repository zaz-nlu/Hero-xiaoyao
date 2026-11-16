extends RefCounted

const Balance = preload("res://core/balance.gd")


static func can_strike(attacker, target) -> bool:
	var has_points: bool = attacker.jianyi_points > 0
	var target_ok: bool = not target.incorporeal and not target.is_dead()
	return has_points and target_ok


static func strike(attacker, target) -> int:
	if not can_strike(attacker, target):
		return -1
	var damage: int = Balance.JIANYI_BASE + int(attacker.stats["skill"])
	target.take_wound(damage)
	attacker.jianyi_points -= 1
	return damage


static func restore(attacker) -> void:
	if attacker.jianyi_points >= attacker.jianyi_max:
		return
	attacker.jianyi_points += 1

extends RefCounted

# 无限回复：带 def.regen_pct 的敌人在玩家回合结束后瞬间回血。
# 伤口（剑意造成的伤害）会压低气血上限，回复不会超过上限；眩晕（被击破）期间不回复。
# 只产生 heal 事件（source = "regen"），不依赖场景类型。


static func on_player_turn_end(battle) -> Array:
	var events: Array = []
	for raw in battle.units:
		var unit = raw
		if unit.side != "enemy" or not unit.is_alive() or unit.unit == null:
			continue
		var def = unit.unit.def
		if def == null or int(def.regen_pct) <= 0 or unit.unit.is_stunned():
			continue
		var amount: int = ceili(float(unit.unit.max_hp) * float(def.regen_pct) / 100.0)
		var healed: int = unit.unit.heal(amount)
		if healed > 0:
			events.append({"type": "heal", "unit": unit.id, "amount": healed, "source": "regen"})
	return events

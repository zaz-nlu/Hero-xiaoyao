extends RefCounted

# 紫气主动释放：玩家对自己运功，消耗紫气池、恢复最大气血的一定百分比，
# 占用本回合行动（释放前后仍可移动）。数值来自 data/tactics_rules.json 的
# ziqi_release 段；这里只读写战斗状态，不触发反制、不削韧、不判定弱点。

const TacticsRuleData = preload("res://core/tactics/tactics_rule_data.gd")


static func cost() -> int:
	var block := _block()
	return maxi(0, int(block.get("cost", 0)))


static func heal_pct() -> int:
	var block := _block()
	return maxi(1, int(block.get("heal_pct", 0)))


# 固定回复量：最大气血的 heal_pct%，向下取整，至少 1 点。
static func heal_amount(max_hp: int) -> int:
	return maxi(1, floori(float(maxi(0, max_hp)) * float(heal_pct()) / 100.0))


# 只做资格检查，不改状态；release() 复用同一套判断。
static func availability(battle, unit_id: String) -> Dictionary:
	if battle == null or battle.result() != "":
		return _fail("battle_over")
	var unit = battle.get_unit(unit_id)
	if unit == null or not unit.is_alive():
		return _fail("no_unit")
	if unit_id != battle.current_actor:
		return _fail("not_active")
	if unit.side != "player":
		return _fail("player_only")
	if unit.has_acted:
		return _fail("already_acted")
	if not unit.can_pay("ziqi", cost()):
		return _fail("no_energy")
	if int(unit.unit.hp) >= int(unit.unit.max_hp) - int(unit.unit.wound):
		return _fail("full_hp")
	return {"ok": true, "reason": ""}


static func release(battle, unit_id: String) -> Dictionary:
	var check := availability(battle, unit_id)
	if not bool(check.get("ok", false)):
		return _fail(str(check.get("reason", "")))
	var unit = battle.get_unit(unit_id)
	var healed: int = unit.unit.heal(heal_amount(int(unit.unit.max_hp)))
	if healed <= 0:
		return _fail("full_hp")
	unit.spend_energy("ziqi", cost())
	unit.has_acted = true
	var events: Array = [{
		"type": "heal", "unit": unit_id, "amount": healed, "source": "ziqi_release"}]
	battle._record(events)
	return {"ok": true, "reason": "", "events": events}


static func _block() -> Dictionary:
	var block = TacticsRuleData.ziqi_release()
	return block if block is Dictionary else {}


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "events": []}

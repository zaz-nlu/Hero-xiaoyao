extends RefCounted

const Balance = preload("res://core/balance.gd")
const Damage = preload("res://core/damage.gd")
const Jianyi = preload("res://core/jianyi.gd")
const EnemyAi = preload("res://core/enemy_ai.gd")

enum State { ONGOING, WON, LOST, TIMEOUT }

var player: Variant = null
var enemies: Array = []
var loadout: Array = []
var mastery: Variant = null
var martials: Dictionary = {}
var first_strike: bool = false
var round: int = 1
var intents: Array = []
var log: Array[String] = []

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _stunned_at_start: Array[bool] = []


func _init(p_player, p_enemies: Array, p_loadout: Array, p_mastery, p_martials: Dictionary, p_seed: int, p_first_strike: bool) -> void:
	player = p_player
	enemies = p_enemies
	loadout = p_loadout
	mastery = p_mastery
	martials = p_martials
	first_strike = p_first_strike
	_rng.seed = p_seed
	round = 1
	begin_round()


func begin_round() -> void:
	intents = []
	_stunned_at_start.clear()
	for i in range(enemies.size()):
		var enemy: Variant = enemies[i]
		var stunned: bool = enemy.is_stunned()
		_stunned_at_start.append(stunned)
		if enemy.is_dead() or stunned:
			intents.append({})
		else:
			intents.append(EnemyAi.choose(enemy.def.moves, _rng))


func submit(action: Dictionary) -> Dictionary:
	var check: Dictionary = _validate(action)
	if not bool(check["ok"]):
		return check
	_settle(action)
	if state() == State.ONGOING:
		round += 1
		begin_round()
	return {"ok": true, "error": ""}


func state() -> int:
	var all_dead := true
	for enemy in enemies:
		if not enemy.is_dead():
			all_dead = false
			break
	if all_dead:
		return State.WON
	if player.is_dead():
		return State.LOST
	if round > Balance.MAX_ROUNDS:
		return State.TIMEOUT
	return State.ONGOING


func _validate(action: Dictionary) -> Dictionary:
	if state() != State.ONGOING:
		return {"ok": false, "error": "battle is over"}
	var kind: String = str(action.get("kind", ""))
	if kind != "martial" and kind != "jianyi" and kind != "probe":
		return {"ok": false, "error": "unknown action kind: %s" % kind}
	var target_index: int = int(action.get("target", -1))
	if target_index < 0 or target_index >= enemies.size():
		return {"ok": false, "error": "target index out of range: %d" % target_index}
	var target: Variant = enemies[target_index]
	if target.is_dead():
		return {"ok": false, "error": "target is already dead"}
	if kind == "martial":
		var id: String = str(action.get("id", ""))
		if not loadout.has(id):
			return {"ok": false, "error": "martial not in loadout: %s" % id}
		if not martials.has(id):
			return {"ok": false, "error": "unknown martial: %s" % id}
		if mastery.level(id) < 1:
			return {"ok": false, "error": "martial not learned: %s" % id}
	elif kind == "jianyi":
		if not Jianyi.can_strike(player, target):
			return {"ok": false, "error": "cannot use jianyi now"}
	return {"ok": true, "error": ""}


func _settle(action: Dictionary) -> void:
	var order: Array = _actor_order()
	var finished := false
	for actor in order:
		if not finished:
			if bool(actor["is_player"]):
				_player_step(action)
			else:
				_enemy_step(int(actor["index"]))
		if state() != State.ONGOING:
			finished = true
	for i in range(enemies.size()):
		var enemy: Variant = enemies[i]
		if i < _stunned_at_start.size() and _stunned_at_start[i] and not enemy.is_dead():
			enemy.tick_stun()


func _actor_order() -> Array:
	var entries: Array = []
	var force_first: bool = first_strike and round == 1
	entries.append({
		"key": int(player.stats["speed"]),
		"tie": 0,
		"is_player": true,
		"index": -1,
	})
	for i in range(enemies.size()):
		var enemy: Variant = enemies[i]
		if enemy.is_dead():
			continue
		entries.append({
			"key": int(enemy.stats["speed"]),
			"tie": i + 1,
			"is_player": false,
			"index": i,
		})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if force_first and bool(a["is_player"]) != bool(b["is_player"]):
			return bool(a["is_player"])
		if int(a["key"]) != int(b["key"]):
			return int(a["key"]) > int(b["key"])
		return int(a["tie"]) < int(b["tie"])
	)
	return entries


func _player_step(action: Dictionary) -> void:
	var kind: String = str(action.get("kind", ""))
	var target_index: int = int(action.get("target", -1))
	var target: Variant = enemies[target_index]
	if kind == "martial":
		var id: String = str(action.get("id", ""))
		var martial: Variant = martials[id]
		var dealt: int = Damage.hit(martial.power, mastery.damage_multiplier(id), player.stats, target)
		_log("R%d act:player martial %s -> e%d dmg %d" % [round, id, target_index, dealt])
	elif kind == "jianyi":
		var dealt: int = Jianyi.strike(player, target)
		_log("R%d act:player jianyi -> e%d dmg %d" % [round, target_index, dealt])
	elif kind == "probe":
		target.probe()
		_log("R%d act:player probe -> e%d" % [round, target_index])


func _enemy_step(index: int) -> void:
	var enemy: Variant = enemies[index]
	if enemy.is_dead():
		return
	if index < _stunned_at_start.size() and _stunned_at_start[index]:
		_log("R%d skip:e%d stunned" % [round, index])
		return
	var healed: int = enemy.heal(int(enemy.stats["recovery"]) * Balance.REGEN_PER_RECOVERY)
	var intent: Dictionary = {}
	if index < intents.size():
		intent = intents[index]
	var power: int = int(intent.get("power", 0))
	var damage: int = maxi(1, power - int(player.stats["defense"]))
	player.take_damage(damage)
	_log("R%d act:e%d heal %d dmg %d" % [round, index, healed, damage])


func _log(line: String) -> void:
	log.append(line)

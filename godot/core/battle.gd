extends RefCounted

const Balance = preload("res://core/balance.gd")
const Counter = preload("res://core/counter.gd")
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
var known_moves: Dictionary = {}
var log: Array[String] = []

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _stunned_at_start: Array[bool] = []
var _intent_from_queue: Array[bool] = []
var _queues: Array = []
var _current_action: Dictionary = {}


func _init(p_player, p_enemies: Array, p_loadout: Array, p_mastery, p_martials: Dictionary, p_seed: int, p_first_strike: bool) -> void:
	player = p_player
	enemies = p_enemies
	loadout = p_loadout
	mastery = p_mastery
	martials = p_martials
	first_strike = p_first_strike
	_rng.seed = p_seed
	round = 1
	_queues = []
	for i in range(enemies.size()):
		_queues.append([])
	begin_round()


func begin_round() -> void:
	intents = []
	_stunned_at_start.clear()
	_intent_from_queue.clear()
	for i in range(enemies.size()):
		var enemy: Variant = enemies[i]
		var stunned: bool = enemy.is_stunned()
		_stunned_at_start.append(stunned)
		if enemy.is_dead() or stunned:
			intents.append({})
			_intent_from_queue.append(false)
		else:
			var queued: bool = false
			if i < _queues.size():
				var queue: Array = _queues[i]
				if not queue.is_empty():
					intents.append(queue.pop_front())
					_intent_from_queue.append(true)
					queued = true
			if not queued:
				intents.append(EnemyAi.choose(enemy.def.moves, _rng))
				_intent_from_queue.append(false)


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


func preview(martial_id: String, target: int) -> int:
	if not martials.has(martial_id):
		return Counter.Verdict.IMPOSSIBLE
	if target < 0 or target >= enemies.size():
		return Counter.Verdict.IMPOSSIBLE
	var enemy: Variant = enemies[target]
	if enemy.is_dead():
		return Counter.Verdict.IMPOSSIBLE
	if target >= intents.size():
		return Counter.Verdict.IMPOSSIBLE
	var intent: Dictionary = intents[target]
	if intent.is_empty():
		return Counter.Verdict.IMPOSSIBLE
	return Counter.evaluate(
		martials[martial_id],
		player.stats,
		int(enemy.stats["speed"]),
		intent,
		first_strike and round == 1
	)


func is_move_known(enemy_index: int) -> bool:
	if enemy_index < 0 or enemy_index >= enemies.size() or enemy_index >= intents.size():
		return false
	var intent: Dictionary = intents[enemy_index]
	if intent.is_empty():
		return false
	var enemy: Variant = enemies[enemy_index]
	var raw_ids: Variant = known_moves.get(str(enemy.id), [])
	if not (raw_ids is Array):
		return false
	var ids: Array = raw_ids
	return ids.has(str(intent.get("id", "")))


func foreseen(enemy_index: int) -> Array:
	var result: Array = []
	if enemy_index < 0 or enemy_index >= enemies.size() or enemy_index >= _queues.size():
		return result
	var enemy: Variant = enemies[enemy_index]
	if enemy.is_dead():
		return result
	if enemy_index < _intent_from_queue.size() and _intent_from_queue[enemy_index]:
		if enemy_index < intents.size():
			var current: Dictionary = intents[enemy_index]
			if not current.is_empty():
				result.append(current.duplicate())
	for raw in _queues[enemy_index]:
		var move: Dictionary = raw
		result.append(move.duplicate())
	return result


func foresight_available() -> bool:
	if player == null or int(player.foresight_points) <= 0:
		return false
	for enemy in enemies:
		if not enemy.is_dead():
			return true
	return false


func _mark_known(enemy_index: int, move_id: String) -> void:
	if move_id == "":
		return
	if enemy_index < 0 or enemy_index >= enemies.size():
		return
	var enemy: Variant = enemies[enemy_index]
	var key: String = str(enemy.id)
	if not known_moves.has(key):
		known_moves[key] = []
	var ids: Array = known_moves[key]
	if not ids.has(move_id):
		ids.append(move_id)


func _validate(action: Dictionary) -> Dictionary:
	if state() != State.ONGOING:
		return {"ok": false, "error": "battle is over"}
	var kind: String = str(action.get("kind", ""))
	if kind != "martial" and kind != "jianyi" and kind != "probe" and kind != "foresight":
		return {"ok": false, "error": "unknown action kind: %s" % kind}
	if kind == "foresight":
		if int(player.foresight_points) <= 0:
			return {"ok": false, "error": "no foresight points left"}
		if not foresight_available():
			return {"ok": false, "error": "no living enemies for foresight"}
		return {"ok": true, "error": ""}
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
	_current_action = action.duplicate()
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
	_current_action = {}


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
	if kind == "foresight":
		_do_foresight()
		return
	var target: Variant = enemies[target_index]
	if kind == "martial":
		var id: String = str(action.get("id", ""))
		var martial: Variant = martials[id]
		var dealt: int = Damage.hit(martial.power, mastery.damage_multiplier(id), player.stats, target)
		mastery.add_exp(id, 1)
		_log("R%d act:player martial %s -> e%d dmg %d" % [round, id, target_index, dealt])
	elif kind == "jianyi":
		var dealt: int = Jianyi.strike(player, target)
		_log("R%d act:player jianyi -> e%d dmg %d" % [round, target_index, dealt])
	elif kind == "probe":
		target.probe()
		_log("R%d act:player probe -> e%d" % [round, target_index])


func _do_foresight() -> void:
	player.foresight_points -= 1
	for i in range(enemies.size()):
		var enemy: Variant = enemies[i]
		if enemy.is_dead():
			continue
		var queue: Array = _queues[i]
		while queue.size() < Balance.FORESIGHT_ROUNDS:
			queue.append(EnemyAi.choose(enemy.def.moves, _rng))
		for raw in queue:
			var move: Dictionary = raw
			_mark_known(i, str(move.get("id", "")))
	_log("R%d act:player foresight" % round)


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
	if not intent.is_empty():
		_mark_known(index, str(intent.get("id", "")))
	var power: int = int(intent.get("power", 0))
	var base_damage: int = maxi(1, power - int(player.stats["defense"]))

	var counter_id: String = ""
	var counter_martial: Variant = null
	if str(_current_action.get("kind", "")) == "martial" \
			and int(_current_action.get("target", -1)) == index:
		var id: String = str(_current_action.get("id", ""))
		if martials.has(id):
			counter_id = id
			counter_martial = martials[id]

	var verdict: int = Counter.Verdict.IMPOSSIBLE
	var perfect: bool = false
	if counter_martial != null:
		verdict = Counter.evaluate(
			counter_martial,
			player.stats,
			int(enemy.stats["speed"]),
			intent,
			first_strike and round == 1
		)
		perfect = Counter.is_perfect(
			verdict,
			counter_martial,
			player.stats,
			enemy.weak_moves,
			str(intent["id"])
		)

	var damage: int = base_damage
	if verdict == Counter.Verdict.ADVANTAGE:
		damage = 0
	elif verdict == Counter.Verdict.BARELY:
		damage = maxi(1, floori(float(base_damage) / 2.0))
	player.take_damage(damage)

	var stunned_now: bool = false
	if counter_martial != null and verdict != Counter.Verdict.IMPOSSIBLE:
		var cost: float = Counter.toughness_cost(verdict, perfect)
		stunned_now = enemy.apply_toughness(cost)
		if verdict == Counter.Verdict.ADVANTAGE:
			Jianyi.restore(player)
		mastery.add_exp(counter_id, 2)
		if perfect:
			Damage.hit(counter_martial.power, mastery.damage_multiplier(counter_id), player.stats, enemy)
			player.foresight_points = mini(int(player.foresight_max), int(player.foresight_points) + 1)
		if verdict == Counter.Verdict.ADVANTAGE:
			for raw_effect in counter_martial.effects:
				var effect: Dictionary = raw_effect
				if str(effect.get("kind", "")) == "reflect":
					enemy.take_damage(floori(base_damage * float(effect.get("value", 0.0))))

	var extra: String = "verdict=NONE"
	if counter_martial != null:
		extra = "verdict=%s perfect=%s toughness_left=%.1f stunned=%s" % [
			_verdict_name(verdict),
			str(perfect),
			enemy.toughness_left,
			str(stunned_now),
		]
	_log("R%d act:e%d heal %d dmg %d %s" % [round, index, healed, damage, extra])


func _verdict_name(verdict: int) -> String:
	match verdict:
		Counter.Verdict.ADVANTAGE:
			return "ADVANTAGE"
		Counter.Verdict.BARELY:
			return "BARELY"
		_:
			return "IMPOSSIBLE"


func _log(line: String) -> void:
	log.append(line)

extends RefCounted

const Balance = preload("res://core/balance.gd")
const Counter = preload("res://core/counter.gd")
const Damage = preload("res://core/damage.gd")
const Jianyi = preload("res://core/jianyi.gd")
const EnemyAi = preload("res://core/enemy_ai.gd")
const Mastery = preload("res://core/mastery.gd")
const Progression = preload("res://core/progression.gd")
const Realms = preload("res://core/realms.gd")

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
# item id -> 数量。BattleView 指向 GameState.inventory，模拟器使用自己的字典。
var inventory: Dictionary = {}
var log: Array[String] = []
var uses: Dictionary = {}
var pending_exp: int = 0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _stunned_at_start: Array[bool] = []
var _intent_from_queue: Array[bool] = []
var _queues: Array = []
var _current_action: Dictionary = {}
var _settled: bool = false


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
	var extra_counter := 0
	if mastery != null:
		extra_counter = int(mastery.counter_bonus(martial_id))
	return Counter.evaluate(
		martials[martial_id],
		player.stats,
		int(enemy.stats["speed"]),
		intent,
		first_strike and round == 1,
		extra_counter
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
	if kind != "martial" and kind != "jianyi" and kind != "probe" and kind != "foresight" \
			and kind != "item":
		return {"ok": false, "error": "unknown action kind: %s" % kind}
	if kind == "item":
		return _validate_item(action)
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


func _validate_item(action: Dictionary) -> Dictionary:
	var id: String = str(action.get("id", ""))
	if int(inventory.get(id, 0)) <= 0:
		return {"ok": false, "error": "no item left: %s" % id}
	var item: Dictionary = Progression.item_def(id)
	var consumable_value: Variant = item.get("consumable", null)
	if not (consumable_value is Dictionary):
		return {"ok": false, "error": "item is not consumable: %s" % id}
	var consumable: Dictionary = consumable_value
	if int(consumable.get("heal", 0)) <= 0:
		return {"ok": false, "error": "item has no heal: %s" % id}
	if int(player.hp) >= int(player.max_hp) - int(player.wound):
		return {"ok": false, "error": "hp is already full"}
	return {"ok": true, "error": ""}


func _settle(action: Dictionary) -> void:
	_current_action = action.duplicate()
	var alive_before: Array[bool] = []
	for enemy in enemies:
		alive_before.append(not enemy.is_dead())
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
	if not finished:
		_regen_player()
	for i in range(enemies.size()):
		var enemy: Variant = enemies[i]
		if i < alive_before.size() and alive_before[i] and enemy.is_dead():
			_register_kill(i)
		if i < _stunned_at_start.size() and _stunned_at_start[i] and not enemy.is_dead():
			enemy.tick_stun()
	_current_action = {}


func _register_kill(index: int) -> void:
	if index < 0 or index >= enemies.size():
		return
	var enemy: Variant = enemies[index]
	if enemy.def == null:
		return
	pending_exp += maxi(0, int(enemy.def.exp))


# 胜利后把本场击杀经验按武学使用次数分配；只生效一次，失败/超时不发放。
func settle_exp() -> Dictionary:
	if state() != State.WON or _settled:
		return {}
	_settled = true
	var gained: Dictionary = {}
	if pending_exp <= 0 or mastery == null:
		return gained

	var ids: Array[String] = []
	var total_uses := 0
	for raw_id in uses.keys():
		var id := str(raw_id)
		var count := int(uses[raw_id])
		if count <= 0:
			continue
		ids.append(id)
		total_uses += count
	if total_uses <= 0:
		return gained

	ids.sort_custom(func(a: String, b: String) -> bool:
		var uses_a := int(uses[a])
		var uses_b := int(uses[b])
		if uses_a != uses_b:
			return uses_a > uses_b
		return a < b
	)

	var shares: Dictionary = {}
	var assigned := 0
	for id in ids:
		var share := roundi(float(pending_exp) * float(int(uses[id])) / float(total_uses))
		shares[id] = share
		assigned += share

	var remainder := pending_exp - assigned
	if remainder > 0:
		var cursor := 0
		while remainder > 0:
			var id: String = ids[cursor % ids.size()]
			shares[id] = int(shares[id]) + 1
			remainder -= 1
			cursor += 1
	elif remainder < 0:
		var overflow := -remainder
		for id in ids:
			if overflow <= 0:
				break
			var trimmed: int = mini(int(shares[id]), overflow)
			shares[id] = int(shares[id]) - trimmed
			overflow -= trimmed

	for id in ids:
		var amount := int(shares.get(id, 0))
		if amount <= 0:
			continue
		mastery.add_exp(id, amount)
		gained[id] = amount
		_log("R%d exp %s +%d" % [round, id, amount])
	return gained


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
	if kind == "item":
		_use_item(action)
		return
	var target: Variant = enemies[target_index]
	if kind == "martial":
		var id: String = str(action.get("id", ""))
		var martial: Variant = martials[id]
		var dealt: int = Damage.hit(martial.power, mastery.damage_multiplier(id), player.stats, target, player.realm)
		mastery.add_exp(id, 1)
		uses[id] = int(uses.get(id, 0)) + 1
		_log("R%d act:player martial %s -> e%d dmg %d" % [round, id, target_index, dealt])
	elif kind == "jianyi":
		var dealt: int = Jianyi.strike(player, target)
		_log("R%d act:player jianyi -> e%d dmg %d" % [round, target_index, dealt])
	elif kind == "probe":
		target.probe()
		_log("R%d act:player probe -> e%d" % [round, target_index])


func _use_item(action: Dictionary) -> void:
	var id: String = str(action.get("id", ""))
	inventory[id] = maxi(0, int(inventory.get(id, 0)) - 1)
	var item: Dictionary = Progression.item_def(id)
	var heal_value := 0
	var consumable_value: Variant = item.get("consumable", null)
	if consumable_value is Dictionary:
		var consumable: Dictionary = consumable_value
		heal_value = int(consumable.get("heal", 0))
	var amount: int = Balance.heal_amount(
		heal_value, int(player.stats.get("recovery", 0)), Realms.scale(str(player.realm))
	)
	var healed: int = player.heal(amount)
	_log("R%d act:player item %s heal %d" % [round, id, healed])


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


func _regen_player() -> void:
	if player.is_dead():
		return
	var recovery := int(player.stats.get("recovery", 0))
	var amount: int = floori(recovery * Balance.REGEN_PER_RECOVERY * Realms.scale(str(player.realm)))
	if amount <= 0:
		return
	var healed: int = player.heal(amount)
	if healed > 0:
		_log("R%d regen:player %d" % [round, healed])


func _enemy_step(index: int) -> void:
	var enemy: Variant = enemies[index]
	if enemy.is_dead():
		return
	if index < _stunned_at_start.size() and _stunned_at_start[index]:
		_log("R%d skip:e%d stunned" % [round, index])
		return
	var enemy_scale := Realms.scale(str(enemy.realm))
	var player_scale := Realms.scale(str(player.realm))
	var healed: int = enemy.heal(
		floori(int(enemy.stats["recovery"]) * Balance.REGEN_PER_RECOVERY * enemy_scale)
	)
	var intent: Dictionary = {}
	if index < intents.size():
		intent = intents[index]
	if not intent.is_empty():
		_mark_known(index, str(intent.get("id", "")))
	var power: int = int(intent.get("power", 0))
	var base_damage: int = maxi(
		1,
		floori(power * enemy_scale) - floori(int(player.stats["defense"]) * player_scale)
	)

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
		var extra_counter := 0
		if mastery != null:
			extra_counter = int(mastery.counter_bonus(counter_id))
		verdict = Counter.evaluate(
			counter_martial,
			player.stats,
			int(enemy.stats["speed"]),
			intent,
			first_strike and round == 1,
			extra_counter
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
		var counter_kind := "barely"
		if verdict == Counter.Verdict.ADVANTAGE:
			counter_kind = "perfect" if perfect else "advantage"
		var counter_gain: int = Mastery.counter_exp(counter_kind)
		if counter_gain > 0:
			mastery.add_exp(counter_id, counter_gain)
		if perfect:
			Damage.hit(counter_martial.power, mastery.damage_multiplier(counter_id), player.stats, enemy, player.realm)
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

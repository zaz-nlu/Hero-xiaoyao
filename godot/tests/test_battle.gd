extends "res://tests/test_case.gd"

const Unit = preload("res://core/unit.gd")
const EnemyDef = preload("res://core/enemy_def.gd")
const MartialDef = preload("res://core/martial_def.gd")
const Mastery = preload("res://core/mastery.gd")
const Battle = preload("res://core/battle.gd")
const Balance = preload("res://core/balance.gd")


func _stats(power := 0, speed := 15, defense := 0, recovery := 0, skill := 0, constitution := 0) -> Dictionary:
	return {
		"power": power,
		"speed": speed,
		"defense": defense,
		"recovery": recovery,
		"skill": skill,
		"constitution": constitution,
	}


func _make_player(stats: Dictionary, hp := 100, jianyi_max := 1) -> Variant:
	return Unit.make_player("测试", stats, hp, jianyi_max)


func _make_enemy(hp := 100, speed := 10, defense := 0, recovery := 0, power := 10, move_count := 1) -> Variant:
	var moves: Array = []
	for i in range(move_count):
		moves.append({
			"id": "move%d" % i,
			"name": "招式%d" % i,
			"type": "heavy",
			"threat": power,
			"power": power,
		})
	var d: Variant = EnemyDef.from_dict({
		"id": "enemy",
		"name": "木人",
		"tier": "minion",
		"stats": _stats(0, speed, defense, recovery, 0, 0),
		"max_hp": hp,
		"toughness": 4,
		"stun_turns": 1,
		"moves": moves,
		"weak_moves": [],
	})
	return Unit.from_enemy(d)


func _martial(id: String, power: int) -> Variant:
	return MartialDef.from_dict({
		"id": id,
		"name": id,
		"power": power,
		"counters": ["heavy"],
		"initiative": 0,
		"counter_level": 1,
		"advantage_stat": "power",
	})


func _mastery(ids: Array) -> Variant:
	var m: Variant = Mastery.new()
	for id in ids:
		m.learn(str(id))
	return m


func _battle(player: Variant, enemies: Array, martials: Dictionary, mastery: Variant, loadout: Array = [], seed_value := 1, first_strike := false) -> Variant:
	return Battle.new(player, enemies, loadout, mastery, martials, seed_value, first_strike)


func _first_log_index(lines: Array[String], prefix: String) -> int:
	for i in range(lines.size()):
		if lines[i].begins_with(prefix):
			return i
	return -1


func _intent_ids(intents: Array) -> Array[String]:
	var ids: Array[String] = []
	for raw in intents:
		var move: Dictionary = raw
		ids.append(str(move.get("id", "")))
	return ids


func test_intents_declared_for_living_enemies() -> void:
	var player: Variant = _make_player(_stats())
	var enemies: Array = [_make_enemy(), _make_enemy()]
	var b: Variant = _battle(player, enemies, {"a": _martial("a", 5)}, _mastery(["a"]))
	assert_eq(b.intents.size(), b.enemies.size(), "one intent per enemy")
	for i in range(b.intents.size()):
		var intent: Dictionary = b.intents[i]
		assert_true(not intent.is_empty(), "living enemy %d has an intent" % i)


func test_stunned_or_dead_enemy_has_empty_intent() -> void:
	var player: Variant = _make_player(_stats())
	var stunned: Variant = _make_enemy()
	stunned.stun_left = 1
	var dead: Variant = _make_enemy()
	dead.hp = 0
	var b: Variant = _battle(player, [stunned, dead], {"a": _martial("a", 5)}, _mastery(["a"]))
	assert_eq(b.intents.size(), 2, "intents match enemies")
	var first: Dictionary = b.intents[0]
	var second: Dictionary = b.intents[1]
	assert_true(first.is_empty(), "stunned enemy has no intent")
	assert_true(second.is_empty(), "dead enemy has no intent")


func test_order_by_speed_player_first_on_tie() -> void:
	var martials := {"a": _martial("a", 1)}
	var mastery: Variant = _mastery(["a"])

	var tie_player: Variant = _make_player(_stats(0, 15))
	var tie_enemy: Variant = _make_enemy(100, 15)
	var tie_battle: Variant = _battle(tie_player, [tie_enemy], martials, mastery, ["a"])
	tie_battle.submit({"kind": "martial", "id": "a", "target": 0})
	var player_index: int = _first_log_index(tie_battle.log, "R1 act:player")
	var enemy_index: int = _first_log_index(tie_battle.log, "R1 act:e0")
	assert_true(player_index >= 0, "player acted")
	assert_true(enemy_index >= 0, "enemy acted")
	assert_true(player_index < enemy_index, "player acts first on a speed tie")

	var fast_player: Variant = _make_player(_stats(0, 15))
	var fast_enemy: Variant = _make_enemy(100, 25)
	var fast_battle: Variant = _battle(fast_player, [fast_enemy], martials, mastery, ["a"])
	fast_battle.submit({"kind": "martial", "id": "a", "target": 0})
	var late_player_index: int = _first_log_index(fast_battle.log, "R1 act:player")
	var early_enemy_index: int = _first_log_index(fast_battle.log, "R1 act:e0")
	assert_true(late_player_index >= 0, "player acted")
	assert_true(early_enemy_index >= 0, "enemy acted")
	assert_true(early_enemy_index < late_player_index, "faster enemy acts first")


func test_first_strike_round_one_player_acts_first() -> void:
	var player: Variant = _make_player(_stats(0, 15))
	var enemy: Variant = _make_enemy(100, 30, 0, 0, 1)
	var b: Variant = _battle(player, [enemy], {"a": _martial("a", 1)}, _mastery(["a"]), ["a"], 1, true)
	b.submit({"kind": "martial", "id": "a", "target": 0})
	assert_true(_first_log_index(b.log, "R1 act:player") < _first_log_index(b.log, "R1 act:e0"), "round 1 player first")
	b.submit({"kind": "martial", "id": "a", "target": 0})
	assert_true(_first_log_index(b.log, "R2 act:e0") < _first_log_index(b.log, "R2 act:player"), "round 2 enemy first")


func test_submit_rejects_unlearned_martial() -> void:
	var player: Variant = _make_player(_stats())
	var enemy: Variant = _make_enemy()
	var b: Variant = _battle(player, [enemy], {"a": _martial("a", 5)}, Mastery.new(), ["a"])
	var result: Dictionary = b.submit({"kind": "martial", "id": "a", "target": 0})
	assert_true(not bool(result["ok"]), "unlearned martial is rejected")
	assert_eq(b.round, 1, "round does not advance")


func test_submit_rejects_martial_not_in_loadout() -> void:
	var player: Variant = _make_player(_stats())
	var enemy: Variant = _make_enemy()
	var martials := {"a": _martial("a", 5), "b": _martial("b", 5)}
	var b: Variant = _battle(player, [enemy], martials, _mastery(["a", "b"]), ["a"])
	var result: Dictionary = b.submit({"kind": "martial", "id": "b", "target": 0})
	assert_true(not bool(result["ok"]), "martial outside the loadout is rejected")
	assert_eq(b.round, 1, "round does not advance")


func test_submit_rejects_dead_target() -> void:
	var player: Variant = _make_player(_stats())
	var dead: Variant = _make_enemy()
	dead.hp = 0
	var alive: Variant = _make_enemy()
	var b: Variant = _battle(player, [dead, alive], {"a": _martial("a", 5)}, _mastery(["a"]), ["a"])
	var result: Dictionary = b.submit({"kind": "martial", "id": "a", "target": 0})
	assert_true(not bool(result["ok"]), "dead target is rejected")
	assert_eq(b.round, 1, "round does not advance")


func test_submit_rejects_invalid_target_index() -> void:
	var player: Variant = _make_player(_stats())
	var enemy: Variant = _make_enemy()
	var b: Variant = _battle(player, [enemy], {"a": _martial("a", 5)}, _mastery(["a"]), ["a"])
	var too_high: Dictionary = b.submit({"kind": "martial", "id": "a", "target": 3})
	assert_true(not bool(too_high["ok"]), "index past the end is rejected")
	var negative: Dictionary = b.submit({"kind": "martial", "id": "a", "target": -1})
	assert_true(not bool(negative["ok"]), "negative index is rejected")
	assert_eq(b.round, 1, "round does not advance")


func test_rejected_submit_does_not_advance_round() -> void:
	var player: Variant = _make_player(_stats())
	var enemy: Variant = _make_enemy()
	var b: Variant = _battle(player, [enemy], {}, Mastery.new())
	var unknown: Dictionary = b.submit({"kind": "dance", "target": 0})
	assert_true(not bool(unknown["ok"]), "unknown kind is rejected")
	var bad_target: Dictionary = b.submit({"kind": "probe", "target": 9})
	assert_true(not bool(bad_target["ok"]), "bad target is rejected")
	assert_eq(b.round, 1, "round stays at 1")
	assert_eq(enemy.hp, 100, "enemy untouched")
	assert_eq(player.hp, 100, "player untouched")


func test_martial_damages_target() -> void:
	var player: Variant = _make_player(_stats(0, 15))
	var enemy: Variant = _make_enemy(100, 10, 0, 0, 0)
	var b: Variant = _battle(player, [enemy], {"a": _martial("a", 10)}, _mastery(["a"]), ["a"])
	var result: Dictionary = b.submit({"kind": "martial", "id": "a", "target": 0})
	assert_true(bool(result["ok"]), "martial action accepted")
	assert_eq(enemy.hp, 90, "10 power at level 1 deals 10")


func test_enemy_attacks_player_with_power_minus_defense() -> void:
	var player: Variant = _make_player(_stats(0, 15, 2), 100)
	var enemy: Variant = _make_enemy(100, 10, 0, 0, 10)
	var b: Variant = _battle(player, [enemy], {"a": _martial("a", 1)}, _mastery(["a"]), ["a"])
	b.submit({"kind": "martial", "id": "a", "target": 0})
	assert_true(not enemy.is_dead(), "enemy survives the player's attack")
	assert_eq(player.hp, 92, "enemy power 10 minus defense 2")


func test_jianyi_action_wounds_target() -> void:
	var player: Variant = _make_player(_stats(0, 15, 0, 0, 20), 100, 1)
	var enemy: Variant = _make_enemy(200, 10, 0, 0, 0)
	var b: Variant = _battle(player, [enemy], {}, Mastery.new())
	var result: Dictionary = b.submit({"kind": "jianyi", "target": 0})
	assert_true(bool(result["ok"]), "jianyi accepted")
	assert_eq(enemy.wound, 50, "30 base plus 20 skill")


func test_jianyi_refused_with_zero_points() -> void:
	var player: Variant = _make_player(_stats(0, 15, 0, 0, 20), 100, 1)
	var enemy: Variant = _make_enemy(200, 10, 0, 0, 0)
	var b: Variant = _battle(player, [enemy], {}, Mastery.new())
	var first: Dictionary = b.submit({"kind": "jianyi", "target": 0})
	assert_true(bool(first["ok"]), "first jianyi accepted")
	assert_eq(b.round, 2, "round advanced")
	var second: Dictionary = b.submit({"kind": "jianyi", "target": 0})
	assert_true(not bool(second["ok"]), "no jianyi points left")
	assert_eq(b.round, 2, "round unchanged")


func test_probe_reveals_weak_moves() -> void:
	var player: Variant = _make_player(_stats())
	var enemy: Variant = _make_enemy()
	var b: Variant = _battle(player, [enemy], {}, Mastery.new())
	assert_true(not enemy.weak_revealed, "weak moves hidden at first")
	var result: Dictionary = b.submit({"kind": "probe", "target": 0})
	assert_true(bool(result["ok"]), "probe accepted")
	assert_true(enemy.weak_revealed, "probe reveals weak moves")


func test_win_when_all_enemies_dead() -> void:
	var player: Variant = _make_player(_stats())
	var enemy: Variant = _make_enemy(10)
	var b: Variant = _battle(player, [enemy], {"a": _martial("a", 1000)}, _mastery(["a"]), ["a"])
	var result: Dictionary = b.submit({"kind": "martial", "id": "a", "target": 0})
	assert_true(bool(result["ok"]), "action accepted")
	assert_eq(b.state(), Battle.State.WON, "all enemies dead")
	assert_eq(b.round, 1, "round does not advance after victory")


func test_lose_when_player_dead() -> void:
	var player: Variant = _make_player(_stats(0, 15), 5)
	var enemy: Variant = _make_enemy(100, 10, 0, 0, 10)
	var b: Variant = _battle(player, [enemy], {"a": _martial("a", 1)}, _mastery(["a"]), ["a"])
	b.submit({"kind": "martial", "id": "a", "target": 0})
	assert_eq(b.state(), Battle.State.LOST, "player died")
	assert_eq(b.round, 1, "round does not advance after defeat")


func test_stunned_enemy_does_not_regen_or_act() -> void:
	var player: Variant = _make_player(_stats(), 100)
	var enemy: Variant = _make_enemy(100, 10, 0, 100, 10)
	enemy.hp = 10
	enemy.stun_left = 1
	var b: Variant = _battle(player, [enemy], {}, Mastery.new())
	var result: Dictionary = b.submit({"kind": "probe", "target": 0})
	assert_true(bool(result["ok"]), "probe accepted")
	assert_eq(enemy.hp, 10, "stunned enemy does not regen")
	assert_eq(player.hp, 100, "stunned enemy does not attack")
	assert_true(_first_log_index(b.log, "R1 skip:e0") >= 0, "skip is logged")


func test_stun_ticks_at_end_of_round() -> void:
	var player: Variant = _make_player(_stats())
	var enemy: Variant = _make_enemy()
	enemy.stun_left = 1
	var b: Variant = _battle(player, [enemy], {}, Mastery.new())
	b.submit({"kind": "probe", "target": 0})
	assert_true(not enemy.is_stunned(), "stun ticks down at end of round")


func test_timeout_on_stalemate() -> void:
	var player: Variant = _make_player(_stats(), 100000)
	var enemy: Variant = _make_enemy(100, 10, 0, 100, 0)
	var b: Variant = _battle(player, [enemy], {"a": _martial("a", 1)}, _mastery(["a"]), ["a"])
	var guard: int = Balance.MAX_ROUNDS + 5
	for i in range(guard):
		if b.state() != Battle.State.ONGOING:
			break
		b.submit({"kind": "martial", "id": "a", "target": 0})
	assert_eq(b.state(), Battle.State.TIMEOUT, "stalemate times out")


func test_enemy_ai_deterministic_with_seed() -> void:
	var martials := {"a": _martial("a", 1)}
	var mastery: Variant = _mastery(["a"])
	for i in range(5):
		var player_a: Variant = _make_player(_stats())
		var enemy_a: Variant = _make_enemy(100, 10, 0, 0, 10, 3)
		var battle_a: Variant = _battle(player_a, [enemy_a], martials, mastery, ["a"], 12345)
		var player_b: Variant = _make_player(_stats())
		var enemy_b: Variant = _make_enemy(100, 10, 0, 0, 10, 3)
		var battle_b: Variant = _battle(player_b, [enemy_b], martials, mastery, ["a"], 12345)
		assert_eq(_intent_ids(battle_a.intents), _intent_ids(battle_b.intents), "same seed, same intents")

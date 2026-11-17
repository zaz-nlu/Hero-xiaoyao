extends "res://tests/test_case.gd"

const Unit = preload("res://core/unit.gd")
const EnemyDef = preload("res://core/enemy_def.gd")
const MartialDef = preload("res://core/martial_def.gd")
const Mastery = preload("res://core/mastery.gd")
const Battle = preload("res://core/battle.gd")


func _stats(speed := 15, skill := 0) -> Dictionary:
	return {
		"power": 10,
		"speed": speed,
		"defense": 0,
		"recovery": 0,
		"skill": skill,
		"mechanism": 0,
	}


func _make_player(foresight_max := 2, stats: Dictionary = {}) -> Variant:
	if stats.is_empty():
		stats = _stats()
	return Unit.make_player("测试", stats, 1000, 1, foresight_max)


func _make_enemy(speed := 10, power := 0, move_count := 3, toughness := 99) -> Variant:
	var moves: Array = []
	for i in range(move_count):
		moves.append({
			"id": "m%d" % i,
			"name": "招式%d" % i,
			"type": "heavy",
			"threat": 20,
			"power": power,
		})
	var d: Variant = EnemyDef.from_dict({
		"id": "enemy",
		"name": "木人",
		"tier": "minion",
		"stats": {
			"power": 0,
			"speed": speed,
			"defense": 0,
			"recovery": 0,
			"skill": 0,
			"mechanism": 0,
		},
		"max_hp": 1000,
		"toughness": toughness,
		"stun_turns": 1,
		"moves": moves,
		"weak_moves": [],
	})
	return Unit.from_enemy(d)


func _martial() -> Variant:
	return MartialDef.from_dict({
		"id": "m",
		"name": "m",
		"power": 1,
		"counters": ["heavy"],
		"initiative": 0,
		"counter_level": 5,
		"advantage_stat": "skill",
		"effects": [],
	})


func _battle(player: Variant, enemies: Array, seed_value := 1) -> Variant:
	return Battle.new(player, enemies, [], Mastery.new(), {}, seed_value, false)


func _intent_ids(intents: Array) -> Array[String]:
	var ids: Array[String] = []
	for raw in intents:
		var move: Dictionary = raw
		ids.append(str(move.get("id", "")))
	return ids


func _known_ids(battle: Variant, enemy_id: String) -> Array:
	var raw: Variant = battle.known_moves.get(enemy_id, [])
	if raw is Array:
		return raw
	return []


func test_no_foresight_keeps_rng_order() -> void:
	var first: Variant = _battle(_make_player(0), [_make_enemy()], 12345)
	var second: Variant = _battle(_make_player(0), [_make_enemy()], 12345)
	for _i in range(6):
		assert_eq(
			_intent_ids(first.intents),
			_intent_ids(second.intents),
			"round %d intents match on the same seed" % first.round
		)
		first.submit({"kind": "probe", "target": 0})
		second.submit({"kind": "probe", "target": 0})


func test_foresight_reveals_next_two_moves() -> void:
	var player: Variant = _make_player(2)
	var enemy: Variant = _make_enemy()
	var b: Variant = _battle(player, [enemy], 7)
	var result: Dictionary = b.submit({"kind": "foresight"})
	assert_true(bool(result["ok"]), "foresight accepted")
	var revealed: Array = b.foreseen(0)
	assert_eq(revealed.size(), 2, "two moves foreseen")
	var first_move: Dictionary = revealed[0]
	var second_move: Dictionary = revealed[1]
	var first_id: String = str(first_move.get("id", ""))
	var second_id: String = str(second_move.get("id", ""))
	assert_eq(str(b.intents[0].get("id", "")), first_id, "round 2 intent is the first foreseen move")
	b.submit({"kind": "probe", "target": 0})
	assert_eq(str(b.intents[0].get("id", "")), second_id, "round 3 intent is the second foreseen move")


func test_foresight_spends_the_action_and_a_point() -> void:
	var player: Variant = _make_player(1)
	var enemy: Variant = _make_enemy()
	var b: Variant = _battle(player, [enemy])
	var hp_before: int = enemy.hp
	var result: Dictionary = b.submit({"kind": "foresight"})
	assert_true(bool(result["ok"]), "foresight accepted")
	assert_eq(enemy.hp, hp_before, "foresight deals no damage")
	assert_eq(player.foresight_points, 0, "one foresight point spent")
	assert_true(b.log.has("R1 act:player foresight"), "foresight is logged")
	var again: Dictionary = b.submit({"kind": "foresight"})
	assert_true(not bool(again["ok"]), "no points means no foresight")
	assert_true(str(again["error"]).contains("foresight"), "error mentions foresight")
	assert_eq(b.round, 2, "rejected action does not advance the round")


func test_executed_move_becomes_known() -> void:
	var player: Variant = _make_player(0)
	var enemy: Variant = _make_enemy()
	var b: Variant = _battle(player, [enemy])
	var executed_id: String = str(b.intents[0].get("id", ""))
	b.submit({"kind": "probe", "target": 0})
	assert_true(_known_ids(b, "enemy").has(executed_id), "executed move is remembered")


func test_foresight_revealed_moves_become_known() -> void:
	var player: Variant = _make_player(2)
	var enemy: Variant = _make_enemy()
	var b: Variant = _battle(player, [enemy], 3)
	b.submit({"kind": "foresight"})
	for raw in b.foreseen(0):
		var move: Dictionary = raw
		assert_true(_known_ids(b, "enemy").has(str(move.get("id", ""))), "revealed move is remembered")
	assert_true(b.is_move_known(0), "foreseen intent is recognized")


func test_known_moves_are_shared_between_battles() -> void:
	var player_a: Variant = _make_player(0)
	var enemy_a: Variant = _make_enemy()
	var first: Variant = _battle(player_a, [enemy_a], 99)
	first.submit({"kind": "probe", "target": 0})
	var shared: Dictionary = first.known_moves
	assert_true(not shared.is_empty(), "first battle recorded a move")
	var player_b: Variant = _make_player(0)
	var enemy_b: Variant = _make_enemy()
	var second: Variant = _battle(player_b, [enemy_b], 99)
	second.known_moves = shared
	assert_true(second.is_move_known(0), "shared knowledge applies immediately")


func _perfect_setup() -> Array:
	var player: Variant = Unit.make_player("测试", _stats(15, 20), 1000, 1, 1)
	var enemy: Variant = _make_enemy(10, 0, 1, 2)
	enemy.weak_moves = ["m0"]
	var martials := {"m": _martial()}
	var mastery: Variant = Mastery.new()
	mastery.learn("m")
	var b: Variant = Battle.new(player, [enemy], ["m"], mastery, martials, 1, false)
	return [player, b]


func test_perfect_counter_restores_a_foresight_point() -> void:
	var setup: Array = _perfect_setup()
	var player: Variant = setup[0]
	var b: Variant = setup[1]
	b.submit({"kind": "foresight"})
	assert_eq(player.foresight_points, 0, "foresight spent the only point")
	b.submit({"kind": "martial", "id": "m", "target": 0})
	assert_eq(player.foresight_points, 1, "perfect counter restores one point")


func test_perfect_counter_does_not_exceed_foresight_max() -> void:
	var setup: Array = _perfect_setup()
	var player: Variant = setup[0]
	var b: Variant = setup[1]
	assert_eq(player.foresight_points, 1, "points start full")
	b.submit({"kind": "martial", "id": "m", "target": 0})
	assert_eq(player.foresight_points, 1, "points never exceed the maximum")


func test_stunned_enemy_keeps_its_queue() -> void:
	var player: Variant = _make_player(2)
	var enemy: Variant = _make_enemy()
	enemy.stun_left = 2
	var b: Variant = _battle(player, [enemy], 5)
	var result: Dictionary = b.submit({"kind": "foresight"})
	assert_true(bool(result["ok"]), "foresight accepted while the enemy is stunned")
	var revealed: Array = b.foreseen(0)
	assert_eq(revealed.size(), 2, "queue is kept while the enemy is stunned")
	var first_move: Dictionary = revealed[0]
	var first_id: String = str(first_move.get("id", ""))
	b.submit({"kind": "probe", "target": 0})
	assert_true(not enemy.is_stunned(), "stun ended")
	assert_eq(str(b.intents[0].get("id", "")), first_id, "first move after the stun is the queue head")

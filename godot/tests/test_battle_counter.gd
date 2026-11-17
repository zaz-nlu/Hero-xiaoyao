extends "res://tests/test_case.gd"

const Unit = preload("res://core/unit.gd")
const EnemyDef = preload("res://core/enemy_def.gd")
const MartialDef = preload("res://core/martial_def.gd")
const Mastery = preload("res://core/mastery.gd")
const Battle = preload("res://core/battle.gd")
const Counter = preload("res://core/counter.gd")


func _stats() -> Dictionary:
	return {
		"power": 10,
		"speed": 15,
		"defense": 0,
		"recovery": 0,
		"skill": 20,
		"constitution": 0,
	}


func _make_player(hp := 1000, jianyi_max := 1) -> Variant:
	return Unit.make_player("测试", _stats(), hp, jianyi_max)


func _make_enemy(speed := 10, defense := 0, move_type := "heavy", toughness := 2) -> Variant:
	var moves: Array = [{
		"id": "m1",
		"name": "重击",
		"type": move_type,
		"threat": 20,
		"power": 10,
	}]
	var d: Variant = EnemyDef.from_dict({
		"id": "enemy",
		"name": "木人",
		"tier": "minion",
		"stats": {
			"power": 0,
			"speed": speed,
			"defense": defense,
			"recovery": 0,
			"skill": 0,
			"constitution": 0,
		},
		"max_hp": 1000,
		"toughness": toughness,
		"stun_turns": 1,
		"moves": moves,
		"weak_moves": [],
	})
	return Unit.from_enemy(d)


func _martial(effects: Array = []) -> Variant:
	return MartialDef.from_dict({
		"id": "m",
		"name": "m",
		"power": 1,
		"counters": ["heavy"],
		"initiative": 0,
		"counter_level": 5,
		"advantage_stat": "skill",
		"effects": effects,
	})


func _setup(player: Variant, enemy: Variant, first_strike := false, effects: Array = []) -> Variant:
	var martials := {"m": _martial(effects)}
	var mastery: Variant = Mastery.new()
	mastery.learn("m")
	return Battle.new(player, [enemy], ["m"], mastery, martials, 1, first_strike)


func _first_log_index(lines: Array[String], prefix: String) -> int:
	for i in range(lines.size()):
		if lines[i].begins_with(prefix):
			return i
	return -1


func _log_verdict(lines: Array[String], prefix: String) -> String:
	for line in lines:
		if not line.begins_with(prefix):
			continue
		var marker := "verdict="
		var at: int = line.find(marker)
		if at < 0:
			continue
		var rest: String = line.substr(at + marker.length())
		var space: int = rest.find(" ")
		if space >= 0:
			return rest.substr(0, space)
		return rest
	return ""


func test_advantage_counter_negates_damage_and_costs_one_toughness() -> void:
	var player: Variant = _make_player()
	var enemy: Variant = _make_enemy(10)
	var b: Variant = _setup(player, enemy)
	var result: Dictionary = b.submit({"kind": "martial", "id": "m", "target": 0})
	assert_true(bool(result["ok"]), "martial accepted")
	assert_eq(player.hp, 1000, "advantage counter negates incoming damage")
	assert_near(enemy.toughness_left, 1.0, 0.0001, "advantage costs one toughness")


func test_two_counters_stun_enemy_and_next_round_it_skips() -> void:
	var player: Variant = _make_player()
	var enemy: Variant = _make_enemy(10, 5)
	var b: Variant = _setup(player, enemy)
	b.submit({"kind": "martial", "id": "m", "target": 0})
	b.submit({"kind": "martial", "id": "m", "target": 0})
	assert_true(enemy.is_stunned(), "two advantage counters stun the enemy")
	assert_eq(b.round, 3, "third round begins")
	var intent: Dictionary = b.intents[0]
	assert_true(intent.is_empty(), "stunned enemy has no intent in round 3")
	var hp_before: int = enemy.hp
	b.submit({"kind": "martial", "id": "m", "target": 0})
	assert_true(_first_log_index(b.log, "R3 skip:e0") >= 0, "stunned enemy skips in round 3")
	# 武学威力 1 + 力量 10，1 级熟练度倍率 1.04 → floori(11.04) = 11；暴击 ×1.5 → 16，晕眩时无视防御 5。
	assert_eq(hp_before - enemy.hp, 16, "stunned enemy takes crit damage with defense ignored")


func test_barely_counter_half_damage_half_toughness() -> void:
	var player: Variant = _make_player()
	var enemy: Variant = _make_enemy(30)
	var b: Variant = _setup(player, enemy)
	b.submit({"kind": "martial", "id": "m", "target": 0})
	assert_eq(player.hp, 995, "barely counter halves the incoming damage")
	assert_near(enemy.toughness_left, 1.5, 0.0001, "barely costs half toughness")


func test_impossible_takes_full_damage() -> void:
	var player: Variant = _make_player()
	var enemy: Variant = _make_enemy(10, 0, "sweep")
	var b: Variant = _setup(player, enemy)
	b.submit({"kind": "martial", "id": "m", "target": 0})
	assert_eq(player.hp, 990, "full damage when the move cannot be countered")
	assert_near(enemy.toughness_left, 2.0, 0.0001, "no toughness lost without a counter")


func test_perfect_counter_costs_two_and_counterattacks() -> void:
	var player: Variant = _make_player()
	var enemy: Variant = _make_enemy(10)
	enemy.weak_moves = ["m1"]
	var b: Variant = _setup(player, enemy)
	var hp_before: int = enemy.hp
	b.submit({"kind": "martial", "id": "m", "target": 0})
	assert_true(enemy.is_stunned(), "perfect counter spends two toughness and stuns")
	var one_hit: int = floori(1 * 1.04 + 10)
	assert_true(hp_before - enemy.hp > one_hit, "perfect counter adds a second hit")


func test_advantage_counter_restores_jianyi() -> void:
	var player: Variant = _make_player()
	var enemy: Variant = _make_enemy(10)
	var b: Variant = _setup(player, enemy)
	var first: Dictionary = b.submit({"kind": "jianyi", "target": 0})
	assert_true(bool(first["ok"]), "jianyi accepted")
	assert_eq(player.jianyi_points, 0, "jianyi point spent")
	b.submit({"kind": "martial", "id": "m", "target": 0})
	assert_eq(player.jianyi_points, 1, "advantage counter restores one jianyi point")


func test_barely_counter_does_not_restore_jianyi() -> void:
	var player: Variant = _make_player()
	var enemy: Variant = _make_enemy(30)
	var b: Variant = _setup(player, enemy)
	var first: Dictionary = b.submit({"kind": "jianyi", "target": 0})
	assert_true(bool(first["ok"]), "jianyi accepted")
	assert_eq(player.jianyi_points, 0, "jianyi point spent")
	b.submit({"kind": "martial", "id": "m", "target": 0})
	assert_eq(player.jianyi_points, 0, "barely counter does not restore jianyi")


func test_reflect_effect_returns_damage() -> void:
	var player: Variant = _make_player()
	var enemy: Variant = _make_enemy(10)
	var b: Variant = _setup(player, enemy, false, [{"kind": "reflect", "value": 0.3}])
	var hp_before: int = enemy.hp
	b.submit({"kind": "martial", "id": "m", "target": 0})
	# 武学本身 floori(1 * 1.04 + 10) = 11，反伤 floori(10 * 0.3) = 3。
	assert_eq(hp_before - enemy.hp, 14, "martial hit plus reflect damage")


func test_mastery_exp_gained() -> void:
	var player: Variant = _make_player()
	var enemy: Variant = _make_enemy(10, 0, "heavy", 99)
	var b: Variant = _setup(player, enemy)
	# learn() 后经验为 5；每次使用武学 +1、反制成功再 +2，共 +3/回合。
	for i in range(3):
		b.submit({"kind": "martial", "id": "m", "target": 0})
	assert_eq(b.mastery.level("m"), 1, "14 exp is still level 1")
	b.submit({"kind": "martial", "id": "m", "target": 0})
	assert_eq(b.mastery.level("m"), 2, "17 exp reaches level 2")


func test_preview_matches_resolution() -> void:
	var advantage_enemy: Variant = _make_enemy(10)
	var advantage_battle: Variant = _setup(_make_player(), advantage_enemy)
	assert_eq(advantage_battle.preview("m", 0), Counter.Verdict.ADVANTAGE, "fast enough for advantage")
	advantage_battle.submit({"kind": "martial", "id": "m", "target": 0})
	assert_eq(
		_log_verdict(advantage_battle.log, "R1 act:e0"),
		str(Counter.Verdict.find_key(Counter.Verdict.ADVANTAGE)),
		"advantage preview matches the log"
	)

	var barely_enemy: Variant = _make_enemy(30)
	var barely_battle: Variant = _setup(_make_player(), barely_enemy)
	assert_eq(barely_battle.preview("m", 0), Counter.Verdict.BARELY, "slow enough for barely")
	barely_battle.submit({"kind": "martial", "id": "m", "target": 0})
	assert_eq(
		_log_verdict(barely_battle.log, "R1 act:e0"),
		str(Counter.Verdict.find_key(Counter.Verdict.BARELY)),
		"barely preview matches the log"
	)

	var impossible_enemy: Variant = _make_enemy(10, 0, "sweep")
	var impossible_battle: Variant = _setup(_make_player(), impossible_enemy)
	assert_eq(impossible_battle.preview("m", 0), Counter.Verdict.IMPOSSIBLE, "wrong move type is impossible")
	impossible_battle.submit({"kind": "martial", "id": "m", "target": 0})
	assert_eq(
		_log_verdict(impossible_battle.log, "R1 act:e0"),
		str(Counter.Verdict.find_key(Counter.Verdict.IMPOSSIBLE)),
		"impossible preview matches the log"
	)


func test_preview_impossible_when_no_intent() -> void:
	var player: Variant = _make_player()
	var enemy: Variant = _make_enemy(10)
	enemy.stun_left = 1
	var b: Variant = _setup(player, enemy)
	assert_eq(b.preview("m", 0), Counter.Verdict.IMPOSSIBLE, "no intent means no counter")


func test_first_strike_counter_only_round_one() -> void:
	var player: Variant = _make_player()
	var enemy: Variant = _make_enemy(30)
	var b: Variant = _setup(player, enemy, true)
	assert_eq(b.preview("m", 0), Counter.Verdict.ADVANTAGE, "first strike upgrades round 1 to advantage")
	b.submit({"kind": "martial", "id": "m", "target": 0})
	assert_eq(_log_verdict(b.log, "R1 act:e0"), "ADVANTAGE", "round 1 is an advantage")
	b.submit({"kind": "martial", "id": "m", "target": 0})
	assert_eq(_log_verdict(b.log, "R2 act:e0"), "BARELY", "round 2 falls back to barely")

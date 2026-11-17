extends "res://tests/test_case.gd"

const GameState = preload("res://core/game_state.gd")
const Prefight = preload("res://core/prefight.gd")
const Simulator = preload("res://core/simulator.gd")


func test_damage_stays_in_the_target_band_for_every_bandit_count() -> void:
	for bandit_count in range(2, 6):
		var result: Dictionary = Prefight.simulate(bandit_count)
		var damage: int = int(result.get("boss_damage", -1))
		assert_true(
			damage >= 88 and damage <= 112,
			"bandit_count=%d deals %d (want 88..112)" % [bandit_count, damage]
		)
		assert_true(int(result.get("rounds", 0)) > 0, "the sim runs at least one round")
		assert_true(int(result.get("sister_hp", -1)) >= 0, "the sister has hp left")
		var raw_log: Variant = result.get("log", [])
		assert_true(raw_log is Array, "the sim returns a log")
		if raw_log is Array:
			assert_true(not (raw_log as Array).is_empty(), "the log is not empty")


func test_the_same_bandit_count_is_deterministic() -> void:
	for bandit_count in range(2, 6):
		var first: Dictionary = Prefight.simulate(bandit_count)
		var second: Dictionary = Prefight.simulate(bandit_count)
		assert_eq(
			str(first), str(second),
			"bandit_count=%d returns the same result twice" % bandit_count
		)


func test_the_simulation_never_damages_bandits() -> void:
	var result: Dictionary = Prefight.simulate(5)
	# 弟子打马匪只用于叙述：结果里没有任何马匪损失，马匪在战斗里仍然是满血。
	assert_true(not result.has("bandit_hp"), "no bandit hp is reported")
	assert_true(not result.has("bandit_damage"), "no bandit damage is reported")
	assert_true(not result.has("bandit_hp_loss"), "no bandit hp loss is reported")
	assert_true(int(result.get("disciples_alive", -1)) >= 0, "the disciples are counted")


func test_battle_view_applies_the_boss_wound_once() -> void:
	GameState.reset()
	GameState.boss_hp_loss = 100
	GameState.encounter_group = [
		{"id": "ma_youwei", "count": 1},
		{"id": "bandit", "count": 1},
	]
	var view: Variant = load("res://ui/battle_view.gd").new()
	view.build_ui()
	view.start("ma_youwei", 1, false, false)
	assert_eq(int(view.battle.enemies.size()), 2, "the mixed group is built")
	if view.battle.enemies.size() == 2:
		var boss: Variant = view.battle.enemies[0]
		var bandit: Variant = view.battle.enemies[1]
		assert_eq(str(boss.id), "ma_youwei", "the boss comes first")
		assert_eq(int(boss.max_hp), 295, "the boss keeps its full maximum")
		assert_eq(int(boss.hp), int(boss.max_hp) - 100, "the prefight wound is applied")
		assert_eq(int(bandit.hp), int(bandit.max_hp), "bandits stay at full health")
		assert_eq(int(bandit.max_hp), 55, "a bandit keeps its full 55 hp")
	assert_eq(GameState.boss_hp_loss, 0, "the wound is spent after one battle")
	assert_eq(GameState.encounter_group.size(), 0, "the encounter group is consumed")
	view.free()
	GameState.reset()


func test_simulator_accepts_a_boss_hp_loss() -> void:
	GameState.reset()
	var result: Dictionary = Simulator.run({
		"enemy_id": "ma_youwei",
		"enemy_count": 1,
		"battles": 1,
		"seed": 7,
		"bot": "smart",
		"first_strike": false,
		"boss_hp_loss": 294,
	})
	assert_eq(int(result.get("wins", 0)), 1, "a boss left at 1 hp goes down")
	assert_eq(int(result.get("losses", -1)), 0, "the player does not lose to it")
	GameState.reset()

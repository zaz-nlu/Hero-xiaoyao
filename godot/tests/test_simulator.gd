extends "res://tests/test_case.gd"

const Simulator = preload("res://tools/simulator.gd")
const EnemyDef = preload("res://core/enemy_def.gd")


func _config(overrides: Dictionary = {}) -> Dictionary:
	var base: Dictionary = {
		"enemy_id": "bandit",
		"enemy_count": 1,
		"battles": 20,
		"seed": 1,
		"bot": "smart",
		"first_strike": false,
	}
	for key in overrides.keys():
		base[key] = overrides[key]
	return base


func test_same_seed_same_result() -> void:
	var config: Dictionary = _config({"battles": 20})
	var first: Dictionary = Simulator.run(config)
	var second: Dictionary = Simulator.run(config)
	assert_eq(first, second, "same config yields the same result")


func test_counts_add_up() -> void:
	var battles := 20
	var result: Dictionary = Simulator.run(_config({"battles": battles}))
	var total: int = int(result["wins"]) + int(result["losses"]) + int(result["timeouts"])
	assert_eq(total, battles, "wins + losses + timeouts equals battles")
	assert_eq(int(result["wins"]) + int(result["losses"]), battles - int(result["timeouts"]), "timeouts are the remainder")


func test_smart_bot_beats_minions_often() -> void:
	var result: Dictionary = Simulator.run(_config({
		"enemy_id": "bandit",
		"bot": "smart",
		"battles": 50,
	}))
	assert_true(float(result["win_rate"]) >= 0.8, "smart bot wins at least 80% against bandits")


func test_smart_is_not_worse_than_random_on_boss() -> void:
	var smart: Dictionary = Simulator.run(_config({
		"enemy_id": "ma_youwei",
		"bot": "smart",
		"battles": 30,
	}))
	var random: Dictionary = Simulator.run(_config({
		"enemy_id": "ma_youwei",
		"bot": "random",
		"battles": 30,
	}))
	assert_true(
		float(smart["win_rate"]) >= float(random["win_rate"]),
		"smart win rate %.2f is not below random %.2f" % [float(smart["win_rate"]), float(random["win_rate"])]
	)


func test_stalemate_reports_timeout_not_hang() -> void:
	var wall: Variant = EnemyDef.from_dict({
		"id": "wall",
		"name": "石墙",
		"tier": "minion",
		"stats": {
			"power": 0,
			"speed": 0,
			"defense": 0,
			"recovery": 100,
			"skill": 0,
			"constitution": 0,
		},
		"max_hp": 100000,
		"toughness": 99,
		"stun_turns": 1,
		"incorporeal": true,
		"moves": [
			{"id": "wall_sweep", "name": "横扫", "type": "sweep", "threat": 0, "power": 0},
		],
		"weak_moves": [],
	})
	var result: Dictionary = Simulator.run(_config({
		"enemy_id": "wall",
		"battles": 2,
		"bot": "smart",
		"enemy_defs": {"wall": wall},
	}))
	assert_eq(int(result["timeouts"]), 2, "a stalemate ends as a timeout instead of hanging")
	assert_eq(int(result["wins"]), 0, "the wall cannot be killed in time")
	assert_eq(int(result["losses"]), 0, "the wall cannot kill the player")


func test_first_strike_flag_runs() -> void:
	var battles := 5
	var result: Dictionary = Simulator.run(_config({
		"enemy_id": "bandit",
		"bot": "smart",
		"battles": battles,
		"first_strike": true,
	}))
	var total: int = int(result["wins"]) + int(result["losses"]) + int(result["timeouts"])
	assert_eq(total, battles, "first strike battles are all accounted for")

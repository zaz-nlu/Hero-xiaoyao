extends "res://tests/test_case.gd"

const DataLoader = preload("res://core/data_loader.gd")
const GameState = preload("res://core/game_state.gd")
const TacticsSim = preload("res://tools/tactics_sim.gd")

const BALANCE_PATH := "res://data/tactics_balance.json"
const STAT_KEYS: Array[String] = ["power", "speed", "defense", "recovery", "skill", "constitution"]
const EXPECTED_SUMS := {"initial": 37, "mid": 44, "trained": 50}
const TARGET_KEYS: Array[String] = ["win_min", "win_max", "hp_min", "hp_max"]


func _balance() -> Dictionary:
	var text := FileAccess.get_file_as_string(BALANCE_PATH)
	if text == "":
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {}
	var data: Dictionary = parsed
	return data


func _player_stats() -> Dictionary:
	var player: Dictionary = DataLoader.load_player(DataLoader.PLAYER_PATH)
	var stats: Dictionary = player.get("stats", {})
	return stats


func _profile_stats(profile: Dictionary) -> Dictionary:
	if profile.is_empty():
		return _player_stats()
	return profile


func _sum_stats(stats: Dictionary) -> int:
	var total := 0
	for key in STAT_KEYS:
		total += int(stats.get(key, 0))
	return total


func _count_units(battle, base_id: String) -> int:
	var count := 0
	for entry in battle.units:
		if entry.unit != null and str(entry.unit.id) == base_id:
			count += 1
	return count


func test_balance_profiles_match_table() -> void:
	var balance := _balance()
	assert_true(not balance.is_empty(), "tactics_balance.json parses")
	var profiles: Dictionary = balance.get("profiles", {})
	for profile_name in EXPECTED_SUMS.keys():
		assert_true(profiles.has(profile_name), "profile '%s' exists" % str(profile_name))
	for raw_name in profiles.keys():
		var profile_name := str(raw_name)
		var profile: Dictionary = profiles[raw_name]
		var expected := int(EXPECTED_SUMS.get(profile_name, -1))
		assert_true(expected >= 0, "profile '%s' is a known preset" % profile_name)
		assert_eq(
			_sum_stats(_profile_stats(profile)), expected,
			"profile '%s' six-stat sum" % profile_name)
		if profile.is_empty():
			assert_eq(profile_name, "initial", "only 'initial' may inherit player.json")
			continue
		for key in STAT_KEYS:
			assert_true(profile.has(key), "profile '%s' has '%s'" % [profile_name, key])


func test_scenarios_reference_profiles() -> void:
	var balance := _balance()
	var scenarios: Dictionary = balance.get("scenarios", {})
	var profiles: Dictionary = balance.get("profiles", {})
	for scenario_name in ["unprepared", "half", "prepared"]:
		assert_true(scenarios.has(scenario_name), "scenario '%s' exists" % scenario_name)
		var entry: Dictionary = scenarios.get(scenario_name, {})
		assert_true(
			profiles.has(str(entry.get("profile", ""))),
			"scenario '%s' references an existing profile" % scenario_name)
		assert_true(
			entry.has("bandits") and int(entry.get("bandits", -1)) >= 0,
			"scenario '%s' has a non-negative bandit count" % scenario_name)
		assert_true(
			entry.has("boss_loss") and int(entry.get("boss_loss", -1)) >= 0,
			"scenario '%s' has a non-negative boss loss" % scenario_name)


func test_targets_are_valid_ranges() -> void:
	var balance := _balance()
	var targets: Dictionary = balance.get("targets", {})
	var scenarios: Dictionary = balance.get("scenarios", {})
	for scenario_name in scenarios.keys():
		assert_true(targets.has(scenario_name), "targets cover '%s'" % scenario_name)
		var per_bot: Dictionary = targets.get(scenario_name, {})
		for bot_mode in ["best", "never"]:
			assert_true(per_bot.has(bot_mode), "'%s' has a '%s' target" % [scenario_name, bot_mode])
			var target: Dictionary = per_bot.get(bot_mode, {})
			assert_true(not target.is_empty(), "'%s/%s' target is not empty" % [scenario_name, bot_mode])
			for raw_key in target.keys():
				var key := str(raw_key)
				assert_true(TARGET_KEYS.has(key), "target key '%s' is known" % key)
				var value := float(target[raw_key])
				assert_true(
					value >= 0.0 and value <= 100.0,
					"'%s/%s' target '%s' is a percentage" % [scenario_name, bot_mode, key])
			if target.has("win_min") and target.has("win_max"):
				assert_true(
					float(target["win_min"]) <= float(target["win_max"]),
					"'%s/%s' win range is ordered" % [scenario_name, bot_mode])
			if target.has("hp_min") and target.has("hp_max"):
				assert_true(
					float(target["hp_min"]) <= float(target["hp_max"]),
					"'%s/%s' hp range is ordered" % [scenario_name, bot_mode])


func test_scenario_battle_matches_profile_and_wound() -> void:
	GameState.reset()
	var balance := _balance()
	var scenarios: Dictionary = balance.get("scenarios", {})
	var profiles: Dictionary = balance.get("profiles", {})
	for scenario_name in ["unprepared", "half", "prepared"]:
		var built: Dictionary = TacticsSim.build_scenario_battle(balance, scenario_name, {}, 1)
		assert_true(
			bool(built.get("ok", false)),
			"build '%s': %s" % [scenario_name, str(built.get("errors", []))])
		if not bool(built.get("ok", false)):
			continue
		var battle: Variant = built["battle"]
		var entry: Dictionary = scenarios[scenario_name]
		var profile_name := str(entry.get("profile", ""))
		var profile: Dictionary = profiles.get(profile_name, {})
		var expected_sum := _sum_stats(_profile_stats(profile))
		assert_eq(
			_count_units(battle, "bandit"), int(entry.get("bandits", 0)),
			"'%s' spawns the configured bandits" % scenario_name)
		var hero = battle.get_unit("player")
		assert_true(hero != null, "'%s' has a player unit" % scenario_name)
		if hero != null:
			assert_eq(
				_sum_stats(hero.unit.stats), expected_sum,
				"'%s' player stats match profile '%s'" % [scenario_name, profile_name])
		var boss = battle.get_unit("ma_youwei")
		assert_true(boss != null, "'%s' has the boss unit" % scenario_name)
		if boss != null:
			assert_eq(
				int(boss.unit.hp),
				maxi(1, int(boss.unit.max_hp) - int(entry.get("boss_loss", 0))),
				"'%s' boss starts wounded by boss_loss" % scenario_name)


func test_report_runs_all_scenarios() -> void:
	GameState.reset()
	var report: Dictionary = TacticsSim.run_report({"scenario": "all", "runs": 2, "seed": 1})
	assert_true(
		bool(report.get("ok", false)),
		"report runs: %s" % str(report.get("errors", [])))
	var rows: Array = report.get("rows", [])
	assert_eq(rows.size(), 6, "three scenarios x best/never")
	var lines: Array = report.get("lines", [])
	assert_eq(lines.size(), 7, "six table rows plus the pass summary")
	for row in rows:
		assert_true(row.has("win_rate"), "row has a win rate")
		assert_true(row.has("pass"), "row is judged against its target")

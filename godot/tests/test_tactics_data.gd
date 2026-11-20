extends "res://tests/test_case.gd"

const DataLoader = preload("res://core/data_loader.gd")
const MapLoader = preload("res://core/tactics/map_loader.gd")
const StatsRules = preload("res://core/tactics/stats_rules.gd")

const SHAPES: Array[String] = ["melee", "line", "ranged", "cone", "burst"]


func test_martials_have_normalized_ranges() -> void:
	var result: Dictionary = DataLoader.load_martials("res://data/martials.json")
	assert_eq(result["errors"].size(), 0, "the shipped martials file is valid")
	var defs: Dictionary = result["defs"]
	assert_eq(defs.size(), 14, "fourteen martials load")
	for martial_id in defs.keys():
		var martial: Variant = defs[martial_id]
		assert_true(martial.range is Dictionary, "martial '%s' has a range dictionary" % str(martial_id))
		assert_true(
			SHAPES.has(str(martial.range.get("shape", ""))),
			"martial '%s' has a valid shape" % str(martial_id)
		)
	assert_eq(defs["basic_sword"].range["shape"], "melee")
	assert_eq(int(defs["basic_sword"].range["max"]), 1)
	assert_eq(defs["qingyun"].range["shape"], "line")
	assert_eq(int(defs["qingyun"].range["max"]), 2)
	assert_eq(defs["huifeng"].range["shape"], "cone")
	assert_eq(int(defs["huifeng"].range["max"]), 3)
	assert_eq(defs["liuxing"].range["shape"], "ranged")
	assert_eq(int(defs["liuxing"].range["min"]), 2)
	assert_eq(int(defs["liuxing"].range["max"]), 5)
	assert_eq(defs["jueshi"].range["shape"], "line")
	assert_eq(int(defs["jueshi"].range["max"]), 3)
	assert_eq(bool(defs["jueshi"].range["pierce"]), true)


func test_enemies_have_ranges_and_ai() -> void:
	var result: Dictionary = DataLoader.load_enemies("res://data/enemies.json")
	assert_eq(result["errors"].size(), 0, "the shipped enemies file is valid")
	var defs: Dictionary = result["defs"]
	for enemy_id in defs.keys():
		var enemy: Variant = defs[enemy_id]
		for move in enemy.moves:
			assert_true(move["range"] is Dictionary, "move '%s' has a range" % str(move["id"]))
			assert_true(
				SHAPES.has(str(move["range"].get("shape", ""))),
				"move '%s' has a valid shape" % str(move["id"])
			)
	var bandit: Variant = defs["bandit"]
	assert_eq(bandit.ai, "rush")
	assert_eq(bandit.moves[0]["range"]["shape"], "melee")
	assert_eq(int(bandit.moves[0]["range"]["max"]), 1)
	var scout: Variant = defs["bandit_scout"]
	assert_eq(scout.ai, "archer")
	assert_eq(scout.moves[1]["range"]["shape"], "ranged")
	assert_eq(int(scout.moves[1]["range"]["min"]), 2)
	assert_eq(int(scout.moves[1]["range"]["max"]), 4)
	var boss: Variant = defs["ma_youwei"]
	assert_eq(boss.ai, "boss")
	assert_eq(boss.moves[0]["range"]["shape"], "line")
	assert_eq(int(boss.moves[0]["range"]["max"]), 2)
	assert_eq(boss.moves[1]["range"]["shape"], "cone")
	assert_eq(int(boss.moves[1]["range"]["max"]), 2)
	assert_eq(defs["disciple_spar"].ai, "rush")


func test_enemy_range_defaults_by_type() -> void:
	var json := '[{"id":"a","name":"甲","tier":"minion",' \
			+ '"stats":{"power":4,"speed":8,"defense":3,"recovery":1,"skill":3,"constitution":1},' \
			+ '"toughness":2,"stun_turns":1,"moves":[' \
			+ '{"id":"m1","name":"砍","type":"sweep","threat":10,"power":6},' \
			+ '{"id":"m2","name":"掷","type":"ranged","threat":10,"power":6}],' \
			+ '"weak_moves":[]}]'
	var result: Dictionary = DataLoader.parse_enemies(json)
	assert_eq(result["errors"].size(), 0, "moves without range are accepted")
	var enemy: Variant = result["defs"]["a"]
	assert_eq(enemy.moves[0]["range"]["shape"], "melee")
	assert_eq(int(enemy.moves[0]["range"]["min"]), 1)
	assert_eq(int(enemy.moves[0]["range"]["max"]), 1)
	assert_eq(enemy.moves[1]["range"]["shape"], "ranged")
	assert_eq(int(enemy.moves[1]["range"]["min"]), 2)
	assert_eq(int(enemy.moves[1]["range"]["max"]), 4)
	assert_eq(enemy.ai, "rush", "ai defaults to rush")
	assert_eq(enemy.move_override, -1, "move defaults to the speed formula")


func test_martial_range_defaults_to_melee() -> void:
	var json := '[{"id":"a","name":"甲","power":10,"counters":["heavy"],"initiative":0,' \
			+ '"counter_level":2,"advantage_stat":"skill","effects":[]}]'
	var result: Dictionary = DataLoader.parse_martials(json)
	assert_eq(result["errors"].size(), 0, "a martial without range is accepted")
	var martial: Variant = result["defs"]["a"]
	assert_eq(martial.range["shape"], "melee")
	assert_eq(int(martial.range["min"]), 1)
	assert_eq(int(martial.range["max"]), 1)


func test_stats_rules_boundaries() -> void:
	assert_eq(StatsRules.move_range(8), 3)
	assert_eq(StatsRules.move_range(50), 8)
	assert_eq(StatsRules.move_range(100), 8)
	assert_eq(StatsRules.max_climb(0), 1)
	assert_eq(StatsRules.max_climb(29), 1)
	assert_eq(StatsRules.max_climb(30), 2)
	assert_eq(StatsRules.reaction_points(12), 1)
	assert_eq(StatsRules.reaction_points(17), 2)
	assert_eq(StatsRules.reaction_points(50), 4)
	assert_near(StatsRules.height_bonus(2, 0), 0.20)
	assert_near(StatsRules.height_bonus(5, 0), 0.30, 0.0001, "height bonus is capped")
	assert_near(StatsRules.height_bonus(0, 2), 0.0)
	assert_near(StatsRules.facing_bonus("back"), 0.50)
	assert_near(StatsRules.facing_bonus("side"), 0.20)
	assert_near(StatsRules.facing_bonus("front"), 0.0)
	assert_eq(StatsRules.React_SLACK, 5)


func test_maps_load() -> void:
	var tavern: Dictionary = MapLoader.load_map("tavern_brawl")
	assert_true(tavern["ok"], "tavern_brawl loads: %s" % str(tavern["errors"]))
	assert_eq(tavern["grid"].width, 10)
	assert_eq(tavern["grid"].height, 8)
	assert_eq(tavern["meta"]["spawns"]["player"].size(), 3)
	assert_eq(tavern["meta"]["spawns"]["enemies"].size(), 8)
	assert_eq(tavern["meta"]["objective"], "defeat_leader")
	for pair in tavern["meta"]["spawns"]["enemies"]:
		var cell := Vector2i(int(pair[0]), int(pair[1]))
		assert_true(tavern["grid"].is_walkable(cell), "enemy spawn %s is walkable" % str(cell))

	var forest: Dictionary = MapLoader.load_map("forest_clearing")
	assert_true(forest["ok"], "forest_clearing loads: %s" % str(forest["errors"]))
	assert_eq(forest["grid"].width, 8)
	assert_eq(forest["grid"].height, 6)
	assert_true(forest["meta"].has("exit"), "the forest map has an exit cell")

	var ids: Array = MapLoader.list_maps()
	assert_true(ids.has("tavern_brawl"), "list_maps finds the tavern")
	assert_true(ids.has("forest_clearing"), "list_maps finds the forest")


func test_map_validation_rejects_bad_data() -> void:
	var bad_rows: Dictionary = MapLoader.parse_map({
		"id": "bad_rows",
		"name": "坏行",
		"width": 3,
		"height": 2,
		"tiles": ["...", ".."],
		"spawns": {"player": [[0, 0]], "enemies": [[2, 1]]},
	})
	assert_true(not bad_rows["ok"])
	assert_true(_errors_contain(bad_rows["errors"], "tiles row 1"), "row length mismatch is reported")

	var bad_spawn: Dictionary = MapLoader.parse_map({
		"id": "bad_spawn",
		"name": "坏出生点",
		"width": 3,
		"height": 2,
		"tiles": ["...", ".#."],
		"spawns": {"player": [[0, 0]], "enemies": [[1, 1]]},
	})
	assert_true(not bad_spawn["ok"])
	assert_true(_errors_contain(bad_spawn["errors"], "not walkable"), "a spawn in a wall is reported")

	var split: Dictionary = MapLoader.parse_map({
		"id": "split",
		"name": "断路",
		"width": 5,
		"height": 1,
		"tiles": ["..#.."],
		"spawns": {"player": [[0, 0]], "enemies": [[4, 0]]},
	})
	assert_true(not split["ok"])
	assert_true(_errors_contain(split["errors"], "not connected"), "disconnected spawns are reported")

	assert_true(not MapLoader.load_map("does_not_exist")["ok"], "a missing map returns ok=false")


func _errors_contain(errors: Array, needle: String) -> bool:
	for message in errors:
		if str(message).contains(needle):
			return true
	return false

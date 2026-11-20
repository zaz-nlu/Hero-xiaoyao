extends "res://tests/test_case.gd"

const DataLoader = preload("res://core/data_loader.gd")
const MoveTypes = preload("res://core/move_types.gd")
const Stats = preload("res://core/stats.gd")

const MARTIALS_PATH := "res://data/martials.json"
const ENEMIES_PATH := "res://data/enemies.json"
const PLAYER_PATH := "res://data/player.json"


func test_content_loads_without_errors() -> void:
	var martials := DataLoader.load_martials(MARTIALS_PATH)
	assert_eq(martials["errors"].size(), 0, "martials load without errors")
	var enemies := DataLoader.load_enemies(ENEMIES_PATH)
	assert_eq(enemies["errors"].size(), 0, "enemies load without errors")
	var player := DataLoader.load_player(PLAYER_PATH)
	assert_true(not player.is_empty(), "player loads")


func test_martial_count_between_8_and_10() -> void:
	var defs: Dictionary = DataLoader.load_martials(MARTIALS_PATH)["defs"]
	var count := defs.size()
	assert_true(count >= 8 and count <= 14, "8 to 14 martials (4 are the tutorial-only 御神剑术), got %d" % count)


func test_every_move_type_has_a_counter_martial() -> void:
	var defs: Dictionary = DataLoader.load_martials(MARTIALS_PATH)["defs"]
	for move_type in MoveTypes.ALL:
		var found := false
		for def in defs.values():
			if def.counters.has(move_type):
				found = true
				break
		assert_true(found, "some martial counters '%s'" % move_type)


func test_boss_has_3_or_4_types_and_toughness_8() -> void:
	var defs: Dictionary = DataLoader.load_enemies(ENEMIES_PATH)["defs"]
	assert_true(defs.has("ma_youwei"), "boss ma_youwei exists")
	if not defs.has("ma_youwei"):
		return
	var boss = defs["ma_youwei"]
	var types := {}
	for move in boss.moves:
		types[move["type"]] = true
	var type_count := types.size()
	assert_true(type_count >= 3 and type_count <= 4, "boss has 3 to 4 move types, got %d" % type_count)
	assert_eq(boss.toughness, 8, "boss toughness")
	assert_eq(boss.stun_turns, 2, "boss stun_turns")


func test_bandit_has_1_or_2_types_and_toughness_2() -> void:
	var defs: Dictionary = DataLoader.load_enemies(ENEMIES_PATH)["defs"]
	assert_true(defs.has("bandit"), "bandit exists")
	if not defs.has("bandit"):
		return
	var bandit = defs["bandit"]
	var types := {}
	for move in bandit.moves:
		types[move["type"]] = true
	var type_count := types.size()
	assert_true(type_count >= 1 and type_count <= 2, "bandit has 1 to 2 move types, got %d" % type_count)
	assert_eq(bandit.toughness, 0, "minions have no toughness")
	assert_eq(bandit.stun_turns, 1, "bandit stun_turns")


func test_default_loadout_has_four_learned_martials() -> void:
	var martials: Dictionary = DataLoader.load_martials(MARTIALS_PATH)["defs"]
	var player := DataLoader.load_player(PLAYER_PATH)
	var loadout: Array = player.get("loadout", [])
	var learned: Array = player.get("learned", [])
	assert_eq(loadout.size(), 4, "loadout has four martials")
	for def_id in loadout:
		assert_true(martials.has(str(def_id)), "loadout martial '%s' exists" % str(def_id))
		assert_true(learned.has(def_id), "learned contains '%s'" % str(def_id))


func test_player_stats_total_thirty_seven() -> void:
	var player := DataLoader.load_player(PLAYER_PATH)
	var stats: Dictionary = player.get("stats", {})
	var total := 0
	for key in Stats.KEYS:
		total += int(stats.get(key, 0))
	assert_eq(total, 37, "player stats total 37")


func test_player_default_loadout_covers_boss_types() -> void:
	var martials: Dictionary = DataLoader.load_martials(MARTIALS_PATH)["defs"]
	var enemies: Dictionary = DataLoader.load_enemies(ENEMIES_PATH)["defs"]
	var player := DataLoader.load_player(PLAYER_PATH)
	assert_true(enemies.has("ma_youwei"), "boss ma_youwei exists")
	if not enemies.has("ma_youwei"):
		return
	var covered := {}
	for def_id in player.get("loadout", []):
		if not martials.has(str(def_id)):
			continue
		var def = martials[str(def_id)]
		for counter_type in def.counters:
			covered[counter_type] = true
	for move in enemies["ma_youwei"].moves:
		assert_true(covered.has(move["type"]), "default loadout counters '%s'" % move["type"])

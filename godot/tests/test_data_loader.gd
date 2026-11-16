extends "res://tests/test_case.gd"

const DataLoader = preload("res://core/data_loader.gd")
const Stats = preload("res://core/stats.gd")


func test_valid_martial_loads() -> void:
	var json := '[{"id":"a","name":"甲","power":10,"counters":["heavy"],"initiative":0,' \
			+ '"counter_level":2,"advantage_stat":"skill","effects":[]}]'
	var result := DataLoader.parse_martials(json)
	assert_eq(result["errors"].size(), 0, "valid martial has no errors")
	assert_true(result["defs"].has("a"), "martial a loaded")
	assert_eq(result["defs"]["a"].counters, ["heavy"])
	assert_eq(result["defs"]["a"].power, 10)


func test_martial_with_unknown_type_is_error() -> void:
	var json := '[{"id":"a","name":"甲","power":10,"counters":["fire"],"initiative":0,' \
			+ '"counter_level":2,"advantage_stat":"skill","effects":[]}]'
	var result := DataLoader.parse_martials(json)
	assert_true(result["errors"].size() > 0, "unknown counter type rejected")
	assert_true(_errors_contain(result["errors"], "fire"), "error mentions fire")
	assert_true(not result["defs"].has("a"), "invalid martial not in defs")


func test_martial_with_four_counters_is_error() -> void:
	var json := '[{"id":"a","name":"甲","power":10,' \
			+ '"counters":["heavy","thrust","sweep","combo"],"initiative":0,' \
			+ '"counter_level":2,"advantage_stat":"skill","effects":[]}]'
	var result := DataLoader.parse_martials(json)
	assert_true(result["errors"].size() > 0, "four counters rejected")
	assert_true(not result["defs"].has("a"), "invalid martial not in defs")


func test_minion_with_three_types_is_error() -> void:
	var json := '[{"id":"bandit","name":"马匪","tier":"minion",' \
			+ '"stats":{"power":5,"speed":8,"defense":3,"recovery":1,"skill":3,"mechanism":1},' \
			+ '"max_hp":40,"toughness":2,"stun_turns":1,"moves":[' \
			+ '{"id":"m1","name":"横扫","type":"sweep","threat":12,"power":8},' \
			+ '{"id":"m2","name":"重劈","type":"heavy","threat":14,"power":10},' \
			+ '{"id":"m3","name":"突刺","type":"thrust","threat":10,"power":6}],' \
			+ '"weak_moves":[]}]'
	var result := DataLoader.parse_enemies(json)
	assert_true(result["errors"].size() > 0, "minion with three types rejected")
	assert_true(_errors_contain(result["errors"], "bandit"), "error mentions bandit")
	assert_true(not result["defs"].has("bandit"), "invalid enemy not in defs")


func test_boss_with_two_types_is_error() -> void:
	var json := '[{"id":"ma_youwei","name":"马友为","tier":"boss",' \
			+ '"stats":{"power":20,"speed":12,"defense":8,"recovery":6,"skill":10,"mechanism":4},' \
			+ '"max_hp":300,"toughness":8,"stun_turns":2,"moves":[' \
			+ '{"id":"m1","name":"开山","type":"heavy","threat":18,"power":25},' \
			+ '{"id":"m2","name":"乱刀横扫","type":"sweep","threat":14,"power":16}],' \
			+ '"weak_moves":[]}]'
	var result := DataLoader.parse_enemies(json)
	assert_true(result["errors"].size() > 0, "boss with two types rejected")
	assert_true(_errors_contain(result["errors"], "ma_youwei"), "error mentions ma_youwei")
	assert_true(not result["defs"].has("ma_youwei"), "invalid enemy not in defs")


func test_valid_boss_loads() -> void:
	var json := '[{"id":"ma_youwei","name":"马友为","tier":"boss",' \
			+ '"stats":{"power":20,"speed":12,"defense":8,"recovery":6,"skill":10,"mechanism":4},' \
			+ '"max_hp":300,"toughness":8,"stun_turns":2,"moves":[' \
			+ '{"id":"m1","name":"开山","type":"heavy","threat":18,"power":25},' \
			+ '{"id":"m2","name":"乱刀横扫","type":"sweep","threat":14,"power":16},' \
			+ '{"id":"m3","name":"刺喉","type":"thrust","threat":16,"power":18}],' \
			+ '"weak_moves":["m1"]}]'
	var result := DataLoader.parse_enemies(json)
	assert_eq(result["errors"].size(), 0, "valid boss has no errors")
	assert_true(result["defs"].has("ma_youwei"), "boss loaded")
	assert_eq(result["defs"]["ma_youwei"].tier, "boss")
	assert_eq(result["defs"]["ma_youwei"].weak_moves, ["m1"])
	assert_eq(result["defs"]["ma_youwei"].max_hp, 300)
	assert_eq(result["defs"]["ma_youwei"].moves.size(), 3)
	assert_eq(result["defs"]["ma_youwei"].moves[0]["threat"], 18)


func test_weak_move_must_exist() -> void:
	var json := '[{"id":"ma_youwei","name":"马友为","tier":"boss",' \
			+ '"stats":{"power":20,"speed":12,"defense":8,"recovery":6,"skill":10,"mechanism":4},' \
			+ '"max_hp":300,"toughness":8,"stun_turns":2,"moves":[' \
			+ '{"id":"m1","name":"开山","type":"heavy","threat":18,"power":25},' \
			+ '{"id":"m2","name":"乱刀横扫","type":"sweep","threat":14,"power":16},' \
			+ '{"id":"m3","name":"刺喉","type":"thrust","threat":16,"power":18}],' \
			+ '"weak_moves":["nope"]}]'
	var result := DataLoader.parse_enemies(json)
	assert_true(result["errors"].size() > 0, "unknown weak move rejected")
	assert_true(_errors_contain(result["errors"], "ma_youwei"), "error mentions ma_youwei")
	assert_true(_errors_contain(result["errors"], "nope"), "error mentions weak move id")
	assert_true(not result["defs"].has("ma_youwei"), "invalid enemy not in defs")


func test_top_keys_returns_all_ties() -> void:
	assert_eq(
		Stats.top_keys({"power": 10, "speed": 10, "defense": 5, "recovery": 5, "skill": 5, "mechanism": 5}),
		["power", "speed"],
		"ties are returned in KEYS order"
	)


func test_top_keys_single() -> void:
	assert_eq(
		Stats.top_keys({"power": 3, "speed": 9, "defense": 1, "recovery": 4, "skill": 2, "mechanism": 0}),
		["speed"],
		"single top key"
	)


func _errors_contain(errors: Array, needle: String) -> bool:
	for message in errors:
		if str(message).contains(needle):
			return true
	return false

extends "res://tests/test_case.gd"

const GameState = preload("res://core/game_state.gd")
const Progression = preload("res://core/progression.gd")
const Realms = preload("res://core/realms.gd")


func test_known_realms_load() -> void:
	Realms.reload()
	assert_eq(str(Realms.get_realm("lianti").get("name", "")), "炼体", "lianti name")
	assert_eq(str(Realms.get_realm("renjie").get("name", "")), "人杰", "renjie name")
	assert_near(Realms.scale("renjie"), 2.0, 0.0001, "renjie scale")
	assert_eq(Realms.hp_per_con("diling"), 50, "diling hp per constitution")
	assert_eq(Realms.stage_name(0), "初期", "first stage")
	assert_eq(Realms.stage_name(3), "巅峰", "last stage")


func test_unknown_realm_falls_back_to_lianti() -> void:
	Realms.reload()
	var realm: Dictionary = Realms.get_realm("nope")
	assert_eq(str(realm.get("id", "")), "lianti", "unknown realm falls back to lianti")
	assert_near(Realms.scale("nope"), 1.0, 0.0001, "unknown realm uses lianti scale")
	assert_eq(Realms.hp_per_con("nope"), 15, "unknown realm uses lianti hp per constitution")


func test_max_hp_for_examples() -> void:
	Realms.reload()
	assert_eq(Realms.max_hp_for(4, "lianti"), 100, "炼体体质 4")
	assert_eq(Realms.max_hp_for(50, "banshen"), 5290, "半神体质 50")
	assert_eq(Realms.max_hp_for(40, "jiyi"), 3640, "极意体质 40")


func test_age_bonus_by_milestone() -> void:
	GameState.reset()
	assert_eq(Progression.age_bonus_constitution(), 0, "age 9 is before every milestone")
	GameState.age = 14
	assert_eq(Progression.age_bonus_constitution(), 3, "age 14 grants +3")
	GameState.age = 17
	assert_eq(Progression.age_bonus_constitution(), 6, "age 17 accumulates +6")
	GameState.age = 33
	assert_eq(Progression.age_bonus_constitution(), 18, "age 33 accumulates +18")
	GameState.reset()


func test_reload_and_missing_data_fall_back_to_defaults() -> void:
	Realms.reload()
	assert_eq(Realms.max_hp_for(4, "lianti"), 100, "reload keeps the file values")
	Realms.reload()
	assert_eq(Realms.base_hp(), 40, "missing cache falls back to the built-in base hp")
	assert_eq(Realms.stage_name(-1), "", "out-of-range stage index is empty")
	assert_eq(Realms.stage_name(99), "", "out-of-range stage index is empty")


func test_max_hp_stacks_growth_and_age() -> void:
	GameState.reset()
	Progression.reload_items()
	var base := {
		"power": 10,
		"speed": 15,
		"defense": 5,
		"recovery": 5,
		"skill": 20,
		"constitution": 4,
	}
	assert_eq(Progression.max_hp(base), 100, "constitution 4 at lianti")
	GameState.stat_bonus["constitution"] = 1
	assert_eq(Progression.max_hp(base), 115, "one spent point adds one hp step")
	GameState.age = 14
	assert_eq(Progression.max_hp(base), 160, "age 14 adds three constitution (+45 hp)")
	GameState.reset()

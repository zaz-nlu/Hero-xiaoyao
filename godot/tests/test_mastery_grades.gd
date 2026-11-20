extends "res://tests/test_case.gd"

const Battle = preload("res://core/battle.gd")
const Counter = preload("res://core/counter.gd")
const DataLoader = preload("res://core/data_loader.gd")
const EnemyDef = preload("res://core/enemy_def.gd")
const GameState = preload("res://core/game_state.gd")
const MartialDef = preload("res://core/martial_def.gd")
const Mastery = preload("res://core/mastery.gd")
const Realms = preload("res://core/realms.gd")
const Unit = preload("res://core/unit.gd")


func _stats(speed := 15, skill := 20, power := 0) -> Dictionary:
	return {
		"power": power,
		"speed": speed,
		"defense": 0,
		"recovery": 0,
		"skill": skill,
		"constitution": 0,
	}


func _martial(id: String) -> Variant:
	return MartialDef.from_dict({
		"id": id,
		"name": id,
		"power": 1,
		"counters": ["heavy"],
		"initiative": 0,
		"counter_level": 5,
		"advantage_stat": "skill",
		"effects": [],
	})


func _enemy(exp := 0, hp := 1000, speed := 10, power := 0, threat := 20) -> Variant:
	var def: Variant = EnemyDef.from_dict({
		"id": "enemy",
		"name": "木人",
		"tier": "minion",
		"exp": exp,
		"stats": _stats(speed, 0, 0),
		"max_hp": hp,
		"toughness": 99,
		"stun_turns": 1,
		"moves": [{"id": "m1", "name": "重击", "type": "heavy", "threat": threat, "power": power}],
		"weak_moves": [],
	})
	return Unit.from_enemy(def)


func _counter_battle(enemy_speed: int, weak_moves: Array = []) -> Array:
	var player: Variant = Unit.make_player("测试", _stats(), 1000, 1)
	var enemy: Variant = _enemy(0, 1000, enemy_speed)
	enemy.weak_moves = weak_moves
	var martial: Variant = _martial("m")
	var mastery: Variant = Mastery.new()
	mastery.realm_id = "banshen"
	mastery.learn("m")
	var battle: Variant = Battle.new(player, [enemy], ["m"], mastery, {"m": martial}, 1, false)
	return [battle, mastery]


func test_grade_thresholds_match_the_grade_table() -> void:
	assert_eq(Mastery.grade_per_level("common"), 100, "common levels every 100 exp")
	assert_eq(Mastery.grade_per_level("legendary"), 300, "legendary levels every 300 exp")

	var common: Variant = Mastery.new()
	common.realm_id = "banshen"
	common.add_exp("a", 99)
	assert_eq(common.level("a"), 0, "99 common exp is level zero")
	common.add_exp("a", 1)
	assert_eq(common.level("a"), 1, "100 common exp is level one")
	common.add_exp("a", 199)
	assert_eq(common.level("a"), 2, "299 common exp is level two")

	var legendary: Variant = Mastery.new()
	legendary.realm_id = "banshen"
	legendary.set_grades({"a": "legendary"})
	legendary.add_exp("a", 299)
	assert_eq(legendary.level("a"), 0, "299 legendary exp is level zero")
	legendary.add_exp("a", 1)
	assert_eq(legendary.level("a"), 1, "300 legendary exp is level one")
	legendary.add_exp("a", 600)
	assert_eq(legendary.level("a"), 3, "900 legendary exp is level three")
	legendary.learn("a")
	assert_eq(legendary.exp_of("a"), 900, "learn does not lower legendary exp")


func test_realm_caps_mastery_level() -> void:
	Realms.reload()
	assert_eq(Realms.mastery_cap("lianti"), 5, "炼体 caps mastery at five")
	assert_eq(Realms.mastery_cap("renjie"), 7, "人杰 caps mastery at seven")

	var mastery: Variant = Mastery.new()
	mastery.realm_id = "lianti"
	mastery.add_exp("a", 700)
	assert_eq(mastery.level("a"), 5, "common 700 exp is capped at five in 炼体")
	var progress: Dictionary = Mastery.progress_in_level(700, "common", 5)
	assert_eq(int(progress["level"]), 5, "progress reports the capped level")
	assert_true(bool(progress["capped"]), "progress reports the cap")
	assert_eq(int(progress["need"]), 0, "a capped martial needs no more exp")

	mastery.realm_id = "renjie"
	assert_eq(mastery.level("a"), 7, "the same 700 exp reaches seven in 人杰")


func test_counter_bonus_steps() -> void:
	var mastery: Variant = Mastery.new()
	mastery.realm_id = "banshen"
	mastery.set_grades({"a": "common"})
	mastery.add_exp("a", 200)
	assert_eq(mastery.level("a"), 2, "200 exp is level two")
	assert_eq(mastery.counter_bonus("a"), 0, "level two gives no counter strength")
	mastery.add_exp("a", 100)
	assert_eq(mastery.counter_bonus("a"), 1, "level three gives one")
	mastery.add_exp("a", 600)
	assert_eq(mastery.level("a"), 9, "900 exp is level nine")
	assert_eq(mastery.counter_bonus("a"), 3, "level nine is capped at three")
	mastery.add_exp("a", 100)
	assert_eq(mastery.level("a"), 10, "1000 exp is level ten")
	assert_eq(mastery.counter_bonus("a"), 3, "level ten stays at three")


func test_extra_counter_upgrades_barely_to_advantage() -> void:
	var martial: Variant = _martial("m")
	var stats := _stats(10, 20)
	var move := {"id": "m1", "type": "heavy", "threat": 26}
	assert_eq(
		Counter.evaluate(martial, stats, 10, move, false),
		Counter.Verdict.BARELY,
		"gap -1 is barely"
	)
	assert_eq(
		Counter.evaluate(martial, stats, 10, move, false, 1),
		Counter.Verdict.ADVANTAGE,
		"one point of counter strength reaches gap 0"
	)


func test_counter_success_exp() -> void:
	assert_eq(Mastery.counter_exp("advantage"), 1, "advantage counters give one exp")
	assert_eq(Mastery.counter_exp("perfect"), 2, "perfect counters give two exp")
	assert_eq(Mastery.counter_exp("barely"), 0, "barely counters give no exp")

	var advantage: Array = _counter_battle(10)
	var advantage_battle: Variant = advantage[0]
	advantage_battle.submit({"kind": "martial", "id": "m", "target": 0})
	var advantage_mastery: Variant = advantage_battle.mastery
	assert_eq(advantage_mastery.exp_of("m"), 102, "use +1 and advantage counter +1")

	var perfect: Array = _counter_battle(10, ["m1"])
	var perfect_battle: Variant = perfect[0]
	perfect_battle.submit({"kind": "martial", "id": "m", "target": 0})
	var perfect_mastery: Variant = perfect_battle.mastery
	assert_eq(perfect_mastery.exp_of("m"), 103, "use +1 and perfect counter +2")

	var barely: Array = _counter_battle(30)
	var barely_battle: Variant = barely[0]
	barely_battle.submit({"kind": "martial", "id": "m", "target": 0})
	var barely_mastery: Variant = barely_battle.mastery
	assert_eq(barely_mastery.exp_of("m"), 101, "use +1 and barely counter +0")


func _settle_battle() -> Variant:
	var player: Variant = Unit.make_player("测试", _stats(), 1000, 1)
	var enemies: Array = [_enemy(15, 1, 0), _enemy(15, 1, 0)]
	var martials := {"a": _martial("a"), "b": _martial("b")}
	var mastery: Variant = Mastery.new()
	mastery.realm_id = "banshen"
	mastery.learn("a")
	mastery.learn("b")
	var battle: Variant = Battle.new(player, enemies, ["a", "b"], mastery, martials, 1, false)
	battle.submit({"kind": "martial", "id": "a", "target": 0})
	battle.submit({"kind": "martial", "id": "b", "target": 1})
	return battle


func test_settle_exp_splits_by_usage_and_only_once() -> void:
	var battle: Variant = _settle_battle()
	assert_eq(battle.state(), Battle.State.WON, "both enemies are defeated")
	assert_eq(battle.pending_exp, 30, "two 15 exp enemies are banked")
	battle.uses = {"a": 3, "b": 1}
	var gained: Dictionary = battle.settle_exp()
	assert_eq(int(gained.get("a", 0)), 22, "three quarters of 30 rounds down to 22")
	assert_eq(int(gained.get("b", 0)), 8, "the remaining share goes to the other martial")
	assert_eq(int(gained.get("a", 0)) + int(gained.get("b", 0)), 30, "the whole haul is awarded")
	assert_eq(battle.mastery.exp_of("a"), 101 + 22, "the main martial receives its share")
	assert_eq(battle.mastery.exp_of("b"), 101 + 8, "the secondary martial receives its share")

	var again: Dictionary = battle.settle_exp()
	assert_eq(again, {}, "settling twice awards nothing")
	assert_eq(battle.mastery.exp_of("a"), 123, "a second settle does not change exp")


func test_settle_exp_skips_losses() -> void:
	var player: Variant = Unit.make_player("测试", _stats(), 1, 1)
	var enemy: Variant = _enemy(15, 1000, 30, 100, 100)
	var mastery: Variant = Mastery.new()
	mastery.learn("a")
	var battle: Variant = Battle.new(
		player, [enemy], ["a"], mastery, {"a": _martial("a")}, 1, false
	)
	battle.submit({"kind": "martial", "id": "a", "target": 0})
	assert_eq(battle.state(), Battle.State.LOST, "the player falls")
	var before := int(mastery.exp_of("a"))
	assert_eq(battle.settle_exp(), {}, "a loss awards no kill exp")
	assert_eq(int(mastery.exp_of("a")), before, "the loss leaves exp untouched")


func test_settle_exp_skips_battles_without_martials() -> void:
	var player: Variant = Unit.make_player("测试", _stats(20, 100), 1000, 1)
	var enemy: Variant = _enemy(15, 1)
	var mastery: Variant = Mastery.new()
	var battle: Variant = Battle.new(player, [enemy], [], mastery, {}, 1, false)
	battle.submit({"kind": "jianyi", "target": 0})
	assert_eq(battle.state(), Battle.State.WON, "jianyi wins the fight")
	assert_eq(battle.uses, {}, "jianyi does not count as martial use")
	assert_eq(battle.settle_exp(), {}, "unused martial arts receive no exp")
	assert_eq(mastery.export_exp(), {}, "the mastery stays empty")


func test_battle_view_shows_exp_toast_and_updates_mastery_total() -> void:
	GameState.reset()
	var view: Variant = load("res://features/battle/battle_view.gd").new()
	view.build_ui()
	view.start("bandit", 1, true)
	assert_true(
		view.martial_buttons[0].tooltip_text.contains("品阶"),
		"the martial tooltip names its grade"
	)
	view.battle.enemies[0].hp = 1
	view.press_action({"kind": "martial", "id": "basic_sword", "target": 0})
	assert_eq(int(view.battle.state()), Battle.State.WON, "the weakened bandit falls")
	assert_true(
		GameState.toasts.has("熟练度 基础剑术 +15"),
		"the victory queues a mastery toast: %s" % str(GameState.toasts)
	)
	assert_true(
		int(GameState.mastery_total.get("basic_sword", 0)) >= 115,
		"the persistent mastery total includes the kill exp"
	)
	view.free()
	GameState.reset()


func test_battle_view_announces_level_up() -> void:
	GameState.reset()
	GameState.mastery_total["basic_sword"] = 190
	var view: Variant = load("res://features/battle/battle_view.gd").new()
	view.build_ui()
	view.start("bandit", 1, true)
	view.battle.enemies[0].hp = 1
	view.press_action({"kind": "martial", "id": "basic_sword", "target": 0})
	assert_eq(int(view.battle.state()), Battle.State.WON, "the weakened bandit falls")
	assert_true(
		GameState.toasts.has("基础剑术 升至 Lv.2"),
		"crossing a level queues an upgrade toast: %s" % str(GameState.toasts)
	)
	view.free()
	GameState.reset()


func test_shipped_martials_have_valid_grades() -> void:
	var loaded: Dictionary = DataLoader.load_martials("res://data/martials.json")
	assert_eq(loaded["errors"].size(), 0, "the shipped martial file is valid")
	var defs: Dictionary = loaded["defs"]
	var expected := {
		"basic_sword": "common",
		"parry": "common",
		"sidestep": "common",
		"qingyun": "fine",
		"huifeng": "fine",
		"lianhuan": "fine",
		"taiji": "rare",
		"duanshi": "rare",
		"liuxing": "rare",
		"jueshi": "legendary",
		"yushen_thrust": "legendary",
		"yushen_chop": "legendary",
		"yushen_sweep": "legendary",
		"yushen_point": "legendary",
	}
	assert_eq(defs.size(), expected.size(), "all shipped martials load (10 + 4 tutorial-only)")
	for martial_id in expected.keys():
		assert_true(defs.has(martial_id), "martial '%s' loads" % martial_id)
		if defs.has(martial_id):
			assert_eq(
				str(defs[martial_id].grade), str(expected[martial_id]),
				"martial '%s' has the designed grade" % martial_id
			)


func test_unknown_grade_is_rejected() -> void:
	var json := '[{"id":"a","name":"甲","grade":"mythic","power":10,"counters":["heavy"],' \
			+ '"initiative":0,"counter_level":2,"advantage_stat":"skill","effects":[]}]'
	var result: Dictionary = DataLoader.parse_martials(json)
	assert_true(result["errors"].size() > 0, "an unknown grade is rejected")
	assert_true(not result["defs"].has("a"), "the invalid martial is not loaded")


func test_mastery_json_has_five_grades() -> void:
	var text: String = FileAccess.get_file_as_string("res://data/mastery.json")
	var parsed: Variant = JSON.parse_string(text)
	assert_true(parsed is Dictionary, "mastery.json is an object")
	if not (parsed is Dictionary):
		return
	var data: Dictionary = parsed
	var grades: Dictionary = data.get("grades", {})
	var expected := {
		"common": [100, "普通"],
		"fine": [150, "精良"],
		"rare": [200, "稀有"],
		"epic": [250, "史诗"],
		"legendary": [300, "传说"],
	}
	assert_eq(grades.size(), expected.size(), "all five grades are configured")
	for grade_id in expected.keys():
		assert_true(grades.has(grade_id), "grade '%s' exists" % grade_id)
		if not grades.has(grade_id):
			continue
		var entry: Dictionary = grades[grade_id]
		var values: Array = expected[grade_id]
		assert_eq(int(entry.get("exp_per_level", 0)), int(values[0]), "grade '%s' exp" % grade_id)
		assert_eq(str(entry.get("name", "")), str(values[1]), "grade '%s' name" % grade_id)

extends "res://tests/test_case.gd"

const Counter = preload("res://core/counter.gd")
const EnemyDef = preload("res://core/enemy_def.gd")
const Facing = preload("res://core/tactics/facing.gd")
const Grid = preload("res://core/tactics/grid.gd")
const MartialDef = preload("res://core/martial_def.gd")
const Mastery = preload("res://core/mastery.gd")
const TacticsBattle = preload("res://core/tactics/tactics_battle.gd")
const TacticsBot = preload("res://core/tactics/tactics_bot.gd")
const TacticsCounterRules = preload("res://core/tactics/tactics_counter_rules.gd")
const TacticsForms = preload("res://core/tactics/tactics_forms.gd")
const TacticsReaction = preload("res://core/tactics/tactics_reaction.gd")
const TacticsRuleData = preload("res://core/tactics/tactics_rule_data.gd")
const TacticsUnit = preload("res://core/tactics/tactics_unit.gd")
const Unit = preload("res://core/unit.gd")

const BLOCK_ID := "_block"


func _stats(power := 10, speed := 15, defense := 0, recovery := 0, skill := 20,
		constitution := 0) -> Dictionary:
	return {"power": power, "speed": speed, "defense": defense,
			"recovery": recovery, "skill": skill, "constitution": constitution}


func _grid() -> Variant:
	return Grid.from_dict({"width": 4, "height": 3, "tiles": ["....", "....", "...."]})


func _ctx() -> Dictionary:
	return {"grid": _grid()}


func _move(move_type := "heavy", form := "", unblockable := false) -> Dictionary:
	var move := {"id": "swing", "name": "swing", "type": move_type, "threat": 0, "power": 10}
	if form != "":
		move["form"] = form
	if unblockable:
		move["unblockable"] = true
	return move


func _martial(counters: Array = ["heavy"], range_def: Dictionary = {}) -> Variant:
	var parsed_range := range_def
	if parsed_range.is_empty():
		parsed_range = {"shape": "melee", "min": 1, "max": 1, "width": 1, "pierce": false}
	return MartialDef.from_dict({
		"id": "m", "name": "m", "power": 10, "counters": counters,
		"initiative": 0, "counter_level": 5, "grade": "common",
		"advantage_stat": "skill", "range": parsed_range, "effects": [],
	})


func _player(loadout: Array = ["m"], energy: Dictionary = {}) -> Variant:
	var core = Unit.make_player("测试", _stats(), 500, 2, 0, "lianti")
	var unit = TacticsUnit.create("player", core, "player", Vector2i(0, 1), Facing.RIGHT,
		loadout, energy)
	unit.start_turn()
	return unit


func _enemy(moves: Array = []) -> Variant:
	var move_defs := moves
	if move_defs.is_empty():
		move_defs = [_move("heavy")]
	var def = EnemyDef.from_dict({
		"id": "enemy", "name": "enemy", "tier": "minion",
		"stats": _stats(10, 10, 0, 0, 0), "max_hp": 500, "toughness": 4,
		"stun_turns": 1, "moves": move_defs, "weak_moves": [],
	})
	return TacticsUnit.create("enemy", Unit.from_enemy(def), "enemy", Vector2i(1, 1),
		Facing.LEFT, [], {})


func _evaluate(martial, move: Dictionary, relation := "front") -> Dictionary:
	return TacticsCounterRules.evaluate(
		_enemy(), _player(), move, martial, relation, _ctx())


func _option_ids(options: Array) -> Array:
	var out: Array = []
	for raw_option in options:
		if raw_option is Dictionary:
			out.append(str(raw_option.get("id", "")))
	return out


func _option_by_id(options: Array, option_id: String) -> Dictionary:
	for raw_option in options:
		if raw_option is Dictionary and str(raw_option.get("id", "")) == option_id:
			return raw_option
	return {}


func _first_event(events: Array, event_type: String) -> Dictionary:
	for event in events:
		if str(event.get("type", "")) == event_type:
			return event
	return {}


func _errors_contain(errors: Array, needle: String) -> bool:
	for message in errors:
		if str(message).contains(needle):
			return true
	return false


func test_move_form_mapping() -> void:
	assert_eq(TacticsForms.move_form(_move("thrust")), "thrust")
	assert_eq(TacticsForms.move_form(_move("heavy")), "chop")
	assert_eq(TacticsForms.move_form(_move("sweep")), "sweep")
	assert_eq(TacticsForms.move_form(_move("ranged")), "point")
	assert_eq(TacticsForms.move_form(_move("combo")), "thrust")
	assert_eq(TacticsForms.move_form(_move("charge")), "chop")
	assert_eq(TacticsForms.move_form(_move("unknown")), "", "unknown types have no form")
	assert_eq(TacticsForms.move_form(_move("thrust", "chop")), "chop",
		"the explicit form overrides the legacy type")
	assert_eq(TacticsForms.move_form({}), "")


func test_martial_forms_and_names() -> void:
	var martial = _martial(["heavy", "ranged"])
	assert_eq(TacticsForms.martial_forms(martial), ["chop", "point"])
	var declared := {"counters": ["heavy"], "forms": ["sweep", "thrust"]}
	assert_eq(TacticsForms.martial_forms(declared), ["sweep", "thrust"],
		"an explicit forms list overrides counters")
	assert_eq(TacticsForms.form_name("thrust"), "刺")
	assert_eq(TacticsForms.form_name("chop"), "劈")
	assert_eq(TacticsForms.form_name("sweep"), "扫")
	assert_eq(TacticsForms.form_name("point"), "点")
	assert_eq(TacticsForms.form_name("nope"), "")


func test_rule_data_loads_and_result_table() -> void:
	var loaded: Dictionary = TacticsRuleData.load_rules()
	assert_true(bool(loaded["ok"]), "the shipped rules load: %s" % str(loaded["errors"]))
	var perfect := TacticsRuleData.result("perfect")
	assert_eq(int(perfect["damage_pct"]), 0)
	assert_eq(int(perfect["counter_pct"]), 50)
	assert_eq(int(perfect["jianyi"]), 1)
	var counter := TacticsRuleData.result("counter")
	assert_eq(int(counter["damage_pct"]), 0)
	assert_eq(int(counter["counter_pct"]), 20)
	assert_eq(int(counter["jianyi"]), 0)
	var scrape := TacticsRuleData.result("scrape")
	assert_eq(int(scrape["damage_pct"]), 50)
	assert_eq(int(scrape["counter_pct"]), 0)
	var none := TacticsRuleData.result("none")
	assert_eq(int(none["damage_pct"]), 100)
	assert_eq(str(TacticsRuleData.basic_block()["id"]), BLOCK_ID)


func test_rule_data_reports_clear_errors() -> void:
	var missing: Dictionary = TacticsRuleData.load_rules("no_such_tactics_rules.json")
	assert_true(not bool(missing["ok"]))
	assert_true(_errors_contain(missing["errors"], "cannot read"),
		"a missing rules file is named in the error")
	var empty: Dictionary = TacticsRuleData.parse_rules({})
	assert_true(not bool(empty["ok"]))
	assert_true(_errors_contain(empty["errors"], "forms"))
	assert_true(_errors_contain(empty["errors"], "legacy_type_to_form"))
	assert_true(_errors_contain(empty["errors"], "result_table"))
	assert_true(_errors_contain(empty["errors"], "basic_block"))
	var bad_outcome: Dictionary = TacticsRuleData.parse_rules({
		"forms": {"thrust": "刺"},
		"legacy_type_to_form": {"thrust": "thrust"},
		"result_table": {
			"perfect": {"damage_pct": 0, "counter_pct": 50, "jianyi": 1},
			"counter": {"damage_pct": 0, "counter_pct": 20, "jianyi": 0},
			"scrape": {"damage_pct": 50, "counter_pct": 0, "jianyi": 0},
			"none": {"damage_pct": 100, "counter_pct": 0, "jianyi": 0},
		},
		"basic_block": {"id": BLOCK_ID, "name": "基础格挡", "outcome": "bogus"},
	})
	assert_true(not bool(bad_outcome["ok"]))
	assert_true(_errors_contain(bad_outcome["errors"], "basic_block.outcome"))


func test_form_match_front_in_range_is_perfect() -> void:
	var evaluated := _evaluate(_martial(["heavy"]), _move("heavy"), "front")
	assert_eq(str(evaluated["outcome"]), "perfect")
	assert_true(bool(evaluated["perfect"]))
	assert_eq(int(evaluated["verdict"]), Counter.Verdict.ADVANTAGE)


func test_form_match_side_is_counter() -> void:
	var evaluated := _evaluate(_martial(["heavy"]), _move("heavy"), "side")
	assert_eq(str(evaluated["outcome"]), "counter")
	assert_true(not bool(evaluated["perfect"]))
	assert_eq(int(evaluated["verdict"]), Counter.Verdict.ADVANTAGE)


func test_form_match_out_of_range_is_counter() -> void:
	var defender = _player()
	var attacker = _enemy()
	attacker.pos = Vector2i(2, 1)
	var evaluated := TacticsCounterRules.evaluate(
		attacker, defender, _move("heavy"), _martial(["heavy"]), "front", _ctx())
	assert_eq(str(evaluated["outcome"]), "counter",
		"a front-facing defender without reach only counters")


func test_wrong_form_is_none() -> void:
	var evaluated := _evaluate(_martial(["sweep"]), _move("heavy"), "front")
	assert_eq(str(evaluated["outcome"]), "none")
	assert_eq(int(evaluated["verdict"]), Counter.Verdict.IMPOSSIBLE)


func test_basic_block_is_scrape() -> void:
	var evaluated := _evaluate(null, _move("heavy"), "front")
	assert_eq(str(evaluated["outcome"]), "scrape")
	assert_eq(int(evaluated["verdict"]), Counter.Verdict.BARELY)


func test_unblockable_disables_every_outcome() -> void:
	var move := _move("heavy", "", true)
	assert_eq(str(_evaluate(_martial(["heavy"]), move)["outcome"]), "none",
		"even a form match cannot break an unblockable move")
	assert_eq(str(_evaluate(null, move)["outcome"]), "none",
		"basic block also fails against unblockable moves")


func test_numeric_gap_does_not_block_perfect() -> void:
	var defender = _player()
	var attacker = _enemy()
	attacker.unit.stats["skill"] = 999
	attacker.unit.stats["power"] = 999
	var move := _move("heavy")
	move["threat"] = 999
	var evaluated := TacticsCounterRules.evaluate(
		attacker, defender, move, _martial(["heavy"]), "front", _ctx())
	assert_eq(str(evaluated["outcome"]), "perfect",
		"form and geometry decide, not the stat gap")


func test_reaction_options_offer_martial_and_block() -> void:
	var martials := {"m": _martial(["heavy"])}
	var options: Array = TacticsReaction.options(
		_player(["m"]), _enemy(), _move("heavy"), martials, Mastery.new(), "front", _ctx())
	assert_eq(_option_ids(options), ["m", BLOCK_ID])
	var block := _option_by_id(options, BLOCK_ID)
	assert_eq(str(block.get("outcome", "")), "scrape")
	assert_eq(int(block.get("verdict", -1)), Counter.Verdict.BARELY)


func test_reaction_options_keep_block_when_martials_cannot_help() -> void:
	var martials := {"m": _martial(["heavy"])}
	var wrong_form: Array = TacticsReaction.options(
		_player(["m"]), _enemy(), _move("sweep"), martials, Mastery.new(), "front", _ctx())
	assert_eq(_option_ids(wrong_form), [BLOCK_ID],
		"a wrong form removes the martial but keeps basic block")
	var exhausted: Array = TacticsReaction.options(
		_player(["m"], {"neili": 0}), _enemy(), _move("heavy"), martials,
		Mastery.new(), "front", _ctx())
	assert_eq(_option_ids(exhausted), [BLOCK_ID],
		"an empty neili pool falls back to basic block")
	var back: Array = TacticsReaction.options(
		_player(["m"]), _enemy(), _move("heavy"), martials, Mastery.new(), "back", _ctx())
	assert_eq(back.size(), 0, "back attacks still cannot be reacted to")
	var stunned_player = _player(["m"])
	stunned_player.unit.stun_left = 1
	var stunned: Array = TacticsReaction.options(
		stunned_player, _enemy(), _move("heavy"), martials, Mastery.new(), "front", _ctx())
	assert_eq(stunned.size(), 0, "stunned units cannot react")


func test_reaction_options_none_for_unblockable() -> void:
	var options: Array = TacticsReaction.options(
		_player(["m"]), _enemy(), _move("heavy", "", true), {"m": _martial(["heavy"])},
		Mastery.new(), "front", _ctx())
	assert_eq(options.size(), 0, "unblockable moves disable every option including block")


func test_reaction_resolve_reads_result_table() -> void:
	var defender = _player(["m"])
	var attacker = _enemy()
	var martials := {"m": _martial(["heavy"])}
	var perfect := TacticsReaction.resolve(
		defender, attacker, _move("heavy"), "m", martials, Mastery.new(), "front", 20, _ctx())
	assert_eq(str(perfect["outcome"]), "perfect")
	assert_eq(int(perfect["damage"]), 0)
	assert_eq(int(perfect["counter_pct"]), 50)
	assert_eq(int(perfect["jianyi"]), 1)
	var countered := TacticsReaction.resolve(
		defender, attacker, _move("heavy"), "m", martials, Mastery.new(), "side", 20, _ctx())
	assert_eq(str(countered["outcome"]), "counter")
	assert_eq(int(countered["damage"]), 0)
	assert_eq(int(countered["counter_pct"]), 20)
	assert_eq(int(countered["jianyi"]), 0)
	var scraped := TacticsReaction.resolve(
		defender, attacker, _move("heavy"), BLOCK_ID, martials, Mastery.new(), "front", 20, _ctx())
	assert_eq(str(scraped["outcome"]), "scrape")
	assert_eq(int(scraped["damage"]), 10)
	assert_eq(int(scraped["counter_pct"]), 0)
	assert_eq(int(scraped["jianyi"]), 0)
	var none := TacticsReaction.resolve(
		defender, attacker, _move("sweep"), "m", martials, Mastery.new(), "front", 20, _ctx())
	assert_eq(str(none["outcome"]), "none")
	assert_eq(int(none["damage"]), 20)
	assert_eq(int(none["jianyi"]), 0)


func test_bot_priority_prefers_perfect_then_counter_then_block() -> void:
	var full := [{"defender_id": "player", "options": [
		{"id": BLOCK_ID, "verdict": Counter.Verdict.BARELY, "perfect": false, "outcome": "scrape"},
		{"id": "m", "verdict": Counter.Verdict.ADVANTAGE, "perfect": false, "outcome": "counter"},
		{"id": "jueshi", "verdict": Counter.Verdict.ADVANTAGE, "perfect": true, "outcome": "perfect"},
	]}]
	assert_eq(str(TacticsBot.pick_reactions(full, "best").get("player", "")), "jueshi")
	var no_perfect := [{"defender_id": "player", "options": [
		{"id": BLOCK_ID, "verdict": Counter.Verdict.BARELY, "perfect": false, "outcome": "scrape"},
		{"id": "m", "verdict": Counter.Verdict.ADVANTAGE, "perfect": false, "outcome": "counter"},
	]}]
	assert_eq(str(TacticsBot.pick_reactions(no_perfect, "best").get("player", "")), "m")
	var block_only := [{"defender_id": "player", "options": [
		{"id": BLOCK_ID, "verdict": Counter.Verdict.BARELY, "perfect": false, "outcome": "scrape"},
	]}]
	assert_eq(str(TacticsBot.pick_reactions(block_only, "best").get("player", "")), BLOCK_ID)
	assert_eq(TacticsBot.pick_reactions(full, "never").size(), 0, "never mode never reacts")


func test_battle_perfect_counter_restores_jianyi_without_toughness() -> void:
	var player = _player(["m"], {"neili": 3})
	player.unit.jianyi_points = 0
	var enemy = _enemy([_move("heavy")])
	var battle = TacticsBattle.create(
		_grid(), [player, enemy], {"m": _martial(["heavy"])}, Mastery.new())
	assert_eq(battle.begin_turn(), "player")
	battle.end_turn("player")
	assert_eq(battle.begin_turn(), "enemy")
	var result: Dictionary = battle.attack(
		"enemy", "swing", Vector2i(0, 1), {"player": "m"})
	assert_true(bool(result["ok"]))
	var hit := _first_event(result["events"], "hit")
	assert_eq(str(hit.get("outcome", "")), "perfect")
	assert_eq(int(hit.get("damage", -1)), 0, "a perfect counter negates the hit")
	assert_eq(int(player.unit.hp), 500)
	assert_eq(int(player.unit.jianyi_points), 1, "the result table restores one jianyi")
	assert_near(enemy.unit.toughness_left, 4.0, 0.0001, "counters no longer chip toughness")
	assert_eq(int(enemy.unit.hp), 490, "the counter deals 50% of the martial damage")
	var counter_hits := 0
	for event in result["events"]:
		if str(event.get("type", "")) == "counter_hit":
			counter_hits += 1
	assert_eq(counter_hits, 1, "one attack triggers at most one counter")


func test_battle_basic_block_halves_damage_without_energy_or_counter() -> void:
	var player = _player(["m"], {"neili": 5})
	player.unit.jianyi_points = 0
	var enemy = _enemy([_move("sweep")])
	var battle = TacticsBattle.create(
		_grid(), [player, enemy], {"m": _martial(["heavy"])}, Mastery.new())
	assert_eq(battle.begin_turn(), "player")
	battle.end_turn("player")
	assert_eq(battle.begin_turn(), "enemy")
	var reactions_before: int = int(player.reactions_left)
	var result: Dictionary = battle.attack(
		"enemy", "swing", Vector2i(0, 1), {"player": BLOCK_ID})
	assert_true(bool(result["ok"]))
	var hit := _first_event(result["events"], "hit")
	assert_eq(str(hit.get("reaction", "")), BLOCK_ID)
	assert_eq(str(hit.get("outcome", "")), "scrape")
	assert_eq(int(player.unit.hp), 495, "basic block halves the damage")
	assert_eq(int(player.energy_left["neili"]), 5, "basic block does not spend neili")
	assert_eq(int(player.reactions_left), reactions_before - 1,
		"basic block spends a reaction point")
	assert_eq(int(player.unit.jianyi_points), 0, "basic block restores no jianyi")
	assert_near(enemy.unit.toughness_left, 4.0)
	for event in result["events"]:
		assert_true(str(event.get("type", "")) != "counter_hit", "basic block never counters")

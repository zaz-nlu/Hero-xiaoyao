extends "res://tests/test_case.gd"

const Counter = preload("res://core/counter.gd")
const EnemyDef = preload("res://core/enemy_def.gd")
const Facing = preload("res://core/tactics/facing.gd")
const Grid = preload("res://core/tactics/grid.gd")
const MartialDef = preload("res://core/martial_def.gd")
const Mastery = preload("res://core/mastery.gd")
const StatsRules = preload("res://core/tactics/stats_rules.gd")
const TacticsBattle = preload("res://core/tactics/tactics_battle.gd")
const TacticsDamage = preload("res://core/tactics/tactics_damage.gd")
const TacticsEnergy = preload("res://core/tactics/tactics_energy.gd")
const TacticsReaction = preload("res://core/tactics/tactics_reaction.gd")
const TacticsUnit = preload("res://core/tactics/tactics_unit.gd")
const Unit = preload("res://core/unit.gd")


func _stats(power := 10, speed := 15, defense := 0, recovery := 0, skill := 20, constitution := 0) -> Dictionary:
	return {"power": power, "speed": speed, "defense": defense,
			"recovery": recovery, "skill": skill, "constitution": constitution}


func _grid(tiles: Array, heights: Array = []) -> Variant:
	var size_x := 0
	if not tiles.is_empty():
		size_x = str(tiles[0]).length()
	return Grid.from_dict({"width": size_x, "height": tiles.size(), "tiles": tiles, "heights": heights})


func _map() -> Variant:
	return _grid(["........", "..#.....", "........", "....o...", "........", "........"])


func _move(move_type := "heavy", power := 10, threat := 0, move_id := "swing") -> Dictionary:
	return {"id": move_id, "name": move_id, "type": move_type, "threat": threat, "power": power}


func _martial(
	martial_id := "m", power := 10, counters: Array = ["heavy"], initiative := 0,
	counter_level := 5, grade := "common",
	range_def: Dictionary = {"shape": "melee", "min": 1, "max": 1, "width": 1, "pierce": false},
	advantage := "skill"
) -> Variant:
	return MartialDef.from_dict({
		"id": martial_id, "name": martial_id, "power": power, "counters": counters,
		"initiative": initiative, "counter_level": counter_level, "grade": grade,
		"advantage_stat": advantage, "range": range_def, "effects": [],
	})


func _martials() -> Dictionary:
	return {
		"basic_sword": _martial("basic_sword", 10, ["thrust"], 0, 2),
		"breaker": _martial("breaker", 10, ["heavy"], 0, 5),
		"qingyun": _martial("qingyun", 12, ["thrust"], 2, 4, "fine",
			{"shape": "line", "min": 1, "max": 2, "width": 1, "pierce": false}),
		"huifeng": _martial("huifeng", 9, ["sweep"], 2, 4, "fine",
			{"shape": "cone", "min": 1, "max": 3, "width": 1, "pierce": false}),
		"liuxing": _martial("liuxing", 8, ["ranged"], 4, 4, "rare",
			{"shape": "ranged", "min": 2, "max": 5, "width": 1, "pierce": false}),
		"jueshi": _martial("jueshi", 18, ["thrust", "combo"], 3, 7, "legendary",
			{"shape": "line", "min": 1, "max": 3, "width": 1, "pierce": true}),
	}


func _player(player_id := "player", pos := Vector2i(0, 0), facing := Facing.DOWN,
		stats_from: Dictionary = {}, hp := 500, jianyi_max := 2,
		loadout: Array = [], energy: Dictionary = {}) -> Variant:
	var stats := _stats() if stats_from.is_empty() else stats_from
	var core = Unit.make_player("测试", stats, hp, jianyi_max, 0, "lianti")
	return TacticsUnit.create(player_id, core, "player", pos, facing, loadout, energy)


func _enemy(enemy_id := "enemy", pos := Vector2i(1, 0), facing := Facing.LEFT,
		stats_from: Dictionary = {}, moves: Array = [], weak: Array = [],
		toughness := 4, move_override := -1, hp := 500) -> Variant:
	var move_defs := moves
	if move_defs.is_empty():
		move_defs = [_move()]
	var def = EnemyDef.from_dict({
		"id": enemy_id, "name": enemy_id, "tier": "minion",
		"stats": stats_from if not stats_from.is_empty() else _stats(10, 10, 0, 0, 0),
		"max_hp": hp, "toughness": toughness, "stun_turns": 1,
		"moves": move_defs, "weak_moves": weak, "move": move_override,
	})
	return TacticsUnit.create(enemy_id, Unit.from_enemy(def), "enemy", pos, facing, [], {})


func _battle(grid, units: Array, martials: Dictionary, mastery = null,
		objective := "defeat_all", leader_id := "") -> Variant:
	var use_mastery = Mastery.new() if mastery == null else mastery
	return TacticsBattle.create(grid, units, martials, use_mastery, objective, leader_id)


func _advance_to(battle, actor_id: String) -> String:
	for _i in range(30):
		var actor: String = battle.begin_turn()
		if actor == "" or actor == actor_id:
			return actor
		battle.end_turn(actor)
	return ""


func test_energy_costs_follow_grade() -> void:
	assert_eq(TacticsEnergy.grade_cost("common"), 1)
	assert_eq(TacticsEnergy.grade_cost("fine"), 1)
	assert_eq(TacticsEnergy.grade_cost("rare"), 2)
	assert_eq(TacticsEnergy.grade_cost("epic"), 3)
	assert_eq(TacticsEnergy.grade_cost("legendary"), 4)
	var martials := _martials()
	assert_eq(TacticsEnergy.cost_for(martials["basic_sword"]), 0, "basic_sword is free")
	assert_eq(TacticsEnergy.cost_for(martials["breaker"]), 1)
	assert_eq(TacticsEnergy.cost_for(martials["qingyun"]), 1)
	assert_eq(TacticsEnergy.cost_for(martials["jueshi"]), 4)


func test_move_reachable_and_out_of_range() -> void:
	var player = _player("player", Vector2i(0, 0), Facing.RIGHT, _stats(10, 8), 500, 2)
	var enemy = _enemy("enemy", Vector2i(6, 0), Facing.LEFT, _stats(10, 5, 0, 0, 0))
	var b = _battle(_grid(["......."]), [player, enemy], _martials())
	assert_eq(b.begin_turn(), "player")
	var too_far: Dictionary = b.move("player", Vector2i(4, 0))
	assert_true(not bool(too_far["ok"]), "speed 8 moves only 3 cells")
	assert_eq(str(too_far["reason"]), "unreachable")
	assert_true(bool(b.move("player", Vector2i(3, 0))["ok"]))
	assert_eq(player.pos, Vector2i(3, 0))
	var again: Dictionary = b.move("player", Vector2i(0, 0))
	assert_true(not bool(again["ok"]))
	assert_eq(str(again["reason"]), "already_moved")


func test_move_blocked_by_enemy_and_occupied_cells() -> void:
	var player = _player("player", Vector2i(0, 0), Facing.RIGHT, _stats(10, 15), 500, 2)
	var blocker = _enemy("enemy", Vector2i(2, 0), Facing.LEFT, _stats(10, 5, 0, 0, 0))
	var blocked = _battle(_grid(["....."]), [player, blocker], _martials())
	assert_eq(blocked.begin_turn(), "player")
	assert_true(not blocked.reachable_cells("player").has(Vector2i(3, 0)), "enemy blocks the corridor")
	assert_true(not bool(blocked.move("player", Vector2i(3, 0))["ok"]))

	var leader = _player("player", Vector2i(0, 0), Facing.RIGHT, _stats(10, 15), 500, 2)
	var ally = _player("ally", Vector2i(1, 0), Facing.RIGHT, _stats(10, 5), 500, 2)
	var far = _enemy("enemy", Vector2i(4, 0), Facing.LEFT, _stats(10, 1, 0, 0, 0))
	var occupied = _battle(_grid(["....."]), [leader, ally, far], _martials())
	assert_eq(occupied.begin_turn(), "player")
	assert_true(not occupied.reachable_cells("player").has(Vector2i(1, 0)))
	assert_true(not bool(occupied.move("player", Vector2i(1, 0))["ok"]), "cannot stop on an ally")


func test_move_updates_facing_and_climb_limit() -> void:
	var player = _player("player", Vector2i(0, 0), Facing.DOWN, _stats(10, 15), 500, 2)
	var enemy = _enemy("enemy", Vector2i(2, 2), Facing.LEFT, _stats(10, 5, 0, 0, 0))
	var b = _battle(_grid(["...", "...", "..."], ["013", "000", "000"]), [player, enemy], _martials())
	assert_eq(b.begin_turn(), "player")
	assert_true(not b.reachable_cells("player").has(Vector2i(2, 0)), "climb limit is 1")
	assert_true(not bool(b.move("player", Vector2i(2, 0))["ok"]))
	assert_true(bool(b.move("player", Vector2i(1, 0))["ok"]))
	assert_eq(player.pos, Vector2i(1, 0))
	assert_eq(player.facing, Facing.RIGHT, "facing follows the last step")


func test_damage_facing_modifiers() -> void:
	var stats := _stats(10, 15, 0, 0, 20)
	var defender = _enemy("enemy", Vector2i(1, 0), Facing.LEFT, _stats(0, 10, 0, 0, 0)).unit
	var origin := Vector2i(0, 0)
	var spot := Vector2i(1, 0)
	var front_relation := Facing.relation(spot, Facing.LEFT, origin)
	var side_relation := Facing.relation(spot, Facing.UP, origin)
	var back_relation := Facing.relation(spot, Facing.RIGHT, origin)
	assert_eq(front_relation, "front")
	assert_eq(side_relation, "side")
	assert_eq(back_relation, "back")
	var front := TacticsDamage.martial_damage(stats, "lianti", 10, 1.0, defender, front_relation, 0.0)
	var side := TacticsDamage.martial_damage(stats, "lianti", 10, 1.0, defender, side_relation, 0.0)
	var back := TacticsDamage.martial_damage(stats, "lianti", 10, 1.0, defender, back_relation, 0.0)
	assert_eq(front, 20)
	assert_eq(side, 24, "side is x1.2")
	assert_eq(back, 30, "back is x1.5")


func test_damage_height_bonus_caps() -> void:
	var stats := _stats(10, 15, 0, 0, 20)
	var defender = _enemy("enemy", Vector2i(1, 0), Facing.LEFT, _stats(0, 10, 0, 0, 0)).unit
	var flat := TacticsDamage.martial_damage(stats, "lianti", 10, 1.0, defender, "front", StatsRules.height_bonus(0, 0))
	var one := TacticsDamage.martial_damage(stats, "lianti", 10, 1.0, defender, "front", StatsRules.height_bonus(1, 0))
	var three := TacticsDamage.martial_damage(stats, "lianti", 10, 1.0, defender, "front", StatsRules.height_bonus(3, 0))
	var five := TacticsDamage.martial_damage(stats, "lianti", 10, 1.0, defender, "front", StatsRules.height_bonus(5, 0))
	assert_eq(flat, 20)
	assert_eq(one, 22, "+10% per level")
	assert_eq(three, 26, "capped at +30%")
	assert_eq(five, 26, "the cap holds above three levels")


func _options_case(relation := "front", move_type := "heavy", reactions_left := 1,
		defender_speed := 20, attacker_speed := 15, stunned := false,
		counters: Array = ["heavy"], initiative := 0, defender_side := "player",
		skill := 20, threat := 0) -> Array:
	var move := _move(move_type, 10, threat)
	var martials := {"m": _martial("m", 10, counters, initiative)}
	var defender = _player("player", Vector2i(0, 0), Facing.RIGHT,
		_stats(10, defender_speed, 0, 0, skill), 500, 2, ["m"])
	defender.reactions_left = reactions_left
	defender.side = defender_side
	if stunned:
		defender.unit.stun_left = 1
	var attacker = _enemy("enemy", Vector2i(1, 0), Facing.LEFT, _stats(10, attacker_speed, 0, 0, 0))
	return TacticsReaction.options(
		defender, attacker, move, martials, Mastery.new(), relation,
		{"grid": _grid([".....", ".....", "....."])})


func _option_by_id(options: Array, option_id: String) -> Dictionary:
	for raw_option in options:
		if raw_option is Dictionary and str(raw_option.get("id", "")) == option_id:
			return raw_option
	return {}


func test_reaction_options_require_qualification() -> void:
	assert_eq(_options_case("back").size(), 0, "back attacks cannot be countered")
	assert_eq(_options_case("front", "heavy", 0).size(), 0, "no reaction points left")
	var slow: Array = _options_case("front", "heavy", 1, 10, 40)
	assert_true(_option_by_id(slow, "m").is_empty(), "too slow to use the martial")
	assert_true(not _option_by_id(slow, "_block").is_empty(), "basic block is still available")
	var wrong_form: Array = _options_case("front", "sweep")
	assert_true(_option_by_id(wrong_form, "m").is_empty(), "wrong move type cannot counter")
	assert_true(not _option_by_id(wrong_form, "_block").is_empty(),
		"basic block stays available")
	assert_eq(_options_case("front", "heavy", 1, 20, 15, true).size(), 0, "stunned units cannot react")
	assert_eq(_options_case("front", "heavy", 1, 20, 15, false, ["heavy"], 0, "enemy").size(), 0)


func test_reaction_options_offer_qualified_moves() -> void:
	var options: Array = _options_case("front", "heavy", 1, 20, 15)
	assert_eq(options.size(), 2, "one martial option plus basic block")
	var qualified := _option_by_id(options, "m")
	assert_eq(str(qualified.get("id", "")), "m")
	assert_eq(int(qualified.get("verdict", -1)), Counter.Verdict.ADVANTAGE)
	assert_eq(str(qualified.get("outcome", "")), "perfect")
	assert_true(bool(qualified.get("perfect", false)))
	assert_true(not _option_by_id(options, "_block").is_empty())


func _resolve_case(relation := "front", move_type := "heavy", skill := 20,
		counter_level := 5, threat := 0, defender_speed := 20, attacker_speed := 15,
		initiative := 0, base_damage := 20) -> Dictionary:
	var move := _move(move_type, 10, threat)
	var martials := {"m": _martial("m", 10, ["heavy"], initiative, counter_level)}
	var defender = _player("player", Vector2i(0, 0), Facing.RIGHT,
		_stats(10, defender_speed, 0, 0, skill), 500, 2, ["m"])
	var attacker = _enemy("enemy", Vector2i(1, 0), Facing.LEFT, _stats(10, attacker_speed, 0, 0, 0))
	return TacticsReaction.resolve(defender, attacker, move, "m", martials,
		Mastery.new(), relation, base_damage,
		{"grid": _grid([".....", ".....", "....."])})


func test_reaction_resolution_damage_tiers() -> void:
	var perfect := _resolve_case()
	assert_eq(int(perfect["verdict"]), Counter.Verdict.ADVANTAGE)
	assert_eq(str(perfect["outcome"]), "perfect")
	assert_true(bool(perfect["perfect"]))
	assert_eq(int(perfect["damage"]), 0, "a perfect counter negates the hit")
	assert_eq(int(perfect["counter_pct"]), 50)
	assert_true(bool(perfect["counter_attack"]))
	assert_near(float(perfect["toughness_cost"]), 0.0)
	var impossible := _resolve_case("front", "sweep")
	assert_eq(int(impossible["verdict"]), Counter.Verdict.IMPOSSIBLE)
	assert_eq(str(impossible["outcome"]), "none")
	assert_eq(int(impossible["damage"]), 20, "impossible takes full damage")
	assert_near(float(impossible["toughness_cost"]), 0.0)
	assert_true(not bool(impossible["counter_attack"]))


func test_side_attack_counters_but_is_not_perfect() -> void:
	var front := _resolve_case("front", "heavy", 10, 5, 15, 20, 20)
	var side := _resolve_case("side", "heavy", 10, 5, 15, 20, 20)
	assert_true(bool(front["perfect"]), "a front-facing defender lands the perfect counter")
	assert_true(not bool(side["perfect"]), "a side attack only qualifies for a counter")
	assert_eq(str(side["outcome"]), "counter")
	assert_eq(int(side["verdict"]), Counter.Verdict.ADVANTAGE)
	assert_eq(int(side["damage"]), 0, "a qualified counter still negates the hit")
	assert_eq(int(side["counter_pct"]), 20)


func test_perfect_reaction_does_not_spend_toughness() -> void:
	var move := _move("heavy", 10, 0, "swing")
	var martials := {"m": _martial("m", 10, ["heavy"], 0, 5)}
	var defender = _player("player", Vector2i(0, 0), Facing.RIGHT, _stats(10, 20, 0, 0, 30), 500, 2, ["m"])
	var attacker = _enemy("enemy", Vector2i(1, 0), Facing.LEFT, _stats(10, 10, 0, 0, 0), [_move()], ["swing"])
	var resolved := TacticsReaction.resolve(defender, attacker, move, "m", martials,
		Mastery.new(), "front", 20, {"grid": _grid([".....", ".....", "....."])})
	assert_true(bool(resolved["perfect"]), "form match plus front range is a perfect counter")
	assert_near(float(resolved["toughness_cost"]), 0.0)
	assert_eq(int(resolved["damage"]), 0)
	assert_eq(int(resolved["counter_pct"]), 50)


func test_battle_advantage_reaction_negates_and_counters() -> void:
	var player = _player("player", Vector2i(0, 0), Facing.RIGHT, _stats(10, 15, 0, 0, 20), 500, 2, ["breaker"])
	var enemy = _enemy("enemy", Vector2i(1, 0), Facing.LEFT, _stats(10, 10, 0, 0, 0), [_move("heavy", 10, 0)])
	var b = _battle(_map(), [player, enemy], _martials())
	b.begin_turn()
	b.end_turn("player")
	assert_eq(_advance_to(b, "enemy"), "enemy")
	var hp_before := int(player.unit.hp)
	assert_true(bool(b.attack("enemy", "swing", Vector2i(0, 0), {"player": "breaker"})["ok"]))
	assert_eq(player.unit.hp, hp_before, "advantage reaction negates the hit")
	assert_eq(player.reactions_left, 1, "one reaction point is spent")
	assert_near(enemy.unit.toughness_left, 4.0, 0.0001, "counters no longer chip toughness")
	assert_true(enemy.unit.hp < 500, "advantage counterattacks the attacker")


func test_perfect_counter_restores_jianyi_without_stun() -> void:
	var player = _player("player", Vector2i(0, 0), Facing.RIGHT, _stats(10, 15, 0, 0, 20), 500, 2, ["breaker"])
	player.unit.jianyi_points = 0
	var enemy = _enemy("enemy", Vector2i(1, 0), Facing.LEFT, _stats(10, 10, 0, 0, 0),
		[_move("heavy", 10, 0)], ["swing"], 2)
	var b = _battle(_map(), [player, enemy], _martials())
	b.begin_turn()
	b.end_turn("player")
	assert_eq(_advance_to(b, "enemy"), "enemy")
	assert_true(bool(b.attack("enemy", "swing", Vector2i(0, 0), {"player": "breaker"})["ok"]))
	assert_near(enemy.unit.toughness_left, 2.0, 0.0001,
		"a perfect counter no longer breaks toughness")
	assert_true(not enemy.unit.is_stunned(), "the attacker is not stunned by a counter")
	assert_eq(player.unit.jianyi_points, 1, "perfect counter restores one jianyi point")


func test_attacks_spend_the_energy_pool() -> void:
	var player = _player("player", Vector2i(0, 0), Facing.RIGHT, _stats(10, 15, 0, 0, 20),
		1000, 2, ["breaker"], {"neili": 1})
	var enemy = _enemy("enemy", Vector2i(1, 0), Facing.LEFT, _stats(10, 10, 0, 0, 0), [_move("heavy", 1)], [], 99)
	var b = _battle(_map(), [player, enemy], _martials())
	assert_eq(b.begin_turn(), "player")
	assert_true(bool(b.attack("player", "breaker", Vector2i(1, 0))["ok"]))
	assert_eq(int(player.energy_left["neili"]), 0)
	b.end_turn("player")
	assert_eq(_advance_to(b, "player"), "player")
	var again: Dictionary = b.attack("player", "breaker", Vector2i(1, 0))
	assert_true(not bool(again["ok"]))
	assert_eq(str(again["reason"]), "no_energy")


func test_basic_sword_is_unlimited() -> void:
	var martials := _martials()
	var player = _player("player", Vector2i(0, 0), Facing.RIGHT, _stats(10, 15, 0, 0, 20),
		1000, 2, ["basic_sword"], {})
	var enemy = _enemy("enemy", Vector2i(1, 0), Facing.LEFT, _stats(10, 10, 0, 0, 0), [_move("heavy", 1)], [], 99)
	var b = _battle(_map(), [player, enemy], martials)
	b.begin_turn()
	assert_true(bool(b.attack("player", "basic_sword", Vector2i(1, 0))["ok"]))
	b.end_turn("player")
	assert_eq(_advance_to(b, "player"), "player")
	assert_true(bool(b.attack("player", "basic_sword", Vector2i(1, 0))["ok"]))


func test_enemy_moves_have_no_use_limit() -> void:
	var player = _player("player", Vector2i(0, 0), Facing.RIGHT, _stats(10, 15, 0, 0, 20), 1000, 2)
	var enemy = _enemy("enemy", Vector2i(1, 0), Facing.LEFT, _stats(10, 10, 0, 0, 0), [_move("heavy", 5)])
	var b = _battle(_map(), [player, enemy], _martials())
	b.begin_turn()
	b.end_turn("player")
	assert_eq(_advance_to(b, "enemy"), "enemy")
	assert_true(bool(b.attack("enemy", "swing", Vector2i(0, 0))["ok"]))
	b.end_turn("enemy")
	assert_eq(_advance_to(b, "enemy"), "enemy")
	assert_true(bool(b.attack("enemy", "swing", Vector2i(0, 0))["ok"]))
	assert_eq(player.unit.hp, 990, "both enemy attacks land")


func test_jianyi_ignores_defense_and_wounds() -> void:
	var player = _player("player", Vector2i(0, 0), Facing.RIGHT, _stats(10, 15, 0, 0, 20), 500, 1, ["basic_sword"])
	var enemy = _enemy("enemy", Vector2i(1, 0), Facing.LEFT, _stats(0, 10, 100, 0, 0), [], [], 4, -1, 500)
	var b = _battle(_map(), [player, enemy], _martials())
	assert_eq(b.begin_turn(), "player")
	assert_true(bool(b.jianyi("player", "basic_sword", Vector2i(1, 0))["ok"]))
	assert_eq(enemy.unit.hp, 458, "42 true damage despite 100 defense")
	assert_eq(enemy.unit.wound, 42, "jianyi wounds cannot be healed")
	assert_eq(player.unit.jianyi_points, 0)


func test_jianyi_requires_points() -> void:
	var player = _player("player", Vector2i(0, 0), Facing.RIGHT, _stats(10, 15, 0, 0, 20), 500, 1, ["basic_sword"])
	var enemy = _enemy("enemy", Vector2i(1, 0), Facing.LEFT, _stats(0, 10, 0, 0, 0), [], [], 4, -1, 500)
	var b = _battle(_map(), [player, enemy], _martials())
	b.begin_turn()
	assert_true(bool(b.jianyi("player", "basic_sword", Vector2i(1, 0))["ok"]))
	b.end_turn("player")
	assert_eq(_advance_to(b, "player"), "player")
	var second: Dictionary = b.jianyi("player", "basic_sword", Vector2i(1, 0))
	assert_true(not bool(second["ok"]))
	assert_eq(str(second["reason"]), "no_jianyi")


func test_jianyi_pierce_hits_a_row() -> void:
	var player = _player("player", Vector2i(0, 3), Facing.RIGHT, _stats(10, 15, 0, 0, 20), 500, 2, ["jueshi"])
	var first = _enemy("e1", Vector2i(1, 3), Facing.LEFT, _stats(0, 10, 0, 0, 0), [], [], 4, -1, 500)
	var second = _enemy("e2", Vector2i(2, 3), Facing.LEFT, _stats(0, 10, 0, 0, 0), [], [], 4, -1, 500)
	var b = _battle(_map(), [player, first, second], _martials())
	assert_eq(b.begin_turn(), "player")
	assert_eq(b.affected_units("player", "jueshi", Vector2i(2, 3)).size(), 2)
	assert_true(bool(b.jianyi("player", "jueshi", Vector2i(2, 3))["ok"]))
	assert_eq(first.unit.hp, 442)
	assert_eq(second.unit.hp, 442)


func test_line_cone_and_ranged_ranges() -> void:
	var line_player = _player("player", Vector2i(0, 3), Facing.RIGHT, _stats(10, 15, 0, 0, 20), 500, 2, ["qingyun"])
	var near = _enemy("e1", Vector2i(1, 3), Facing.LEFT, _stats(0, 10, 0, 0, 0))
	var far = _enemy("e2", Vector2i(2, 3), Facing.LEFT, _stats(0, 10, 0, 0, 0))
	var line_battle = _battle(_map(), [line_player, near, far], _martials())
	var line_cells: Array = line_battle.attack_cells("player", "qingyun")
	assert_true(line_cells.has(Vector2i(1, 3)))
	assert_true(line_cells.has(Vector2i(2, 3)))
	assert_true(not line_cells.has(Vector2i(3, 3)), "line max is 2")
	var line_targets: Array = line_battle.affected_units("player", "qingyun", Vector2i(2, 3))
	assert_eq(line_targets.size(), 1, "non-pierce line hits only the first unit")
	assert_eq(str(line_targets[0].id), "e1")

	var cone_player = _player("player", Vector2i(2, 3), Facing.UP, _stats(10, 15, 0, 0, 20), 500, 2, ["huifeng"])
	var front = _enemy("front", Vector2i(2, 2), Facing.DOWN, _stats(10, 5, 0, 0, 0))
	var behind = _enemy("behind", Vector2i(2, 4), Facing.UP, _stats(10, 5, 0, 0, 0))
	var cone_battle = _battle(_map(), [cone_player, front, behind], _martials())
	var cone_cells: Array = cone_battle.attack_cells("player", "huifeng")
	assert_true(cone_cells.has(Vector2i(2, 2)))
	assert_true(cone_cells.has(Vector2i(1, 1)))
	assert_true(cone_cells.has(Vector2i(3, 1)))
	assert_true(not cone_cells.has(Vector2i(2, 4)), "cone points forward")
	var cone_targets: Array = cone_battle.affected_units("player", "huifeng", Vector2i(2, 2))
	assert_eq(cone_targets.size(), 1)
	assert_eq(str(cone_targets[0].id), "front")

	var shot_player = _player("player", Vector2i(0, 3), Facing.RIGHT, _stats(10, 15, 0, 0, 20), 500, 2, ["liuxing"])
	var near_shot = _enemy("near", Vector2i(1, 3), Facing.LEFT, _stats(10, 5, 0, 0, 0))
	var far_shot = _enemy("far", Vector2i(5, 3), Facing.LEFT, _stats(10, 5, 0, 0, 0))
	var shot_battle = _battle(_map(), [shot_player, near_shot, far_shot], _martials())
	var shot_cells: Array = shot_battle.attack_cells("player", "liuxing")
	assert_true(not shot_cells.has(Vector2i(1, 3)), "min range is 2")
	assert_true(shot_cells.has(Vector2i(4, 3)))
	assert_true(shot_cells.has(Vector2i(5, 3)))
	assert_true(not shot_cells.has(Vector2i(6, 3)), "max range is 5")
	var shot_targets: Array = shot_battle.affected_units("player", "liuxing", Vector2i(5, 3))
	assert_eq(shot_targets.size(), 1)
	assert_eq(str(shot_targets[0].id), "far")


func test_turn_flow_follows_speed_and_advances_round() -> void:
	var player = _player("player", Vector2i(0, 0), Facing.RIGHT, _stats(10, 30, 0, 0, 20))
	var enemy = _enemy("enemy", Vector2i(7, 5), Facing.LEFT, _stats(10, 10, 0, 0, 0))
	var b = _battle(_map(), [player, enemy], _martials())
	var player_acts := 0
	var enemy_acts := 0
	for _i in range(20):
		var actor: String = b.begin_turn()
		if actor == "":
			break
		if _i == 0:
			assert_eq(actor, "player", "CT order starts with the faster actor")
		if actor == "player":
			player_acts += 1
		else:
			enemy_acts += 1
		b.end_turn(actor)
	assert_eq(b.round, 20, "every end_turn advances the action count")
	assert_true(player_acts > enemy_acts, "speed 30 acts more often than speed 10")


func test_defeat_leader_wins() -> void:
	var player = _player("player", Vector2i(0, 0), Facing.RIGHT, _stats(10, 15, 0, 0, 20), 500, 2, ["breaker"])
	var boss = _enemy("boss", Vector2i(1, 0), Facing.LEFT, _stats(10, 10, 0, 0, 0), [_move()], [], 99, -1, 10)
	var minion = _enemy("minion", Vector2i(6, 5), Facing.LEFT, _stats(10, 1, 0, 0, 0), [_move()], [], 99)
	var b = _battle(_map(), [player, boss, minion], _martials(), null, "defeat_leader", "boss")
	assert_eq(b.begin_turn(), "player")
	assert_true(bool(b.attack("player", "breaker", Vector2i(1, 0))["ok"]))
	assert_eq(b.result(), "win", "killing the leader wins even with minions alive")
	var after: Dictionary = b.wait("player")
	assert_true(not bool(after["ok"]))
	assert_eq(str(after["reason"]), "battle_over")


func test_lose_when_party_wipes() -> void:
	var player = _player("player", Vector2i(0, 0), Facing.RIGHT, _stats(10, 15, 0, 0, 20), 5, 2)
	var enemy = _enemy("enemy", Vector2i(1, 0), Facing.LEFT, _stats(100, 10, 0, 0, 0), [_move("heavy", 100)])
	var b = _battle(_map(), [player, enemy], _martials())
	b.begin_turn()
	b.end_turn("player")
	assert_eq(_advance_to(b, "enemy"), "enemy")
	assert_true(bool(b.attack("enemy", "swing", Vector2i(0, 0))["ok"]))
	assert_eq(b.result(), "lose", "a dead party loses")

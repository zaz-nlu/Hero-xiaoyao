extends "res://tests/test_case.gd"

const Counter = preload("res://core/counter.gd")
const EnemyDef = preload("res://core/enemy_def.gd")
const Facing = preload("res://core/tactics/facing.gd")
const Grid = preload("res://core/tactics/grid.gd")
const Mastery = preload("res://core/mastery.gd")
const TacticsAi = preload("res://core/tactics/tactics_ai.gd")
const TacticsBattle = preload("res://core/tactics/tactics_battle.gd")
const TacticsBot = preload("res://core/tactics/tactics_bot.gd")
const TacticsSetup = preload("res://core/tactics/tactics_setup.gd")
const TacticsUnit = preload("res://core/tactics/tactics_unit.gd")
const Unit = preload("res://core/unit.gd")

const TAVERN_GROUP := [{"id": "ma_youwei", "count": 1}, {"id": "bandit", "count": 5}]
const MAX_ACTIONS := 200


func _stats(power := 10, speed := 15, defense := 0, recovery := 0, skill := 20,
		constitution := 0) -> Dictionary:
	return {"power": power, "speed": speed, "defense": defense,
			"recovery": recovery, "skill": skill, "constitution": constitution}


func _grid(tiles: Array, heights: Array = []) -> Variant:
	var size_x := 0
	if not tiles.is_empty():
		size_x = str(tiles[0]).length()
	return Grid.from_dict({
		"width": size_x, "height": tiles.size(), "tiles": tiles, "heights": heights})


func _move(move_id: String, move_type: String, power: int, threat: int,
		shape := "melee", min_range := 1, max_range := 1) -> Dictionary:
	return {
		"id": move_id, "name": move_id, "type": move_type,
		"threat": threat, "power": power,
		"range": {"shape": shape, "min": min_range, "max": max_range,
				"width": 1, "pierce": false},
	}


func _player(player_id := "player", pos := Vector2i(0, 0), facing := Facing.RIGHT,
		stats_from: Dictionary = {}, hp := 500, jianyi_max := 1) -> Variant:
	var stats := _stats() if stats_from.is_empty() else stats_from
	var core = Unit.make_player("测试", stats, hp, jianyi_max, 0, "lianti")
	return TacticsUnit.create(player_id, core, "player", pos, facing, [], {})


func _enemy(enemy_id := "enemy", pos := Vector2i(1, 0), facing := Facing.LEFT,
		stats_from: Dictionary = {}, moves: Array = [], ai := "rush",
		toughness := 4, hp := 500) -> Variant:
	var move_defs := moves
	if move_defs.is_empty():
		move_defs = [_move("swing", "heavy", 10, 0)]
	var def = EnemyDef.from_dict({
		"id": enemy_id, "name": enemy_id, "tier": "minion", "ai": ai,
		"stats": stats_from if not stats_from.is_empty() else _stats(10, 10, 0, 0, 0),
		"max_hp": hp, "toughness": toughness, "stun_turns": 1,
		"moves": move_defs, "weak_moves": [],
	})
	return TacticsUnit.create(enemy_id, Unit.from_enemy(def), "enemy", pos, facing, [], {})


func _battle(grid, units: Array, objective := "defeat_all", leader_id := "") -> Variant:
	return TacticsBattle.create(grid, units, {}, Mastery.new(), objective, leader_id)


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _has_event_type(events: Array, event_type: String) -> bool:
	for event in events:
		if str(event.get("type", "")) == event_type:
			return true
	return false


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


func test_setup_builds_tavern_battle() -> void:
	var group := [{"id": "bandit", "count": 5}, {"id": "ma_youwei", "count": 1}]
	var built: Dictionary = TacticsSetup.build("tavern_brawl", group, null, 7)
	assert_true(bool(built["ok"]), "tavern setup succeeds: %s" % str(built["errors"]))
	if not bool(built["ok"]):
		return
	var battle: Variant = built["battle"]
	assert_eq(battle.units.size(), 7, "one player plus six enemies")
	assert_eq(battle.alive("player").size(), 1)
	assert_eq(battle.alive("enemy").size(), 6)
	assert_eq(str(battle.objective), "defeat_leader")
	assert_eq(str(battle.leader_id), "ma_youwei")
	var player = battle.get_unit("player")
	assert_true(player != null)
	assert_eq(player.pos, Vector2i(1, 6), "player spawns on spawns.player[0]")
	assert_eq(player.facing, Facing.RIGHT, "player faces the enemy group")
	var leader = battle.get_unit("ma_youwei")
	assert_true(leader != null, "the leader keeps its enemy id")
	assert_eq(leader.pos, Vector2i(5, 2), "the leader takes spawns.enemies[0]")
	assert_eq(str(battle.units[1].id), "ma_youwei", "the leader is the first enemy unit")


func test_setup_missing_map_returns_errors() -> void:
	var built: Dictionary = TacticsSetup.build(
		"does_not_exist", [{"id": "bandit", "count": 1}], null, 1)
	assert_true(not bool(built["ok"]))
	var errors: Array = built["errors"]
	assert_true(errors.size() > 0, "errors are reported")
	assert_true(_errors_contain(errors, "cannot read"), "the missing map is named")


func test_rush_ai_closes_distance() -> void:
	var player = _player("player", Vector2i(0, 0), Facing.RIGHT, _stats(0, 1), 500)
	var enemy = _enemy("enemy", Vector2i(7, 0), Facing.LEFT, _stats(10, 20),
		[_move("swing", "heavy", 10, 0)])
	var battle = _battle(_grid(["........"]), [player, enemy])
	assert_eq(battle.begin_turn(), "enemy", "the faster enemy acts first")
	var before := Grid.manhattan(enemy.pos, player.pos)
	var events: Array = TacticsAi.take_turn(battle, "enemy", _rng(1))
	var attacked := _has_event_type(events, "hit")
	assert_true(
		attacked or Grid.manhattan(enemy.pos, player.pos) < before,
		"rush either closes the distance or attacks"
	)
	battle.end_turn("enemy")


func test_rush_ai_attacks_when_adjacent() -> void:
	var player = _player("player", Vector2i(0, 0), Facing.LEFT, _stats(0, 1), 500)
	var enemy = _enemy("enemy", Vector2i(1, 0), Facing.LEFT, _stats(10, 20),
		[_move("swing", "heavy", 10, 0)])
	var battle = _battle(_grid(["....."]), [player, enemy])
	assert_eq(battle.begin_turn(), "enemy")
	var events: Array = TacticsAi.take_turn(battle, "enemy", _rng(1))
	assert_eq(enemy.pos, Vector2i(1, 0), "no movement when already in range")
	assert_true(not _has_event_type(events, "move"))
	assert_true(_has_event_type(events, "hit"), "the adjacent player is attacked")
	assert_true(player.unit.hp < 500)
	battle.end_turn("enemy")


func test_rush_ai_prefers_back_attack() -> void:
	var player = _player("player", Vector2i(5, 3), Facing.RIGHT, _stats(0, 1), 500)
	var enemy = _enemy("enemy", Vector2i(1, 3), Facing.RIGHT, _stats(10, 20),
		[_move("swing", "heavy", 10, 0)])
	var battle = _battle(_grid([
		"........", "........", "........",
		"........", "........", "........"]), [player, enemy])
	assert_eq(battle.begin_turn(), "enemy")
	var events: Array = TacticsAi.take_turn(battle, "enemy", _rng(1))
	assert_eq(enemy.pos, Vector2i(4, 3), "the cell behind the player is preferred")
	var hit := _first_event(events, "hit")
	assert_true(not hit.is_empty(), "the player is hit from behind")
	assert_eq(str(hit.get("relation", "")), "back")
	battle.end_turn("enemy")


func test_archer_ai_keeps_distance_and_shoots() -> void:
	var player = _player("player", Vector2i(0, 0), Facing.RIGHT, _stats(0, 1), 500)
	var archer = _enemy("archer", Vector2i(2, 0), Facing.LEFT, _stats(6, 20), [
		_move("slash", "sweep", 8, 0),
		_move("dart", "ranged", 7, 0, "ranged", 2, 4),
	], "archer")
	var battle = _battle(_grid(["........."]), [player, archer])
	assert_eq(battle.begin_turn(), "archer")
	var events: Array = TacticsAi.take_turn(battle, "archer", _rng(1))
	assert_true(Grid.manhattan(archer.pos, player.pos) >= 3, "the archer backs off")
	assert_true(_has_event_type(events, "move"), "it repositions first")
	assert_true(_has_event_type(events, "hit"), "then shoots")
	battle.end_turn("archer")


func test_guard_ai_waits_until_player_is_close() -> void:
	var far_player = _player("player", Vector2i(0, 0), Facing.RIGHT, _stats(0, 1), 500)
	var far_guard = _enemy("guard", Vector2i(9, 0), Facing.LEFT, _stats(10, 10),
		[_move("swing", "heavy", 10, 0)], "guard")
	var far_battle = _battle(_grid([".........."]), [far_player, far_guard])
	assert_eq(far_battle.begin_turn(), "guard")
	var far_events: Array = TacticsAi.take_turn(far_battle, "guard", _rng(1))
	assert_eq(far_guard.pos, Vector2i(9, 0), "a guard out of reach stays put")
	assert_true(not _has_event_type(far_events, "move"))
	assert_true(not _has_event_type(far_events, "hit"))
	assert_true(far_guard.has_acted, "waiting still ends the action")
	far_battle.end_turn("guard")

	var near_player = _player("player", Vector2i(0, 0), Facing.RIGHT, _stats(0, 1), 500)
	var near_guard = _enemy("guard", Vector2i(4, 0), Facing.LEFT, _stats(10, 10),
		[_move("swing", "heavy", 10, 0)], "guard")
	var near_battle = _battle(_grid([".........."]), [near_player, near_guard])
	assert_eq(near_battle.begin_turn(), "guard")
	var near_events: Array = TacticsAi.take_turn(near_battle, "guard", _rng(1))
	assert_true(
		_has_event_type(near_events, "move") or _has_event_type(near_events, "hit"),
		"a guard acts once the player is inside its reach"
	)
	assert_true(near_player.unit.hp < 500, "the nearby player is attacked")
	near_battle.end_turn("guard")


func test_bot_pick_reactions() -> void:
	var preview := [{
		"defender_id": "player",
		"options": [
			{"id": "parry", "verdict": Counter.Verdict.BARELY, "perfect": false},
			{"id": "taiji", "verdict": Counter.Verdict.ADVANTAGE, "perfect": false},
			{"id": "jueshi", "verdict": Counter.Verdict.ADVANTAGE, "perfect": true},
		],
	}]
	var best: Dictionary = TacticsBot.pick_reactions(preview, "best")
	assert_eq(str(best.get("player", "")), "jueshi", "perfect advantage wins")
	var never: Dictionary = TacticsBot.pick_reactions(preview, "never")
	assert_eq(never.size(), 0, "never mode declines every reaction")
	var empty: Dictionary = TacticsBot.pick_reactions(
		[{"defender_id": "player", "options": []}], "best")
	assert_eq(empty.size(), 0, "units without options are omitted")


func _run_game(seed_value: int) -> Dictionary:
	var built: Dictionary = TacticsSetup.build("tavern_brawl", TAVERN_GROUP, null, seed_value)
	if not bool(built["ok"]):
		return {"ok": false, "result": "setup_error", "actions": 0, "hp": 0}
	var battle: Variant = built["battle"]
	var rng := _rng(seed_value)
	var picker: Callable = func(preview: Array) -> Dictionary:
		return TacticsBot.pick_reactions(preview, "best")
	var actions := 0
	while battle.result() == "" and actions < MAX_ACTIONS:
		var actor: String = battle.begin_turn()
		if actor == "":
			break
		var unit = battle.get_unit(actor)
		if unit != null and unit.side == "player":
			TacticsBot.take_turn(battle, actor, rng, "best")
		else:
			TacticsAi.take_turn(battle, actor, rng, picker)
		battle.end_turn(actor)
		actions += 1
	var outcome: String = battle.result()
	if outcome == "":
		outcome = "timeout"
	var player = battle.get_unit("player")
	var hp := 0
	if player != null:
		hp = int(player.unit.hp)
	return {"ok": true, "result": outcome, "actions": actions, "hp": hp}


func test_full_battle_finishes_and_is_deterministic() -> void:
	var first := _run_game(11)
	assert_true(bool(first["ok"]), "the tavern battle is assembled")
	assert_true(str(first["result"]) != "timeout", "the fight ends within 200 actions")
	var second := _run_game(11)
	assert_eq(str(first["result"]), str(second["result"]), "same seed, same result")
	assert_eq(int(first["actions"]), int(second["actions"]), "same seed, same action count")
	assert_eq(int(first["hp"]), int(second["hp"]), "same seed, same remaining hp")

	var actions: Array = [int(first["actions"])]
	for seed_value in [12, 13, 14, 15, 16, 17]:
		var run := _run_game(seed_value)
		assert_true(bool(run["ok"]))
		assert_true(str(run["result"]) != "timeout", "seed %d also finishes" % seed_value)
		actions.append(int(run["actions"]))
	var all_same := true
	for value in actions:
		if int(value) != int(actions[0]):
			all_same = false
			break
	assert_true(not all_same, "different seeds change the action count at least once")


func _snapshot_state(battle, uid: String) -> String:
	var unit = battle.get_unit(uid)
	if unit == null:
		return "missing"
	return str({
		"pos": unit.pos,
		"facing": unit.facing,
		"hp": unit.unit.hp,
		"toughness": unit.unit.toughness_left,
		"has_moved": unit.has_moved,
		"has_acted": unit.has_acted,
		"energy": unit.energy_left,
		"reactions_left": unit.reactions_left,
		"current": battle.current_actor,
		"round": battle.round,
		"log": battle.log.size(),
		"queue": battle.queue.snapshot(),
	})


func _wait_events(battle, uid: String) -> Array:
	var result: Dictionary = battle.wait(uid)
	return result.get("events", [])


# 与视图一致的手动执行：move → face → attack；没有攻击时 wait。
func _manual_execute_plan(battle, uid: String, turn_plan: Dictionary) -> Array:
	var unit = battle.get_unit(uid)
	var events: Array = []
	if turn_plan.get("move", null) != null:
		var moved: Dictionary = battle.move(uid, turn_plan["move"])
		if not bool(moved["ok"]):
			return _wait_events(battle, uid)
		events.append_array(moved["events"])
	var attack_plan: Variant = turn_plan.get("attack", null)
	if attack_plan is Dictionary:
		var target_cell: Vector2i = attack_plan["target_cell"]
		battle.face(uid, Facing.from_delta(target_cell - unit.pos, unit.facing))
		var result: Dictionary = battle.attack(
			uid, str(attack_plan["martial_id"]), target_cell, {})
		if bool(result["ok"]):
			events.append_array(result["events"])
		else:
			events.append_array(_wait_events(battle, uid))
	else:
		events.append_array(_wait_events(battle, uid))
	return events


func _plan_battle(enemy_pos: Vector2i) -> Array:
	var player = _player("player", Vector2i(0, 0), Facing.RIGHT, _stats(0, 1), 500)
	var enemy = _enemy("enemy", enemy_pos, Facing.LEFT, _stats(10, 20),
		[_move("swing", "heavy", 10, 0)])
	var battle = _battle(_grid([".........."]), [player, enemy])
	return [battle, player, enemy]


func test_ai_plan_does_not_change_battle_state() -> void:
	var built := _plan_battle(Vector2i(4, 0))
	var battle: Variant = built[0]
	assert_eq(battle.begin_turn(), "enemy")
	var before := _snapshot_state(battle, "enemy")
	var turn_plan: Dictionary = TacticsAi.plan(battle, "enemy", _rng(5))
	assert_eq(_snapshot_state(battle, "enemy"), before, "plan is side-effect free")
	assert_true(turn_plan.get("move", null) != null, "the enemy plans to close in")
	assert_true(turn_plan.get("attack", null) is Dictionary, "the plan ends with an attack")
	battle.end_turn("enemy")


func test_ai_plan_matches_take_turn() -> void:
	for raw_pos in [Vector2i(4, 0), Vector2i(8, 0)]:
		var enemy_pos: Vector2i = raw_pos
		var manual_built := _plan_battle(enemy_pos)
		var manual_battle: Variant = manual_built[0]
		assert_eq(manual_battle.begin_turn(), "enemy")
		var turn_plan: Dictionary = TacticsAi.plan(manual_battle, "enemy", _rng(9))
		var manual_events: Array = _manual_execute_plan(manual_battle, "enemy", turn_plan)

		var auto_built := _plan_battle(enemy_pos)
		var auto_battle: Variant = auto_built[0]
		assert_eq(auto_battle.begin_turn(), "enemy")
		var auto_events: Array = TacticsAi.take_turn(auto_battle, "enemy", _rng(9))

		assert_eq(str(manual_events), str(auto_events),
			"manual plan execution matches take_turn at %s" % str(enemy_pos))
		assert_eq(_snapshot_state(manual_battle, "enemy"), _snapshot_state(auto_battle, "enemy"),
			"battle state matches at %s" % str(enemy_pos))
		assert_eq(int(manual_built[1].unit.hp), int(auto_built[1].unit.hp),
			"the player takes the same damage at %s" % str(enemy_pos))
		manual_battle.end_turn("enemy")
		auto_battle.end_turn("enemy")

extends "res://tests/test_case.gd"

const GameState = preload("res://core/game_state.gd")
const TacticsSession = preload("res://features/tactics/tactics_session.gd")

var results: Array = []


func _on_battle_finished(result: String) -> void:
	results.append(result)


func _new_game() -> Variant:
	Engine.set_meta("skip_title", true)
	GameState.reset()
	results.clear()
	var game: Variant = load("res://app/game.gd").new()
	game.show_town()
	return game


func test_build_uses_the_mixed_encounter_group() -> void:
	Engine.set_meta("legacy_battle", false)
	GameState.reset()
	GameState.encounter_group = [
		{"id": "ma_youwei", "count": 1},
		{"id": "bandit", "count": 3},
	]
	var built: Dictionary = TacticsSession.build("ma_youwei", 1, false, "tavern")
	assert_true(bool(built.get("ok", false)), "the mixed group builds a tactics battle")
	if not bool(built.get("ok", false)):
		return
	var battle: Variant = built["battle"]
	assert_eq(battle.units.size(), 5, "one player, the leader and three bandits")
	assert_true(battle.get_unit("ma_youwei") != null, "the leader is in the group")
	assert_eq(GameState.encounter_group.size(), 0, "the group is cleared after build")
	GameState.reset()


func test_boss_wound_applies_once_to_the_leader() -> void:
	Engine.set_meta("legacy_battle", false)
	GameState.reset()
	GameState.boss_hp_loss = 100
	GameState.encounter_group = [
		{"id": "ma_youwei", "count": 1},
		{"id": "bandit", "count": 1},
	]
	var built: Dictionary = TacticsSession.build("ma_youwei", 1, false, "tavern")
	assert_true(bool(built.get("ok", false)), "the wounded group builds")
	if not bool(built.get("ok", false)):
		return
	var battle: Variant = built["battle"]
	var boss = battle.get_unit("ma_youwei")
	var bandit = battle.get_unit("bandit")
	assert_true(boss != null and bandit != null, "the leader and the bandit exist")
	if boss != null:
		assert_eq(int(boss.unit.max_hp) - int(boss.unit.hp), 100, "the leader keeps its maximum")
		assert_eq(int(boss.unit.hp), int(boss.unit.max_hp) - 100, "the wound lowers current hp")
	if bandit != null:
		assert_eq(int(bandit.unit.hp), int(bandit.unit.max_hp), "bandits stay at full health")
	assert_eq(int(GameState.boss_hp_loss), 0, "the wound is spent after one build")

	var again: Dictionary = TacticsSession.build("ma_youwei", 1, false, "tavern")
	assert_true(bool(again.get("ok", false)), "a second build succeeds")
	if bool(again.get("ok", false)):
		var fresh = again["battle"].get_unit("ma_youwei")
		if fresh != null:
			assert_eq(int(fresh.unit.hp), int(fresh.unit.max_hp), "the wound is not applied twice")
	GameState.reset()


func test_first_strike_puts_the_player_first() -> void:
	Engine.set_meta("legacy_battle", false)
	GameState.reset()
	var plain: Dictionary = TacticsSession.build("bandit_scout", 1, false, "tavern")
	assert_true(bool(plain.get("ok", false)), "the plain battle builds")
	if bool(plain.get("ok", false)):
		assert_eq(
			str(plain["battle"].begin_turn()), "bandit_scout",
			"without the opening the faster scout acts first"
		)
	var striking: Dictionary = TacticsSession.build("bandit_scout", 1, true, "tavern")
	assert_true(bool(striking.get("ok", false)), "the first-strike battle builds")
	if bool(striking.get("ok", false)):
		assert_eq(str(striking["battle"].begin_turn()), "player",
			"first strike lets the player act before the fast scout")
	GameState.reset()


func test_origin_selects_the_tactics_map() -> void:
	Engine.set_meta("legacy_battle", false)
	GameState.reset()
	var tavern: Dictionary = TacticsSession.build("bandit", 1, false, "tavern")
	assert_eq(str(tavern.get("map_id", "")), "tavern_brawl", "tavern encounters use the brawl map")
	var forest: Dictionary = TacticsSession.build("bandit", 1, false, "forest")
	assert_eq(
		str(forest.get("map_id", "")), "forest_clearing", "forest encounters use the clearing"
	)
	var town: Dictionary = TacticsSession.build("bandit", 1, false, "town")
	assert_eq(str(town.get("map_id", "")), "tavern_brawl", "other origins fall back to the tavern")
	GameState.reset()


func test_victory_settles_mastery_exp_once() -> void:
	Engine.set_meta("legacy_battle", false)
	GameState.reset()
	var built: Dictionary = TacticsSession.build("bandit", 1, false, "tavern")
	assert_true(bool(built.get("ok", false)), "the battle builds")
	if not bool(built.get("ok", false)):
		return
	var battle: Variant = built["battle"]
	battle.get_unit("bandit").unit.hp = 0
	battle.log.append({"type": "attack", "unit": "player", "martial_id": "basic_sword"})
	var before := int(battle.mastery.exp_of("basic_sword"))
	TacticsSession.settle(battle)
	var after := int(battle.mastery.exp_of("basic_sword"))
	assert_eq(after - before, 15, "the bandit's kill exp lands on the used martial")
	assert_eq(
		int(GameState.mastery_total.get("basic_sword", 0)), after,
		"settling syncs the persistent mastery total"
	)
	TacticsSession.settle(battle)
	assert_eq(
		int(battle.mastery.exp_of("basic_sword")), after,
		"settling twice does not award exp twice"
	)
	GameState.reset()


func test_legacy_switch_still_uses_the_old_battle() -> void:
	Engine.set_meta("legacy_battle", true)
	var game: Variant = _new_game()
	var town: Variant = game.current
	town.encounter_requested.emit("bandit", 1, false)
	assert_eq(str(game.current_kind), "battle", "the legacy switch still enters a battle")
	var view: Variant = game.current
	assert_true(bool(view.has_method("press_return")), "the legacy battle view is used")
	assert_true(not bool(view.has_method("start_from_game")), "the tactics view is bypassed")
	game.free()
	GameState.reset()


func test_tactics_battle_reports_won() -> void:
	Engine.set_meta("legacy_battle", false)
	var game: Variant = _new_game()
	var town: Variant = game.current
	town.encounter_requested.emit("bandit", 1, false)
	var view: Variant = game.current
	assert_eq(str(game.current_kind), "battle", "the encounter enters the tactics battle")
	assert_true(bool(view.has_method("start_from_game")), "the tactics view is used")
	view.battle_finished.connect(Callable(self, "_on_battle_finished"))
	for unit in view.battle.units:
		if unit.side == "enemy":
			unit.unit.hp = 0
	view.choose_mode("end", "")
	assert_eq(str(view.restart_button.text), "继续", "the game battle offers continue")
	view.restart_button.pressed.emit()
	assert_eq(results, ["won"], "a tactics victory reports won")
	assert_eq(str(game.current_kind), "town", "the game returns to the origin scene")
	game.free()
	GameState.reset()


func test_tactics_battle_reports_lost() -> void:
	Engine.set_meta("legacy_battle", false)
	var game: Variant = _new_game()
	var town: Variant = game.current
	town.encounter_requested.emit("bandit", 1, false)
	var view: Variant = game.current
	view.battle_finished.connect(Callable(self, "_on_battle_finished"))
	view.battle.get_unit("player").unit.hp = 0
	view.choose_mode("end", "")
	view.restart_button.pressed.emit()
	assert_eq(results, ["lost"], "a tactics defeat reports lost")
	assert_eq(str(game.current_kind), "town", "a defeat also returns to the origin scene")
	game.free()
	GameState.reset()


func test_legacy_battle_reports_won_and_lost() -> void:
	Engine.set_meta("legacy_battle", true)
	var game: Variant = _new_game()
	game.current.encounter_requested.emit("bandit", 1, false)
	var won: Variant = game.current
	won.battle_finished.connect(Callable(self, "_on_battle_finished"))
	won.battle.enemies[0].hp = 0
	won.refresh()
	won.press_return()
	assert_eq(results, ["won"], "the legacy battle still reports won")
	game.free()

	game = _new_game()
	game.current.encounter_requested.emit("bandit", 1, false)
	var lost: Variant = game.current
	lost.battle_finished.connect(Callable(self, "_on_battle_finished"))
	lost.battle.player.hp = 0
	lost.refresh()
	lost.press_return()
	assert_eq(results, ["lost"], "the legacy battle still reports lost")
	game.free()
	GameState.reset()

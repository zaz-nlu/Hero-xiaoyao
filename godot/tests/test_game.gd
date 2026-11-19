extends "res://tests/test_case.gd"

const GameState = preload("res://core/game_state.gd")
const TownData = preload("res://shared/resources/town_data.gd")

var battle_finished_count: int = 0


func _new_game() -> Variant:
	Engine.set_meta("skip_title", true)
	# This suite asserts the legacy battle contract; the tactics flow has its own tests.
	Engine.set_meta("legacy_battle", true)
	var game: Variant = load("res://app/game.gd").new()
	game.show_town()
	return game


func _enter_tavern_battle(game: Variant) -> void:
	GameState.set_flag("bandits_entered")
	game.show_tavern()
	var tavern: Variant = game.current
	tavern.encounter_requested.emit("ma_youwei", 1, false)


func _finish_dialogue(view: Variant) -> void:
	for i in range(60):
		if not bool(view.dialogue_view.is_active()):
			return
		view.dialogue_view.advance()


func _on_battle_finished_counted(_result: String) -> void:
	battle_finished_count += 1


func test_show_town_creates_town() -> void:
	GameState.reset()
	var game: Variant = _new_game()
	assert_eq(str(game.current_kind), "town", "the game starts in the town")
	var town: Variant = game.current
	assert_eq(int(town.npc_nodes.size()), 21, "all twenty-one npcs are built")
	game.free()


func test_encounter_switches_to_battle() -> void:
	GameState.reset()
	var game: Variant = _new_game()
	_enter_tavern_battle(game)
	assert_eq(str(game.current_kind), "battle", "the encounter switches to the battle view")
	var view: Variant = game.current
	assert_eq(str(view.battle.enemies[0].id), "ma_youwei", "the boss is the enemy")
	assert_true(
		not bool(view.dialogue_view.is_active()),
		"the intro already played in the tavern, so it does not replay"
	)
	game.free()


func test_tavern_encounter_uses_tavern_backdrop() -> void:
	GameState.reset()
	var game: Variant = _new_game()
	_enter_tavern_battle(game)
	assert_eq(str(GameState.battle_backdrop), "tavern", "the battle uses the tavern backdrop")
	game.free()


func test_town_encounter_still_returns_to_town() -> void:
	GameState.reset()
	var game: Variant = _new_game()
	var town: Variant = game.current
	town.player_pos = Vector2(7.0, -2.0)
	town.encounter_requested.emit("bandit", 1, false)
	var view: Variant = game.current
	view.battle.player.hp = 0
	view.refresh()
	view.press_return()
	assert_eq(str(game.current_kind), "town", "a town encounter still returns to the town")
	var back: Variant = game.current
	assert_eq(back.player_pos, Vector2(7.0, -2.0), "the player returns to the saved position")
	game.free()


func test_battle_won_returns_to_tavern_aftermath() -> void:
	GameState.reset()
	var game: Variant = _new_game()
	_enter_tavern_battle(game)
	var view: Variant = game.current
	view.battle.enemies[0].hp = 10
	view.press_action({"kind": "jianyi", "target": 0})
	_finish_dialogue(view)
	assert_true(bool(view.return_button.visible), "the return button shows once the battle is over")
	view.press_return()
	assert_eq(str(game.current_kind), "tavern", "returning goes back to the tavern")
	assert_true(GameState.has_flag("boss_defeated"), "winning sets the boss_defeated flag")
	var back: Variant = game.current
	assert_eq(str(back.current_state()), "aftermath", "the tavern is in the aftermath")
	assert_true(not back.npc_nodes.has("ma_youwei"), "the boss is gone")
	assert_true(not back.npc_nodes.has("bandit_1"), "the bandits are gone")
	game.free()
	GameState.reset()


func test_battle_lost_returns_to_tavern_brawl() -> void:
	GameState.reset()
	var game: Variant = _new_game()
	_enter_tavern_battle(game)
	var view: Variant = game.current
	view.battle.player.hp = 0
	view.refresh()
	assert_true(bool(view.return_button.visible), "the return button shows after a loss")
	view.press_return()
	assert_eq(str(game.current_kind), "tavern", "a loss returns to the tavern")
	assert_true(not GameState.has_flag("boss_defeated"), "a loss does not set the boss flag")
	var back: Variant = game.current
	assert_eq(str(back.current_state()), "brawl", "the tavern is still in the brawl")
	assert_eq(int(back.bandit_count()), 5, "all five bandits are still there")
	game.free()
	GameState.reset()


func test_return_button_hidden_while_battle_ongoing() -> void:
	GameState.reset()
	battle_finished_count = 0
	var game: Variant = _new_game()
	_enter_tavern_battle(game)
	var view: Variant = game.current
	view.connect("battle_finished", Callable(self, "_on_battle_finished_counted"))
	assert_true(
		not bool(view.return_button.visible),
		"the return button is hidden while the battle is ongoing"
	)
	view.press_return()
	assert_eq(battle_finished_count, 0, "pressing return during the battle emits nothing")
	game.free()
	GameState.reset()


func test_start_three_args_still_plays_intro() -> void:
	var view: Variant = load("res://features/battle/battle_view.gd").new()
	view.build_ui()
	view.start("ma_youwei", 1, false)
	assert_true(bool(view.dialogue_view.is_active()), "a three-argument start plays the intro")
	view.free()

	var quiet: Variant = load("res://features/battle/battle_view.gd").new()
	quiet.build_ui()
	quiet.start("ma_youwei", 1, false, false)
	assert_true(
		not bool(quiet.dialogue_view.is_active()),
		"a four-argument start can skip the intro"
	)
	quiet.free()


func test_town_tavern_round_trip() -> void:
	GameState.reset()
	var game: Variant = _new_game()
	var town: Variant = game.current
	var return_pos: Vector2 = town.tavern_return_pos()
	town.enter_requested.emit("tavern")
	assert_eq(str(game.current_kind), "tavern", "the tavern door enters the tavern")
	var tavern: Variant = game.current
	tavern.exit_requested.emit()
	assert_eq(str(game.current_kind), "town", "leaving the tavern returns to the town")
	var back: Variant = game.current
	assert_true(
		back.player_pos.distance_to(return_pos) < 0.01,
		"the player comes back to the spot in front of the tavern door"
	)
	game.free()


func test_town_forest_round_trip() -> void:
	GameState.reset()
	var game: Variant = _new_game()
	var town: Variant = game.current
	town.enter_requested.emit("forest")
	assert_eq(str(game.current_kind), "forest", "the south exit enters the forest")
	var forest: Variant = game.current
	forest.exit_requested.emit("town")
	assert_eq(str(game.current_kind), "town", "leaving the forest returns to the town")
	var back: Variant = game.current
	var expected_return: Vector2 = TownData.forest_return(back.data)
	assert_true(
		back.player_pos.distance_to(expected_return) < 0.01,
		"the player comes back to the spot in front of the forest exit"
	)
	game.free()


func test_forest_battle_returns_to_forest() -> void:
	GameState.reset()
	var game: Variant = _new_game()
	var town: Variant = game.current
	town.enter_requested.emit("forest")
	var forest: Variant = game.current
	forest.player_pos = Vector2(3.0, 9.0)
	forest.encounter_requested.emit("bandit", 1, false)
	assert_eq(str(game.current_kind), "battle", "a forest encounter enters the battle")
	assert_eq(str(GameState.battle_backdrop), "forest", "the battle uses the forest backdrop")
	assert_eq(GameState.forest_return_pos, Vector2(3.0, 9.0), "the forest position is saved")
	var view: Variant = game.current
	view.battle.player.hp = 0
	view.refresh()
	view.press_return()
	assert_eq(str(game.current_kind), "forest", "the battle returns to the forest")
	assert_eq(str(GameState.battle_backdrop), "town", "the backdrop resets after the battle")
	assert_true(GameState.forest_return_pos == null, "a loss clears the saved forest position")
	var back: Variant = game.current
	assert_true(
		back.player_pos.distance_to(Vector2(0.0, 21.5)) < 0.01,
		"a loss respawns the player at the forest entrance"
	)
	game.free()


func test_wasteland_exit_shows_toast() -> void:
	GameState.reset()
	var game: Variant = _new_game()
	var town: Variant = game.current
	town.enter_requested.emit("forest")
	var forest: Variant = game.current
	forest.exit_requested.emit("wasteland")
	assert_eq(str(game.current_kind), "forest", "the wasteland placeholder stays in the forest")
	assert_true(GameState.toasts.has("前方荒山，暂时过不去"), "a toast explains the blocked path")
	game.free()

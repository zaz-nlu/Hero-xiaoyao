extends "res://tests/test_case.gd"

const GameState = preload("res://core/game_state.gd")

var battle_finished_count: int = 0


func _new_game() -> Variant:
	var game: Variant = load("res://ui/game.gd").new()
	game.show_town()
	return game


func _enter_boss_battle(game: Variant) -> void:
	var town: Variant = game.current
	town.encounter_requested.emit("ma_youwei", 1, false)


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
	assert_eq(int(town.npc_nodes.size()), 5, "all five npcs are built")
	game.free()


func test_encounter_switches_to_battle() -> void:
	GameState.reset()
	var game: Variant = _new_game()
	_enter_boss_battle(game)
	assert_eq(str(game.current_kind), "battle", "the encounter switches to the battle view")
	var view: Variant = game.current
	assert_eq(str(view.battle.enemies[0].id), "ma_youwei", "the boss is the enemy")
	assert_true(
		not bool(view.dialogue_view.is_active()),
		"the intro already played in the town, so it does not replay"
	)
	game.free()


func test_encounter_saves_return_position() -> void:
	GameState.reset()
	var game: Variant = _new_game()
	var town: Variant = game.current
	town.player_pos = Vector2(7.0, 2.5)
	_enter_boss_battle(game)
	assert_eq(
		GameState.town_return_pos, Vector2(7.0, 2.5),
		"the player position is saved before the battle"
	)
	game.free()


func test_battle_won_returns_to_town_and_removes_bandits() -> void:
	GameState.reset()
	var game: Variant = _new_game()
	var town: Variant = game.current
	town.player_pos = Vector2(7.0, 2.5)
	_enter_boss_battle(game)
	var view: Variant = game.current
	view.battle.enemies[0].hp = 10
	view.press_action({"kind": "jianyi", "target": 0})
	_finish_dialogue(view)
	assert_true(bool(view.return_button.visible), "the return button shows once the battle is over")
	view.press_return()
	assert_eq(str(game.current_kind), "town", "returning goes back to the town")
	assert_true(GameState.has_flag("boss_defeated"), "winning sets the boss_defeated flag")
	var back: Variant = game.current
	assert_eq(int(back.npc_nodes.size()), 2, "the boss and the two bandits are gone")
	assert_eq(back.player_pos, Vector2(7.0, 2.5), "the player returns to the saved position")
	game.free()


func test_battle_lost_returns_to_town_without_flag() -> void:
	GameState.reset()
	var game: Variant = _new_game()
	_enter_boss_battle(game)
	var view: Variant = game.current
	view.battle.player.hp = 0
	view.refresh()
	assert_true(bool(view.return_button.visible), "the return button shows after a loss")
	view.press_return()
	assert_eq(str(game.current_kind), "town", "a loss returns to the town")
	assert_true(not GameState.has_flag("boss_defeated"), "a loss does not set the boss flag")
	var back: Variant = game.current
	assert_eq(int(back.npc_nodes.size()), 5, "every npc is still in the town")
	game.free()


func test_return_button_hidden_while_battle_ongoing() -> void:
	GameState.reset()
	battle_finished_count = 0
	var game: Variant = _new_game()
	_enter_boss_battle(game)
	var view: Variant = game.current
	view.connect("battle_finished", Callable(self, "_on_battle_finished_counted"))
	assert_true(
		not bool(view.return_button.visible),
		"the return button is hidden while the battle is ongoing"
	)
	view.press_return()
	assert_eq(battle_finished_count, 0, "pressing return during the battle emits nothing")
	game.free()


func test_start_three_args_still_plays_intro() -> void:
	var view: Variant = load("res://ui/battle_view.gd").new()
	view.build_ui()
	view.start("ma_youwei", 1, false)
	assert_true(bool(view.dialogue_view.is_active()), "a three-argument start plays the intro")
	view.free()

	var quiet: Variant = load("res://ui/battle_view.gd").new()
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

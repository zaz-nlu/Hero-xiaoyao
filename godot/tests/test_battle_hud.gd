extends "res://tests/test_case.gd"

const GameState = preload("res://core/game_state.gd")


func _make_view() -> Variant:
	var view: Variant = load("res://features/battle/battle_view.gd").new()
	view.build_ui()
	return view


func _press_key(view: Variant, code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	view._unhandled_input(event)


func _finish_dialogue(view: Variant) -> void:
	for i in range(40):
		if not bool(view.dialogue_view.is_active()):
			return
		view.dialogue_view.advance()


func test_number_key_uses_first_martial() -> void:
	var view: Variant = _make_view()
	view.start("bandit", 1, true)
	_press_key(view, KEY_1)
	assert_eq(int(view.battle.round), 2, "pressing 1 submits the first martial")
	assert_true(view.battle.log.size() > 0, "the battle log records the action")
	view.free()


func test_keys_are_blocked_during_dialogue() -> void:
	var view: Variant = _make_view()
	view.start("ma_youwei", 1, false)
	assert_true(bool(view.dialogue_view.is_active()), "the boss intro is playing")
	_press_key(view, KEY_1)
	assert_eq(int(view.battle.round), 1, "digit keys do nothing while a dialogue is active")
	_finish_dialogue(view)
	_press_key(view, KEY_1)
	assert_eq(int(view.battle.round), 2, "digit keys work again once the dialogue ends")
	view.free()


func test_enemy_head_click_changes_target() -> void:
	var view: Variant = _make_view()
	view.start("bandit", 2, false)
	assert_eq(int(view.selected_target), 0, "the first enemy starts selected")
	view.target_buttons[1].emit_signal("pressed")
	assert_eq(int(view.selected_target), 1, "clicking an enemy head label selects it")
	view.free()


func test_one_head_label_per_enemy() -> void:
	var view: Variant = _make_view()
	view.start("bandit", 2, false)
	assert_eq(view.enemy_head_labels.size(), 2, "two enemies get two head labels")
	assert_eq(view.target_buttons.size(), 2, "each head label has a target button")
	view.start("bandit", 1, false)
	assert_eq(view.enemy_head_labels.size(), 1, "one enemy leaves one head label")
	assert_eq(view.intent_labels.size(), 1, "the intent labels follow the enemy count")
	view.free()


func test_debug_top_bar_is_hidden_in_game() -> void:
	GameState.reset()
	Engine.set_meta("skip_title", true)
	# The TopBar node only exists on the legacy battle view.
	Engine.set_meta("legacy_battle", true)
	var game: Variant = load("res://app/game.gd").new()
	game.show_town()
	var town: Variant = game.current
	town.encounter_requested.emit("bandit", 1, false)
	assert_eq(str(game.current_kind), "battle", "the encounter enters the battle")
	var view: Variant = game.current
	var top_bar: Control = view.get_node("TopBar")
	assert_true(top_bar != null, "the debug top bar node still exists")
	assert_true(not top_bar.visible, "the debug top bar is hidden inside the game")
	game.free()


func test_f1_toggles_the_log() -> void:
	var view: Variant = _make_view()
	view.start("bandit", 1, true)
	assert_true(not bool(view.log_label.visible), "the battle log starts hidden")
	_press_key(view, KEY_F1)
	assert_true(bool(view.log_label.visible), "F1 shows the log")
	_press_key(view, KEY_F1)
	assert_true(not bool(view.log_label.visible), "F1 hides the log again")
	view.free()

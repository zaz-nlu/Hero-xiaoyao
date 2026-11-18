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


func _popup_texts(stage: Variant) -> String:
	var texts := ""
	for entry in stage.popups:
		var label: Label3D = entry["node"]
		texts += str(label.text) + "\n"
	return texts


func test_unknown_intent_hides_name_and_verdict() -> void:
	GameState.reset()
	var view: Variant = _make_view()
	view.start("bandit", 1, true)
	assert_true(view.intent_labels[0].text.contains("？？？"), "an unknown move shows no name")
	for badge in view.martial_badges:
		assert_eq(badge.text, "？", "an unknown move leaves the verdict as a question mark")
	view.free()
	GameState.reset()


func test_foresight_key_spends_point_and_reveals_moves() -> void:
	GameState.reset()
	var view: Variant = _make_view()
	view.start("bandit", 1, true)
	var points_before: int = int(view.battle.player.foresight_points)
	_press_key(view, KEY_7)
	assert_eq(int(view.battle.round), 2, "foresight spends the action and advances the round")
	assert_eq(int(view.battle.player.foresight_points), points_before - 1, "one foresight point is spent")
	var intent_name: String = str(view.battle.intents[0]["name"])
	assert_true(not view.intent_labels[0].text.contains("？？？"), "the foreseen move is no longer hidden")
	assert_true(view.intent_labels[0].text.contains(intent_name), "the foreseen move name is shown")
	assert_true(view.foresight_labels[0].visible, "the foresight line is visible after foresight")
	assert_true(view.foresight_labels[0].text.contains("→"), "the foresight line lists the coming moves in order")
	assert_true(_popup_texts(view.stage).contains("料敌机先"), "foresight shows its popup")
	view.free()
	GameState.reset()


func test_foresight_card_click_spends_point() -> void:
	GameState.reset()
	var view: Variant = _make_view()
	view.start("bandit", 1, true)
	var points_before: int = int(view.battle.player.foresight_points)
	view.foresight_button.emit_signal("pressed")
	assert_eq(int(view.battle.round), 2, "clicking the foresight card uses the action")
	assert_eq(int(view.battle.player.foresight_points), points_before - 1, "clicking spends one point")
	view.free()
	GameState.reset()


func test_foresight_card_disabled_without_points() -> void:
	GameState.reset()
	var view: Variant = _make_view()
	view.start("bandit", 1, true)
	view.battle.player.foresight_points = 0
	view.refresh()
	assert_true(view.foresight_button.disabled, "no foresight points leaves the card disabled")
	_press_key(view, KEY_7)
	assert_eq(int(view.battle.round), 1, "a disabled foresight card does nothing")
	view.free()
	GameState.reset()


func test_known_moves_survive_battle_and_next_fight() -> void:
	GameState.reset()
	var view: Variant = _make_view()
	view.start("bandit", 1, true)
	var executed_id: String = str(view.battle.intents[0]["id"])
	view.press_action({"kind": "martial", "id": "basic_sword", "target": 0})
	assert_true(
		GameState.known_moves.get("bandit", []).has(executed_id),
		"the executed move is remembered outside the battle"
	)
	var results: Array = []
	view.battle_finished.connect(func(result: String) -> void:
		results.append(result)
	)
	view.battle.enemies[0].hp = 10
	view.press_action({"kind": "jianyi", "target": 0})
	view.press_return()
	assert_eq(results, ["won"], "the battle finishes before the knowledge is checked")
	assert_true(not GameState.known_moves.is_empty(), "known moves survive battle_finished")
	view.free()

	var next_view: Variant = _make_view()
	next_view.start("bandit", 1, true)
	assert_true(
		not next_view.intent_labels[0].text.contains("？？？"),
		"a move seen in an earlier battle is recognized in the next one"
	)
	var next_name: String = str(next_view.battle.intents[0]["name"])
	assert_true(next_view.intent_labels[0].text.contains(next_name), "the known move name is shown")
	next_view.free()
	GameState.reset()


func test_foresight_is_blocked_during_dialogue() -> void:
	GameState.reset()
	var view: Variant = _make_view()
	view.start("ma_youwei", 1, false)
	assert_true(bool(view.dialogue_view.is_active()), "the boss intro is playing")
	var points_before: int = int(view.battle.player.foresight_points)
	_press_key(view, KEY_7)
	assert_eq(int(view.battle.round), 1, "the key does nothing while a dialogue is active")
	assert_eq(int(view.battle.player.foresight_points), points_before, "no point is spent during dialogue")
	view.free()
	GameState.reset()

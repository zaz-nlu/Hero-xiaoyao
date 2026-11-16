extends "res://tests/test_case.gd"

const Battle = preload("res://core/battle.gd")


func _make_view() -> Variant:
	var view: Variant = load("res://ui/battle_view.gd").new()
	view.build_ui()
	return view


func test_view_starts_and_shows_intent() -> void:
	var view: Variant = _make_view()
	view.start("bandit", 1, true)
	var intent_name: String = str(view.battle.intents[0]["name"])
	assert_true(intent_name != "", "bandit has an intent")
	assert_true(view.intent_labels[0].text.contains(intent_name), "intent label shows the move name")
	view.free()


func test_martial_buttons_show_verdict_marks() -> void:
	var view: Variant = _make_view()
	view.start("bandit", 1, true)
	assert_eq(view.martial_buttons.size(), view.battle.loadout.size(), "one button per martial in loadout")
	for button in view.martial_buttons:
		var marked: bool = false
		for mark in ["✅", "⚠", "❌"]:
			if button.text.contains(mark):
				marked = true
				break
		assert_true(marked, "martial button '%s' carries a verdict mark" % button.text)
	view.free()


func test_press_action_advances_round() -> void:
	var view: Variant = _make_view()
	view.start("bandit", 1, true)
	view.press_action({"kind": "martial", "id": "basic_sword", "target": 0})
	assert_eq(int(view.battle.round), 2, "a submitted action advances the round")
	assert_true(view.battle.log.size() > 0, "battle log is not empty after an action")
	view.free()


func test_invalid_action_is_reported_not_crashing() -> void:
	var view: Variant = _make_view()
	view.start("bandit", 1, true)
	view.press_action({"kind": "jianyi", "target": 0})
	assert_eq(int(view.battle.state()), Battle.State.WON, "jianyi kills the bandit")
	var round_before: int = int(view.battle.round)
	view.press_action({"kind": "martial", "id": "basic_sword", "target": 0})
	assert_eq(int(view.battle.round), round_before, "an invalid action does not advance the round")
	assert_true(view.last_error != "", "the invalid action error is recorded")
	view.free()


func test_win_shows_result() -> void:
	var view: Variant = _make_view()
	view.start("bandit", 1, true)
	view.press_action({"kind": "jianyi", "target": 0})
	assert_true(view.result_label.text.contains("胜利"), "result label announces the win")
	view.free()


func test_probe_reveals_weak_in_ui() -> void:
	var view: Variant = _make_view()
	view.start("ma_youwei", 1, false)
	assert_true(view.weak_labels[0].text.contains("未知"), "weakness is hidden before probing")
	var guard := 0
	while view.dialogue_view.is_active() and guard < 40:
		view.dialogue_view.advance()
		guard += 1
	view.press_action({"kind": "probe", "target": 0})
	assert_true(view.weak_labels[0].text.contains("开山"), "weakness is revealed after probing")
	view.free()


func test_two_enemies_build_two_groups() -> void:
	var view: Variant = _make_view()
	view.start("bandit", 2, false)
	assert_eq(view.intent_labels.size(), 2, "each enemy gets its own intent label")
	view.free()

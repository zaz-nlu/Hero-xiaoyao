extends "res://tests/test_case.gd"

const Battle = preload("res://core/battle.gd")
const DataLoader = preload("res://core/data_loader.gd")
const GameState = preload("res://core/game_state.gd")
const Mastery = preload("res://core/mastery.gd")


func _make_view() -> Variant:
	var view: Variant = load("res://ui/battle_view.gd").new()
	view.build_ui()
	return view


func test_view_starts_and_shows_intent() -> void:
	GameState.reset()
	var view: Variant = _make_view()
	view.start("bandit", 1, true)
	var intent_name: String = str(view.battle.intents[0]["name"])
	assert_true(intent_name != "", "bandit has an intent")
	assert_true(view.intent_labels[0].text.contains("？？？"), "an unknown intent hides the move name")
	var intent_id: String = str(view.battle.intents[0]["id"])
	var enemy_key: String = str(view.battle.enemies[0].id)
	view.battle.known_moves[enemy_key] = [intent_id]
	view.refresh()
	assert_true(view.intent_labels[0].text.contains(intent_name), "a recognized intent shows the move name")
	view.free()
	GameState.reset()


func test_martial_buttons_show_verdict_marks() -> void:
	GameState.reset()
	var view: Variant = _make_view()
	view.start("bandit", 1, true)
	assert_eq(view.martial_buttons.size(), view.battle.loadout.size(), "one button per martial in loadout")
	assert_eq(view.martial_badges.size(), view.battle.loadout.size(), "one verdict badge per martial card")
	for badge in view.martial_badges:
		assert_eq(badge.text, "？", "an unknown enemy move leaves the verdict hidden")
	var intent_id: String = str(view.battle.intents[0]["id"])
	var enemy_key: String = str(view.battle.enemies[0].id)
	view.battle.known_moves[enemy_key] = [intent_id]
	view.refresh()
	for badge in view.martial_badges:
		var marked: bool = false
		for mark in ["✅", "⚠", "❌"]:
			if badge.text.contains(mark):
				marked = true
				break
		assert_true(marked, "martial card badge '%s' carries a verdict mark" % badge.text)
	view.free()
	GameState.reset()


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
	view.battle.enemies[0].hp = 30  # jianyi deals 42 now, a full-health bandit has 55
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
	view.battle.enemies[0].hp = 30
	view.press_action({"kind": "jianyi", "target": 0})
	assert_true(view.result_label.text.contains("胜利"), "result label announces the win")
	view.free()


func test_probe_reveals_weak_in_ui() -> void:
	var view: Variant = _make_view()
	view.start("ma_youwei", 1, false)
	assert_true(view.weak_labels[0].text.contains("？"), "weakness is hidden before probing")
	var guard := 0
	while view.dialogue_view.is_active() and guard < 40:
		view.dialogue_view.advance()
		guard += 1
	view.press_action({"kind": "probe", "target": 0})
	assert_true(view.weak_labels[0].text.contains("刺喉"), "weakness is revealed after probing")
	view.free()


func test_two_enemies_build_two_groups() -> void:
	var view: Variant = _make_view()
	view.start("bandit", 2, false)
	assert_eq(view.intent_labels.size(), 2, "each enemy gets its own intent label")
	view.free()


func test_player_stats_include_game_state_bonus() -> void:
	GameState.reset()
	var player_data: Dictionary = DataLoader.load_player("res://data/player.json")
	var base_power := int(player_data.get("stats", {}).get("power", 0))
	var plain: Variant = _make_view()
	plain.start("bandit", 1, true)
	assert_eq(
		int(plain.battle.player.stats["power"]), base_power,
		"without growth the player keeps the base power"
	)
	plain.free()

	GameState.stat_bonus["power"] = 3
	var boosted: Variant = _make_view()
	boosted.start("bandit", 1, true)
	assert_eq(
		int(boosted.battle.player.stats["power"]), base_power + 3,
		"the permanent stat bonus is applied to the battle unit"
	)
	boosted.free()
	GameState.reset()


func test_mastery_carries_between_battles() -> void:
	GameState.reset()
	var first: Variant = _make_view()
	first.start("bandit", 1, true)
	first.press_action({"kind": "martial", "id": "basic_sword", "target": 0})
	assert_true(
		not GameState.mastery_total.is_empty(),
		"the first battle writes the persistent mastery total"
	)
	var first_mastery: Variant = Mastery.new()
	first_mastery.import_exp(GameState.mastery_total)
	var carried_level: int = int(first_mastery.level("basic_sword"))
	assert_true(carried_level >= 1, "the basic sword gained mastery exp")
	first.free()

	var second: Variant = _make_view()
	second.start("bandit", 1, true)
	assert_eq(
		int(second.battle.mastery.level("basic_sword")), carried_level,
		"a new battle imports the carried-over level"
	)
	second.free()
	GameState.reset()

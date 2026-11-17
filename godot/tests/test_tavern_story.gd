extends "res://tests/test_case.gd"

const GameState = preload("res://core/game_state.gd")

var encounter_count: int = 0
var encounter_args: Array = []
var last_open_text: String = ""
var last_ambush_text: String = ""


func _new_tavern() -> Variant:
	var tavern: Variant = load("res://world/tavern.gd").new()
	tavern.build()
	tavern.build_hud()
	return tavern


func _new_game() -> Variant:
	Engine.set_meta("skip_title", true)
	var game: Variant = load("res://ui/game.gd").new()
	game.show_town()
	return game


func _on_encounter(enemy_id: String, count: int, first_strike: bool) -> void:
	encounter_count += 1
	encounter_args = [enemy_id, count, first_strike]


func _finish_dialogue(tavern: Variant) -> void:
	for i in range(120):
		if not bool(tavern.dialogue_view.is_active()):
			return
		tavern.dialogue_view.advance()


func _bandit_nodes(tavern: Variant) -> int:
	var count := 0
	for id in tavern.npc_nodes.keys():
		if str(id).begins_with("bandit_"):
			count += 1
	return count


# 走进触发区 → 开场旁白 → brawl 动画 → 闯入对话 → encounter。
func _run_ambush(killed: int) -> Variant:
	GameState.reset()
	GameState.forest_bandits_killed = killed
	encounter_count = 0
	encounter_args.clear()
	last_open_text = ""
	last_ambush_text = ""
	var tavern: Variant = _new_tavern()
	tavern.connect("encounter_requested", Callable(self, "_on_encounter"))
	tavern.player_pos = Vector2(11.0, -4.0)
	tavern.check_story(0.016)
	assert_true(tavern.is_dialogue_active(), "the opening narration starts")
	last_open_text = str(tavern.dialogue_view.text_label.text)
	assert_true(GameState.has_flag("bandits_entered"), "the ambush sets bandits_entered")
	_finish_dialogue(tavern)
	assert_eq(str(tavern.current_state()), "brawl", "the tavern switches to the brawl")
	tavern.advance(5.0)
	assert_true(tavern.is_dialogue_active(), "the ambush dialogue follows the animation")
	last_ambush_text = str(tavern.dialogue_view.text_label.text)
	_finish_dialogue(tavern)
	return tavern


func test_ambush_flow_uses_the_remaining_bandit_count() -> void:
	var cases: Array = [[0, 5], [1, 4], [3, 2], [4, 2]]
	for case_value in cases:
		var case: Array = case_value
		var killed := int(case[0])
		var expected := int(case[1])
		var tavern: Variant = _run_ambush(killed)
		assert_eq(encounter_count, 1, "one encounter is requested (killed=%d)" % killed)
		assert_eq(str(last_open_text), "砰——酒馆的门被一脚踹开。", "the door is kicked open")
		if expected >= 4:
			assert_true(
				last_ambush_text.contains("一群人涌了进来"), "many bandits use the 'many' dialogue"
			)
		else:
			assert_true(
				last_ambush_text.contains("几个人走了进来"), "few bandits use the 'few' dialogue"
			)
		assert_eq(encounter_args.size(), 3, "the signal carries three arguments")
		if encounter_args.size() == 3:
			assert_eq(str(encounter_args[0]), "ma_youwei", "the boss leads the fight")
			assert_eq(int(encounter_args[1]), 1, "the signal count stays one boss")
			assert_eq(bool(encounter_args[2]), false, "the player does not strike first")
		assert_eq(GameState.encounter_group.size(), 2, "the encounter group has two entries")
		if GameState.encounter_group.size() == 2:
			var boss: Dictionary = GameState.encounter_group[0]
			var bandits: Dictionary = GameState.encounter_group[1]
			assert_eq(str(boss.get("id", "")), "ma_youwei", "the first group entry is the boss")
			assert_eq(int(boss.get("count", 0)), 1, "one boss")
			assert_eq(str(bandits.get("id", "")), "bandit", "the second entry is a bandit stack")
			assert_eq(int(bandits.get("count", 0)), expected, "N = clampi(5 - killed, 2, 5)")
		assert_eq(int(tavern.bandit_count()), expected, "the tavern reports the same count")
		assert_eq(_bandit_nodes(tavern), expected, "the brawl spawns exactly N bandits")
		tavern.free()
	GameState.reset()


func test_timeout_also_triggers_the_ambush() -> void:
	GameState.reset()
	var tavern: Variant = _new_tavern()
	tavern.connect("encounter_requested", Callable(self, "_on_encounter"))
	tavern.player_pos = Vector2(11.0, 3.5)
	tavern.check_story(0.5)
	assert_true(not tavern.is_dialogue_active(), "nothing happens before the timeout")
	tavern.check_story(14.0)
	assert_true(tavern.is_dialogue_active(), "standing around for 14 seconds triggers the ambush")
	assert_true(GameState.has_flag("bandits_entered"), "the timeout sets the flag")
	tavern.free()
	GameState.reset()


func test_reentry_skips_the_cutscene() -> void:
	GameState.reset()
	GameState.set_flag("bandits_entered")
	var tavern: Variant = _new_tavern()
	assert_eq(str(tavern.current_state()), "brawl", "a flagged tavern opens in the brawl")
	assert_true(not tavern.is_dialogue_active(), "no ambush cutscene replays")
	assert_true(not tavern.cutscene_running, "the tavern is not in a cutscene")
	tavern.free()
	GameState.reset()


func test_boss_defeated_opens_the_aftermath() -> void:
	GameState.reset()
	GameState.set_flag("boss_defeated")
	var tavern: Variant = _new_tavern()
	assert_eq(str(tavern.current_state()), "aftermath", "boss_defeated opens the aftermath")
	assert_true(not tavern.npc_nodes.has("ma_youwei"), "no boss in the aftermath")
	tavern.free()
	GameState.reset()


func test_talking_to_the_boss_in_the_brawl_starts_the_fight() -> void:
	GameState.reset()
	GameState.set_flag("bandits_entered")
	encounter_count = 0
	encounter_args.clear()
	var tavern: Variant = _new_tavern()
	tavern.connect("encounter_requested", Callable(self, "_on_encounter"))
	tavern.player_pos = Vector2(11.0, -1.8)
	assert_true(tavern.try_interact(), "talking to the boss starts the challenge")
	assert_true(tavern.is_dialogue_active(), "the ambush dialogue plays first")
	assert_eq(encounter_count, 0, "no encounter while the dialogue runs")
	_finish_dialogue(tavern)
	assert_eq(encounter_count, 1, "the encounter follows the dialogue")
	assert_eq(GameState.encounter_group.size(), 2, "the group is prepared for the battle")
	tavern.free()
	GameState.reset()


func test_game_returns_to_the_tavern_after_a_defeat() -> void:
	GameState.reset()
	GameState.set_flag("bandits_entered")
	var game: Variant = _new_game()
	game.show_tavern()
	var tavern: Variant = game.current
	tavern.encounter_requested.emit("ma_youwei", 1, false)
	var view: Variant = game.current
	assert_eq(str(game.current_kind), "battle", "the tavern encounter enters the battle")
	assert_eq(str(GameState.battle_backdrop), "tavern", "the tavern is the battle backdrop")
	view.battle.player.hp = 0
	view.refresh()
	view.press_return()
	assert_eq(str(game.current_kind), "tavern", "a loss returns to the tavern")
	var back: Variant = game.current
	assert_eq(str(back.current_state()), "brawl", "the tavern is still in the brawl")
	game.free()
	GameState.reset()


func test_game_returns_to_the_tavern_after_a_win() -> void:
	GameState.reset()
	GameState.set_flag("bandits_entered")
	var game: Variant = _new_game()
	game.show_tavern()
	var tavern: Variant = game.current
	tavern.encounter_requested.emit("ma_youwei", 1, false)
	var view: Variant = game.current
	view.battle.enemies[0].hp = 10
	view.press_action({"kind": "jianyi", "target": 0})
	_finish_dialogue(view)
	view.press_return()
	assert_eq(str(game.current_kind), "tavern", "a win returns to the tavern")
	assert_true(GameState.has_flag("boss_defeated"), "the win sets boss_defeated")
	var back: Variant = game.current
	assert_eq(str(back.current_state()), "aftermath", "the tavern shows the aftermath")
	game.free()
	GameState.reset()


func test_the_town_no_longer_has_bandits() -> void:
	GameState.reset()
	var town: Variant = load("res://world/town.gd").new()
	town.build()
	for id in ["ma_youwei", "bandit_1", "bandit_2"]:
		assert_true(not town.npc_nodes.has(id), "%s lives in the tavern now" % id)
	town.free()
	GameState.reset()


func test_forest_wins_count_the_bandits_that_were_beaten() -> void:
	GameState.reset()
	var game: Variant = _new_game()
	var town: Variant = game.current
	town.enter_requested.emit("forest")
	var forest: Variant = game.current
	forest.encounter_requested.emit("bandit", 2, false)
	var view: Variant = game.current
	view.battle.enemies[0].hp = 0
	view.battle.enemies[1].hp = 0
	view.refresh()
	view.press_return()
	assert_eq(
		GameState.forest_bandits_killed, 2,
		"winning a two-bandit forest fight counts two bandits"
	)
	game.free()
	GameState.reset()


extends "res://tests/test_case.gd"

# Demo 结尾：击败马匪 → 酒馆收尾对话 → 在真正的紫霞镇上演出（紫殇登场）→ 字卡 → 回标题。

const GameState = preload("res://core/game_state.gd")
const TownEnding = preload("res://features/ending/town_ending.gd")


func _new_game() -> Variant:
	GameState.reset()
	var game: Variant = load("res://app/game.gd").new()
	game.save_dir = "user://test_ending_" + str(Time.get_ticks_usec())
	return game


func test_ending_data_is_valid() -> void:
	var Dialogue = load("res://core/dialogue.gd")
	var speakers: Dictionary = Dialogue.load_speakers("res://data/speakers.json").get("defs", {})
	for path in ["res://data/dialogues/ending_tavern.json", "res://data/dialogues/ending_street.json"]:
		var loaded: Dictionary = Dialogue.load_file(path, speakers)
		assert_true((loaded.get("errors", []) as Array).is_empty(), "%s loads" % path)
		assert_true((loaded.get("lines", []) as Array).size() >= 5, "%s has lines" % path)
	assert_true(FileAccess.file_exists("res://assets/sprites/zishang.png"), "紫殇 has a sprite sheet")
	assert_true(FileAccess.file_exists("res://assets/portraits/zishang.png"), "紫殇 has a portrait")


func test_boss_victory_leads_to_tavern_talk_then_the_town_street() -> void:
	var game: Variant = _new_game()
	game.show_tavern()
	GameState.set_flag("bandits_entered")
	game._router.start_demo_ending(game.audio)
	assert_eq(str(game.current_kind), "tavern", "the wrap-up talk happens in the tavern first")
	var tavern: Variant = game.current
	assert_true(tavern.is_dialogue_active(), "the wrap-up dialogue plays")
	for i in range(60):
		if not tavern.is_dialogue_active():
			break
		tavern.dialogue_view.advance()
	assert_eq(str(game.current_kind), "town", "then the real town map takes over")
	var ending: Node = game.current.get_node_or_null("TownEnding")
	assert_true(ending != null, "the ending runs inside the town")
	game.free()
	GameState.reset()


func test_town_ending_runs_dialogue_pan_and_card() -> void:
	var game: Variant = _new_game()
	game.show_town()
	var town: Variant = game.current
	var ending: Node = TownEnding.new()
	town.add_child(ending)
	var done := [0]
	ending.finished.connect(func() -> void: done[0] += 1)
	ending.begin(town, null)
	assert_true(town.input_blocked, "the player cannot walk during the ending")
	assert_true(ending.zishang != null and ending.group.size() == 4, "紫殇 and the sect group are on the street")
	var start: Vector3 = ending.zishang.position
	ending.advance(TownEnding.INTRO_SECONDS)
	ending.advance(TownEnding.RUN_SECONDS * 0.5)
	assert_true(ending.zishang.position.distance_to(start) > 2.0, "紫殇 runs toward the group")
	ending.advance(TownEnding.RUN_SECONDS)
	assert_eq(ending.phase, TownEnding.Phase.DIALOGUE, "the talk starts when he arrives")
	for i in range(40):
		if not town.is_dialogue_active():
			break
		town.dialogue_view.advance()
	assert_eq(ending.phase, TownEnding.Phase.PAN, "the camera pans after the last line")
	ending.advance(TownEnding.PAN_SECONDS + 0.1)
	assert_eq(ending.phase, TownEnding.Phase.CARD, "the demo-complete card appears")
	ending.advance(TownEnding.CARD_AUTO_CLOSE + 0.1)
	assert_true(done[0] == 1 and not town.input_blocked, "it finishes once and releases the player")
	game.free()
	GameState.reset()

extends "res://tests/test_case.gd"

const GameState = preload("res://core/game_state.gd")
const OpeningData = preload("res://core/opening_data.gd")
const OpeningStoryScene = preload("res://features/opening/opening_story_scene.gd")

const SPRITES_DIR := "res://assets/sprites/"
const FADE_IN_TIME := 1.0


class FakeAudio extends RefCounted:
	var cues: Array[String] = []

	func play_cue(cue_id: String) -> void:
		cues.append(cue_id)


func _temp_dir(tag: String) -> String:
	return "user://test_opening_story_%s_%d" % [tag, Time.get_ticks_usec()]


func _cleanup(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		return
	var access := DirAccess.open(dir)
	if access == null:
		return
	access.list_dir_begin()
	var file_name := access.get_next()
	while file_name != "":
		if not access.current_is_dir():
			access.remove(file_name)
		file_name = access.get_next()
	access.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))


func _clear_skip_meta() -> void:
	for key in ["skip_title", "skip_opening"]:
		if Engine.has_meta(key):
			Engine.remove_meta(key)


func _valid_data() -> Dictionary:
	var storyteller: Dictionary = OpeningData.load_opening().get("storyteller", {})
	return {
		"music": {"intro": "opening_empire", "town": "opening_town"},
		"slides": [
			{
				"id": "s1",
				"seconds": 2.0,
				"lines": ["一句"],
				"backdrop": {
					"kind": "battlefield", "seed": 1, "palette": "ash", "density": 4
				},
			}
		],
		"storyteller": storyteller.duplicate(true),
	}


func _errors_text(result: Dictionary) -> String:
	var text := ""
	for message in result.get("errors", []):
		text += str(message) + "\n"
	return text


func _storyteller(data: Dictionary) -> Dictionary:
	var value: Variant = data.get("storyteller", {})
	if value is Dictionary:
		return value
	return {}


func test_storyteller_json_validates_and_sprites_exist() -> void:
	var data := OpeningData.load_opening()
	assert_true(bool(data.get("ok", false)), "the shipped opening.json validates")
	var storyteller := _storyteller(data)
	var dialogue := str(storyteller.get("dialogue", ""))
	assert_true(FileAccess.file_exists(dialogue), "the storyteller dialogue file exists")
	var crowd: Array = storyteller.get("crowd", [])
	assert_true(not crowd.is_empty(), "the storyteller has a crowd")
	var scholar_id := str(storyteller.get("scholar", ""))
	assert_true(
		FileAccess.file_exists(SPRITES_DIR + scholar_id + ".png"), "the scholar has a sprite"
	)
	for crowd_id in crowd:
		assert_true(
			FileAccess.file_exists(SPRITES_DIR + str(crowd_id) + ".png"),
			"crowd member %s has a sprite" % str(crowd_id),
		)


func test_storyteller_validation_reports_bad_data() -> void:
	var no_crowd := _valid_data()
	var no_crowd_story: Dictionary = no_crowd["storyteller"]
	no_crowd_story.erase("crowd")
	var no_crowd_result := OpeningData.validate(no_crowd)
	assert_true(not bool(no_crowd_result.get("ok", true)), "a missing crowd is rejected")
	assert_true(_errors_text(no_crowd_result).contains("crowd"), "the error names crowd")

	var bad_id := _valid_data()
	var bad_id_story: Dictionary = bad_id["storyteller"]
	bad_id_story["crowd"] = ["ghost"]
	var bad_id_result := OpeningData.validate(bad_id)
	assert_true(not bool(bad_id_result.get("ok", true)), "an unknown crowd id is rejected")
	assert_true(_errors_text(bad_id_result).contains("ghost"), "the error names the id")

	var no_dialogue := _valid_data()
	var no_dialogue_story: Dictionary = no_dialogue["storyteller"]
	no_dialogue_story["dialogue"] = "res://data/dialogues/missing_story.json"
	var no_dialogue_result := OpeningData.validate(no_dialogue)
	assert_true(
		not bool(no_dialogue_result.get("ok", true)), "a missing dialogue file is rejected"
	)
	assert_true(_errors_text(no_dialogue_result).contains("dialogue"), "the error names dialogue")


func test_scene_builds_headless_with_expected_actors() -> void:
	var data := OpeningData.load_opening()
	var scene: Variant = OpeningStoryScene.new()
	scene.build(data)
	var crowd: Array = _storyteller(data).get("crowd", [])
	assert_eq(scene.actors.size(), 2 + crowd.size(), "ren, the scholar and every crowd member")
	assert_true(scene.scholar != null, "the scholar node is built")
	scene.advance(FADE_IN_TIME)
	assert_true(scene.is_dialogue_active(), "the dialogue starts after the fade-in")
	scene.advance(0.5)
	assert_true(not scene.is_finished(), "the scene keeps running while the dialogue plays")
	scene.skip_all()
	assert_true(scene.is_finished(), "the scene can be skipped")
	scene.free()


func test_dialogue_finish_emits_finished_once() -> void:
	var count := [0]
	var scene: Variant = OpeningStoryScene.new()
	scene.connect("finished", func() -> void: count[0] += 1)
	scene.build(OpeningData.load_opening())
	scene.advance(FADE_IN_TIME)
	var guard := 0
	while scene.is_dialogue_active() and guard < 200:
		scene.dialogue_view.advance()
		guard += 1
	assert_true(not scene.is_dialogue_active(), "the dialogue plays to the end")
	scene.advance(1.0)
	assert_true(scene.is_finished(), "the story scene finishes after the fade-out")
	assert_eq(count[0], 1, "finished is emitted once")
	scene.advance(1.0)
	assert_eq(count[0], 1, "finished is not repeated after the scene ended")
	scene.free()


func test_escape_skips_the_whole_scene() -> void:
	var count := [0]
	var scene: Variant = OpeningStoryScene.new()
	scene.connect("finished", func() -> void: count[0] += 1)
	scene.build(OpeningData.load_opening())
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	scene._unhandled_input(event)
	assert_true(scene.is_finished(), "escape finishes the scene immediately")
	assert_eq(count[0], 1, "escape emits finished")
	scene._unhandled_input(event)
	assert_eq(count[0], 1, "escape does not repeat finished")
	scene.free()


func test_build_plays_the_story_cue() -> void:
	var fake := FakeAudio.new()
	var scene: Variant = OpeningStoryScene.new()
	scene.audio = fake
	scene.build(OpeningData.load_opening())
	assert_eq(fake.cues.size(), 1, "the storyteller cue plays when the scene starts")
	assert_eq(str(fake.cues[0]), "opening_town", "the cue id comes from music.town")
	scene.free()


func test_new_game_flow_runs_subtitles_then_story_then_town() -> void:
	_clear_skip_meta()
	GameState.reset()
	var game: Variant = load("res://app/game.gd").new()
	game.save_dir = _temp_dir("flow")
	var save_dir := str(game.save_dir)
	game.start_new_game()
	assert_eq(str(game.current_kind), "opening", "the subtitle slides play first")
	var opening: Variant = game.current
	opening.advance(opening.total_duration())
	assert_eq(str(game.current_kind), "battle", "the tutorial duel follows the subtitles")
	game.current.emit_signal("battle_finished", "won")
	game.current.advance(game.current.total_duration())
	assert_eq(
		str(game.current_kind), "opening_story", "the storyteller scene follows the subtitles"
	)
	var story: Variant = game.current
	assert_true(story.has_method("advance"), "the second stage is the storyteller scene")
	story.skip_all()
	assert_eq(str(game.current_kind), "town", "the town comes after both opening stages")
	assert_true(GameState.has_flag("opening_done"), "the finished opening sets opening_done")
	assert_true(GameState.has_flag("intro_hint_shown"), "the intro hints follow the opening")
	game.free()
	_cleanup(save_dir)
	_clear_skip_meta()

extends "res://tests/test_case.gd"

const GameState = preload("res://core/game_state.gd")
const OpeningData = preload("res://core/opening_data.gd")
const OpeningSequence = preload("res://features/opening/opening_sequence.gd")


class FakeAudio extends RefCounted:
	var cues: Array[String] = []

	func play_cue(cue_id: String) -> void:
		cues.append(cue_id)


func _temp_dir(tag: String) -> String:
	return "user://test_opening_%s_%d" % [tag, Time.get_ticks_usec()]


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


func _valid_slide() -> Dictionary:
	return {
		"id": "s1",
		"seconds": 2.0,
		"lines": ["一句"],
		"backdrop": {"kind": "battlefield", "seed": 1, "palette": "ash", "density": 4},
	}


func _valid_data() -> Dictionary:
	return {
		"music": {"intro": "opening_empire", "town": "opening_town"},
		"slides": [_valid_slide()],
		"storyteller": {},
	}


func _new_game(tag: String) -> Variant:
	var game: Variant = load("res://app/game.gd").new()
	game.save_dir = _temp_dir(tag)
	return game


func test_opening_json_passes_validation() -> void:
	var data := OpeningData.load_opening()
	assert_true(bool(data.get("ok", false)), "the shipped opening.json validates")
	var slides: Array = data.get("slides", [])
	assert_eq(slides.size(), 7, "the prologue has seven slides before the duel")
	for slide_value in slides:
		var slide: Dictionary = slide_value
		var lines: Array = slide.get("lines", [])
		assert_true(not lines.is_empty(), "every slide has at least one line")
	var music: Dictionary = data.get("music", {})
	assert_eq(str(music.get("intro", "")), "opening_empire", "the intro cue is read")


func test_bad_data_reports_errors() -> void:
	var empty := _valid_data()
	empty["slides"] = []
	var empty_result := OpeningData.validate(empty)
	assert_true(not bool(empty_result.get("ok", true)), "empty slides are rejected")
	assert_true(not (empty_result.get("errors", []) as Array).is_empty(), "empty slides explain")

	var zero := _valid_data()
	var zero_slide: Dictionary = (zero["slides"] as Array)[0]
	zero_slide["seconds"] = 0.0
	var zero_result := OpeningData.validate(zero)
	assert_true(not bool(zero_result.get("ok", true)), "zero seconds are rejected")
	assert_true(
		not (zero_result.get("errors", []) as Array).is_empty(), "zero seconds explain"
	)

	var palette := _valid_data()
	var palette_slide: Dictionary = (palette["slides"] as Array)[0]
	var palette_backdrop: Dictionary = palette_slide["backdrop"]
	palette_backdrop["palette"] = "violet"
	var palette_result := OpeningData.validate(palette)
	assert_true(not bool(palette_result.get("ok", true)), "unknown palettes are rejected")
	assert_true(
		not (palette_result.get("errors", []) as Array).is_empty(),
		"unknown palettes explain",
	)

	var seed_missing := _valid_data()
	var seed_slide: Dictionary = (seed_missing["slides"] as Array)[0]
	var seed_backdrop: Dictionary = seed_slide["backdrop"]
	seed_backdrop.erase("seed")
	var seed_result := OpeningData.validate(seed_missing)
	assert_true(not bool(seed_result.get("ok", true)), "a missing seed is rejected")
	assert_true(
		not (seed_result.get("errors", []) as Array).is_empty(), "a missing seed explains"
	)


func test_advance_reveals_lines_and_matches_total_duration() -> void:
	var opening: Variant = OpeningSequence.new()
	opening.build(OpeningData.load_opening())
	assert_eq(opening.slide_count(), 7, "seven slides are loaded")
	assert_near(opening.total_duration(), 52.0, 0.0001, "total duration is the seconds sum")
	assert_near(opening.line_alpha(0), 0.0, 0.0001, "the first line starts hidden")
	opening.advance(0.6)
	assert_near(opening.line_alpha(0), 1.0, 0.0001, "the first line fades in")
	assert_near(opening.line_alpha(1), 0.0, 0.0001, "the second line waits its window")
	opening.advance(3.0)
	assert_true(opening.line_alpha(1) > 0.0, "the second line starts after the first window")
	opening.advance(opening.total_duration())
	assert_true(opening.is_finished(), "advancing the whole timeline finishes the sequence")
	opening.free()


func test_skip_line_walks_lines_then_pages() -> void:
	var opening: Variant = OpeningSequence.new()
	opening.build(OpeningData.load_opening())
	opening.skip_line()
	assert_eq(opening.revealed_count(), 1, "the first skip shows the first line")
	assert_near(opening.line_alpha(0), 1.0, 0.0001, "the first line is fully shown")
	opening.skip_line()
	assert_eq(opening.revealed_count(), 2, "the second skip shows the last line of the page")
	opening.skip_line()
	assert_eq(opening.page_index(), 1, "skipping past the last line enters the next page")
	assert_true(not opening.is_finished(), "the sequence continues after a page skip")
	opening.free()


func test_skip_all_finishes_once() -> void:
	var opening: Variant = OpeningSequence.new()
	opening.build(OpeningData.load_opening())
	var count := [0]
	opening.connect("finished", func() -> void: count[0] += 1)
	opening.skip_all()
	opening.skip_all()
	assert_true(opening.is_finished(), "skip_all finishes the sequence")
	assert_eq(count[0], 1, "finished is emitted only once")
	opening.free()


func test_natural_end_finishes_once() -> void:
	var opening: Variant = OpeningSequence.new()
	opening.build(OpeningData.load_opening())
	var count := [0]
	opening.connect("finished", func() -> void: count[0] += 1)
	opening.advance(opening.total_duration())
	assert_true(opening.is_finished(), "the timeline ends after the last page")
	opening.advance(10.0)
	assert_eq(count[0], 1, "finished is not repeated after the sequence ended")
	opening.free()


func test_build_plays_the_intro_cue() -> void:
	var fake := FakeAudio.new()
	var opening: Variant = OpeningSequence.new()
	opening.audio = fake
	opening.build(OpeningData.load_opening())
	assert_eq(fake.cues.size(), 1, "the opening cue plays when the sequence starts")
	assert_eq(str(fake.cues[0]), "opening_empire", "the cue id comes from music.intro")
	opening.free()


func test_start_new_game_with_skip_title_enters_town() -> void:
	_clear_skip_meta()
	Engine.set_meta("skip_title", true)
	GameState.reset()
	var game: Variant = _new_game("skip")
	var save_dir := str(game.save_dir)
	game.start_new_game()
	assert_eq(str(game.current_kind), "town", "skip_title starts the new game in the town")
	assert_true(not GameState.has_flag("opening_done"), "no opening ran")
	game.free()
	_cleanup(save_dir)
	_clear_skip_meta()


func test_start_new_game_plays_opening_then_enters_town() -> void:
	_clear_skip_meta()
	GameState.reset()
	var game: Variant = _new_game("opening")
	var save_dir := str(game.save_dir)
	game.start_new_game()
	assert_eq(str(game.current_kind), "opening", "a fresh game starts with the prologue")
	var opening: Variant = game.current
	assert_true(opening.has_method("advance"), "the prologue is the opening sequence")
	opening.advance(opening.total_duration())
	assert_eq(str(game.current_kind), "battle", "the prologue plays the tutorial duel next")
	game.current.emit_signal("battle_finished", "lost")
	assert_eq(str(game.current_kind), "battle", "losing the tutorial duel retries it")
	game.current.emit_signal("battle_finished", "won")
	assert_eq(str(game.current_kind), "opening", "the epilogue slides follow the duel")
	game.current.advance(game.current.total_duration())
	assert_eq(
		str(game.current_kind), "opening_story", "the prologue hands over to the storyteller"
	)
	var story: Variant = game.current
	assert_true(story.has_method("advance"), "the storyteller scene is the second stage")
	story.skip_all()
	assert_eq(str(game.current_kind), "town", "the storyteller hands over to the town")
	assert_true(GameState.has_flag("opening_done"), "finishing the prologue sets opening_done")
	game.free()
	_cleanup(save_dir)
	_clear_skip_meta()


func test_continue_skips_the_opening() -> void:
	_clear_skip_meta()
	Engine.set_meta("skip_title", true)
	GameState.reset()
	var game: Variant = _new_game("continue")
	var save_dir := str(game.save_dir)
	game.start_new_game()
	var town: Variant = game.current
	assert_eq(str(game.current_kind), "town", "the save is written from the town")
	town.player_pos = Vector2(2.0, 3.0)
	assert_true(bool(game.save_to_slot("1")), "the town state is saved")
	game.go_to_title()
	_clear_skip_meta()
	var title: Variant = game.current
	title.load_requested.emit("1")
	assert_eq(str(game.current_kind), "town", "continuing goes straight back to the town")
	assert_true(not GameState.has_flag("opening_done"), "loading a save never runs the prologue")
	game.free()
	_cleanup(save_dir)
	_clear_skip_meta()


func test_domain_stage_plays_recover_and_domain_effects() -> void:
	var DomainStage = load("res://features/opening/opening_domain_stage.gd")
	var recover: Variant = DomainStage.new()
	recover.size = Vector2(1152.0, 648.0)
	recover.build({"stage": "recover"}, 8.0)
	recover.advance(0.5)
	assert_true(recover.effect_count() > 0, "the first sword cut spawns slash effects")
	recover.advance(1.0)
	assert_true(recover.figure("yun").rotation > 0.1, "the defeated enemy lies down")
	recover.advance(0.7)
	assert_true(absf(recover.figure("yun").rotation) < 0.1, "and stands up again, healed")
	recover.free()
	var domain: Variant = DomainStage.new()
	domain.size = Vector2(1152.0, 648.0)
	domain.build({"stage": "domain"}, 9.0)
	for i in range(12):
		domain.advance(0.1)
	assert_true(domain.effect_count() > 0, "the domain expansion effect plays")
	for i in range(20):
		domain.advance(0.1)
	assert_true(domain.effect_count() > 0, "gravity effects follow")
	for i in range(60):
		domain.advance(0.1)
	domain.free()

extends "res://tests/test_case.gd"

const Dialogue = preload("res://core/dialogue.gd")

const SPEAKERS_PATH := "res://data/speakers.json"
const BOSS_INTRO_PATH := "res://data/dialogues/boss_intro.json"

var finished_count: int = 0


func _make_view() -> Variant:
	var view: Variant = load("res://ui/dialogue_view.gd").new()
	view.build_ui()
	return view


func _boss_intro_lines() -> Array:
	var speakers: Dictionary = Dialogue.load_speakers(SPEAKERS_PATH).get("defs", {})
	var loaded: Dictionary = Dialogue.load_file(BOSS_INTRO_PATH, speakers)
	return loaded.get("lines", [])


func _on_view_finished() -> void:
	finished_count += 1


func _advance_to_line(view: Variant, target_index: int) -> void:
	for i in range(target_index):
		view.advance()
		view.advance()


func test_first_line_shows_speaker_and_portrait() -> void:
	var view: Variant = _make_view()
	view.start(_boss_intro_lines())
	assert_eq(view.name_label.text, "马友为", "the first line names ma_youwei")
	assert_true(view.right_portrait.visible, "ma_youwei stands on the right")
	assert_true(view.right_portrait.texture != null, "the right portrait has a texture")
	assert_true(not view.left_portrait.visible, "the left portrait is still hidden")
	view.free()


func test_typewriter_then_advance() -> void:
	var view: Variant = _make_view()
	view.start(_boss_intro_lines())
	assert_true(view.typing, "a new line starts typing")
	view.advance()
	assert_true(not view.typing, "the first advance completes the typing")
	assert_true(view.hint_label.visible, "the continue hint appears when typing is done")
	view.advance()
	assert_true(view.typing, "the next advance starts the following line typing")
	assert_eq(view.name_label.text, "马友为", "the second line is still ma_youwei")
	view.free()


func test_other_side_dimmed_when_speaker_changes() -> void:
	var view: Variant = _make_view()
	view.start(_boss_intro_lines())
	_advance_to_line(view, 2)
	assert_true(view.left_portrait.visible, "ren_xiaoyao stands on the left")
	assert_near(view.left_portrait.modulate.r, 1.0, 0.001, "the active speaker is bright")
	assert_true(view.right_portrait.visible, "the previous speaker portrait is kept")
	assert_true(view.right_portrait.modulate.r < 0.7, "the inactive portrait is dimmed")
	view.free()


func test_narrator_hides_name_plate_and_dims_portraits() -> void:
	var view: Variant = _make_view()
	view.start(_boss_intro_lines())
	_advance_to_line(view, 5)
	assert_true(not view.name_plate.visible, "the narrator has no name plate")
	assert_true(view.left_portrait.modulate.r < 0.7, "the left portrait is dimmed for the narrator")
	assert_true(view.right_portrait.modulate.r < 0.7, "the right portrait is dimmed for the narrator")
	view.free()


func test_finished_signal_after_last_line() -> void:
	finished_count = 0
	var view: Variant = _make_view()
	view.connect("finished", Callable(self, "_on_view_finished"))
	view.start(_boss_intro_lines())
	for i in range(7):
		view.advance()
		view.advance()
	assert_eq(finished_count, 1, "finished is emitted exactly once")
	assert_true(not view.is_active(), "the finished dialogue is not active")
	assert_true(not view.visible, "the finished dialogue hides itself")
	view.free()


func test_empty_lines_emits_finished_immediately() -> void:
	finished_count = 0
	var view: Variant = _make_view()
	view.connect("finished", Callable(self, "_on_view_finished"))
	view.start([])
	assert_eq(finished_count, 1, "an empty dialogue emits finished right away")
	assert_true(not view.is_active(), "an empty dialogue is not active")
	view.free()

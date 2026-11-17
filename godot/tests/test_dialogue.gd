extends "res://tests/test_case.gd"

const Dialogue = preload("res://core/dialogue.gd")

const SPEAKERS_PATH := "res://data/speakers.json"
const BOSS_INTRO_PATH := "res://data/dialogues/boss_intro.json"
const BOSS_WIN_PATH := "res://data/dialogues/boss_win.json"


func _speakers() -> Dictionary:
	var loaded: Dictionary = Dialogue.load_speakers(SPEAKERS_PATH)
	return loaded.get("defs", {})


func test_load_speakers_ok() -> void:
	var loaded: Dictionary = Dialogue.load_speakers(SPEAKERS_PATH)
	var errors: Array = loaded.get("errors", [])
	var defs: Dictionary = loaded.get("defs", {})
	assert_true(errors.is_empty(), "speakers.json loads without errors")
	assert_eq(defs.size(), 23, "speakers.json defines twenty-three speakers")


func test_parse_valid_lines() -> void:
	var speakers: Dictionary = _speakers()
	var json_text := """[
		{"speaker": "ren_xiaoyao", "text": "不想。"},
		{"speaker": "vendor", "text": "客官里边请。"}
	]"""
	var result: Dictionary = Dialogue.parse(json_text, speakers)
	var errors: Array = result.get("errors", [])
	var lines: Array = result.get("lines", [])
	assert_true(errors.is_empty(), "valid dialogue has no errors")
	assert_eq(lines.size(), 2, "both lines are kept")

	var first: Dictionary = lines[0]
	var ren_def: Dictionary = speakers.get("ren_xiaoyao", {})
	assert_eq(first.get("name"), str(ren_def.get("name", "")), "name comes from speakers.json")
	assert_eq(first.get("portrait"), str(ren_def.get("portrait", "")), "portrait comes from speakers.json")
	assert_eq(first.get("side"), str(ren_def.get("side", "")), "side comes from speakers.json")


func test_parse_unknown_speaker_is_error() -> void:
	var json_text := """[
		{"speaker": "nobody", "text": "谁？"}
	]"""
	var result: Dictionary = Dialogue.parse(json_text, _speakers())
	var errors: Array = result.get("errors", [])
	var lines: Array = result.get("lines", [])
	assert_true(not errors.is_empty(), "unknown speaker is reported")
	var mentions_speaker: bool = false
	for error in errors:
		if str(error).contains("nobody"):
			mentions_speaker = true
	assert_true(mentions_speaker, "the error mentions the unknown speaker id")
	assert_true(lines.is_empty(), "the invalid line is dropped")


func test_parse_empty_text_is_error() -> void:
	var json_text := """[
		{"speaker": "ren_xiaoyao", "text": ""}
	]"""
	var result: Dictionary = Dialogue.parse(json_text, _speakers())
	var errors: Array = result.get("errors", [])
	var lines: Array = result.get("lines", [])
	assert_true(not errors.is_empty(), "empty text is reported")
	assert_true(lines.is_empty(), "the empty line is dropped")


func test_parse_bad_side_is_error() -> void:
	var json_text := """[
		{"speaker": "ren_xiaoyao", "text": "嗯。", "side": "up"}
	]"""
	var result: Dictionary = Dialogue.parse(json_text, _speakers())
	var errors: Array = result.get("errors", [])
	var lines: Array = result.get("lines", [])
	assert_true(not errors.is_empty(), "an unknown side is reported")
	assert_true(lines.is_empty(), "the invalid line is dropped")


func test_narrator_has_no_portrait() -> void:
	var json_text := """[
		{"speaker": "narrator", "text": "风声。"}
	]"""
	var result: Dictionary = Dialogue.parse(json_text, _speakers())
	var lines: Array = result.get("lines", [])
	assert_eq(lines.size(), 1, "narrator line is kept")
	var line: Dictionary = lines[0]
	assert_eq(line.get("portrait"), "", "narrator has no portrait")
	assert_eq(line.get("name"), "", "narrator has no name")
	assert_eq(line.get("side"), "center", "narrator sits in the centre")


func test_side_override() -> void:
	var json_text := """[
		{"speaker": "ma_youwei", "text": "来。", "side": "left"}
	]"""
	var result: Dictionary = Dialogue.parse(json_text, _speakers())
	var lines: Array = result.get("lines", [])
	assert_eq(lines.size(), 1, "the overridden line is kept")
	var line: Dictionary = lines[0]
	assert_eq(line.get("side"), "left", "an explicit side overrides the speaker default")


func test_runner_flow() -> void:
	var lines: Array = [{"speaker": "narrator", "text": "一。"}, {"speaker": "narrator", "text": "二。"}, {"speaker": "narrator", "text": "三。"}]
	var runner: Variant = Dialogue.new(lines)
	assert_true(not runner.is_finished(), "a fresh runner is not finished")
	assert_eq(runner.current().get("text"), "一。", "the runner starts at the first line")
	runner.advance()
	runner.advance()
	runner.advance()
	assert_true(runner.is_finished(), "three advances finish a three-line dialogue")
	assert_true(runner.current().is_empty(), "current() is empty after the end")


func test_real_dialogue_files_parse() -> void:
	var speakers: Dictionary = _speakers()
	var intro: Dictionary = Dialogue.load_file(BOSS_INTRO_PATH, speakers)
	var win: Dictionary = Dialogue.load_file(BOSS_WIN_PATH, speakers)
	assert_true(intro.get("errors", []).is_empty(), "boss_intro.json has no errors")
	assert_true(win.get("errors", []).is_empty(), "boss_win.json has no errors")
	assert_eq(intro.get("lines", []).size(), 7, "boss_intro.json has seven lines")
	assert_eq(win.get("lines", []).size(), 3, "boss_win.json has three lines")

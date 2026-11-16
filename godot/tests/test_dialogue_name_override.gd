extends "res://tests/test_case.gd"

const Dialogue = preload("res://core/dialogue.gd")

const SPEAKERS_PATH := "res://data/speakers.json"
const BUN_VENDOR_PATH := "res://data/dialogues/npc_bun_vendor.json"
const DISCIPLE_PATH := "res://data/dialogues/npc_disciple.json"
const BANDIT_1_PATH := "res://data/dialogues/npc_bandit_1.json"
const BANDIT_2_PATH := "res://data/dialogues/npc_bandit_2.json"


func _speakers() -> Dictionary:
	var loaded: Dictionary = Dialogue.load_speakers(SPEAKERS_PATH)
	return loaded.get("defs", {})


func test_name_override_applies() -> void:
	var json_text := """[
		{"speaker": "vendor", "name": "包子摊老板", "text": "逍遥，又没带钱？"}
	]"""
	var result: Dictionary = Dialogue.parse(json_text, _speakers())
	var errors: Array = result.get("errors", [])
	var lines: Array = result.get("lines", [])
	assert_true(errors.is_empty(), str(errors))
	assert_eq(lines.size(), 1, "the line is kept")
	var line: Dictionary = lines[0]
	assert_eq(line.get("name"), "包子摊老板", "the name field overrides the speaker name")
	var vendor: Dictionary = _speakers().get("vendor", {})
	assert_eq(
		line.get("portrait"), str(vendor.get("portrait", "")),
		"the portrait still comes from speakers.json"
	)


func test_no_override_keeps_speaker_name() -> void:
	var json_text := """[
		{"speaker": "vendor", "text": "客官里边请。"}
	]"""
	var result: Dictionary = Dialogue.parse(json_text, _speakers())
	var lines: Array = result.get("lines", [])
	assert_eq(lines.size(), 1, "the line is kept")
	var line: Dictionary = lines[0]
	assert_eq(line.get("name"), "酒家小贩", "without name the speaker name is used")


func test_narrator_ignores_name() -> void:
	var json_text := """[
		{"speaker": "narrator", "name": "旁白", "text": "风声。"}
	]"""
	var result: Dictionary = Dialogue.parse(json_text, _speakers())
	var lines: Array = result.get("lines", [])
	assert_eq(lines.size(), 1, "the narrator line is kept")
	var line: Dictionary = lines[0]
	assert_eq(line.get("name"), "", "a narrator line always has an empty name")


func test_real_npc_dialogue_files_parse() -> void:
	var speakers: Dictionary = _speakers()
	var bun: Dictionary = Dialogue.load_file(BUN_VENDOR_PATH, speakers)
	var disciple: Dictionary = Dialogue.load_file(DISCIPLE_PATH, speakers)
	var bandit_1: Dictionary = Dialogue.load_file(BANDIT_1_PATH, speakers)
	var bandit_2: Dictionary = Dialogue.load_file(BANDIT_2_PATH, speakers)
	assert_true(bun.get("errors", []).is_empty(), "npc_bun_vendor.json has no errors")
	assert_true(disciple.get("errors", []).is_empty(), "npc_disciple.json has no errors")
	assert_true(bandit_1.get("errors", []).is_empty(), "npc_bandit_1.json has no errors")
	assert_true(bandit_2.get("errors", []).is_empty(), "npc_bandit_2.json has no errors")
	assert_eq(bun.get("lines", []).size(), 5, "npc_bun_vendor.json has five lines")
	assert_eq(disciple.get("lines", []).size(), 7, "npc_disciple.json has seven lines")
	assert_eq(bandit_1.get("lines", []).size(), 2, "npc_bandit_1.json has two lines")
	assert_eq(bandit_2.get("lines", []).size(), 1, "npc_bandit_2.json has one line")

extends "res://tests/test_case.gd"

const GameState = preload("res://core/game_state.gd")
const OpeningData = preload("res://core/opening_data.gd")
const TownStoryteller = preload("res://features/opening/town_storyteller.gd")

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


func _town_with_story(audio: Variant) -> Dictionary:
	GameState.reset()
	var game: Variant = load("res://app/game.gd").new()
	game.save_dir = _temp_dir("town")
	game.show_town()
	var town: Variant = game.current
	var story: Node = TownStoryteller.new()
	town.add_child(story)
	story.begin(town, audio, OpeningData.load_opening())
	return {"game": game, "town": town, "story": story}


func test_storyteller_gathers_the_crowd_in_the_real_town() -> void:
	var fake := FakeAudio.new()
	var ctx := _town_with_story(fake)
	var story: Node = ctx["story"]
	var town: Variant = ctx["town"]
	assert_eq(story.crowd.size(), 5, "five townsfolk gather around the scholar")
	assert_true(town.input_blocked, "the player waits during the story")
	assert_eq(str(fake.cues[0]), "opening_town", "the storyteller cue plays")
	var scholar: Node3D = town.npc_nodes["scholar"]
	assert_true(not town.npc_wander.has("scholar"), "the scholar stands still while telling")
	assert_true(scholar.position.distance_to(Vector3(-21.0, 0.0, 20.2)) < 0.5, "he tells stories at the new tea stall")
	assert_true(story.crowd[0].position.distance_to(scholar.position) < 6.0, "the crowd stands near him")
	ctx["game"].free()


func test_storyteller_fades_in_runs_the_dialogue_then_hands_back() -> void:
	var ctx := _town_with_story(null)
	var story: Node = ctx["story"]
	var town: Variant = ctx["town"]
	var done := [0]
	story.finished.connect(func() -> void: done[0] += 1)
	story.advance(FADE_IN_TIME + 0.05)
	assert_true(town.is_dialogue_active(), "the dialogue starts after the fade-in")
	for i in range(60):
		if not town.is_dialogue_active():
			break
		town.dialogue_view.advance()
	assert_eq(done[0], 1, "finished fires once")
	assert_true(not town.input_blocked, "the player gets control back")
	assert_true(town.npc_nodes.has("scholar"), "the scholar stays at his tea stall")
	assert_eq(story.crowd.size(), 0, "the temporary crowd is gone")
	ctx["game"].free()


func test_escape_skips_the_story() -> void:
	var ctx := _town_with_story(null)
	var story: Node = ctx["story"]
	var done := [0]
	story.finished.connect(func() -> void: done[0] += 1)
	story.finish()
	story.finish()
	assert_eq(done[0], 1, "skipping finishes only once")
	ctx["game"].free()

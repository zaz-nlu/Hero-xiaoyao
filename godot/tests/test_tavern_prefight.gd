extends "res://tests/test_case.gd"

const GameState = preload("res://core/game_state.gd")
const Dialogue = preload("res://core/dialogue.gd")
const Prefight = preload("res://core/prefight.gd")

const SPEAKERS_PATH := "res://data/speakers.json"
const PREFIGHT_END_PATH := "res://data/dialogues/tavern_prefight_end.json"
const ZIXIA_AFTERMATH_PATH := "res://data/dialogues/npc_zixia_aftermath.json"
const DISCIPLE_AFTERMATH_PATH := "res://data/dialogues/npc_zixia_disciple_aftermath.json"
const DISCIPLE_IDS: Array[String] = ["disciple_1", "disciple_2", "disciple_3"]

var encounter_count: int = 0
var encounter_args: Array = []


func _new_tavern() -> Variant:
	var tavern: Variant = load("res://features/tavern/tavern.gd").new()
	tavern.build()
	tavern.build_hud()
	return tavern


func _on_encounter(enemy_id: String, count: int, first_strike: bool) -> void:
	encounter_count += 1
	encounter_args = [enemy_id, count, first_strike]


func _finish_dialogue(tavern: Variant) -> void:
	for i in range(400):
		if not bool(tavern.dialogue_view.is_active()):
			return
		tavern.dialogue_view.advance()


func _sprite_of(node: Node3D) -> Sprite3D:
	var sprite_value: Variant = node.get_node_or_null("Sprite")
	if sprite_value is Sprite3D:
		return sprite_value
	return null


func test_the_ambush_plays_the_prefight_then_the_story() -> void:
	GameState.reset()
	encounter_count = 0
	encounter_args.clear()
	var tavern: Variant = _new_tavern()
	tavern.connect("encounter_requested", Callable(self, "_on_encounter"))
	tavern.player_pos = Vector2(11.0, -4.0)
	tavern.check_story(0.016)
	assert_true(tavern.is_dialogue_active(), "the opening narration starts")
	_finish_dialogue(tavern)
	assert_eq(str(tavern.current_state()), "brawl", "the tavern switches to the brawl")

	# 马匪先入场并叫嚣；紫霞派之后才进门，对质对话结束后混战演出开始。
	tavern.advance(3.0)
	assert_true(tavern.is_dialogue_active(), "the bandits taunt first")
	assert_true(not tavern.npc_nodes.has("zixia"), "the sister has not arrived yet")
	_finish_dialogue(tavern)
	tavern.advance(3.0)
	assert_true(tavern.is_dialogue_active(), "the sister confronts the bandits")
	_finish_dialogue(tavern)
	assert_true(tavern._prefight_active, "the prefight performance is running")
	assert_true(tavern.npc_nodes.has("zixia"), "the sister is on stage")
	for id in DISCIPLE_IDS:
		assert_true(tavern.npc_nodes.has(id), "%s is on stage" % id)

	var expected_loss: int = int(Prefight.simulate(tavern.bandit_count())["boss_damage"])
	tavern.advance(15.0)
	assert_true(not tavern._prefight_active, "the performance ends")
	assert_true(GameState.has_flag("prefight_done"), "the prefight_done flag is set")
	assert_eq(int(GameState.boss_hp_loss), expected_loss, "the boss wound is set once")
	assert_true(
		int(GameState.boss_hp_loss) >= 88 and int(GameState.boss_hp_loss) <= 112,
		"the wound is 88..112"
	)
	assert_eq(
		int(GameState.prefight_loss_cached), expected_loss,
		"the same result is cached for a retry"
	)
	for id in DISCIPLE_IDS:
		var node: Node3D = tavern.npc_nodes[id]
		assert_true(absf(node.rotation.z - PI / 2.0) < 0.01, "%s lies on the floor" % id)
		var sprite: Sprite3D = _sprite_of(node)
		assert_true(sprite != null, "%s has a sprite" % id)
		if sprite != null:
			assert_true(sprite.modulate != Color.WHITE, "%s is dimmed" % id)
	var sister: Node3D = tavern.npc_nodes["zixia"]
	assert_true(sister.scale.y < 1.0, "the sister is half-kneeling")

	assert_true(tavern.is_dialogue_active(), "tavern_prefight_end plays next")
	assert_true(
		str(tavern.dialogue_view.text_label.text).contains("撑住"),
		"the prefight-end narration is on screen"
	)
	var prefight_lines: int = tavern.dialogue_view.runner.lines.size()
	for i in range(prefight_lines * 2):
		tavern.dialogue_view.advance()
	assert_true(tavern.is_dialogue_active(), "the ambush dialogue follows")
	assert_true(
		str(tavern.dialogue_view.text_label.text).contains("一群人涌了进来"),
		"the many-bandits dialogue plays after the prefight"
	)
	_finish_dialogue(tavern)
	assert_eq(encounter_count, 1, "the encounter is requested once")
	assert_eq(encounter_args.size(), 3, "the signal carries three arguments")
	assert_eq(int(GameState.boss_hp_loss), expected_loss, "the wound waits for the battle")
	tavern.free()
	GameState.reset()


func test_a_defeat_return_does_not_replay_the_prefight_and_reapplies_the_wound() -> void:
	GameState.reset()
	GameState.set_flag("bandits_entered")
	GameState.set_flag("prefight_done")
	encounter_count = 0
	encounter_args.clear()
	var tavern: Variant = _new_tavern()
	tavern.connect("encounter_requested", Callable(self, "_on_encounter"))
	var expected_loss: int = int(Prefight.simulate(tavern.bandit_count())["boss_damage"])
	assert_eq(
		int(GameState.prefight_loss_cached), expected_loss,
		"a loaded tavern recomputes the same cached wound"
	)
	assert_true(not tavern._prefight_active, "the performance does not replay")
	for id in DISCIPLE_IDS:
		assert_true(tavern.npc_nodes.has(id), "%s is still on the floor" % id)
		var node: Node3D = tavern.npc_nodes[id]
		assert_true(absf(node.rotation.z - PI / 2.0) < 0.01, "%s stays fallen" % id)
	var sister: Node3D = tavern.npc_nodes["zixia"]
	assert_true(sister.scale.y < 1.0, "the sister stays half-kneeling")
	assert_true(tavern._boss_bar != null and tavern._boss_bar.visible, "the boss bar is shown")
	if tavern._boss_bar_fill != null:
		assert_near(
			tavern._boss_bar_fill.scale.x,
			(200.0 - float(expected_loss)) / 200.0,
			0.001,
			"the boss bar keeps the prefight ratio"
		)

	assert_eq(GameState.boss_hp_loss, 0, "nothing is spent before the challenge")
	tavern.player_pos = Vector2(11.0, -1.8)
	assert_true(tavern.try_interact(), "talking to the boss starts the challenge")
	assert_true(tavern.is_dialogue_active(), "the challenge dialogue plays")
	assert_true(
		str(tavern.dialogue_view.text_label.text).contains("一群人涌了进来"),
		"the prefight does not replay before the challenge"
	)
	_finish_dialogue(tavern)
	assert_eq(encounter_count, 1, "the encounter is requested again")
	assert_eq(
		int(GameState.boss_hp_loss), expected_loss,
		"the cached wound is re-applied for the retry"
	)
	tavern.free()
	GameState.reset()


func test_the_aftermath_has_the_sister_and_the_disciples_to_talk_to() -> void:
	GameState.reset()
	GameState.set_flag("boss_defeated")
	var tavern: Variant = _new_tavern()
	assert_eq(str(tavern.current_state()), "aftermath", "the aftermath is shown")
	assert_true(tavern.npc_nodes.has("zixia"), "the sister is by the bar")
	for id in DISCIPLE_IDS:
		assert_true(tavern.npc_nodes.has(id), "%s stands behind the sister" % id)
	var sister: Node3D = tavern.npc_nodes["zixia"]
	assert_near(sister.position.x, 8.5, 0.01, "the sister stands in front of the bar")
	assert_near(sister.position.z, -8.0, 0.01, "the sister stands in front of the bar")

	tavern.player_pos = Vector2(8.5, -7.2)
	assert_eq(tavern.nearby_npc(), "zixia", "the sister is the nearest npc")
	assert_true(tavern.try_interact(), "the sister can be talked to")
	assert_true(tavern.is_dialogue_active(), "her aftermath dialogue plays")
	assert_true(
		str(tavern.dialogue_view.text_label.text).contains("你赢了"),
		"the sister's aftermath line is shown"
	)
	_finish_dialogue(tavern)

	tavern.player_pos = Vector2(7.0, -7.0)
	assert_eq(tavern.nearby_npc(), "disciple_1", "a disciple is the nearest npc")
	assert_true(tavern.try_interact(), "the disciples can be talked to")
	assert_true(tavern.is_dialogue_active(), "their shared aftermath dialogue plays")
	assert_true(
		str(tavern.dialogue_view.text_label.text).contains("师姐一个人"),
		"the disciple's aftermath line is shown"
	)
	_finish_dialogue(tavern)
	tavern.free()
	GameState.reset()


func test_the_new_dialogue_files_load_with_zixia_sister() -> void:
	var loaded_speakers: Dictionary = Dialogue.load_speakers(SPEAKERS_PATH)
	var speakers: Variant = loaded_speakers.get("defs", {})
	assert_true(speakers is Dictionary, "the speakers file loads")
	if not (speakers is Dictionary):
		return
	var defs: Dictionary = speakers
	assert_true(defs.has("zixia_sister"), "zixia_sister is a known speaker")
	var paths: Array[String] = [
		PREFIGHT_END_PATH, ZIXIA_AFTERMATH_PATH, DISCIPLE_AFTERMATH_PATH
	]
	for path in paths:
		var loaded: Dictionary = Dialogue.load_file(path, defs)
		var errors: Array = loaded.get("errors", [])
		assert_true(errors.is_empty(), "%s loads without errors (%s)" % [path, str(errors)])
		var lines: Array = loaded.get("lines", [])
		assert_true(not lines.is_empty(), "%s has lines" % path)
	var zixia: Dictionary = Dialogue.load_file(ZIXIA_AFTERMATH_PATH, defs)
	var zixia_lines: Array = zixia.get("lines", [])
	if not zixia_lines.is_empty():
		var first: Dictionary = zixia_lines[0]
		assert_eq(str(first.get("speaker", "")), "zixia_sister", "the sister speaks")

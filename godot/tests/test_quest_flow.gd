extends "res://tests/test_case.gd"

const Dialogue = preload("res://core/dialogue.gd")
const GameState = preload("res://core/game_state.gd")
const Progression = preload("res://core/progression.gd")
const Quests = preload("res://core/quests.gd")
const QuestFlow = preload("res://core/quest_flow.gd")

const SPEAKERS_PATH := "res://data/speakers.json"
const BUN_FALLBACK := "res://data/dialogues/npc_bun_vendor.json"
const DISCIPLE_FALLBACK := "res://data/dialogues/npc_disciple.json"
const BUN_OFFER := "res://data/dialogues/quest_herbs_offer.json"
const BUN_ACTIVE := "res://data/dialogues/quest_herbs_active.json"
const BUN_READY := "res://data/dialogues/quest_herbs_ready.json"
const SPAR_OFFER := "res://data/dialogues/quest_spar_offer.json"
const SPAR_ACTIVE := "res://data/dialogues/quest_spar_active.json"
const SPAR_READY := "res://data/dialogues/quest_spar_ready.json"
const SCOUT_OFFER := "res://data/dialogues/quest_scout_offer.json"
const SCOUT_ACTIVE := "res://data/dialogues/quest_scout_active.json"
const SCOUT_READY := "res://data/dialogues/quest_scout_ready.json"
const QUEST_DIALOGUES: Array[String] = [
	BUN_OFFER,
	BUN_ACTIVE,
	BUN_READY,
	SPAR_OFFER,
	SPAR_ACTIVE,
	SPAR_READY,
	SCOUT_OFFER,
	SCOUT_ACTIVE,
	SCOUT_READY,
]


func _reset() -> void:
	GameState.reset()
	Quests.reload()
	Progression.reload_items()


func test_bun_vendor_picks_by_state() -> void:
	_reset()
	var result: Dictionary = QuestFlow.pick("bun_vendor", BUN_FALLBACK)
	assert_eq(str(result.get("file")), BUN_OFFER, "none offers the herbs quest")
	var after: Dictionary = result.get("after", {})
	assert_eq(str(after.get("kind")), "start", "the offer starts the quest")
	assert_eq(str(after.get("quest")), "herbs", "the start targets herbs")

	Quests.start("herbs")
	result = QuestFlow.pick("bun_vendor", BUN_FALLBACK)
	assert_eq(str(result.get("file")), BUN_ACTIVE, "active plays the active dialogue")
	assert_eq(str(result.get("after", {}).get("kind")), "none", "active has no follow-up")

	Progression.give_item("herb", 3)
	result = QuestFlow.pick("bun_vendor", BUN_FALLBACK)
	assert_eq(str(result.get("file")), BUN_READY, "ready plays the ready dialogue")
	assert_eq(str(result.get("after", {}).get("kind")), "turn_in", "ready hands the quest in")

	Quests.turn_in("herbs")
	result = QuestFlow.pick("bun_vendor", BUN_FALLBACK)
	assert_eq(str(result.get("file")), BUN_FALLBACK, "done falls back to the plain chat")
	assert_eq(str(result.get("after", {}).get("kind")), "none", "done has no follow-up")
	_reset()


func test_disciple_spar_then_scout_chain() -> void:
	_reset()
	var result: Dictionary = QuestFlow.pick("disciple", DISCIPLE_FALLBACK)
	assert_eq(str(result.get("file")), SPAR_OFFER, "the disciple first offers the spar")
	assert_eq(str(result.get("after", {}).get("kind")), "start", "the spar offer starts the quest")

	Quests.start("spar")
	result = QuestFlow.pick("disciple", DISCIPLE_FALLBACK)
	assert_eq(str(result.get("file")), SPAR_ACTIVE, "the active spar plays its dialogue")
	var after: Dictionary = result.get("after", {})
	assert_eq(str(after.get("kind")), "encounter", "the active spar starts a fight")
	var encounter: Dictionary = after.get("encounter", {})
	assert_eq(str(encounter.get("enemy")), "disciple_spar", "the spar enemy is the disciple")
	assert_eq(int(encounter.get("count")), 1, "the spar is one on one")
	assert_eq(bool(encounter.get("first_strike")), false, "the disciple does not strike first")

	Quests.notify("defeat", "disciple_spar", 1)
	result = QuestFlow.pick("disciple", DISCIPLE_FALLBACK)
	assert_eq(str(result.get("file")), SPAR_READY, "winning plays the ready dialogue")
	assert_eq(str(result.get("after", {}).get("kind")), "turn_in", "the spar can be turned in")

	Quests.turn_in("spar")
	result = QuestFlow.pick("disciple", DISCIPLE_FALLBACK)
	assert_eq(str(result.get("file")), SCOUT_OFFER, "the scout unlocks after the spar is done")
	assert_eq(str(result.get("after", {}).get("kind")), "start", "the scout offer starts the quest")

	Quests.start("scout")
	result = QuestFlow.pick("disciple", DISCIPLE_FALLBACK)
	assert_eq(str(result.get("file")), SCOUT_ACTIVE, "the active scout plays its dialogue")
	assert_eq(str(result.get("after", {}).get("kind")), "none", "the scout has no encounter")

	Quests.notify("defeat", "bandit_scout", 1)
	result = QuestFlow.pick("disciple", DISCIPLE_FALLBACK)
	assert_eq(str(result.get("file")), SCOUT_READY, "beating the scout plays the ready dialogue")
	assert_eq(str(result.get("after", {}).get("kind")), "turn_in", "the scout can be turned in")

	Quests.turn_in("scout")
	result = QuestFlow.pick("disciple", DISCIPLE_FALLBACK)
	assert_eq(str(result.get("file")), DISCIPLE_FALLBACK, "the finished chain falls back to the chat")
	assert_eq(str(result.get("after", {}).get("kind")), "none", "nothing follows the chat")
	_reset()


func test_markers_follow_quest_state() -> void:
	_reset()
	assert_eq(QuestFlow.marker("bun_vendor"), "!", "a new quest is available")
	Quests.start("herbs")
	assert_eq(QuestFlow.marker("bun_vendor"), "…", "an active quest shows dots")
	Progression.give_item("herb", 3)
	assert_eq(QuestFlow.marker("bun_vendor"), "?", "a ready quest asks for turn in")
	Quests.turn_in("herbs")
	assert_eq(QuestFlow.marker("bun_vendor"), "", "a finished quest shows nothing")
	assert_eq(QuestFlow.marker("ma_youwei"), "", "an npc without quests shows nothing")
	_reset()


func test_scout_is_locked_until_spar_is_done() -> void:
	_reset()
	var result: Dictionary = QuestFlow.pick("disciple", DISCIPLE_FALLBACK)
	assert_eq(str(result.get("file")), SPAR_OFFER, "the disciple offers the spar first")
	assert_true(str(result.get("file")) != SCOUT_OFFER, "the scout is not offered yet")

	Quests.start("spar")
	result = QuestFlow.pick("disciple", DISCIPLE_FALLBACK)
	assert_eq(str(result.get("file")), SPAR_ACTIVE, "the spar takes precedence")
	assert_true(str(result.get("file")) != SCOUT_OFFER, "the scout stays locked while sparring")
	assert_eq(QuestFlow.marker("disciple"), "…", "the marker points at the spar, not the scout")
	_reset()


func test_missing_dialogue_falls_back() -> void:
	_reset()
	var defs: Dictionary = Quests.load_all()
	var herbs: Dictionary = defs["herbs"]
	var dialogue: Dictionary = herbs["dialogue"]
	var original := str(dialogue.get("offer", ""))
	dialogue["offer"] = "res://data/dialogues/__missing_offer__.json"
	var result: Dictionary = QuestFlow.pick("bun_vendor", BUN_FALLBACK)
	assert_eq(str(result.get("file")), BUN_FALLBACK, "a missing file falls back to the chat")
	assert_eq(str(result.get("after", {}).get("kind")), "none", "a missing file has no follow-up")
	dialogue["offer"] = original
	_reset()


func test_quest_dialogues_load_clean() -> void:
	var speakers: Dictionary = Dialogue.load_speakers(SPEAKERS_PATH).get("defs", {})
	for path in QUEST_DIALOGUES:
		var loaded: Dictionary = Dialogue.load_file(path, speakers)
		var errors: Array = loaded.get("errors", [])
		assert_true(errors.is_empty(), "%s loads without errors: %s" % [path, str(errors)])
		assert_true(loaded.get("lines", []).size() > 0, "%s has at least one line" % path)

extends "res://tests/test_case.gd"

const Dialogue = preload("res://core/dialogue.gd")
const GameState = preload("res://core/game_state.gd")
const Progression = preload("res://core/progression.gd")
const Quests = preload("res://core/quests.gd")
const QuestFlow = preload("res://core/quest_flow.gd")

const SPEAKERS_PATH := "res://data/speakers.json"
const WAITER_FALLBACK := "res://data/dialogues/npc_waiter.json"
const PEDDLER_FALLBACK := "res://data/dialogues/npc_peddler.json"

const NEW_QUEST_IDS: Array[String] = [
	"smith_whet", "hunter_hunt", "fisher_box", "woman_pin", "peddler_deliver", "herb_order",
]
const NEW_ITEM_IDS: Array[String] = ["iron_ore", "old_box", "jade_hairpin", "ginseng"]
const NEW_DIALOGUES: Array[String] = [
	"res://data/dialogues/quest_smith_whet_offer.json",
	"res://data/dialogues/quest_smith_whet_active.json",
	"res://data/dialogues/quest_smith_whet_ready.json",
	"res://data/dialogues/quest_hunter_hunt_offer.json",
	"res://data/dialogues/quest_hunter_hunt_active.json",
	"res://data/dialogues/quest_hunter_hunt_ready.json",
	"res://data/dialogues/quest_fisher_box_offer.json",
	"res://data/dialogues/quest_fisher_box_active.json",
	"res://data/dialogues/quest_fisher_box_ready.json",
	"res://data/dialogues/quest_woman_pin_offer.json",
	"res://data/dialogues/quest_woman_pin_active.json",
	"res://data/dialogues/quest_woman_pin_ready.json",
	"res://data/dialogues/quest_peddler_deliver_offer.json",
	"res://data/dialogues/quest_peddler_deliver_active.json",
	"res://data/dialogues/quest_peddler_deliver_talk_waiter.json",
	"res://data/dialogues/quest_peddler_deliver_ready.json",
	"res://data/dialogues/quest_herb_order_offer.json",
	"res://data/dialogues/quest_herb_order_active.json",
	"res://data/dialogues/quest_herb_order_ready.json",
]


func _reset() -> void:
	GameState.reset()
	Quests.reload()
	Progression.reload_items()


func test_new_quests_and_items_load() -> void:
	var defs: Dictionary = Quests.load_all()
	for quest_id in NEW_QUEST_IDS:
		assert_true(defs.has(quest_id), "quest %s is defined" % quest_id)
	for item_id in NEW_ITEM_IDS:
		var item: Dictionary = Progression.item_def(item_id)
		assert_true(not item.is_empty(), "item %s loads" % item_id)
		assert_eq(str(item.get("kind", "")), "material", "item %s is a material" % item_id)


func test_new_quest_dialogues_load_clean() -> void:
	var speakers: Dictionary = Dialogue.load_speakers(SPEAKERS_PATH).get("defs", {})
	for path in NEW_DIALOGUES:
		var loaded: Dictionary = Dialogue.load_file(path, speakers)
		var errors: Array = loaded.get("errors", [])
		assert_true(errors.is_empty(), "%s loads without errors: %s" % [path, str(errors)])
		assert_true(
			loaded.get("lines", []).size() > 0, "%s has at least one line" % path
		)


func test_smith_whet_item_flow() -> void:
	_reset()
	assert_true(Quests.start("smith_whet"), "the smith quest starts")
	assert_eq(Quests.state("smith_whet"), "active", "the quest is active")
	Progression.give_item("iron_ore", 2)
	assert_eq(Quests.state("smith_whet"), "active", "two ores are not enough")
	Progression.give_item("iron_ore")
	assert_eq(Quests.state("smith_whet"), "ready", "three ores make the quest ready")
	assert_true(Quests.turn_in("smith_whet"), "the smith quest turns in")
	assert_eq(Quests.state("smith_whet"), "done", "the quest is done")
	assert_eq(
		int(GameState.mastery_exp.get("basic_sword", 0)), 6,
		"the smith reward grants sword mastery exp"
	)
	assert_eq(
		int(GameState.stat_bonus.get("power", 0)), 0,
		"the smith quest does not touch permanent stats"
	)
	assert_eq(
		GameState.unspent_points, GameState.INITIAL_POINTS,
		"the smith quest does not grant attribute points"
	)
	_reset()


func test_hunter_hunt_defeat_flow() -> void:
	_reset()
	assert_true(Quests.start("hunter_hunt"), "the hunter quest starts")
	Quests.notify("defeat", "bandit", 2)
	assert_eq(Quests.state("hunter_hunt"), "active", "two bandits are not enough")
	Quests.notify("defeat", "bandit", 2)
	assert_eq(Quests.state("hunter_hunt"), "ready", "four bandits make the quest ready")
	var progress: Array = Quests.progress("hunter_hunt")
	assert_eq(int(progress[0]["have"]), 4, "progress is capped at four")
	assert_true(Quests.turn_in("hunter_hunt"), "the hunter quest turns in")
	assert_eq(Quests.state("hunter_hunt"), "done", "the hunter quest is done")
	assert_eq(
		int(GameState.mastery_exp.get("sidestep", 0)), 6,
		"the hunter reward grants sidestep mastery exp"
	)
	assert_eq(
		GameState.unspent_points, GameState.INITIAL_POINTS,
		"the hunter quest does not grant attribute points"
	)
	_reset()


func test_fisher_box_item_flow() -> void:
	_reset()
	assert_true(Quests.start("fisher_box"), "the fisherman quest starts")
	Progression.give_item("old_box")
	assert_eq(Quests.state("fisher_box"), "ready", "finding the box makes the quest ready")
	assert_true(Quests.turn_in("fisher_box"), "the fisherman quest turns in")
	assert_eq(Quests.state("fisher_box"), "done", "the fisherman quest is done")
	assert_eq(Progression.item_count("herb"), 2, "the fisherman rewards two herbs")
	assert_eq(
		int(GameState.mastery_exp.get("sidestep", 0)), 6,
		"the fisherman reward grants sidestep mastery exp"
	)
	_reset()


func test_woman_pin_item_flow() -> void:
	_reset()
	assert_true(Quests.start("woman_pin"), "the townswoman quest starts")
	Progression.give_item("jade_hairpin")
	assert_eq(Quests.state("woman_pin"), "ready", "finding the hairpin makes the quest ready")
	assert_true(Quests.turn_in("woman_pin"), "the townswoman quest turns in")
	assert_eq(Quests.state("woman_pin"), "done", "the townswoman quest is done")
	assert_eq(Progression.item_count("herb"), 2, "the townswoman rewards two herbs")
	assert_eq(
		int(GameState.mastery_exp.get("huifeng", 0)), 6,
		"the townswoman reward grants huifeng mastery exp"
	)
	_reset()


func test_herb_order_item_flow() -> void:
	_reset()
	assert_true(Quests.start("herb_order"), "the herbalist quest starts")
	Progression.give_item("ginseng")
	assert_eq(Quests.state("herb_order"), "active", "one ginseng is not enough")
	Progression.give_item("ginseng")
	assert_eq(Quests.state("herb_order"), "ready", "two ginseng make the quest ready")
	assert_true(Quests.turn_in("herb_order"), "the herbalist quest turns in")
	assert_eq(Quests.state("herb_order"), "done", "the herbalist quest is done")
	assert_eq(Progression.item_count("yangyuan_pill"), 1, "the order rewards one pill")
	assert_eq(Progression.item_count("herb"), 2, "the order rewards two herbs")
	_reset()


func test_peddler_deliver_talk_flow() -> void:
	_reset()
	var before: Dictionary = QuestFlow.pick("waiter", WAITER_FALLBACK)
	assert_eq(
		str(before.get("file")), WAITER_FALLBACK, "the waiter keeps his chat before the quest"
	)

	assert_true(Quests.start("peddler_deliver"), "the peddler quest starts")
	var talk: Dictionary = QuestFlow.pick("waiter", WAITER_FALLBACK)
	assert_eq(
		str(talk.get("file")),
		"res://data/dialogues/quest_peddler_deliver_talk_waiter.json",
		"the waiter plays the errand dialogue"
	)
	var after: Dictionary = talk.get("after", {})
	assert_eq(str(after.get("kind")), "talk", "the errand dialogue reports a talk")
	assert_eq(str(after.get("quest")), "peddler_deliver", "the talk targets the errand")
	assert_eq(str(after.get("key")), "waiter", "the talk key is the waiter")

	var peddler_active: Dictionary = QuestFlow.pick("peddler", PEDDLER_FALLBACK)
	assert_eq(
		str(peddler_active.get("file")),
		"res://data/dialogues/quest_peddler_deliver_active.json",
		"the peddler has his own active dialogue"
	)

	Quests.notify("talk", "waiter", 1)
	assert_eq(Quests.state("peddler_deliver"), "ready", "delivering the words makes it ready")
	var peddler_ready: Dictionary = QuestFlow.pick("peddler", PEDDLER_FALLBACK)
	assert_eq(
		str(peddler_ready.get("file")),
		"res://data/dialogues/quest_peddler_deliver_ready.json",
		"the peddler hands the reward over"
	)
	assert_eq(
		str(peddler_ready.get("after", {}).get("kind")), "turn_in", "the errand turns in"
	)
	assert_true(Quests.turn_in("peddler_deliver"), "the errand turns in")
	assert_eq(Quests.state("peddler_deliver"), "done", "the errand is done")
	assert_eq(Progression.item_count("herb"), 3, "the errand rewards three herbs")
	assert_eq(
		int(GameState.mastery_exp.get("taiji", 0)), 6,
		"the errand reward grants taiji mastery exp"
	)
	_reset()

extends "res://tests/test_case.gd"

const GameState = preload("res://core/game_state.gd")
const Progression = preload("res://core/progression.gd")
const Quests = preload("res://core/quests.gd")


func _reset() -> void:
	GameState.reset()
	Quests.reload()
	Progression.reload_items()


func test_herbs_none_then_start_active() -> void:
	_reset()
	assert_eq(Quests.state("herbs"), "none", "a new quest starts as none")
	assert_true(Quests.start("herbs"), "start succeeds")
	assert_eq(Quests.state("herbs"), "active", "start moves none to active")
	assert_true(not Quests.start("herbs"), "starting an active quest again returns false")
	assert_eq(Quests.state("herbs"), "active", "repeat start does not change the state")
	GameState.reset()


func test_herbs_ready_after_three_and_toast() -> void:
	_reset()
	Quests.start("herbs")
	Progression.take_toasts()
	Progression.give_item("herb")
	Progression.give_item("herb")
	assert_eq(Quests.state("herbs"), "active", "two herbs are not enough")
	Progression.give_item("herb")
	assert_eq(Quests.state("herbs"), "ready", "three herbs complete the objectives")
	var toasts: Array = Progression.take_toasts()
	assert_true(toasts.has("任务完成：草药"), "completion toast is queued: %s" % str(toasts))
	var progress: Array = Quests.progress("herbs")
	assert_eq(progress.size(), 1, "the herbs quest has one objective")
	assert_eq(int(progress[0]["have"]), 3, "progress reaches three")
	assert_eq(int(progress[0]["need"]), 3, "the objective needs three")
	GameState.reset()


func test_turn_in_applies_rewards_once() -> void:
	_reset()
	Quests.start("herbs")
	for i in range(3):
		Progression.give_item("herb")
	assert_eq(Quests.state("herbs"), "ready", "the quest is ready before turn in")
	assert_true(Quests.turn_in("herbs"), "turn in succeeds")
	assert_eq(Quests.state("herbs"), "done", "turn in moves ready to done")
	assert_eq(int(GameState.stat_bonus.get("recovery", 0)), 2, "the reward adds recovery")
	assert_true(not Quests.turn_in("herbs"), "turn in again returns false")
	assert_eq(
		int(GameState.stat_bonus.get("recovery", 0)), 2,
		"rewards are not applied twice"
	)
	GameState.reset()


func test_start_counts_existing_herbs() -> void:
	_reset()
	Progression.give_item("herb", 2)
	Quests.start("herbs")
	var progress: Array = Quests.progress("herbs")
	assert_eq(int(progress[0]["have"]), 2, "herbs already in the bag count towards the objective")
	Progression.give_item("herb")
	assert_eq(Quests.state("herbs"), "ready", "the last herb completes the quest")
	GameState.reset()


func test_spar_and_scout_complete_by_defeat() -> void:
	_reset()
	Quests.start("spar")
	Quests.start("scout")
	Quests.notify("defeat", "disciple_spar", 1)
	assert_eq(Quests.state("spar"), "ready", "spar is ready after the duel")
	assert_eq(Quests.state("scout"), "active", "scout is untouched by the duel")
	Quests.notify("defeat", "bandit_scout", 1)
	assert_eq(Quests.state("scout"), "ready", "scout is ready after the scout is defeated")
	assert_true(Quests.turn_in("spar"), "spar can be turned in")
	assert_eq(int(GameState.stat_bonus.get("skill", 0)), 2, "spar rewards skill")
	assert_true(Quests.turn_in("scout"), "scout can be turned in")
	assert_eq(int(GameState.stat_bonus.get("power", 0)), 1, "scout rewards power")
	assert_eq(int(GameState.stat_bonus.get("defense", 0)), 1, "scout rewards defense")
	GameState.reset()


func test_list_by_state_in_json_order() -> void:
	_reset()
	Quests.start("scout")
	assert_eq(Quests.list_by_state("active"), ["scout"], "active list holds the started quest")
	assert_eq(
		Quests.list_by_state("none"),
		[
			"zixia_recruit", "herbs", "spar", "smith_whet", "hunter_hunt", "fisher_box",
			"woman_pin", "peddler_deliver", "herb_order",
		],
		"none list keeps the JSON order"
	)
	assert_eq(Quests.list_by_state("done"), [], "nothing is done yet")
	GameState.reset()


func test_reward_item_advances_another_quest_in_order() -> void:
	_reset()
	Quests.start("herbs")
	Quests.start("smith_whet")
	Quests.notify("item", "iron_ore", 3)
	assert_eq(Quests.state("smith_whet"), "ready", "three ores complete the smith quest")
	Progression.take_toasts()
	assert_true(Quests.turn_in("smith_whet"), "the smith quest can be turned in")
	assert_eq(Quests.state("herbs"), "active", "two reward herbs are not enough for the herbs quest")
	var progress: Array = Quests.progress("herbs")
	assert_eq(int(progress[0]["have"]), 2, "reward items count towards the other active quest")
	assert_eq(
		Progression.take_toasts(), ["获得 草药"],
		"turning in queues only the reward item toast"
	)
	assert_true(not Quests.turn_in("smith_whet"), "turning in again returns false")
	assert_eq(
		int(GameState.inventory.get("herb", 0)), 2,
		"a repeated turn in does not grant the reward again"
	)
	Progression.give_item("herb")
	assert_eq(Quests.state("herbs"), "ready", "the third herb completes the cascaded quest")
	assert_eq(
		Progression.take_toasts(), ["获得 草药", "任务完成：草药"],
		"the pickup toast precedes the quest completion toast"
	)
	GameState.reset()


func test_recruit_schedule_and_keeper_gate() -> void:
	GameState.reset()
	Quests.reload()
	var Calendar = load("res://core/calendar.gd")
	Quests.start("zixia_recruit")
	assert_eq(Quests.state("zixia_recruit"), "active")
	assert_true(not Calendar.recruit_due(), "day 1 morning is before the recruit day")
	assert_eq(Calendar.phases_until(3, 1), 9, "two days and one phase away")
	Calendar.advance(9)
	assert_true(Calendar.recruit_due(), "the recruit time has arrived")
	Quests.notify("defeat", "ma_youwei", 1)
	assert_eq(Quests.state("zixia_recruit"), "done", "the main quest turns itself in")
	GameState.reset()

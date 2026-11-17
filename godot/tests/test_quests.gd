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
			"herbs", "spar", "smith_whet", "hunter_hunt", "fisher_box",
			"woman_pin", "peddler_deliver", "herb_order",
		],
		"none list keeps the JSON order"
	)
	assert_eq(Quests.list_by_state("done"), [], "nothing is done yet")
	GameState.reset()

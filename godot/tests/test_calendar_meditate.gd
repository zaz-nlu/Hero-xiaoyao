extends "res://tests/test_case.gd"

# 内力恢复手段：最小日历、回气丹、打坐、暂停菜单入口与早期任务奖励。

const Calendar = preload("res://core/calendar.gd")
const GameState = preload("res://core/game_state.gd")
const Progression = preload("res://core/progression.gd")
const Quests = preload("res://core/quests.gd")
const TacticsEnergy = preload("res://core/tactics/tactics_energy.gd")
const PauseMenu = preload("res://features/pause/pause_menu.gd")
const StatusOverlay = preload("res://features/character/status_overlay.gd")

const UNRECORDED := -1


func _reset() -> void:
	GameState.reset()
	Progression.reload_items()
	Calendar.reload()
	Quests.reload()


func _neili_cap() -> int:
	return TacticsEnergy.max_neili_for(GameState.realm_id)


func test_calendar_advance_crosses_phases_and_days() -> void:
	_reset()
	assert_eq(GameState.day, 1, "a new game starts on day one")
	assert_eq(GameState.phase, 0, "a new game starts in the morning")
	var first: Dictionary = Calendar.advance(2)
	assert_eq(int(first["day"]), 1, "morning plus two phases stays on the same day")
	assert_eq(int(first["phase"]), 2, "the phase lands on the evening")
	var second: Dictionary = Calendar.advance(1)
	assert_eq(int(second["day"]), 1, "one more phase reaches the night")
	assert_eq(int(second["phase"]), 3)
	var third: Dictionary = Calendar.advance(1)
	assert_eq(int(third["day"]), 2, "crossing the night rolls over to the next day")
	assert_eq(int(third["phase"]), 0, "the next day starts in the morning")
	var many: Dictionary = Calendar.advance(9)
	assert_eq(int(many["day"]), 4, "nine phases from day two morning add two days and one phase")
	assert_eq(int(many["phase"]), 1)
	GameState.reset()


func test_calendar_label_names_day_and_phase() -> void:
	_reset()
	GameState.day = 3
	GameState.phase = 2
	assert_eq(Calendar.phase_name(), "晚上", "phase two is the evening")
	assert_eq(Calendar.label(), "第 3 天 · 晚上", "the label joins the day and the phase")
	GameState.phase = 0
	assert_eq(Calendar.phase_name(), "早上", "phase zero is the morning")
	GameState.reset()


func test_calendar_state_round_trips_and_old_saves_default() -> void:
	_reset()
	GameState.day = 4
	GameState.phase = 3
	var saved := GameState.to_dict()
	assert_true(saved.has("day"), "day is written to the save")
	assert_true(saved.has("phase"), "phase is written to the save")
	GameState.reset()
	GameState.from_dict(saved)
	assert_eq(GameState.day, 4, "day survives the round trip")
	assert_eq(GameState.phase, 3, "phase survives the round trip")
	GameState.from_dict({"flags": {}})
	assert_eq(GameState.day, 1, "an old save without day starts on day one")
	assert_eq(GameState.phase, 0, "an old save without phase starts in the morning")
	GameState.from_dict({"day": "soon", "phase": {}})
	assert_eq(GameState.day, 1, "a bad day type keeps the default")
	assert_eq(GameState.phase, 0, "a bad phase type keeps the default")
	GameState.from_dict({"day": -2, "phase": -1})
	assert_eq(GameState.day, 1, "a negative day clamps to one")
	assert_eq(GameState.phase, 0, "a negative phase clamps to the morning")
	GameState.reset()


func test_huiqi_pill_restores_neili_and_clamps() -> void:
	_reset()
	var cap := _neili_cap()
	var item: Dictionary = Progression.item_def("huiqi_pill")
	assert_eq(str(item.get("name")), "回气丹", "the pill is defined")
	var restore: Dictionary = item.get("restore", {})
	assert_eq(int(restore.get("neili", 0)), 8, "the pill restores eight neili")
	Progression.give_item("huiqi_pill", 2)
	Progression.take_toasts()
	GameState.neili_left = 2
	assert_true(Progression.use_restore_item("huiqi_pill"), "the pill can be used")
	assert_eq(GameState.neili_left, 10, "the restore adds the item amount")
	assert_eq(Progression.item_count("huiqi_pill"), 1, "one pill is consumed")
	assert_eq(Progression.take_toasts(), ["内力恢复 8"], "the restore is toasted")

	GameState.neili_left = cap - 2
	assert_true(Progression.use_restore_item("huiqi_pill"), "the second pill can be used")
	assert_eq(GameState.neili_left, cap, "the restore never exceeds the pool cap")
	assert_eq(Progression.take_toasts(), ["内力恢复 2"], "the toast shows the clamped amount")
	assert_eq(Progression.item_count("huiqi_pill"), 0, "the second pill is consumed")
	GameState.reset()


func test_huiqi_pill_rejects_full_pool_and_empty_stack() -> void:
	_reset()
	var cap := _neili_cap()
	Progression.give_item("huiqi_pill", 2)
	GameState.neili_left = UNRECORDED
	assert_true(not Progression.use_restore_item("huiqi_pill"), "a full pool rejects the pill")
	assert_eq(Progression.item_count("huiqi_pill"), 2, "a rejected pill is not consumed")
	GameState.neili_left = cap
	assert_true(not Progression.use_restore_item("huiqi_pill"), "a recorded full pool rejects too")
	assert_eq(Progression.item_count("huiqi_pill"), 2, "the second rejection keeps the stack")
	GameState.inventory["huiqi_pill"] = 0
	GameState.neili_left = 1
	assert_true(not Progression.use_restore_item("huiqi_pill"), "an empty stack is rejected")
	assert_true(not Progression.use_restore_item("herb"), "items without restore are rejected")
	GameState.reset()


func test_meditate_refuses_when_neili_is_full() -> void:
	_reset()
	GameState.neili_left = UNRECORDED
	var result: Dictionary = Progression.meditate()
	assert_true(not bool(result.get("ok", false)), "meditating with a full pool is refused")
	assert_eq(str(result.get("reason")), "内力已满，无需打坐", "the refusal explains why")
	assert_eq(GameState.day, 1, "a refused meditation does not spend a phase")
	assert_eq(GameState.phase, 0)
	GameState.neili_left = _neili_cap()
	assert_true(not bool(Progression.meditate().get("ok", false)), "a recorded full pool is refused too")
	GameState.reset()


func test_meditate_refills_neili_and_advances_one_phase() -> void:
	_reset()
	GameState.neili_left = 3
	Progression.take_toasts()
	var result: Dictionary = Progression.meditate()
	assert_true(bool(result.get("ok", false)), "meditating with a partial pool works")
	assert_eq(GameState.neili_left, UNRECORDED, "a full restore uses the unrecorded marker")
	assert_eq(GameState.day, 1, "one phase does not reach the next day")
	assert_eq(GameState.phase, 1, "meditating costs one phase")
	var text := str(result.get("text", ""))
	assert_true(text.contains("打坐调息，内力恢复。"), "the result text explains the restore: %s" % text)
	assert_true(text.contains("第 1 天 · 白天"), "the result text shows the new calendar: %s" % text)
	assert_eq(Progression.take_toasts(), [text], "the same text is queued as a toast")
	GameState.reset()


func test_pause_menu_meditate_item_follows_can_meditate() -> void:
	_reset()
	var menu: Variant = PauseMenu.new()
	menu.open()
	menu.can_meditate = false
	menu.show_page("main")
	var button: Node = menu.find_child("Main_1", true, false)
	assert_true(button is Button, "the main page has a meditate item")
	if button is Button:
		assert_true((button as Button).disabled, "the item is disabled without can_meditate")
	menu.can_meditate = true
	menu.show_page("main")
	if button is Button:
		assert_true(not (button as Button).disabled, "the item enables when can_meditate is set")
	menu.close()
	menu.free()


func test_pause_menu_meditate_blocks_and_runs() -> void:
	_reset()
	GameState.neili_left = 3
	var menu: Variant = PauseMenu.new()
	menu.open()
	menu.can_meditate = false
	menu.show_page("main")
	Progression.take_toasts()
	menu._activate_main(1)
	assert_eq(GameState.neili_left, 3, "a blocked meditation keeps the neili")
	assert_eq(GameState.phase, 0, "a blocked meditation does not advance the calendar")
	assert_true(Progression.take_toasts().has("现在不能打坐"), "the block is toasted")
	menu.can_meditate = true
	menu._activate_main(1)
	assert_eq(GameState.neili_left, UNRECORDED, "an allowed meditation refills the neili")
	assert_eq(GameState.phase, 1, "an allowed meditation advances one phase")
	menu.free()


func test_game_allows_meditation_in_map_scenes_only() -> void:
	_reset()
	Engine.set_meta("skip_title", true)
	var game: Variant = load("res://app/game.gd").new()
	var menu: Variant = PauseMenu.new()
	menu.game = game
	game.show_town()
	menu.open()
	assert_true(menu.can_meditate, "meditating is available in the town")
	menu.close()
	game.show_battle("bandit", 1, false, false)
	assert_eq(str(game.current_kind), "battle", "the battle scene is current")
	menu.open()
	assert_true(not menu.can_meditate, "meditating is not available in battle")
	menu.close()
	menu.free()
	game.free()
	GameState.reset()


func test_character_panel_use_button_for_restore_item() -> void:
	_reset()
	var overlay: Variant = StatusOverlay.new()
	overlay.toggle_character()
	Progression.give_item("huiqi_pill")
	GameState.neili_left = 4
	overlay.refresh()
	overlay.character_panel.select_tab(2)
	var button: Node = overlay.character_panel.find_child("Use_huiqi_pill", true, false)
	assert_true(button is Button, "a restore item shows the use button")
	if button is Button:
		(button as Button).emit_signal("pressed")
	assert_eq(Progression.item_count("huiqi_pill"), 0, "using from the panel consumes the pill")
	assert_eq(GameState.neili_left, 12, "using from the panel restores the neili")
	overlay.free()
	GameState.reset()


func test_early_herb_quest_rewards_one_pill() -> void:
	_reset()
	var defs: Dictionary = Quests.load_all()
	assert_true(defs.has("herbs"), "the early herb quest exists")
	if not defs.has("herbs"):
		return
	var quest: Dictionary = defs["herbs"]
	var rewards: Variant = quest.get("rewards", {})
	var items: Dictionary = {}
	if rewards is Dictionary and (rewards as Dictionary).get("items", {}) is Dictionary:
		items = (rewards as Dictionary)["items"]
	assert_eq(int(items.get("huiqi_pill", 0)), 1, "the herb quest rewards one huiqi pill")
	GameState.reset()

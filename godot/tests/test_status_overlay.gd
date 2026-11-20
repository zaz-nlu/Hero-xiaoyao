extends "res://tests/test_case.gd"

const GameState = preload("res://core/game_state.gd")
const Progression = preload("res://core/progression.gd")
const Quests = preload("res://core/quests.gd")
const StatusOverlay = preload("res://features/character/status_overlay.gd")


func _reset() -> void:
	GameState.reset()
	Quests.reload()
	Progression.reload_items()


func _text_of(panel: Node, node_name: String) -> String:
	var node: Node = panel.find_child(node_name, true, false)
	if node == null:
		return ""
	return str(node.get("text"))


func _press(overlay: Variant, key: int) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	overlay._unhandled_input(event)


func test_character_panel_toggle_and_stats() -> void:
	_reset()
	var overlay: Variant = StatusOverlay.new()
	_press(overlay, KEY_C)
	assert_true(bool(overlay.is_panel_open()), "C opens the character panel")
	assert_eq(int(overlay.character_panel.tab_index), 0, "the panel opens on the attributes tab")
	var power_text: String = _text_of(overlay.character_panel, "AttrValue_power")
	assert_true(power_text.contains("6"), "the power row shows its base value: %s" % power_text)

	GameState.stat_bonus["speed"] = 1
	overlay.refresh()
	var speed_text: String = _text_of(overlay.character_panel, "AttrValue_speed")
	assert_true(speed_text.contains("+1"), "the speed row shows the permanent bonus: %s" % speed_text)

	Progression.give_item("plain_sword")
	overlay.refresh()
	overlay.character_panel.select_tab(2)
	var equipment_text: String = _text_of(overlay.character_panel, "SlotItem_weapon")
	assert_true(
		equipment_text.contains("普通的剑"),
		"the weapon slot names the equipped sword: %s" % equipment_text
	)

	_press(overlay, KEY_C)
	assert_true(not bool(overlay.is_panel_open()), "C closes the character panel again")
	overlay.free()
	GameState.reset()


func test_quest_panel_lists_progress() -> void:
	_reset()
	Quests.start("herbs")
	var overlay: Variant = StatusOverlay.new()
	overlay.toggle_quests()
	assert_true(bool(overlay.is_panel_open()), "J opens the quest panel")
	assert_eq(
		_text_of(overlay.quest_panel, "Group_active"), "进行中", "the active group header is shown"
	)
	var quest_text: String = _text_of(overlay.quest_panel, "Quest_herbs")
	assert_true(quest_text.contains("草药"), "the herbs quest is in the active list: %s" % quest_text)
	var objective_text: String = _text_of(overlay.quest_panel, "ObjectiveRow_0")
	assert_true(objective_text.contains("0/3"), "the objective starts at 0/3: %s" % objective_text)

	Progression.give_item("herb")
	Progression.give_item("herb")
	overlay.refresh()
	objective_text = _text_of(overlay.quest_panel, "ObjectiveRow_0")
	assert_true(objective_text.contains("2/3"), "the objective updates to 2/3: %s" % objective_text)
	overlay.close_all()
	overlay.free()
	GameState.reset()


func test_toasts_consume_queue_and_respect_enabled() -> void:
	_reset()
	var overlay: Variant = StatusOverlay.new()
	overlay._process(0.0)
	Progression.take_toasts()

	Progression.give_item("plain_sword")
	overlay._process(0.0)
	assert_true(overlay.toasts.box.get_child_count() >= 1, "a pickup toast is shown")
	overlay.advance(3.5)
	assert_eq(overlay.toasts.box.get_child_count(), 0, "toasts are removed after fading out")

	overlay.enabled = false
	Progression.give_item("herb")
	overlay._process(0.0)
	assert_eq(overlay.toasts.box.get_child_count(), 0, "toasts are not shown while disabled")
	assert_true(GameState.toasts.size() >= 1, "the queue keeps the toast while disabled")

	overlay.enabled = true
	overlay._process(0.0)
	assert_true(overlay.toasts.box.get_child_count() >= 1, "the queued toast shows after re-enabling")
	overlay.advance(3.5)
	overlay.free()
	GameState.reset()


func test_game_syncs_input_blocked_and_battle_disables_overlay() -> void:
	_reset()
	Engine.set_meta("skip_title", true)
	var game: Variant = load("res://app/game.gd").new()
	game.show_town()
	var overlay: Variant = game.overlay
	overlay.toggle_character()
	game._process(0.0)
	assert_true(
		bool(game.current.get("input_blocked")), "the map blocks movement while a panel is open"
	)

	overlay.toggle_character()
	game._process(0.0)
	assert_true(
		not bool(game.current.get("input_blocked")), "closing the panel unblocks movement"
	)

	game.current.set_input_override(Vector2(1.0, 0.0))
	overlay.toggle_character()
	game._process(0.0)
	var before: Vector2 = game.current.player_pos
	game.current.tick_player(0.2)
	assert_true(
		game.current.player_pos.distance_to(before) < 0.01,
		"input_blocked overrides even a test move override"
	)

	game.show_battle("ma_youwei", 1, false, false)
	assert_true(not bool(overlay.enabled), "the overlay is disabled during battle")
	assert_true(not bool(overlay.is_panel_open()), "the panels close when the battle starts")
	_press(overlay, KEY_C)
	assert_true(not bool(overlay.is_panel_open()), "C is ignored during battle")
	game.free()
	GameState.reset()


func test_k_opens_the_inventory_and_buttons_use_the_same_path() -> void:
	_reset()
	GameState.inventory["herb"] = 2
	var overlay: Variant = StatusOverlay.new()
	_press(overlay, KEY_K)
	assert_true(bool(overlay.inventory_panel.visible), "K opens the inventory")
	assert_eq(overlay.inventory_panel.item_ids(), ["herb"], "owned items are listed")
	assert_true(overlay.inventory_panel.find_child("Cell_herb", true, false) != null, "the item has a cell")
	_press(overlay, KEY_C)
	assert_true(not bool(overlay.inventory_panel.visible), "opening another panel closes the inventory")
	overlay._on_button_key("K")
	assert_true(bool(overlay.inventory_panel.visible), "the top-right K button opens the inventory")
	var btn: Node = overlay.buttons.find_child("Btn_J", true, false)
	assert_true(btn != null and str(btn.get("text")).contains("[J]"), "buttons show their hotkeys")
	overlay.free()


func test_item_found_before_accepting_the_quest_is_ready_at_once() -> void:
	_reset()
	GameState.inventory["jade_hairpin"] = 1
	assert_true(Quests.start("woman_pin"), "the quest starts")
	assert_eq(Quests.state("woman_pin"), "ready", "the hairpin is already in the bag")

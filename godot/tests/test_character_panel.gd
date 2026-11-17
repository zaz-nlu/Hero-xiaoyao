extends "res://tests/test_case.gd"

const GameState = preload("res://core/game_state.gd")
const Progression = preload("res://core/progression.gd")
const StatusOverlay = preload("res://ui/status_overlay.gd")


func _reset() -> void:
	GameState.reset()
	Progression.reload_items()


func _open() -> Variant:
	_reset()
	var overlay: Variant = StatusOverlay.new()
	overlay.toggle_character()
	return overlay


func _text_of(panel: Node, node_name: String) -> String:
	var node: Node = panel.find_child(node_name, true, false)
	if node == null:
		return ""
	return str(node.get("text"))


func _press_button(panel: Node, node_name: String) -> bool:
	var node: Node = panel.find_child(node_name, true, false)
	if node == null or not (node is Button):
		return false
	var button: Button = node
	button.emit_signal("pressed")
	return true


func _press_key(overlay: Variant, key: int) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	overlay._unhandled_input(event)


func _button(overlay: Variant, node_name: String) -> Button:
	var node: Node = overlay.character_panel.find_child(node_name, true, false)
	if node is Button:
		var button: Button = node
		return button
	return null


func test_opens_on_attributes_tab_and_shows_best_mark() -> void:
	var overlay: Variant = _open()
	assert_eq(int(overlay.character_panel.tab_index), 0, "the panel opens on the attributes tab")
	assert_true(
		overlay.character_panel.find_child("AttrValue_skill", true, false) != null,
		"the attributes tab shows the skill row"
	)
	var best: String = _text_of(overlay.character_panel, "BestMark_skill")
	assert_true(best.contains("最强"), "skill is the top stat and is marked: %s" % best)
	assert_eq(
		_text_of(overlay.character_panel, "BestMark_power"), "",
		"only the top stat carries the best mark"
	)
	overlay.free()
	GameState.reset()


func test_tab_switching_with_select_and_keys() -> void:
	var overlay: Variant = _open()
	overlay.character_panel.select_tab(1)
	assert_eq(int(overlay.character_panel.tab_index), 1, "select_tab jumps to the skills tab")
	_press_key(overlay, KEY_TAB)
	assert_eq(int(overlay.character_panel.tab_index), 2, "Tab moves to the next tab")
	_press_key(overlay, KEY_Q)
	assert_eq(int(overlay.character_panel.tab_index), 1, "Q moves to the previous tab")
	_press_key(overlay, KEY_3)
	assert_eq(int(overlay.character_panel.tab_index), 2, "a number key jumps straight to its tab")
	_press_key(overlay, KEY_E)
	assert_eq(int(overlay.character_panel.tab_index), 3, "E moves to the next tab")
	assert_true(
		overlay.character_panel.find_child("PointsAvailable", true, false) != null,
		"the points tab content is shown"
	)
	overlay.character_panel.select_tab(2)
	overlay.toggle_character()
	assert_true(not bool(overlay.is_panel_open()), "the panel closes on a second C press")
	overlay.toggle_character()
	assert_eq(
		int(overlay.character_panel.tab_index), 2, "reopening returns to the last viewed tab"
	)
	overlay.advance(0.2)
	overlay.free()
	GameState.reset()


func test_attributes_update_after_growth() -> void:
	var overlay: Variant = _open()
	var before: String = _text_of(overlay.character_panel, "AttrValue_power")
	assert_true(before.contains("6"), "power starts at its base value: %s" % before)

	GameState.stat_bonus["power"] = 1
	overlay.refresh()
	var after: String = _text_of(overlay.character_panel, "AttrValue_power")
	assert_true(after.contains("7"), "the total includes the permanent bonus: %s" % after)
	assert_true(after.contains("+1"), "the bonus is shown next to the total: %s" % after)
	assert_true(
		overlay.character_panel.find_child("AttrBonusFill_power", true, false) != null,
		"the bonus segment of the bar appears"
	)
	overlay.free()
	GameState.reset()


func test_skills_tab_shows_slots_and_detail() -> void:
	var overlay: Variant = _open()
	overlay.character_panel.select_tab(1)
	for i in range(4):
		assert_true(
			overlay.character_panel.find_child("MartialSlot_%d" % i, true, false) != null,
			"slot card %d exists" % i
		)
	assert_true(
		overlay.character_panel.find_child("MartialLearned_basic_sword", true, false) != null,
		"the learned list contains the basic sword"
	)
	_press_button(overlay.character_panel, "MartialLearned_basic_sword")
	var level_text: String = _text_of(overlay.character_panel, "DetailLevel")
	assert_true(level_text.contains("熟练度"), "the detail shows mastery: %s" % level_text)
	assert_true(level_text.contains("Lv.1"), "an unused martial starts at level one: %s" % level_text)
	var advantage: String = _text_of(overlay.character_panel, "DetailAdvantage")
	assert_true(advantage.contains("优势属性"), "the detail shows the advantage stat: %s" % advantage)
	assert_true(advantage.contains("你的最强属性"), "skill matches the player's top stat")

	GameState.mastery_total["basic_sword"] = 25
	overlay.refresh()
	level_text = _text_of(overlay.character_panel, "DetailLevel")
	assert_true(level_text.contains("Lv.2"), "stored mastery exp raises the level: %s" % level_text)
	var exp_text: String = _text_of(overlay.character_panel, "DetailExp")
	assert_true(exp_text.contains("10"), "the current level progress is shown: %s" % exp_text)

	_press_button(overlay.character_panel, "MartialLearned_taiji")
	var effect: String = _text_of(overlay.character_panel, "DetailEffect")
	assert_true(effect.contains("反震"), "reflect effects are listed: %s" % effect)
	overlay.free()
	GameState.reset()


func test_equipment_equip_and_unequip_flow() -> void:
	var overlay: Variant = _open()
	Progression.give_item("cloth_robe")
	overlay.refresh()
	overlay.character_panel.select_tab(2)
	assert_true(
		overlay.character_panel.find_child("BagItem_cloth_robe", true, false) != null,
		"the bag lists the robe"
	)
	assert_true(
		_text_of(overlay.character_panel, "BagName_cloth_robe").contains("粗布衣"),
		"the bag row shows the item name"
	)
	assert_true(
		_press_button(overlay.character_panel, "Equip_cloth_robe"),
		"the robe has an equip button"
	)
	assert_eq(
		str(GameState.equipment.get("armor", "")), "cloth_robe", "equipping fills the armor slot"
	)
	assert_true(
		_text_of(overlay.character_panel, "SlotItem_armor").contains("粗布衣"),
		"the armor slot card shows the robe"
	)
	assert_true(
		_text_of(overlay.character_panel, "SlotBonus_armor").contains("防御+1"),
		"the armor slot card shows its bonus"
	)

	overlay.character_panel.select_tab(0)
	var defense_text: String = _text_of(overlay.character_panel, "AttrValue_defense")
	assert_true(defense_text.contains("5"), "defense grows with the robe: %s" % defense_text)
	assert_true(defense_text.contains("+1"), "the equipment bonus is shown: %s" % defense_text)

	overlay.character_panel.select_tab(2)
	assert_true(
		_press_button(overlay.character_panel, "Unequip_cloth_robe"),
		"the equipped robe has an unequip button"
	)
	assert_eq(str(GameState.equipment.get("armor", "")), "", "unequipping empties the slot")

	Progression.give_item("herb")
	overlay.refresh()
	assert_true(
		overlay.character_panel.find_child("Equip_herb", true, false) == null,
		"materials cannot be equipped"
	)
	overlay.free()
	GameState.reset()


func test_points_pending_confirm_and_cap() -> void:
	var overlay: Variant = _open()
	overlay.character_panel.select_tab(3)
	assert_true(
		_text_of(overlay.character_panel, "PointsAvailable").contains("3"),
		"the tutorial grants three points"
	)
	for i in range(3):
		_press_button(overlay.character_panel, "PointPlus_power")
	assert_eq(
		int(overlay.character_panel.pending_points.get("power", 0)), 3,
		"three pending points are assigned to power"
	)
	var plus: Button = _button(overlay, "PointPlus_power")
	assert_true(plus != null and plus.disabled, "plus is disabled once every point is pending")

	_press_button(overlay.character_panel, "PointMinus_power")
	assert_eq(
		int(overlay.character_panel.pending_points.get("power", 0)), 2,
		"minus withdraws one pending point"
	)
	_press_button(overlay.character_panel, "PointPlus_power")
	assert_eq(
		int(overlay.character_panel.pending_points.get("power", 0)), 3,
		"plus can refill the withdrawn point"
	)

	Progression.take_toasts()
	assert_true(_press_button(overlay.character_panel, "ConfirmPoints"), "confirm is clickable")
	assert_eq(GameState.unspent_points, 0, "confirming spends all points")
	assert_eq(int(GameState.stat_bonus.get("power", 0)), 3, "the pending points become permanent")
	assert_eq(overlay.character_panel.pending_points.size(), 0, "confirming clears the pending map")
	assert_true(Progression.take_toasts().has("加点完成"), "confirming shows the completion toast")
	assert_true(
		overlay.character_panel.find_child("NoPointsMessage", true, false) != null,
		"with no points the empty-state message appears"
	)

	GameState.unspent_points = 3
	GameState.stat_bonus["speed"] = 42
	overlay.refresh()
	var capped: Button = _button(overlay, "PointPlus_speed")
	assert_true(capped != null and capped.disabled, "plus is disabled at the stat cap")
	overlay.free()
	GameState.reset()


func test_points_reset_clears_pending() -> void:
	var overlay: Variant = _open()
	overlay.character_panel.select_tab(3)
	_press_button(overlay.character_panel, "PointPlus_skill")
	_press_button(overlay.character_panel, "PointPlus_skill")
	assert_eq(
		int(overlay.character_panel.pending_points.get("skill", 0)), 2,
		"two points are pending"
	)
	assert_true(_press_button(overlay.character_panel, "ResetPoints"), "reset is clickable")
	assert_eq(overlay.character_panel.pending_points.size(), 0, "reset clears the pending map")
	assert_eq(GameState.unspent_points, 3, "reset does not spend points")
	overlay.free()
	GameState.reset()


func test_left_column_shows_realm_stage_age_and_hp() -> void:
	var overlay: Variant = _open()
	assert_eq(
		_text_of(overlay.character_panel, "CharRealm"), "炼体·中期",
		"the left column shows realm name and stage"
	)
	var age_text: String = _text_of(overlay.character_panel, "CharAge")
	assert_true(age_text.contains("9"), "the age line shows the player age: %s" % age_text)
	assert_true(
		_text_of(overlay.character_panel, "HpValue").contains("100"),
		"hp comes from constitution (40 + 4 × 15)"
	)
	overlay.free()
	GameState.reset()


func test_constitution_point_hint_uses_realm_hp_per_con() -> void:
	var overlay: Variant = _open()
	overlay.character_panel.select_tab(3)
	var hint: String = _text_of(overlay.character_panel, "ConstitutionHpHint")
	assert_true(hint.contains("+15"), "the constitution row explains its hp value: %s" % hint)
	overlay.free()
	GameState.reset()


func test_permanent_item_shows_use_button_and_applies() -> void:
	var overlay: Variant = _open()
	Progression.give_item("yangyuan_pill")
	overlay.refresh()
	overlay.character_panel.select_tab(2)
	assert_true(
		_press_button(overlay.character_panel, "Use_yangyuan_pill"),
		"a permanent consumable has a use button"
	)
	assert_eq(Progression.item_count("yangyuan_pill"), 0, "using the pill consumes it")
	assert_eq(int(GameState.stat_bonus.get("constitution", 0)), 1, "the pill adds constitution")
	overlay.character_panel.select_tab(0)
	assert_true(
		_text_of(overlay.character_panel, "AttrValue_constitution").contains("5"),
		"the attributes tab reflects the constitution gain"
	)
	assert_true(
		_text_of(overlay.character_panel, "HpValue").contains("115"),
		"the hp display follows the new constitution"
	)
	overlay.free()
	GameState.reset()

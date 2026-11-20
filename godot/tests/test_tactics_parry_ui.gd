extends "res://tests/test_case.gd"

# 破招界面测试：反制菜单的形态标题、结果徽章与消耗、内力不足置灰、固定两行、
# 数字键选择、不可破标记、缺素材回退；技能 tooltip 的可破形态图标；攻击日志的形态后缀。

const GameState = preload("res://core/game_state.gd")
const TacticsForms = preload("res://core/tactics/tactics_forms.gd")
const UI = preload("res://features/tactics/tactics_ui_style.gd")
const ReactionMenu = preload("res://features/tactics/tactics_reaction_menu.gd")

const BLOCK_ID := "_block"
const MISSING_TEX_DIR := "res://assets/ui/tactics/missing/"


func _holder() -> Control:
	var tree: Variant = Engine.get_meta("test_tree", null)
	var holder := Control.new()
	holder.size = Vector2(1152.0, 720.0)
	if tree != null:
		tree.root.add_child(holder)
	return holder


func _martial(id: String, grade: String, forms: Array) -> Dictionary:
	return {
		"id": id, "name": "乱砍", "grade": grade, "forms": forms,
		"power": 12, "counters": ["heavy"],
		"range": {"shape": "melee", "min": 1, "max": 1},
	}


func _option(id: String, outcome: String) -> Dictionary:
	return {"id": id, "outcome": outcome, "perfect": outcome == "perfect", "verdict": 0}


func _sweep_move() -> Dictionary:
	return {"id": "bandit_sweep", "name": "乱砍", "type": "sweep"}


func _open(menu, options: Array, neili: int, move: Dictionary) -> void:
	menu.open_for("马匪", "乱砍", "正面", "player", options,
		{"m": _martial("m", "common", ["chop"]), "m2": _martial("m2", "epic", ["sweep"])},
		{"neili": neili}, move)


func test_reaction_menu_title_names_the_attack_form() -> void:
	UI.reset_texture_dir()
	var holder := _holder()
	var menu: Variant = ReactionMenu.new()
	holder.add_child(menu)
	_open(menu, [_option("m", "perfect")], 14, _sweep_move())
	var title := str(menu.title_label.text) + str(menu.form_name_label.text)
	assert_true(title.contains("乱砍"), "the title names the incoming move: %s" % title)
	assert_true(title.contains("扫"), "the title names the move form: %s" % title)
	assert_true(menu.form_icon_rect.visible, "the form icon shows when its texture exists")
	assert_true(menu.form_icon_rect.texture != null, "the form icon texture loads")
	assert_true(not menu.form_text_block.visible, "the text fallback stays hidden with textures")
	holder.free()


func test_option_rows_show_result_badges_and_cost() -> void:
	UI.reset_texture_dir()
	var holder := _holder()
	var menu: Variant = ReactionMenu.new()
	holder.add_child(menu)
	_open(menu, [_option("m", "perfect"), _option("m2", "counter")], 14, _sweep_move())
	assert_eq(menu._buttons.size(), 4, "two martials plus basic block and skip")
	var perfect_row: Button = menu._buttons[0]
	var perfect_badge: Label = perfect_row.get_meta("badge", null)
	assert_true(perfect_badge != null, "the perfect row carries a badge")
	if perfect_badge != null:
		assert_eq(str(perfect_badge.text), "完美破招")
	var perfect_cost: Label = perfect_row.get_meta("cost_label", null)
	assert_true(perfect_cost != null, "the perfect row carries a cost label")
	if perfect_cost != null:
		assert_eq(str(perfect_cost.text), "1", "a common martial costs one neili")
	var counter_row: Button = menu._buttons[1]
	var counter_badge: Label = counter_row.get_meta("badge", null)
	if counter_badge != null:
		assert_eq(str(counter_badge.text), "克制", "a non-perfect counter reads 克制")
	var counter_cost: Label = counter_row.get_meta("cost_label", null)
	if counter_cost != null:
		assert_eq(str(counter_cost.text), "3", "an epic martial costs three neili")
	holder.free()


func test_unaffordable_option_is_greyed_out() -> void:
	UI.reset_texture_dir()
	var holder := _holder()
	var menu: Variant = ReactionMenu.new()
	holder.add_child(menu)
	_open(menu, [_option("m2", "counter")], 1, _sweep_move())
	assert_eq(menu._buttons.size(), 3, "one martial plus basic block and skip")
	var row: Button = menu._buttons[0]
	assert_true(row.disabled, "a martial the pool cannot pay for is disabled")
	var poor_label: Label = row.get_meta("poor_label", null)
	assert_true(poor_label != null, "the disabled row explains why")
	if poor_label != null:
		assert_eq(str(poor_label.text), "内力不足")
	holder.free()


func test_basic_block_and_skip_are_always_present() -> void:
	UI.reset_texture_dir()
	var holder := _holder()
	var menu: Variant = ReactionMenu.new()
	holder.add_child(menu)
	_open(menu, [_option("m", "perfect")], 14, _sweep_move())
	assert_true(menu.block_button != null, "basic block is always listed")
	assert_true(menu.skip_button != null, "declining is always listed")
	assert_eq(menu._choice_ids.size(), 3, "martial, then block, then skip")
	assert_eq(str(menu._choice_ids[0]), "m")
	assert_eq(str(menu._choice_ids[1]), BLOCK_ID)
	assert_eq(str(menu._choice_ids[2]), "")
	holder.free()


func test_unblockable_move_hides_martial_rows() -> void:
	UI.reset_texture_dir()
	var holder := _holder()
	var menu: Variant = ReactionMenu.new()
	holder.add_child(menu)
	_open(menu, [_option("m", "perfect")], 14,
		{"id": "kaishan", "name": "开山", "type": "heavy", "unblockable": true})
	assert_true(menu.unblockable_label.visible, "an unblockable move gets a visible flag")
	assert_eq(str(menu.unblockable_label.text), "不可破")
	assert_eq(menu._choice_ids.size(), 2, "no martial row survives an unblockable move")
	assert_eq(str(menu._choice_ids[0]), BLOCK_ID)
	assert_eq(str(menu._choice_ids[1]), "")
	holder.free()


func test_number_keys_choose_rows() -> void:
	UI.reset_texture_dir()
	var holder := _holder()
	var menu: Variant = ReactionMenu.new()
	holder.add_child(menu)
	_open(menu, [_option("m", "perfect")], 14, _sweep_move())
	var picked: Array = []
	menu.chosen.connect(func(defender_id: String, martial_id: String) -> void:
		picked.append("%s|%s" % [defender_id, martial_id]))
	assert_true(menu.handle_key(KEY_1), "key 1 picks the first row")
	assert_true(menu.handle_key(KEY_3), "key 3 picks 不反制")
	assert_eq(picked, ["player|m", "player|"], "number keys reuse the chosen signal")
	holder.free()


func test_missing_form_textures_fall_back_to_text() -> void:
	UI.set_texture_dir(MISSING_TEX_DIR)
	var holder := _holder()
	var menu: Variant = ReactionMenu.new()
	holder.add_child(menu)
	_open(menu, [_option("m", "perfect")], 14, _sweep_move())
	assert_true(not menu.form_icon_rect.visible, "no form icon without the texture")
	assert_true(menu.form_text_block.visible, "the form falls back to a text block")
	assert_eq(str(menu.form_text_block.text), "扫", "the fallback block shows the form name")
	UI.reset_texture_dir()
	holder.free()


func _make_view() -> Dictionary:
	GameState.reset()
	var tree: Variant = Engine.get_meta("test_tree", null)
	var holder := Control.new()
	holder.size = Vector2(1152.0, 720.0)
	if tree != null:
		tree.root.add_child(holder)
	var view: Variant = load("res://features/tactics/tactics_view.gd").new()
	view.use_3d = false
	holder.add_child(view)
	view.size = Vector2(1152.0, 720.0)
	return {"holder": holder, "view": view}


func _finish(holder: Control) -> void:
	holder.free()
	GameState.reset()


func test_martial_tooltip_lists_breakable_forms() -> void:
	UI.reset_texture_dir()
	var built := _make_view()
	var view: Variant = built["view"]
	view.start()
	var panel: Variant = view.panel
	assert_true(panel.martial_ids.size() > 0, "the player has martial buttons")
	if panel.martial_ids.is_empty():
		_finish(built["holder"])
		return
	var martial_id := str(panel.martial_ids[0])
	panel._on_martial_hover(panel.martial_buttons[0], martial_id)
	var tooltip: Variant = panel._tooltip
	assert_true(tooltip.visible, "hovering a martial button shows the tooltip")
	assert_eq(str(tooltip.forms_label.text), "可破形态：")
	var expected: int = TacticsForms.martial_forms(view.battle.martials[martial_id]).size()
	assert_true(expected > 0, "the first martial breaks at least one form")
	assert_eq(tooltip.form_icon_count(), expected, "one form icon per breakable form")
	_finish(built["holder"])


func test_attack_log_line_carries_move_form() -> void:
	var built := _make_view()
	var view: Variant = built["view"]
	view.start()
	var enemy = null
	var move_id := ""
	for unit in view.battle.units:
		if unit.side != "enemy" or unit.unit == null or unit.unit.def == null:
			continue
		for move in unit.unit.def.moves:
			if move is Dictionary and str(move.get("type", "")) == "sweep":
				enemy = unit
				move_id = str(move.get("id", ""))
				break
		if enemy != null:
			break
	assert_true(enemy != null, "the tavern battle has a sweeping enemy move")
	if enemy == null:
		_finish(built["holder"])
		return
	var text: String = view._event_text({
		"type": "attack", "unit": str(enemy.id), "martial_id": move_id,
		"target": Vector2i(1, 1)})
	assert_true(text.contains("[扫]"), "the attack log line names the form: %s" % text)
	_finish(built["holder"])

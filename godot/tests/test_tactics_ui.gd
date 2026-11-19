extends "res://tests/test_case.gd"

# 战棋战斗界面的 UI 结构测试：行动条卡片数、技能栏按钮数、选中/置灰、
# 日志最多 5 条，以及无贴图时样式工厂回退 StyleBoxFlat。

const GameState = preload("res://core/game_state.gd")
const UI = preload("res://features/tactics/tactics_ui_style.gd")


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


func test_turn_bar_shows_at_most_eight_cards() -> void:
	var built := _make_view()
	var view: Variant = built["view"]
	view.start()
	var expected: int = mini(8, view.battle.queue.preview(8).size())
	assert_eq(view.turn_bar.card_count(), expected,
		"the turn bar shows the previewed actors, capped at 8")
	_finish(built["holder"])


func test_turn_bar_cards_use_84x98_textured_frames() -> void:
	UI.reset_texture_dir()
	var built := _make_view()
	var view: Variant = built["view"]
	view.start()
	var bar: Variant = view.turn_bar
	assert_true(bar.card_count() > 0, "the turn bar has cards")
	if bar.card_count() == 0:
		_finish(built["holder"])
		return
	var active_tex: Texture2D = UI.texture_for("turn_card_active")
	var normal_tex: Texture2D = UI.texture_for("turn_card")
	var current_id := str(view.battle.current_actor)
	var saw_current := false
	for i in range(bar.card_count()):
		var card: Control = bar.card_at(i)
		if card == null:
			continue
		assert_eq(card.custom_minimum_size, Vector2(84.0, 98.0),
			"turn card %d is 84x98" % i)
		var style: StyleBox = bar.card_style(i)
		assert_true(style is StyleBoxTexture,
			"turn card %d uses its nine-patch texture" % i)
		if not (style is StyleBoxTexture):
			continue
		var current := str(card.get_meta("unit_id", "")) == current_id
		if current:
			saw_current = true
		assert_eq((style as StyleBoxTexture).texture,
			active_tex if current else normal_tex,
			"turn card %d follows the active/queue state" % i)
	assert_true(saw_current, "the current actor appears in the preview")
	var expected_width := (
		float(bar.card_count()) * 84.0 + float(maxi(0, bar.card_count() - 1)) * 4.0)
	assert_near(bar.contents_width(), expected_width, 0.5,
		"cards are 84 wide with 4 px gaps")
	_finish(built["holder"])


func test_skill_bar_has_move_martials_jianyi_wait_end() -> void:
	var built := _make_view()
	var view: Variant = built["view"]
	view.start()
	var player = view.battle.get_unit("player")
	assert_true(player != null, "the player unit exists")
	if player == null:
		_finish(built["holder"])
		return
	assert_eq(view.panel.skill_buttons.size(), player.loadout.size() + 4,
		"move + loadout + jianyi + wait + end")
	_finish(built["holder"])


func test_selected_martial_button_is_marked() -> void:
	var built := _make_view()
	var view: Variant = built["view"]
	view.start()
	assert_true(view.panel.martial_ids.size() > 0, "the player has martial buttons")
	if view.panel.martial_ids.is_empty():
		_finish(built["holder"])
		return
	var martial_id := str(view.panel.martial_ids[0])
	view.choose_mode("attack", martial_id)
	var button: Button = view.panel.martial_buttons[0]
	assert_true(bool(button.get_meta("selected", false)),
		"the chosen martial button is marked selected")
	_finish(built["holder"])


func test_martial_buttons_disable_after_action() -> void:
	var built := _make_view()
	var view: Variant = built["view"]
	view.start()
	var player = view.battle.get_unit("player")
	assert_true(player != null, "the player unit exists")
	if player == null:
		_finish(built["holder"])
		return
	player.has_acted = true
	view.panel.refresh(view.battle, view._actor_id)
	for button in view.panel.martial_buttons:
		assert_true(button.disabled, "martial buttons grey out after acting")
	_finish(built["holder"])


func test_log_feed_keeps_five_lines() -> void:
	var built := _make_view()
	var view: Variant = built["view"]
	view.start()
	for i in range(6):
		view.log_feed.add_line("第 %d 条测试日志" % (i + 1))
	assert_true(view.log_feed.line_count() <= 5,
		"the feed keeps at most five visible lines")
	_finish(built["holder"])


func test_style_factory_matches_available_textures() -> void:
	# 有约定贴图（assets/ui/tactics/）时用九宫格贴图，缺文件时回退 StyleBoxFlat。
	var textured: bool = FileAccess.file_exists("res://assets/ui/tactics/panel_frame.png")
	var unit_textured: bool = FileAccess.file_exists("res://assets/ui/tactics/unit_card.png")
	var button_textured: bool = FileAccess.file_exists("res://assets/ui/tactics/skill_button.png")
	assert_eq(UI.panel_style() is StyleBoxTexture, textured,
		"panel style follows the presence of its texture")
	assert_eq(UI.button_style("normal") is StyleBoxTexture, button_textured,
		"button style follows the presence of its texture")
	assert_eq(UI.unit_card_style() is StyleBoxTexture, unit_textured,
		"unit card style follows the presence of its texture")
	assert_true(UI.panel_style() is StyleBox, "a panel style is always available")

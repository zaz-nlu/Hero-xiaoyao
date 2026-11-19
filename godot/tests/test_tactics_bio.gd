extends "res://tests/test_case.gd"

# 战棋人物介绍卡：简介数据覆盖酒馆/森林战斗单位、玩家简介文本、
# 点击与右键打开、Esc 与关闭按钮收起。

const GameState = preload("res://core/game_state.gd")
const DataLoader = preload("res://core/data_loader.gd")
const TacticsSetup = preload("res://core/tactics/tactics_setup.gd")
const BioCard = preload("res://features/tactics/tactics_bio_card.gd")

const TAVERN_GROUP := [{"id": "ma_youwei", "count": 1}, {"id": "bandit", "count": 5}]
const FOREST_GROUP := [{"id": "bandit", "count": 2}]


func _make_view() -> Dictionary:
	GameState.reset()
	var tree: Variant = Engine.get_meta("test_tree", null)
	var holder := Control.new()
	holder.size = Vector2(1152.0, 648.0)
	if tree != null:
		tree.root.add_child(holder)
	var view: Variant = load("res://features/tactics/tactics_view.gd").new()
	view.use_3d = false
	holder.add_child(view)
	view.size = Vector2(1152.0, 648.0)
	return {"holder": holder, "view": view}


func _finish(holder: Control) -> void:
	holder.free()
	GameState.reset()


func test_every_enemy_def_has_a_bio() -> void:
	var bios: Dictionary = BioCard.load_bios()
	assert_true(bios.has(BioCard.PLAYER_BIO_ID), "the player character has a bio")
	var enemies: Dictionary = DataLoader.load_enemies(DataLoader.ENEMIES_PATH)
	assert_eq(enemies["errors"].size(), 0, "the enemies file is valid")
	for enemy_id in enemies["defs"].keys():
		assert_true(bios.has(str(enemy_id)), "enemy '%s' has a bio" % str(enemy_id))
	for key in bios.keys():
		var entry: Variant = bios[key]
		assert_true(entry is Dictionary, "bio '%s' is an object" % str(key))
		if not (entry is Dictionary):
			continue
		assert_true(str(entry.get("title", "")) != "",
			"bio '%s' has a title" % str(key))
		assert_true(str(entry.get("bio", "")) != "",
			"bio '%s' has body text" % str(key))


func test_tavern_and_forest_units_resolve_to_a_bio() -> void:
	GameState.reset()
	var setups := [
		{"map": "tavern_brawl", "group": TAVERN_GROUP},
		{"map": "forest_clearing", "group": FOREST_GROUP},
	]
	for raw in setups:
		var setup: Dictionary = raw
		var built: Dictionary = TacticsSetup.build(
			str(setup["map"]), setup["group"], null, 1)
		assert_true(bool(built.get("ok", false)),
			"%s assembles: %s" % [str(setup["map"]), str(built.get("errors", []))])
		if not bool(built.get("ok", false)):
			continue
		var battle: Variant = built["battle"]
		for unit in battle.units:
			var key := BioCard.bio_key(unit)
			assert_true(BioCard.entry_for(key).has("bio"),
				"%s unit '%s' resolves to a bio" % [str(setup["map"]), key])
	GameState.reset()


func test_ren_xiaoyao_bio_matches_the_story() -> void:
	var entry: Dictionary = BioCard.entry_for(BioCard.PLAYER_BIO_ID)
	assert_eq(str(entry.get("title", "")), "流落四方的少年",
		"the hero has the expected title")
	assert_true(str(entry.get("bio", "")).contains("紫霞镇"),
		"the hero bio mentions 紫霞镇")


func test_inspect_cell_opens_bio_for_both_sides() -> void:
	var built := _make_view()
	var view: Variant = built["view"]
	view.start()
	assert_eq(view.state(), "player", "the player acts first")
	var player = view.battle.get_unit("player")
	view.inspect_cell(player.pos)
	assert_true(view.is_bio_open(), "inspecting the player opens the card")
	assert_eq(view.bio_unit_id(), "ren_xiaoyao",
		"the player bio uses the character id")

	var enemy = view.battle.units[1]
	view.inspect_cell(enemy.pos)
	assert_true(view.is_bio_open(), "inspecting an enemy keeps the card open")
	assert_eq(view.bio_unit_id(), str(enemy.unit.def.id),
		"the enemy bio uses the enemy def id")
	_finish(built["holder"])


func test_idle_click_opens_bio_but_action_mode_does_not() -> void:
	var built := _make_view()
	var view: Variant = built["view"]
	view.start()
	var player = view.battle.get_unit("player")
	view._on_cell_clicked(player.pos)
	assert_true(view.is_bio_open(), "an idle click on a unit opens its bio")

	view.bio_card.close()
	view.choose_mode("move", "")
	view._on_cell_clicked(player.pos)
	assert_true(not view.is_bio_open(),
		"clicks in move mode keep their original meaning")
	_finish(built["holder"])


func test_right_click_signal_opens_bio() -> void:
	var built := _make_view()
	var view: Variant = built["view"]
	view.start()
	var player = view.battle.get_unit("player")
	view.board.cell_inspected.emit(player.pos)
	assert_true(view.is_bio_open(), "cell_inspected opens the bio")
	assert_eq(view.bio_unit_id(), "ren_xiaoyao", "the inspected unit is the player")
	_finish(built["holder"])


func test_escape_and_close_hide_the_bio() -> void:
	var built := _make_view()
	var view: Variant = built["view"]
	view.start()
	var player = view.battle.get_unit("player")

	view.inspect_cell(player.pos)
	assert_true(view.is_bio_open(), "the card is open before Esc")
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	view._input(event)
	assert_true(not view.is_bio_open(), "Esc closes the card")

	view.inspect_cell(player.pos)
	view.bio_card.close()
	assert_true(not view.is_bio_open(), "close() hides the card")
	_finish(built["holder"])


func test_empty_cell_does_not_open_bio() -> void:
	var built := _make_view()
	var view: Variant = built["view"]
	view.start()
	view.inspect_cell(Vector2i(9, 0))
	assert_true(not view.is_bio_open(), "a cell without a unit opens nothing")
	_finish(built["holder"])

extends "res://tests/test_case.gd"

const GameState = preload("res://core/game_state.gd")
const Progression = preload("res://core/progression.gd")
const Quests = preload("res://core/quests.gd")
const PlayerMotion = preload("res://shared/gameplay/player_motion.gd")
const TownData = preload("res://shared/resources/town_data.gd")

const TOWN_PATH := "res://data/town.json"

const ORE_POSITIONS: Array = [Vector2(-7.0, 2.0), Vector2(11.0, 8.5), Vector2(1.0, -14.0)]
const ORE_FLAGS: Array[String] = [
	"iron_ore_picked_1", "iron_ore_picked_2", "iron_ore_picked_3"
]
const GINSENG_POSITIONS: Array = [Vector2(-9.0, -8.0), Vector2(12.5, -15.0)]
const GINSENG_FLAGS: Array[String] = ["ginseng_picked_1", "ginseng_picked_2"]
const HAIRPIN_POS := Vector2(3.0, 15.5)
const OLD_BOX_POS := Vector2(11.5, 13.6)


func _reset() -> void:
	GameState.reset()
	Quests.reload()
	Progression.reload_items()


func _new_forest() -> Variant:
	var forest: Variant = load("res://features/forest/forest.gd").new()
	forest.build()
	forest.build_hud()
	return forest


func _new_town() -> Variant:
	var town: Variant = load("res://features/town/town.gd").new()
	town.build()
	town.build_hud()
	return town


func _collect_at(
	forest: Variant, pos: Vector2, display_name: String, item: String, flag: String
) -> void:
	forest.player_pos = pos
	forest.update_prompt()
	assert_true(bool(forest.prompt_label.visible), "%s prompt is visible" % display_name)
	assert_true(
		str(forest.prompt_label.text).contains(display_name),
		"%s prompt names the item: %s" % [display_name, str(forest.prompt_label.text)]
	)
	assert_true(forest.try_interact(), "%s can be collected" % display_name)
	assert_true(GameState.has_flag(flag), "%s sets its flag" % display_name)
	assert_true(Progression.item_count(item) > 0, "%s lands in the inventory" % item)


func test_forest_pickup_positions_are_clear() -> void:
	_reset()
	var forest: Variant = _new_forest()
	var positions: Array = ORE_POSITIONS.duplicate()
	positions.append(HAIRPIN_POS)
	positions.append_array(GINSENG_POSITIONS)
	for pos_value in positions:
		var pos: Vector2 = pos_value
		assert_true(forest._in_bounds(pos), "pickup %s is in bounds" % str(pos))
		assert_true(
			not PlayerMotion.blocked(pos, forest.blockers),
			"pickup %s is walkable" % str(pos)
		)
	for deco_value in forest.find_children("DecoHerb_*", "", true, false):
		var deco: Node3D = deco_value
		var deco_pos := Vector2(deco.position.x, deco.position.z)
		for pos_value in positions:
			var pos: Vector2 = pos_value
			assert_true(
				deco_pos.distance_to(pos) >= 1.5 - 0.001,
				"decorative herbs stay clear of collectables"
			)
	forest.free()


func test_forest_ore_collection_completes_smith_quest() -> void:
	_reset()
	var forest: Variant = _new_forest()
	assert_true(Quests.start("smith_whet"), "the smith quest starts")
	for i in range(ORE_POSITIONS.size()):
		var pos: Vector2 = ORE_POSITIONS[i]
		_collect_at(forest, pos, "铁矿石", "iron_ore", ORE_FLAGS[i])
		assert_true(
			forest.find_child("Pickup_%d" % (i + 4), true, false) == null,
			"ore node %d is removed" % (i + 4)
		)
	assert_eq(Progression.item_count("iron_ore"), 3, "three ores are collected")
	assert_eq(Quests.state("smith_whet"), "ready", "three ores make the smith quest ready")
	forest.free()

	var again: Variant = _new_forest()
	for i in range(ORE_POSITIONS.size()):
		assert_true(
			again.find_child("Pickup_%d" % (i + 4), true, false) == null,
			"a collected ore is not rebuilt"
		)
	again.free()


func test_forest_hairpin_and_ginseng_collection() -> void:
	_reset()
	var forest: Variant = _new_forest()
	assert_true(Quests.start("woman_pin"), "the townswoman quest starts")
	forest.player_pos = HAIRPIN_POS
	forest.update_prompt()
	assert_true(str(forest.prompt_label.text).contains("青玉发簪"), "the hairpin prompt shows")
	assert_true(forest.try_interact(), "the hairpin can be collected")
	assert_eq(Progression.item_count("jade_hairpin"), 1, "the hairpin is in the inventory")
	assert_true(GameState.has_flag("hairpin_picked"), "the hairpin flag is set")
	assert_eq(Quests.state("woman_pin"), "ready", "the hairpin completes the townswoman quest")
	assert_true(forest.find_child("Pickup_7", true, false) == null, "the hairpin node is removed")

	assert_true(Quests.start("herb_order"), "the herbalist quest starts")
	for i in range(GINSENG_POSITIONS.size()):
		var pos: Vector2 = GINSENG_POSITIONS[i]
		_collect_at(forest, pos, "人参", "ginseng", GINSENG_FLAGS[i])
	assert_eq(Progression.item_count("ginseng"), 2, "two ginseng are collected")
	assert_eq(Quests.state("herb_order"), "ready", "the ginseng completes the herbalist order")
	forest.free()


func test_town_old_box_collection() -> void:
	_reset()
	assert_true(Quests.start("fisher_box"), "the fisherman quest starts")
	var town: Variant = _new_town()
	var data: Dictionary = TownData.load_town(TOWN_PATH)["data"]
	assert_true(
		not PlayerMotion.blocked(OLD_BOX_POS, TownData.footprints(data)),
		"the old box spot is walkable"
	)
	town.player_pos = OLD_BOX_POS
	town.update_prompt()
	assert_true(bool(town.prompt_label.visible), "the old box prompt is visible")
	assert_true(
		str(town.prompt_label.text).contains("木匣"),
		"the old box prompt names the box: %s" % str(town.prompt_label.text)
	)
	assert_true(town.try_interact(), "the old box can be collected")
	assert_eq(Progression.item_count("old_box"), 1, "the old box is in the inventory")
	assert_true(GameState.has_flag("old_box_picked"), "the old box flag is set")
	assert_eq(Quests.state("fisher_box"), "ready", "the old box completes the fisherman quest")
	assert_true(
		town.find_child("Pickup_old_box", true, false) == null, "the old box node is removed"
	)
	town.free()

	var again: Variant = _new_town()
	assert_true(
		again.find_child("Pickup_old_box", true, false) == null,
		"a collected old box is not rebuilt"
	)
	assert_eq(Progression.item_count("old_box"), 1, "there is no second old box")
	again.free()

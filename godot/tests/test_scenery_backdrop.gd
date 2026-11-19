extends "res://tests/test_case.gd"

# 纯背景的边界回归：展示模式、演员缺席、幂等构建与持久状态隔离。
# 这些测试只使用 shared BackdropFactory，不经过任何 feature 控制器。

const GameState = preload("res://core/game_state.gd")
const Progression = preload("res://core/progression.gd")
const BackdropFactory = preload("res://shared/scenery/backdrop_factory.gd")
const TownData = preload("res://shared/resources/town_data.gd")

const TOWN_PATH := "res://data/town.json"
const ALL_WORLDS: Array[String] = ["town", "forest", "tavern"]


func _make_backdrop(world: String, options: Dictionary) -> Variant:
	var backdrop: Variant = BackdropFactory.create(world, options)
	backdrop.build()
	return backdrop


func test_title_town_keeps_ambient_npcs_without_visible_player_or_markers() -> void:
	GameState.reset()
	var backdrop: Variant = _make_backdrop("town", {
		"skip_actors": false,
		"hide_player": true,
		"quest_markers": false,
		"input_blocked": true,
		"cinematic": true,
	})
	assert_true(backdrop.npc_nodes.size() > 0, "title town keeps its ambient npcs")
	assert_true(
		backdrop.player == null or not backdrop.player.visible,
		"the cinematic player is hidden"
	)
	assert_eq(
		backdrop.find_children("QuestMarker_*", "", true, false).size(),
		0,
		"the shared backdrop never creates quest markers"
	)
	assert_true(bool(backdrop.input_blocked), "the cinematic display is input-blocked")
	backdrop.free()
	GameState.reset()


func test_battle_backdrops_have_no_actors_on_any_map() -> void:
	GameState.reset()
	for world in ALL_WORLDS:
		var backdrop: Variant = _make_backdrop(world, {"skip_actors": true})
		assert_eq(backdrop.player, null, "%s battle backdrop has no player" % world)
		assert_eq(backdrop.npc_nodes.size(), 0, "%s battle backdrop has no npcs" % world)
		assert_eq(
			backdrop.find_children("Pickup_*", "", true, false).size(),
			0,
			"%s battle backdrop has no pickup visuals" % world
		)
		backdrop.free()
	GameState.reset()


func test_title_town_keeps_uncollected_pickup_visuals() -> void:
	GameState.reset()
	var provider := func(flag: String) -> bool:
		return bool(GameState.has_flag(flag))
	var backdrop: Variant = _make_backdrop("town", _title_options(provider))
	var pickup_value: Variant = backdrop.find_child("Pickup_old_box", true, false)
	assert_true(pickup_value is Node3D, "the uncollected old box is drawn")
	if pickup_value is Node3D:
		var pickup: Node3D = pickup_value
		assert_true(pickup.visible, "the uncollected pickup is visible")
		var entry: Dictionary = _town_pickup("old_box")
		var px := float(entry.get("x", 0.0))
		var pz := float(entry.get("z", 0.0))
		var town_data: Dictionary = TownData.load_town(TOWN_PATH)["data"]
		var expected := Vector3(px, TownData.ground_height(town_data, px, pz), pz)
		assert_true(
			pickup.position.is_equal_approx(expected),
			"the pickup keeps its data position"
		)
	backdrop.free()
	GameState.reset()


func test_title_town_hides_collected_pickup_visuals() -> void:
	GameState.reset()
	GameState.set_flag("old_box_picked")
	var provider := func(flag: String) -> bool:
		return bool(GameState.has_flag(flag))
	var backdrop: Variant = _make_backdrop("town", _title_options(provider))
	assert_true(
		backdrop.find_child("Pickup_old_box", true, false) == null,
		"a collected pickup is not drawn"
	)
	backdrop.free()
	GameState.reset()


func test_title_backdrop_build_does_not_collect_pickups() -> void:
	GameState.reset()
	GameState.inventory["herb"] = 2
	GameState.quests["quest_keep"] = {"state": "active", "progress": {}}
	var before_flags: Dictionary = GameState.flags.duplicate(true)
	var before_inventory: Dictionary = GameState.inventory.duplicate(true)
	var before_quests: Dictionary = GameState.quests.duplicate(true)
	var provider := func(flag: String) -> bool:
		return bool(GameState.has_flag(flag))
	var backdrop: Variant = _make_backdrop("town", _title_options(provider))
	assert_eq(Progression.item_count("old_box"), 0, "the backdrop never grants the pickup item")
	assert_eq(GameState.flags, before_flags, "the backdrop never sets pickup flags")
	assert_eq(GameState.inventory, before_inventory, "the backdrop never changes inventory")
	assert_eq(GameState.quests, before_quests, "the backdrop never changes quests")
	backdrop.free()
	GameState.reset()


func test_title_town_uses_explicit_player_anchor_for_npcs() -> void:
	GameState.reset()
	var anchor := Vector2(8.5, -2.6)
	var provider := func(flag: String) -> bool:
		return bool(GameState.has_flag(flag))
	var backdrop: Variant = _make_backdrop("town", _title_options(provider, anchor))
	assert_true(
		backdrop.player_pos.is_equal_approx(anchor),
		"the hidden player feeds the explicit anchor to npc wandering"
	)
	if backdrop.player is Node3D:
		var player: Node3D = backdrop.player
		assert_true(
			Vector2(player.position.x, player.position.z).is_equal_approx(anchor),
			"the hidden player node sits on the anchor"
		)
	var waiter_value: Variant = backdrop.npc_nodes.get("waiter", null)
	assert_true(waiter_value is Node3D, "the waiter npc exists")
	if waiter_value is Node3D:
		var waiter: Node3D = waiter_value
		waiter.set("moving", true)
		backdrop.advance(0.1)
		assert_true(not bool(waiter.get("moving")), "the nearby anchor stops the wandering npc")
	backdrop.free()
	GameState.reset()


func _title_options(provider: Callable, anchor: Variant = null) -> Dictionary:
	return {
		"skip_actors": false,
		"hide_player": true,
		"cinematic": true,
		"picked_flag_provider": provider,
		"player_anchor": anchor,
	}


func _town_pickup(pickup_id: String) -> Dictionary:
	var town_data: Dictionary = TownData.load_town(TOWN_PATH)["data"]
	for pickup_value in town_data.get("pickups", []):
		var pickup: Dictionary = pickup_value
		if str(pickup.get("id", "")) == pickup_id:
			return pickup
	return {}


func test_backdrop_build_is_idempotent() -> void:
	GameState.reset()
	for world in ALL_WORLDS:
		var backdrop: Variant = _make_backdrop(world, {"skip_actors": true})
		var before: int = int(backdrop.get_child_count())
		assert_true(before > 0, "%s build creates scene nodes" % world)
		backdrop.build()
		assert_eq(
			int(backdrop.get_child_count()),
			before,
			"%s build does not duplicate scene nodes" % world
		)
		backdrop.free()
	GameState.reset()


func test_tavern_brawl_backdrop_applies_static_furniture() -> void:
	GameState.reset()
	var backdrop: Variant = _make_backdrop("tavern", {
		"skip_actors": true,
		"force_state": "brawl",
	})
	var debris: Variant = backdrop.find_child("WreckedDebris", true, false)
	assert_true(debris is Node3D and (debris as Node3D).visible, "brawl debris is visible")
	var fallen_tables := 0
	for id in backdrop.furniture_nodes.keys():
		var node_value: Variant = backdrop.furniture_nodes[id]
		if not (node_value is Node3D):
			continue
		var node: Node3D = node_value
		if node.get_node_or_null("TableWreckedSprite") == null:
			continue
		if absf(node.rotation.z) <= 0.5 and absf(node.rotation.x) <= 0.5:
			continue
		fallen_tables += 1
		var normal_value: Variant = node.get_node_or_null("TableSprite")
		var wrecked_value: Variant = node.get_node_or_null("TableWreckedSprite")
		if normal_value is Sprite3D:
			assert_true(not (normal_value as Sprite3D).visible, "the intact table is hidden")
		if wrecked_value is Sprite3D:
			assert_true((wrecked_value as Sprite3D).visible, "the wrecked table is shown")
	assert_true(fallen_tables >= 2, "the brawl knocks at least two tables over")
	backdrop.free()
	GameState.reset()


func test_building_backdrops_does_not_change_persistent_state() -> void:
	GameState.reset()
	GameState.set_flag("keep_me")
	GameState.inventory["herb"] = 2
	GameState.quests["quest_keep"] = {"state": "active", "progress": {}}
	GameState.dialogue_counters["keeper"] = 3
	var before_flags: Dictionary = GameState.flags.duplicate(true)
	var before_inventory: Dictionary = GameState.inventory.duplicate(true)
	var before_quests: Dictionary = GameState.quests.duplicate(true)
	var before_state: Dictionary = GameState.to_dict()
	for world in ALL_WORLDS:
		var options: Dictionary = {"skip_actors": true}
		if world == "tavern":
			options["force_state"] = "brawl"
		var backdrop: Variant = _make_backdrop(world, options)
		backdrop.free()
	assert_eq(GameState.flags, before_flags, "backdrop builds leave flags untouched")
	assert_eq(GameState.inventory, before_inventory, "backdrop builds leave inventory untouched")
	assert_eq(GameState.quests, before_quests, "backdrop builds leave quests untouched")
	assert_eq(GameState.to_dict(), before_state, "backdrop builds leave persistent state untouched")
	GameState.reset()

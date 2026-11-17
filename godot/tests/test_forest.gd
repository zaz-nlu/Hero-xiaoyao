extends "res://tests/test_case.gd"

const GameState = preload("res://core/game_state.gd")
const Progression = preload("res://core/progression.gd")
const DataLoader = preload("res://core/data_loader.gd")
const PlayerMotion = preload("res://world/player_motion.gd")
const AiAssets = preload("res://world/ai_assets.gd")

const FOREST_PATH := "res://data/forest.json"

var exit_places: Array = []


func _new_forest() -> Variant:
	var forest: Variant = load("res://world/forest.gd").new()
	forest.build()
	forest.build_hud()
	return forest


func _forest_data() -> Dictionary:
	if not FileAccess.file_exists(FOREST_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FOREST_PATH))
	if parsed is Dictionary:
		return parsed
	return {}


func _on_exit_requested(place: String) -> void:
	exit_places.append(place)


func _blocked(blockers: Array, point: Vector2) -> bool:
	for value in blockers:
		var rect: Rect2 = value
		if rect.grow(PlayerMotion.RADIUS).has_point(point):
			return true
	return false


# Walks a half-unit grid over the bounds, honouring the same blockers as the player,
# and reports whether any reachable cell sits within goal_dist of the goal.
func _bfs_reaches(forest: Variant, start: Vector2, goal: Vector2, goal_dist: float) -> bool:
	var bounds: Rect2 = forest.bounds_rect
	if bounds.size == Vector2.ZERO:
		return false
	var step := 0.5
	var cols := int(ceil(bounds.size.x / step))
	var rows := int(ceil(bounds.size.y / step))
	var start_cell := Vector2i(
		int(round((start.x - bounds.position.x) / step)),
		int(round((start.y - bounds.position.y) / step))
	)
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [start_cell]
	visited[start_cell] = true
	var head := 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		var point := bounds.position + Vector2(float(cell.x), float(cell.y)) * step
		if point.distance_to(goal) <= goal_dist:
			return true
		for direction in dirs:
			var next: Vector2i = cell + direction
			if next.x < 0 or next.y < 0 or next.x >= cols or next.y >= rows:
				continue
			if visited.has(next):
				continue
			var next_point := bounds.position + Vector2(float(next.x), float(next.y)) * step
			if _blocked(forest.blockers, next_point):
				continue
			visited[next] = true
			queue.append(next)
	return false


func test_forest_data_loads() -> void:
	var data: Dictionary = _forest_data()
	assert_true(not data.is_empty(), "forest.json parses as an object")
	if data.is_empty():
		return
	var bounds: Dictionary = data.get("bounds", {})
	assert_eq(float(bounds.get("x0", 0.0)), -24.0, "west bound")
	assert_eq(float(bounds.get("x1", 0.0)), 24.0, "east bound")
	assert_eq(float(bounds.get("z0", 0.0)), -24.0, "north bound")
	assert_eq(float(bounds.get("z1", 0.0)), 24.0, "south bound")
	var pickups: Array = data.get("pickups", [])
	assert_eq(pickups.size(), 4, "three herbs and one chest")
	var hide_spots: Array = data.get("hide_spots", [])
	assert_eq(hide_spots.size(), 25, "twenty-five grass hide spots")
	var road_spots := 0
	for spot_value in hide_spots:
		var spot: Dictionary = spot_value
		if bool(spot.get("road", false)):
			road_spots += 1
	assert_eq(road_spots, 8, "eight of the hide spots are by the road")
	var patrol: Dictionary = data.get("patrol_slots", {})
	var routes: Array = patrol.get("routes", [])
	var scout: Array = patrol.get("scout", [])
	assert_eq(routes.size(), 2, "two patrol routes are reserved")
	assert_eq(float(scout[0]), 4.0, "the scout slot x")


func test_build_creates_the_forest() -> void:
	GameState.reset()
	var forest: Variant = _new_forest()
	assert_true(not forest.data.is_empty(), "forest data loaded")
	assert_true(forest.camera != null, "the forest has a camera")
	assert_true(forest.player != null, "the roaming player exists")
	assert_true(forest.sun != null, "the sun exists")
	assert_true(forest.tree_positions.size() >= 80, "at least eighty trees")
	assert_true(forest.rock_positions.size() >= 6, "the roadside has rocks")
	assert_eq(forest.hide_spots.size(), 25, "hide spots are loaded")
	assert_true(float(forest.arena_origin.x) < 0.0, "the arena origin comes from data")
	forest.free()


func test_clearings_have_no_tree_or_rock_blockers() -> void:
	GameState.reset()
	var forest: Variant = _new_forest()
	var spawn := Vector2(0.0, 21.5)
	var arena := Vector2(forest.arena_origin.x, forest.arena_origin.z)
	var chest := Vector2(8.0, -21.0)
	for value in forest.tree_positions:
		var point: Vector2 = value
		assert_true(point.distance_to(spawn) >= 3.0 - 0.001, "tree at spawn clearing")
		assert_true(point.distance_to(arena) >= 9.0 - 0.001, "tree in the arena clearing")
		assert_true(point.distance_to(chest) >= 2.5 - 0.001, "tree at the chest clearing")
	for value in forest.rock_positions:
		var point: Vector2 = value
		assert_true(point.distance_to(spawn) >= 3.0 - 0.001, "rock at spawn clearing")
		assert_true(point.distance_to(arena) >= 9.0 - 0.001, "rock in the arena clearing")
		assert_true(point.distance_to(chest) >= 2.5 - 0.001, "rock at the chest clearing")
	var base_blockers: int = forest.tree_positions.size() + forest.rock_positions.size()
	assert_true(
		forest.blockers.size() >= base_blockers,
		"every tree and rock still contributes a blocker"
	)
	forest.free()


func test_pickup_nodes_exist() -> void:
	GameState.reset()
	var forest: Variant = _new_forest()
	assert_true(forest.find_child("Herb_1", true, false) != null, "herb 1 exists")
	assert_true(forest.find_child("Herb_2", true, false) != null, "herb 2 exists")
	assert_true(forest.find_child("Herb_3", true, false) != null, "herb 3 exists")
	assert_true(forest.find_child("Chest", true, false) != null, "the chest exists")
	forest.free()


func test_collect_herb_once() -> void:
	GameState.reset()
	var forest: Variant = _new_forest()
	forest.player_pos = Vector2(2.5, 11.0)
	forest.update_prompt()
	assert_true(bool(forest.prompt_label.visible), "the herb prompt shows")
	assert_true(str(forest.prompt_label.text).contains("草药"), "the prompt mentions the herb")
	assert_true(forest.try_interact(), "pressing E collects the herb")
	assert_eq(Progression.item_count("herb"), 1, "the herb lands in the inventory")
	assert_true(GameState.has_flag("herb_picked_1"), "the herb flag is set")
	assert_true(forest.find_child("Herb_1", true, false) == null, "the node is removed")
	forest.free()

	var again: Variant = _new_forest()
	assert_true(again.find_child("Herb_1", true, false) == null, "a picked herb is not rebuilt")
	assert_true(again.find_child("Herb_2", true, false) != null, "the other herbs are still there")
	again.free()


func test_open_chest_once() -> void:
	GameState.reset()
	var forest: Variant = _new_forest()
	forest.player_pos = Vector2(8.0, -21.0)
	forest.update_prompt()
	assert_true(bool(forest.prompt_label.visible), "the chest prompt shows")
	assert_true(str(forest.prompt_label.text).contains("宝箱"), "the prompt mentions the chest")
	assert_true(forest.try_interact(), "pressing E opens the chest")
	assert_true(forest.chest_opened, "the chest is open")
	assert_eq(Progression.item_count("plain_sword"), 1, "the sword lands in the inventory")
	assert_eq(Progression.equipped("weapon"), "plain_sword", "the sword is equipped")
	assert_true(GameState.has_flag("chest_plain_sword_opened"), "the chest flag is set")
	var base: Dictionary = DataLoader.load_player("res://data/player.json").get("stats", {})
	var final_stats: Dictionary = Progression.final_stats(base)
	assert_eq(
		int(final_stats.get("speed", 0)) - int(base.get("speed", 0)), 1, "speed +1 from the sword"
	)
	assert_eq(
		int(final_stats.get("power", 0)) - int(base.get("power", 0)), 1, "power +1 from the sword"
	)
	assert_true(not forest.try_interact(), "an open chest cannot be opened again")
	forest.free()

	var again: Variant = _new_forest()
	assert_true(again.chest_opened, "a rebuilt chest starts open")
	again.player_pos = Vector2(8.0, -21.0)
	assert_true(not again.try_interact(), "the rebuilt chest gives nothing")
	assert_eq(Progression.item_count("plain_sword"), 1, "there is no second sword")
	again.free()


func test_exits_emit_place() -> void:
	GameState.reset()
	exit_places.clear()
	var forest: Variant = _new_forest()
	forest.connect("exit_requested", Callable(self, "_on_exit_requested"))
	forest.player_pos = Vector2(0.0, 22.5)
	forest.update_prompt()
	assert_true(
		str(forest.prompt_label.text).contains("紫霞镇"), "the south exit prompt mentions the town"
	)
	assert_true(forest.try_interact(), "the south exit can be used")
	forest.player_pos = Vector2(6.0, -22.5)
	assert_true(forest.try_interact(), "the north exit can be used")
	assert_eq(exit_places.size(), 2, "both exits fired")
	if exit_places.size() == 2:
		assert_eq(str(exit_places[0]), "town", "the south exit leads to town")
		assert_eq(str(exit_places[1]), "wasteland", "the north exit leads to the wasteland")
	forest.free()


func test_player_cannot_walk_through_trees() -> void:
	GameState.reset()
	var forest: Variant = _new_forest()
	var tree := Vector2.ZERO
	var found := false
	for value in forest.tree_positions:
		var point: Vector2 = value
		if absf(point.x) < 20.0 and point.y > -18.0 and point.y < 18.0:
			tree = point
			found = true
			break
	assert_true(found, "found an interior tree to test")
	if not found:
		forest.free()
		return
	forest.player_pos = Vector2(tree.x, tree.y + 1.6)
	forest.set_input_override(Vector2(0.0, -1.0))
	for i in range(30):
		forest.tick_player(0.1)
	assert_true(
		forest.player_pos.distance_to(tree) >= 0.85,
		"the tree blocker stops the player (dist %.2f)" % forest.player_pos.distance_to(tree)
	)
	forest.free()


func test_road_reaches_the_chest() -> void:
	GameState.reset()
	var forest: Variant = _new_forest()
	assert_true(
		_bfs_reaches(forest, Vector2(0.0, 21.5), Vector2(8.0, -21.0), 2.0),
		"the winding road connects the spawn to the chest"
	)
	forest.free()


func test_tree_species_variety() -> void:
	GameState.reset()
	var forest: Variant = _new_forest()
	var textures: Dictionary = {}
	for node_value in forest.find_children("*Tree_*", "", true, false):
		if not (node_value is Sprite3D):
			continue
		var sprite: Sprite3D = node_value
		if sprite.texture != null:
			textures[sprite.texture] = true
	assert_true(textures.size() >= 4, "at least four tree textures are in use")
	forest.free()


func test_forest_landmarks_exist() -> void:
	GameState.reset()
	var forest: Variant = _new_forest()
	assert_true(forest.find_child("Camp", true, false) != null, "the bandit camp exists")
	assert_true(
		forest.find_child("ForestSignpost", true, false) != null, "the forest signpost exists"
	)
	assert_true(forest.find_child("FloorProps", true, false) != null, "floor props exist")
	var deco_herbs: Array = forest.find_children("DecoHerb_*", "", true, false)
	assert_true(deco_herbs.size() >= 10, "at least ten decorative herbs are scattered")
	var herbs: Array = forest.find_children("Herb_*", "", true, false)
	assert_eq(herbs.size(), 3, "the three collectable herbs remain")
	forest.free()


func test_chest_switches_to_open_texture() -> void:
	GameState.reset()
	var forest: Variant = _new_forest()
	var sprite_value: Variant = forest.find_child("ChestSprite", true, false)
	assert_true(sprite_value is Sprite3D, "the chest uses a closed texture sprite")
	var open_tex: ImageTexture = AiAssets.load_texture("chest_open.png")
	assert_true(open_tex != null, "the open chest texture loads")
	forest.player_pos = Vector2(8.0, -21.0)
	assert_true(forest.try_interact(), "the chest opens")
	forest.advance_chest(0.3)
	if sprite_value is Sprite3D and open_tex != null:
		var sprite: Sprite3D = sprite_value
		assert_true(sprite.texture == open_tex, "the chest swaps to the open texture")
	forest.free()


func test_arena_has_no_blocking_props() -> void:
	GameState.reset()
	var forest: Variant = _new_forest()
	var arena := Vector2(forest.arena_origin.x, forest.arena_origin.z)
	for value in forest.blockers:
		var rect: Rect2 = value
		var center := rect.get_center()
		assert_true(
			center.distance_to(arena) >= 9.0 - 0.001,
			"no blocker inside the arena clearing (dist %.2f)" % center.distance_to(arena)
		)
	forest.free()

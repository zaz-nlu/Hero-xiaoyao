extends "res://tests/test_case.gd"

const TacticsSetup = preload("res://core/tactics/tactics_setup.gd")
const TacticsStage = preload("res://features/tactics/tactics_stage.gd")
const TacticsPicker = preload("res://features/tactics/tactics_picker.gd")
const GameState = preload("res://core/game_state.gd")

const TAVERN_GROUP := [{"id": "ma_youwei", "count": 1}, {"id": "bandit", "count": 5}]
const FOREST_GROUP := [{"id": "bandit", "count": 2}]


func _make_battle(map_id: String, group: Array) -> Variant:
	GameState.reset()
	var built: Dictionary = TacticsSetup.build(map_id, group, null, 1)
	if not bool(built.get("ok", false)):
		return null
	return built["battle"]


func _make_stage(battle: Variant, backdrop: String = "tavern") -> Variant:
	var stage: Variant = TacticsStage.new()
	stage.build(battle, backdrop)
	return stage


func test_stage_builds_one_tile_per_cell() -> void:
	var battle: Variant = _make_battle("tavern_brawl", TAVERN_GROUP)
	assert_true(battle != null, "the tavern battle is assembled")
	if battle == null:
		return
	var stage: Variant = _make_stage(battle)
	assert_eq(stage.tiles.cell_count(), int(battle.grid.width) * int(battle.grid.height),
		"the tile count matches the grid")
	for y in range(int(battle.grid.height)):
		for x in range(int(battle.grid.width)):
			assert_true(stage.tiles.tile_node(Vector2i(x, y)) != null,
				"tile (%d,%d) has a node" % [x, y])
	stage.free()


func test_terrain_cells_have_meshes_and_props() -> void:
	var battle: Variant = _make_battle("tavern_brawl", TAVERN_GROUP)
	assert_true(battle != null, "the tavern battle is assembled")
	if battle == null:
		return
	var stage: Variant = _make_stage(battle)
	var walls := 0
	var furniture := 0
	for y in range(int(battle.grid.height)):
		for x in range(int(battle.grid.width)):
			var cell := Vector2i(x, y)
			var terrain := str(battle.grid.terrain_at(cell))
			if terrain != "wall" and terrain != "furniture" and terrain != "obstacle":
				continue
			var tile = stage.tiles.tile_node(cell)
			assert_true(tile != null, "%s cell %s has a tile node" % [terrain, str(cell)])
			if tile == null:
				continue
			assert_true(tile.get_node_or_null("Column") != null,
				"%s cell %s has a column mesh" % [terrain, str(cell)])
			assert_true(tile.get_node_or_null("Top") != null,
				"%s cell %s has a top surface" % [terrain, str(cell)])
			if terrain == "wall":
				walls += 1
			else:
				furniture += 1
				assert_true(stage.tiles.prop_node(cell) != null,
					"%s cell %s has a prop sprite" % [terrain, str(cell)])
	assert_true(walls > 0, "the tavern map has wall cells")
	assert_true(furniture > 0, "the tavern map has furniture cells")
	stage.free()


func test_each_alive_unit_has_an_actor() -> void:
	var battle: Variant = _make_battle("tavern_brawl", TAVERN_GROUP)
	assert_true(battle != null, "the tavern battle is assembled")
	if battle == null:
		return
	var stage: Variant = _make_stage(battle)
	var alive := 0
	for unit in battle.units:
		if not unit.is_alive():
			continue
		alive += 1
		assert_true(stage.units.actor(str(unit.id)) != null,
			"unit %s has an actor" % str(unit.id))
	assert_eq(stage.units.actor_count(), alive, "one actor per living unit")
	stage.free()


func test_cell_center_rises_with_height() -> void:
	var battle: Variant = _make_battle("tavern_brawl", TAVERN_GROUP)
	assert_true(battle != null, "the tavern battle is assembled")
	if battle == null:
		return
	var stage: Variant = _make_stage(battle)
	var low := Vector2i(-1, -1)
	var high := Vector2i(-1, -1)
	for y in range(int(battle.grid.height)):
		for x in range(int(battle.grid.width)):
			var cell := Vector2i(x, y)
			if int(battle.grid.height_at(cell)) > 0:
				if high.x < 0:
					high = cell
			elif low.x < 0 and str(battle.grid.terrain_at(cell)) == "floor":
				low = cell
	assert_true(low.x >= 0, "the map has a ground cell")
	assert_true(high.x >= 0, "the map has a raised cell")
	if low.x >= 0 and high.x >= 0:
		var low_center: Vector3 = stage.cell_center(low)
		var high_center: Vector3 = stage.cell_center(high)
		assert_true(high_center.y > low_center.y,
			"raised cell %s sits above ground cell %s" % [str(high), str(low)])
	stage.free()


func test_highlights_follow_overlays() -> void:
	var battle: Variant = _make_battle("tavern_brawl", TAVERN_GROUP)
	assert_true(battle != null, "the tavern battle is assembled")
	if battle == null:
		return
	var stage: Variant = _make_stage(battle)
	var move_cell := Vector2i(2, 3)
	var attack_cell := Vector2i(3, 3)
	var selected_cell := Vector2i(4, 3)
	var untouched := Vector2i(7, 5)
	stage.set_state(battle, {
		"move": [move_cell], "attack": [attack_cell], "selected": selected_cell,
	})
	assert_true(stage.tiles.highlight_node(move_cell).visible,
		"the move overlay is visible")
	assert_true(stage.tiles.highlight_node(attack_cell).visible,
		"the attack overlay is visible")
	assert_true(stage.tiles.highlight_node(selected_cell).visible,
		"the selected overlay is visible")
	assert_true(not stage.tiles.highlight_node(untouched).visible,
		"cells outside the overlays stay hidden")
	stage.free()


func test_show_events_spawns_feedback() -> void:
	var battle: Variant = _make_battle("tavern_brawl", TAVERN_GROUP)
	assert_true(battle != null, "the tavern battle is assembled")
	if battle == null:
		return
	var stage: Variant = _make_stage(battle)
	var defender = null
	for unit in battle.units:
		if unit.side == "enemy":
			defender = unit
			break
	assert_true(defender != null, "the battle has an enemy")
	if defender == null:
		stage.free()
		return
	stage.set_state(battle, {})
	var effects_before := int(stage.fx.effect_count())
	var popups_before := int(stage.fx.popup_count())
	stage.show_events([
		{"type": "hit", "attacker": "player", "defender": str(defender.id),
			"damage": 4, "relation": "front"},
		{"type": "counter_hit", "attacker": str(defender.id),
			"defender": "player", "damage": 2},
		{"type": "stun", "unit": str(defender.id)},
	])
	assert_true(stage.fx.effect_count() > effects_before, "the events spawn vfx")
	assert_true(stage.fx.popup_count() > popups_before, "the events spawn damage numbers")
	stage.free()


func test_forest_map_builds() -> void:
	var battle: Variant = _make_battle("forest_clearing", FOREST_GROUP)
	assert_true(battle != null, "the forest battle is assembled")
	if battle == null:
		return
	var stage: Variant = _make_stage(battle, "forest")
	assert_eq(stage.backdrop, "forest", "the stage uses the forest backdrop")
	assert_eq(stage.tiles.cell_count(), int(battle.grid.width) * int(battle.grid.height),
		"the forest tiles match the grid")
	var obstacles := 0
	for y in range(int(battle.grid.height)):
		for x in range(int(battle.grid.width)):
			var cell := Vector2i(x, y)
			if str(battle.grid.terrain_at(cell)) != "obstacle":
				continue
			obstacles += 1
			assert_true(stage.tiles.prop_node(cell) != null,
				"obstacle cell %s has a prop sprite" % str(cell))
	assert_true(obstacles > 0, "the forest map has obstacle cells")
	stage.free()


func test_picker_maps_screen_point_to_its_cell() -> void:
	var battle: Variant = _make_battle("tavern_brawl", TAVERN_GROUP)
	assert_true(battle != null, "the tavern battle is assembled")
	if battle == null:
		return
	var stage: Variant = _make_stage(battle)
	var tree: Variant = Engine.get_meta("test_tree", null)
	if tree == null:
		stage.free()
		return
	var camera := Camera3D.new()
	tree.root.add_child(camera)
	if not camera.is_inside_tree():
		camera.free()
		stage.free()
		return
	var target := Vector2i(4, 4)
	var center: Vector3 = stage.cell_center(target)
	camera.fov = 40.0
	camera.near = 0.1
	camera.far = 500.0
	camera.global_position = center + Vector3(0.0, 9.0, 6.0)
	camera.look_at(center, Vector3.UP)
	camera.current = true
	var screen: Vector2 = camera.unproject_position(center)
	var picked: Vector2i = TacticsPicker.cell_at_screen(
		camera, screen, battle.grid, stage.tiles)
	assert_eq(picked, target, "the picker resolves the projected centre back to its cell")
	camera.current = false
	camera.free()
	stage.free()

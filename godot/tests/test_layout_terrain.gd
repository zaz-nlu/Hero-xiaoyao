extends "res://tests/test_case.gd"

# 地形数据 + 运行时试跑的回归测试：
# 旧平地兼容、三层台地上下楼、挡墙与开口侧边、坡道连续 Y、四向连接、
# 水面阻挡、建筑/出生点落位，以及错误草稿被 document 校验拒绝。

const LayoutCatalog = preload("res://core/layouts/layout_catalog.gd")
const LayoutDocument = preload("res://core/layouts/layout_document.gd")
const LayoutTerrain = preload("res://core/layouts/layout_terrain.gd")
const LayoutBuilder = preload("res://shared/scenery/layouts/layout_builder.gd")
const LayoutWalk = preload("res://features/layouts/layout_walk.gd")
const PlayerMotion = preload("res://shared/gameplay/player_motion.gd")

const SPAWN_PATH := "user://test_layout_terrain_spawn.json"
const TICK := 0.05


func _catalog() -> Dictionary:
	return LayoutCatalog.load_catalog()


func _base_document() -> Dictionary:
	return {
		"version": 1,
		"id": "terrain_test",
		"name": "地形测试",
		"width": 12,
		"depth": 10,
		"ground": "grass",
		"tiles": [],
		"objects": [],
		"spawn": {"x": 11.0, "z": 18.5},
		"regions": [],
	}


func _three_tier_document() -> Dictionary:
	var document := _base_document()
	document["terraces"] = [
		{
			"name": "一层",
			"rect": [2, 10, 22, 16],
			"y": 1.0,
			"from_y": 0.0,
			"stairs": [{"x0": 8, "x1": 12}],
		},
		{
			"name": "二层",
			"rect": [2, 4, 22, 10],
			"y": 2.0,
			"from_y": 1.0,
			"stairs": [{"x0": 8, "x1": 12}],
		},
		{
			"name": "三层",
			"rect": [2, 0, 22, 4],
			"y": 3.0,
			"from_y": 2.0,
			"stairs": [{"x0": 8, "x1": 12}],
		},
	]
	return document


func _has_error(errors: Array, needle: String) -> bool:
	for message in errors:
		if str(message).contains(needle):
			return true
	return false


func _validate(document: Dictionary) -> Array:
	return LayoutDocument.validate_document(document, _catalog())


func _walk(
	start: Vector2, input: Vector2, seconds: float, compiled: Dictionary
) -> Vector2:
	var pos := start
	var blockers: Array = compiled.get("blockers", [])
	var bounds: Rect2 = compiled.get("bounds", Rect2())
	var ticks := int(ceil(seconds / TICK))
	for i in range(ticks):
		pos = PlayerMotion.step(pos, input, TICK, blockers, bounds)
	return pos


func _remove_user_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# ---------------------------------------------------------------- flat compatibility


func test_flat_map_without_terrain_stays_flat() -> void:
	var document := _base_document()
	var errors := _validate(document)
	assert_eq(errors.size(), 0, "a flat map keeps validating: %s" % str(errors))
	var compiled := LayoutTerrain.compile(document)
	var platforms: Array = compiled.get("platforms", [])
	var connectors: Array = compiled.get("connectors", [])
	var water: Array = compiled.get("water", [])
	var blockers: Array = compiled.get("blockers", [])
	assert_eq(platforms.size(), 0, "no platforms")
	assert_eq(connectors.size(), 0, "no connectors")
	assert_eq(water.size(), 0, "no water")
	assert_eq(blockers.size(), 0, "no terrain blockers")
	assert_near(LayoutTerrain.height_at(compiled, Vector2(11, 11)), 0.0, 0.0001,
		"flat ground is 0")


# ---------------------------------------------------------------- three tiers


func test_three_tiers_walk_up_and_down() -> void:
	var document := _three_tier_document()
	var errors := _validate(document)
	assert_eq(errors.size(), 0, "three tiers validate: %s" % str(errors))
	var compiled := LayoutTerrain.compile(document)
	assert_near(LayoutTerrain.height_at(compiled, Vector2(11, 13)), 1.0, 0.001, "tier 1")
	assert_near(LayoutTerrain.height_at(compiled, Vector2(11, 7)), 2.0, 0.001, "tier 2")
	assert_near(LayoutTerrain.height_at(compiled, Vector2(11, 2)), 3.0, 0.001, "tier 3")

	var top := _walk(Vector2(11, 18.5), Vector2(0, -1), 4.5, compiled)
	assert_near(LayoutTerrain.height_at(compiled, top), 3.0, 0.001,
		"the player climbs to the top tier")
	assert_true(top.y < 1.0, "the player reaches the north side: %s" % str(top))
	assert_near(top.x, 11.0, 0.01, "stairs keep x aligned")

	var bottom := _walk(top, Vector2(0, 1), 4.5, compiled)
	assert_near(LayoutTerrain.height_at(compiled, bottom), 0.0, 0.001,
		"the player walks back down to the ground")
	assert_true(bottom.y > 19.0, "the player returns south: %s" % str(bottom))


func test_walls_block_edges_and_opening_sides() -> void:
	var document := _three_tier_document()
	var compiled := LayoutTerrain.compile(document)

	var outside := _walk(Vector2(5, 17.5), Vector2(0, -1), 1.0, compiled)
	assert_true(outside.y > 16.5, "the south wall stops the player: %s" % str(outside))
	assert_near(LayoutTerrain.height_at(compiled, outside), 0.0, 0.001,
		"the player cannot pop onto the terrace from outside")

	var beside := _walk(Vector2(5, 17.5), Vector2(1, 0), 1.0, compiled)
	assert_true(beside.x < 8.0, "the stair side wall stops the player: %s" % str(beside))
	assert_near(LayoutTerrain.height_at(compiled, beside), 0.0, 0.001,
		"walking beside the stairs stays on the ground")

	var west := _walk(Vector2(0.5, 12), Vector2(1, 0), 1.0, compiled)
	assert_true(west.x < 1.5, "the west wall stops the player: %s" % str(west))
	assert_near(LayoutTerrain.height_at(compiled, west), 0.0, 0.001,
		"the west wall keeps the player on the ground")


# ---------------------------------------------------------------- ramps / sides


func test_ramp_height_is_continuous() -> void:
	var document := _base_document()
	document["terraces"] = [{
		"name": "坡道台",
		"rect": [2, 4, 16, 12],
		"y": 1.5,
		"from_y": 0.0,
		"stairs": [{"side": "east", "z0": 6, "z1": 10, "kind": "ramp"}],
	}]
	var errors := _validate(document)
	assert_eq(errors.size(), 0, "the ramp draft validates: %s" % str(errors))
	var compiled := LayoutTerrain.compile(document)
	assert_near(LayoutTerrain.height_at(compiled, Vector2(16, 8)), 1.5, 0.001,
		"ramp meets the terrace at its height")
	assert_near(LayoutTerrain.height_at(compiled, Vector2(21, 8)), 0.0, 0.001,
		"ramp meets the ground at from_y")
	var d := 0.0
	while d <= 5.0:
		var expected := 1.5 - 1.5 * (d / 5.0)
		var actual := LayoutTerrain.height_at(compiled, Vector2(16 + d, 8))
		assert_near(actual, expected, 0.01, "ramp is linear at depth %.2f" % d)
		d += 0.25

	var top := _walk(Vector2(22, 8), Vector2(-1, 0), 4.0, compiled)
	assert_near(LayoutTerrain.height_at(compiled, top), 1.5, 0.001,
		"the player walks up the ramp")
	assert_true(top.x < 16.0, "the player reaches the terrace: %s" % str(top))


func test_four_side_openings_compile() -> void:
	var document := _base_document()
	document["width"] = 20
	document["depth"] = 20
	document["spawn"] = {"x": 11.0, "z": 12.0}
	document["terraces"] = [
		{"rect": [2, 2, 10, 10], "y": 1.0, "from_y": 0.0,
			"stairs": [{"side": "south", "x0": 4, "x1": 8}]},
		{"rect": [12, 2, 20, 10], "y": 1.0, "from_y": 0.0,
			"stairs": [{"side": "north", "x0": 14, "x1": 18}]},
		{"rect": [2, 14, 10, 22], "y": 1.0, "from_y": 0.0,
			"stairs": [{"side": "west", "z0": 16, "z1": 20}]},
		{"rect": [12, 14, 20, 22], "y": 1.0, "from_y": 0.0,
			"stairs": [{"side": "east", "z0": 16, "z1": 20}]},
	]
	var errors := _validate(document)
	assert_eq(errors.size(), 0, "all four directions validate: %s" % str(errors))
	var compiled := LayoutTerrain.compile(document)
	var connectors: Array = compiled["connectors"]
	assert_eq(connectors.size(), 4, "each terrace exposes one connector")
	var sides: Dictionary = {}
	for connector_value in connectors:
		var connector: Dictionary = connector_value
		sides[str(connector["side"])] = true
		var connector_rect: Rect2 = connector["rect"]
		assert_near(
			LayoutTerrain.height_at(compiled, connector_rect.get_center()), 1.0, 0.01,
			"connector top meets its terrace"
		)
	for side in ["north", "south", "east", "west"]:
		assert_true(sides.has(side), "the %s opening compiles" % side)


# ---------------------------------------------------------------- water


func test_water_blocks_and_rejects_placement() -> void:
	var document := _base_document()
	document["water"] = [{"name": "池塘", "rect": [4, 6, 12, 10]}]
	var errors := _validate(document)
	assert_eq(errors.size(), 0, "water validates: %s" % str(errors))
	var compiled := LayoutTerrain.compile(document)
	var water: Array = compiled["water"]
	assert_eq(water.size(), 1, "one water rectangle")
	var water_entry: Dictionary = water[0]
	assert_near(float(water_entry["y"]), 0.05, 0.001,
		"water sits slightly above its bottom")
	var blockers: Array = compiled["blockers"]
	assert_true(blockers.has(Rect2(4, 6, 8, 4)), "water is a blocker")

	var stopped := _walk(Vector2(8, 12), Vector2(0, -1), 1.0, compiled)
	assert_true(stopped.y > 10.3, "water stops the player: %s" % str(stopped))
	assert_near(LayoutTerrain.height_at(compiled, stopped), 0.0, 0.001,
		"the player never stands on water")

	var blocked_spawn := _base_document()
	blocked_spawn["water"] = [{"rect": [4, 6, 12, 10]}]
	blocked_spawn["spawn"] = {"x": 8.0, "z": 8.0}
	assert_true(_has_error(_validate(blocked_spawn), "water"),
		"a spawn inside water is rejected")

	var blocked_object := _base_document()
	blocked_object["water"] = [{"rect": [4, 6, 12, 10]}]
	blocked_object["objects"] = [{"asset": "rock", "x": 4, "z": 3, "turn": 0}]
	assert_true(_has_error(_validate(blocked_object), "overlaps water"),
		"an object footprint on water is rejected")


func test_water_bottom_must_be_continuous() -> void:
	var document := _base_document()
	document["terraces"] = [{"rect": [2, 4, 12, 6], "y": 1.0, "from_y": 0.0}]
	document["water"] = [{"rect": [4, 4, 8, 8]}]
	var errors := _validate(document)
	assert_true(_has_error(errors, "continuous height"),
		"water cannot cross a height change: %s" % str(errors))

	var shallow := _base_document()
	shallow["water"] = [{"rect": [4, 6, 12, 10], "y": 0.0}]
	assert_true(_has_error(_validate(shallow), "above the water bottom"),
		"an explicit water level must be above the bottom")


# ---------------------------------------------------------------- object / spawn height


func test_builder_places_objects_and_tiles_on_terrace() -> void:
	var document := _base_document()
	document["terraces"] = [{
		"name": "平台",
		"rect": [2, 4, 22, 16],
		"y": 1.0,
		"from_y": 0.0,
		"stairs": [{"x0": 8, "x1": 12}],
	}]
	document["tiles"] = [{"asset": "stone", "x": 10, "z": 6}]
	document["objects"] = [
		{"asset": "main_hall", "x": 2, "z": 4, "turn": 0, "label": ""},
		{"asset": "disciple", "x": 10, "z": 6, "turn": 0, "label": "弟子"},
	]
	var errors := _validate(document)
	assert_eq(errors.size(), 0, "terrace placement validates: %s" % str(errors))

	var root := Node3D.new()
	var built := LayoutBuilder.build(root, document, _catalog())
	assert_true(bool(built.get("ok", false)),
		"the builder accepts terrace placement: %s" % str(built.get("errors", [])))
	var terrain: Dictionary = built.get("terrain", {})
	assert_near(LayoutTerrain.height_at(terrain, Vector2(21, 13)), 1.0, 0.001,
		"objects query the terrace height")

	var npc := root.find_child("Npc_disciple", true, false)
	assert_true(npc is Node3D, "the disciple is built")
	if npc is Node3D:
		assert_near((npc as Node3D).position.y, 1.0, 0.001,
			"the npc sits on the terrace")
	var hall := root.find_child("Sprite_main_hall", true, false)
	assert_true(hall is Node3D, "the hall sprite is built")
	if hall is Node3D:
		assert_near((hall as Node3D).position.y, 1.02, 0.02,
			"the hall sprite sits on the terrace")
	var tiles := root.find_child("Tiles_stone", true, false)
	assert_true(tiles is MultiMeshInstance3D, "the painted tile is a MultiMesh")
	if tiles is MultiMeshInstance3D:
		var mesh_instance := tiles as MultiMeshInstance3D
		assert_eq(mesh_instance.multimesh.instance_count, 1,
			"the terrace painted tile is its own batch")
		assert_near(mesh_instance.position.y, 1.012, 0.02,
			"ground paint follows the terrace top")
	var anchors: Array = built.get("anchors", [])
	assert_eq(anchors.size(), 1, "one npc anchor")
	if not anchors.is_empty():
		var anchor: Dictionary = anchors[0]
		assert_near(float(anchor.get("height", 0.0)), 1.0, 0.001,
			"anchors carry their surface height")
	var built_blockers: Array = built.get("blockers", [])
	assert_true(built_blockers.size() > 2, "terrain walls join object blockers")
	root.free()


func test_layout_walk_uses_terrain_spawn_height() -> void:
	_remove_user_file(SPAWN_PATH)
	var document := _base_document()
	document["terraces"] = [{"rect": [2, 2, 22, 18], "y": 1.0, "from_y": 0.0}]
	document["spawn"] = {"x": 12.0, "z": 10.0}
	var errors := _validate(document)
	assert_eq(errors.size(), 0, "the spawn-on-terrace draft validates: %s" % str(errors))
	var saved := LayoutDocument.save_document(SPAWN_PATH, document, _catalog())
	assert_true(bool(saved.get("ok", false)),
		"the spawn draft saves: %s" % str(saved.get("errors", [])))

	var walk = LayoutWalk.new()
	walk.map_path = SPAWN_PATH
	walk.build()
	var player = walk.get("player")
	assert_true(player is Node3D, "the walk builds a player")
	if player is Node3D:
		assert_near((player as Node3D).position.y, 1.0, 0.001,
			"the trial walk spawns at the terrain height")
	assert_near(float(walk.get("player_height")), 1.0, 0.001,
		"the walk keeps the queried height")
	walk.free()
	_remove_user_file(SPAWN_PATH)


# ---------------------------------------------------------------- rejected drafts


func test_document_rejects_bad_terraces() -> void:
	var overlap := _base_document()
	overlap["terraces"] = [
		{"rect": [2, 2, 10, 10], "y": 1.0},
		{"rect": [8, 8, 16, 16], "y": 2.0},
	]
	assert_true(_has_error(_validate(overlap), "overlaps"),
		"terrace areas cannot overlap")

	var misaligned := _base_document()
	misaligned["terraces"] = [{"rect": [2, 2, 9, 10], "y": 1.0}]
	assert_true(_has_error(_validate(misaligned), "align to 2-unit cell edges"),
		"terrace rectangles align to cell edges")

	var off_step := _base_document()
	off_step["terraces"] = [{"rect": [2, 2, 10, 10], "y": 1.2}]
	assert_true(_has_error(_validate(off_step), "0.5 increments"),
		"terrace heights use half-unit increments")

	var too_high := _base_document()
	too_high["terraces"] = [{"rect": [2, 2, 10, 10], "y": 25.0, "from_y": 0.0}]
	assert_true(_has_error(_validate(too_high), "must not exceed 24"),
		"terrace heights are capped")

	var not_above := _base_document()
	not_above["terraces"] = [{"rect": [2, 2, 10, 10], "y": 1.0, "from_y": 1.0}]
	assert_true(_has_error(_validate(not_above), "greater than from_y"),
		"y must be above from_y")

	var low_side := _base_document()
	low_side["terraces"] = [{
		"rect": [2, 10, 22, 16], "y": 2.0, "from_y": 1.0,
		"stairs": [{"x0": 8, "x1": 12}],
	}]
	assert_true(_has_error(_validate(low_side), "low side ground"),
		"the low side of a connection must be at from_y")


func test_document_rejects_bad_connectors() -> void:
	var outside_edge := _base_document()
	outside_edge["terraces"] = [{
		"rect": [2, 10, 22, 16], "y": 1.0, "from_y": 0.0,
		"stairs": [{"x0": 8, "x1": 24}],
	}]
	assert_true(_has_error(_validate(outside_edge), "along the terrace edge"),
		"openings stay on the terrace edge")

	var misaligned := _base_document()
	misaligned["terraces"] = [{
		"rect": [2, 10, 22, 16], "y": 1.0, "from_y": 0.0,
		"stairs": [{"x0": 7, "x1": 12}],
	}]
	assert_true(_has_error(_validate(misaligned), "align to 2-unit cell edges"),
		"opening endpoints align to cell edges")

	var out_of_map := _base_document()
	out_of_map["terraces"] = [{
		"rect": [2, 12, 22, 20], "y": 1.0, "from_y": 0.0,
		"stairs": [{"x0": 8, "x1": 12}],
	}]
	assert_true(_has_error(_validate(out_of_map), "outside the map"),
		"connections must stay inside the map")

	var bad_side := _base_document()
	bad_side["terraces"] = [{
		"rect": [2, 10, 22, 16], "y": 1.0, "from_y": 0.0,
		"stairs": [{"side": "up", "x0": 8, "x1": 12}],
	}]
	assert_true(_has_error(_validate(bad_side), "side must be"),
		"connection sides are enumerated")

	var bad_kind := _base_document()
	bad_kind["terraces"] = [{
		"rect": [2, 10, 22, 16], "y": 1.0, "from_y": 0.0,
		"stairs": [{"kind": "slide", "x0": 8, "x1": 12}],
	}]
	assert_true(_has_error(_validate(bad_kind), "kind must be stairs or ramp"),
		"connection kinds are enumerated")


func test_document_rejects_objects_crossing_terrain() -> void:
	var spanned := _base_document()
	spanned["terraces"] = [{
		"rect": [2, 10, 22, 16], "y": 1.0, "from_y": 0.0,
		"stairs": [{"x0": 8, "x1": 12}],
	}]
	spanned["objects"] = [{"asset": "main_hall", "x": 0, "z": 4, "turn": 0}]
	assert_true(_has_error(_validate(spanned), "spans a height change"),
		"object footprints cannot cross a terrace edge")

	var covered := _base_document()
	covered["terraces"] = [{
		"rect": [2, 10, 22, 16], "y": 1.0, "from_y": 0.0,
		"stairs": [{"x0": 8, "x1": 12}],
	}]
	covered["objects"] = [{"asset": "rock", "x": 5, "z": 8, "turn": 0}]
	assert_true(_has_error(_validate(covered), "covers a stairs/ramp opening"),
		"objects cannot sit on a stairs/ramp opening")

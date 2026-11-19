extends "res://tests/test_case.gd"

const LayoutCatalog = preload("res://core/layouts/layout_catalog.gd")
const LayoutDocument = preload("res://core/layouts/layout_document.gd")
const LayoutBuilder = preload("res://shared/scenery/layouts/layout_builder.gd")
const PlayerMotion = preload("res://shared/gameplay/player_motion.gd")

const SAMPLE_PATH := "res://data/layouts/zixia_sect.json"
const FIXTURE_PATH := "res://tests/fixtures/layout_training_yard.json"
const FIXTURE_WIDTH := 12
const FIXTURE_DEPTH := 10
const ROUND_TRIP_PATH := "user://test_layout_round_trip.json"
const INVALID_PATH := "user://test_layout_invalid.json"
const FORBIDDEN_PATH := "res://features/layouts/should_not_write.json"


func _load_sample() -> Dictionary:
	return LayoutDocument.load_document(SAMPLE_PATH)


func _load_fixture() -> Dictionary:
	return LayoutDocument.load_document(FIXTURE_PATH)


func _has_error(errors: Array, needle: String) -> bool:
	for message in errors:
		if str(message).contains(needle):
			return true
	return false


func _find_object(document: Dictionary, asset: String) -> Dictionary:
	var objects_value: Variant = document.get("objects", [])
	if not (objects_value is Array):
		return {}
	for object_value in objects_value:
		if not (object_value is Dictionary):
			continue
		var object: Dictionary = object_value
		if str(object.get("asset", "")) == asset:
			return object
	return {}


func _walk(
	start: Vector2, input: Vector2, seconds: float, blockers: Array, bounds: Rect2
) -> Vector2:
	var pos := start
	var ticks := int(round(seconds / 0.05))
	for i in range(ticks):
		pos = PlayerMotion.step(pos, input, 0.05, blockers, bounds)
	return pos


func _remove_user_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# ---------------------------------------------------------------- catalog


func test_catalog_loads() -> void:
	var catalog := LayoutCatalog.load_catalog()
	assert_true(
		bool(catalog.get("ok", false)),
		"the layout catalog loads: %s" % str(catalog.get("errors", []))
	)
	assert_eq(int(catalog.get("version", 0)), 1, "catalog schema version is 1")
	var items: Dictionary = catalog.get("items", {})
	assert_true(items.size() >= 12, "the catalog exposes at least 12 items")
	for id in [
		"grass", "stone", "dirt", "sect_gate", "main_hall", "stone_wall",
		"wood_fence", "wood_pillar", "pine_tree", "stone_lantern", "rock",
		"disciple", "sect_exit", "training_plaque",
	]:
		assert_true(items.has(id), "catalog item '%s' exists" % id)
	var dummy := LayoutCatalog.item(catalog, "practice_dummy")
	assert_eq(str(dummy.get("kind", "")), "scene", "the wooden dummy is a scene item")
	assert_eq(
		str(dummy.get("scene", "")),
		"res://shared/scenery/layouts/prefabs/training_dummy.tscn",
		"the dummy points at the prefab scene"
	)
	assert_true(
		ResourceLoader.exists(str(dummy.get("scene", "")), "PackedScene"),
		"the dummy prefab loads as a PackedScene"
	)


func test_catalog_rejects_bad_items() -> void:
	var bad := {
		"version": 1,
		"items": [
			{
				"id": "Bad-Id",
				"name": "bad",
				"category": "test",
				"kind": "ground",
				"size": [1, 1],
				"texture": "res://assets/textures/tex_grass.png",
			},
			{
				"id": "dup",
				"name": "",
				"category": "test",
				"kind": "weird",
				"size": [0, 1],
			},
			{
				"id": "dup",
				"name": "dup",
				"category": "test",
				"kind": "box",
				"size": [0, 1],
				"texture": "res://assets/textures/not_a_real_texture.png",
			},
			{
				"id": "scene_dotdot",
				"name": "dotdot",
				"category": "test",
				"kind": "scene",
				"size": [1, 1],
				"scene": "res://shared/scenery/layouts/prefabs/../training_dummy.tscn",
			},
			{
				"id": "scene_outside",
				"name": "outside",
				"category": "test",
				"kind": "scene",
				"size": [1, 1],
				"scene": "res://features/layouts/nope.tscn",
			},
			{
				"id": "scene_not_packed",
				"name": "not packed",
				"category": "test",
				"kind": "scene",
				"size": [1, 1],
				"scene": "res://assets/scenery/town_wooden_dummy.png",
			},
		],
	}
	var errors := LayoutCatalog.validate_catalog(bad)
	assert_true(_has_error(errors, "invalid id"), "invalid ids are rejected")
	assert_true(_has_error(errors, "duplicate id"), "duplicate ids are rejected")
	assert_true(_has_error(errors, "invalid kind"), "invalid kinds are rejected")
	assert_true(
		_has_error(errors, "size values must be positive"),
		"non-positive sizes are rejected"
	)
	assert_true(
		_has_error(errors, "file not found"),
		"missing texture files are rejected"
	)
	assert_true(
		_has_error(errors, "without '..' segments"),
		"scene paths reject '..' segments"
	)
	assert_true(
		_has_error(errors, "scene path must be under"),
		"scene paths stay in the trusted asset/prefab roots"
	)
	assert_true(
		_has_error(errors, "not a loadable PackedScene"),
		"scene entries must point at PackedScene resources"
	)


# ---------------------------------------------------------------- document loading


func test_sample_map_loads() -> void:
	var loaded := _load_sample()
	assert_true(
		bool(loaded.get("ok", false)),
		"zixia_sect loads: %s" % str(loaded.get("errors", []))
	)
	# 真实地图允许用户自由编辑：这里只锁定可读/可校验与稳定 ID，
	# 尺寸、石板、装饰与路线的具体数量交给 fixture 覆盖。
	var document: Dictionary = loaded.get("document", {})
	assert_eq(str(document.get("id", "")), "zixia_sect", "map id is stable")


func test_rejects_out_of_bounds_object() -> void:
	var loaded := _load_fixture()
	var document: Dictionary = (loaded.get("document", {}) as Dictionary).duplicate(true)
	var objects: Array = document["objects"]
	objects.append({"asset": "sect_gate", "x": 11, "z": 3, "turn": 0, "label": ""})
	var errors := LayoutDocument.validate_document(document, loaded.get("catalog", {}))
	assert_true(
		_has_error(errors, "exceeds map 12x10"),
		"footprints crossing the map edge are rejected"
	)
	assert_true(
		_has_error(errors, "cell (11,3)"),
		"the error names the offending cell"
	)


func test_rejects_unknown_asset() -> void:
	var loaded := _load_fixture()
	var document: Dictionary = (loaded.get("document", {}) as Dictionary).duplicate(true)
	var objects: Array = document["objects"]
	objects.append({"asset": "no_such_item", "x": 0, "z": 0, "turn": 0})
	var errors := LayoutDocument.validate_document(document, loaded.get("catalog", {}))
	assert_true(_has_error(errors, "unknown asset id"), "unknown assets are rejected")
	assert_true(_has_error(errors, "no_such_item"), "the error names the asset")


func test_rejects_overlapping_objects() -> void:
	var loaded := _load_fixture()
	var document: Dictionary = (loaded.get("document", {}) as Dictionary).duplicate(true)
	var objects: Array = document["objects"]
	objects.append({"asset": "pine_tree", "x": 4, "z": 2, "turn": 0})
	var errors := LayoutDocument.validate_document(document, loaded.get("catalog", {}))
	assert_true(_has_error(errors, "overlaps"), "two objects cannot share a cell")
	assert_true(_has_error(errors, "pine_tree"), "the error names the object")


func test_rejects_blocked_spawn() -> void:
	var loaded := _load_fixture()
	var document: Dictionary = (loaded.get("document", {}) as Dictionary).duplicate(true)
	document["spawn"] = {"x": 12, "z": 5}
	var errors := LayoutDocument.validate_document(document, loaded.get("catalog", {}))
	assert_true(_has_error(errors, "spawn"), "the spawn is validated")
	assert_true(
		_has_error(errors, "blocked by 'main_hall'"),
		"a spawn inside the hall footprint is rejected"
	)


func test_rejects_non_integer_cells_and_turns() -> void:
	var loaded := _load_fixture()
	var document: Dictionary = (loaded.get("document", {}) as Dictionary).duplicate(true)
	var objects: Array = document["objects"]
	objects.append({"asset": "rock", "x": 3.5, "z": 5, "turn": 0})
	objects.append({"asset": "rock", "x": 0, "z": 6, "turn": 4})
	var errors := LayoutDocument.validate_document(document, loaded.get("catalog", {}))
	assert_true(
		_has_error(errors, "field 'x' must be an integer"),
		"fractional cell coordinates are rejected"
	)
	assert_true(_has_error(errors, "turn must be 0..3"), "turn is limited to 0..3")


func test_rotation_swaps_footprint() -> void:
	var catalog := LayoutCatalog.load_catalog()
	var item := LayoutCatalog.item(catalog, "wood_fence")
	assert_eq(
		LayoutDocument.footprint_cells(item, 3, 4, 0),
		Rect2i(3, 4, 2, 1),
		"turn 0 keeps the catalog size"
	)
	assert_eq(
		LayoutDocument.footprint_cells(item, 3, 4, 1),
		Rect2i(3, 4, 1, 2),
		"turn 1 swaps width and depth"
	)
	assert_eq(
		LayoutDocument.footprint_cells(item, 3, 4, 2),
		Rect2i(3, 4, 2, 1),
		"turn 2 restores the original footprint"
	)


# ---------------------------------------------------------------- saving


func test_save_round_trip_keeps_extra_metadata() -> void:
	_remove_user_file(ROUND_TRIP_PATH)
	var loaded := _load_fixture()
	var document: Dictionary = (loaded.get("document", {}) as Dictionary).duplicate(true)
	document["editor_note"] = "keep me"
	var saved := LayoutDocument.save_document(
		ROUND_TRIP_PATH, document, loaded.get("catalog", {})
	)
	assert_true(
		bool(saved.get("ok", false)),
		"saving a valid draft succeeds: %s" % str(saved.get("errors", []))
	)
	assert_true(FileAccess.file_exists(ROUND_TRIP_PATH), "the draft file exists")

	var reloaded := LayoutDocument.load_document(ROUND_TRIP_PATH)
	assert_true(
		bool(reloaded.get("ok", false)),
		"the saved draft reloads: %s" % str(reloaded.get("errors", []))
	)
	var saved_document: Dictionary = reloaded.get("document", {})
	assert_eq(str(saved_document.get("editor_note", "")), "keep me", "extra metadata stays")
	assert_eq(
		int(saved_document.get("width", 0)), FIXTURE_WIDTH,
		"dimensions survive the round trip"
	)

	var first_text := FileAccess.get_file_as_string(ROUND_TRIP_PATH)
	var resaved := LayoutDocument.save_document(
		ROUND_TRIP_PATH, saved_document, reloaded.get("catalog", {})
	)
	assert_true(
		bool(resaved.get("ok", false)),
		"re-saving over an existing draft succeeds: %s" % str(resaved.get("errors", []))
	)
	var second_text := FileAccess.get_file_as_string(ROUND_TRIP_PATH)
	assert_eq(first_text, second_text, "serialization is stable")
	_remove_user_file(ROUND_TRIP_PATH)


func test_save_rejects_invalid_draft_and_foreign_path() -> void:
	_remove_user_file(INVALID_PATH)
	var loaded := _load_fixture()
	var document: Dictionary = (loaded.get("document", {}) as Dictionary).duplicate(true)
	document["width"] = 3
	var saved := LayoutDocument.save_document(
		INVALID_PATH, document, loaded.get("catalog", {})
	)
	assert_true(not bool(saved.get("ok", false)), "an invalid draft is refused")
	assert_true(not FileAccess.file_exists(INVALID_PATH), "no file is written")

	var foreign := LayoutDocument.save_document(
		FORBIDDEN_PATH, loaded.get("document", {}), loaded.get("catalog", {})
	)
	assert_true(not bool(foreign.get("ok", false)), "paths outside the save roots are refused")
	assert_true(
		_has_error(foreign.get("errors", []), "path must be under"),
		"the save error explains the allowed roots"
	)
	assert_true(
		not FileAccess.file_exists(FORBIDDEN_PATH),
		"nothing is written outside res://data/layouts/ or user://"
	)


func test_save_refusal_keeps_existing_draft() -> void:
	_remove_user_file(INVALID_PATH)
	var loaded := _load_fixture()
	var catalog: Dictionary = loaded.get("catalog", {})
	var saved := LayoutDocument.save_document(
		INVALID_PATH, loaded.get("document", {}), catalog
	)
	assert_true(bool(saved.get("ok", false)), "the first draft saves")
	var before := FileAccess.get_file_as_string(INVALID_PATH)

	var invalid: Dictionary = (loaded.get("document", {}) as Dictionary).duplicate(true)
	invalid["width"] = 3
	var refused := LayoutDocument.save_document(INVALID_PATH, invalid, catalog)
	assert_true(not bool(refused.get("ok", false)), "the invalid draft is refused")
	assert_true(FileAccess.file_exists(INVALID_PATH), "the existing draft still exists")
	assert_eq(
		FileAccess.get_file_as_string(INVALID_PATH), before,
		"the existing draft is left untouched"
	)

	var reloaded := LayoutDocument.load_document(INVALID_PATH)
	assert_true(
		bool(reloaded.get("ok", false)),
		"the preserved draft is still valid: %s" % str(reloaded.get("errors", []))
	)
	var preserved: Dictionary = reloaded.get("document", {})
	assert_eq(
		int(preserved.get("width", 0)), FIXTURE_WIDTH,
		"the preserved draft keeps its dimensions"
	)
	_remove_user_file(INVALID_PATH)


# ---------------------------------------------------------------- runtime building


func test_builder_creates_blockers_and_anchors() -> void:
	var loaded := _load_fixture()
	var catalog: Dictionary = loaded.get("catalog", {})
	var document: Dictionary = loaded.get("document", {})
	assert_eq(int(document.get("width", 0)), FIXTURE_WIDTH, "fixture width")
	assert_eq(int(document.get("depth", 0)), FIXTURE_DEPTH, "fixture depth")
	var root := Node3D.new()
	var built := LayoutBuilder.build(root, document, catalog)
	assert_true(
		bool(built.get("ok", false)),
		"the builder accepts the fixture: %s" % str(built.get("errors", []))
	)
	var expected_blockers := 0
	var objects: Array = document.get("objects", [])
	for object_value in objects:
		var object: Dictionary = object_value
		var item := LayoutCatalog.item(catalog, str(object.get("asset", "")))
		if bool(item.get("blocking", false)):
			expected_blockers += 1
	var blockers: Array = built.get("blockers", [])
	assert_eq(blockers.size(), expected_blockers, "every blocking object adds one blocker")
	assert_true(
		blockers.has(Rect2(2.0, 2.0, 2.0, 2.0)),
		"the prefab footprint blocks movement"
	)

	var anchors: Array = built.get("anchors", [])
	assert_eq(anchors.size(), 2, "the disciple and the exit expose anchors")
	var kinds: Dictionary = {}
	for anchor_value in anchors:
		var anchor: Dictionary = anchor_value
		kinds[str(anchor.get("kind", ""))] = true
	assert_true(kinds.has("npc"), "an npc anchor is returned")
	assert_true(kinds.has("exit"), "an exit anchor is returned")
	assert_true(
		root.find_child("Npc_disciple", true, false) != null,
		"the disciple character node is built"
	)
	assert_true(
		root.find_child("Tiles_stone", true, false) is MultiMeshInstance3D,
		"ground tiles are merged into a MultiMesh"
	)
	var dummy := root.find_child("Scene_practice_dummy_1_1", true, false)
	assert_true(dummy is Node3D, "the wooden dummy prefab is instantiated")
	if dummy is Node3D:
		assert_eq(
			(dummy as Node3D).position, Vector3(3.0, 0.0, 3.0),
			"the prefab sits at the footprint center with Y=0 as the ground"
		)
		assert_near(
			(dummy as Node3D).rotation_degrees.y, 90.0, 0.001,
			"turn rotates the prefab"
		)
	root.free()


func test_builder_rejects_invalid_scene() -> void:
	var loaded := _load_fixture()
	var catalog: Dictionary = (loaded.get("catalog", {}) as Dictionary).duplicate(true)
	var items: Dictionary = catalog["items"]
	var dummy: Dictionary = items["practice_dummy"]
	dummy["scene"] = "res://assets/scenery/town_wooden_dummy.png"
	var root := Node3D.new()
	var built := LayoutBuilder.build(root, loaded.get("document", {}), catalog)
	assert_true(not bool(built.get("ok", false)), "a non-PackedScene asset fails the build")
	assert_true(built.get("node", null) == null, "no partial layout root is returned")
	assert_true(
		_has_error(built.get("errors", []), "not a loadable PackedScene"),
		"the build error names the bad scene"
	)
	assert_eq(root.get_child_count(), 0, "the failed build leaves no nodes behind")
	root.free()


func test_walk_from_spawn_into_courtyard() -> void:
	var loaded := _load_fixture()
	var root := Node3D.new()
	var built := LayoutBuilder.build(root, loaded.get("document", {}), loaded.get("catalog", {}))
	if not bool(built.get("ok", false)):
		assert_true(false, "builder failed: %s" % str(built.get("errors", [])))
		root.free()
		return
	var spawn: Vector2 = built.get("spawn", Vector2.ZERO)
	var players_start := _walk(
		spawn, Vector2(0.0, -1.0), 7.0, built.get("blockers", []), built.get("bounds", Rect2())
	)
	assert_true(players_start.y < 10.0, "the player walks north through the open gate")
	assert_true(players_start.y > 8.0, "the hall stops the player at the north end")
	assert_near(players_start.x, spawn.x, 0.001, "walking straight north keeps x aligned")
	root.free()


func test_blocker_stops_player() -> void:
	var loaded := _load_fixture()
	var root := Node3D.new()
	var built := LayoutBuilder.build(root, loaded.get("document", {}), loaded.get("catalog", {}))
	if not bool(built.get("ok", false)):
		assert_true(false, "builder failed: %s" % str(built.get("errors", [])))
		root.free()
		return
	var stopped := _walk(
		Vector2(18.0, 17.0),
		Vector2(1.0, 0.0),
		1.0,
		built.get("blockers", []),
		built.get("bounds", Rect2())
	)
	assert_true(stopped.x < 19.7, "the pine tree blocks eastward movement")
	assert_true(stopped.x > 18.0, "the player still moves until the blocker")
	root.free()


func test_playtest_scenes_load() -> void:
	var scene := load("res://features/layouts/layout_walk.tscn")
	assert_true(scene is PackedScene, "the layout walk scene loads")
	if scene is PackedScene:
		var instance = (scene as PackedScene).instantiate()
		assert_true(instance != null, "the layout walk scene instantiates")
		if instance != null:
			assert_eq(
				str(instance.get("map_path")),
				"res://data/layouts/zixia_sect.json",
				"the direct scene opens the sample map"
			)
			instance.free()
	var tool_scene := load("res://tools/layout_playtest.tscn")
	assert_true(tool_scene is PackedScene, "the tool playtest scene loads")
	if tool_scene is PackedScene:
		var tool_instance = (tool_scene as PackedScene).instantiate()
		assert_true(tool_instance != null, "the tool playtest scene instantiates")
		if tool_instance != null:
			var walk = tool_instance.get_node_or_null("LayoutWalk")
			assert_true(walk != null, "the tool scene wraps the runtime scene")
			if walk != null:
				assert_eq(
					str(walk.get("map_path")),
					"user://map_editor_playtest.json",
					"the tool scene reads the editor playtest draft"
				)
			tool_instance.free()

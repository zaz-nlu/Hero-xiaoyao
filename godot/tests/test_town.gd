extends "res://tests/test_case.gd"

const Texgen = preload("res://world/texgen.gd")
const TownData = preload("res://world/town_data.gd")

const TOWN_PATH := "res://data/town.json"
const CAMERA_OFFSET := Vector3(0.0, 16.7, 37.5)


func _new_town():
	return load("res://world/town.gd").new()


func _count_nodes(root: Node, native_class: String) -> int:
	var count: int = 0
	if root.is_class(native_class):
		count += 1
	for child in root.get_children():
		count += _count_nodes(child, native_class)
	return count


func _distinct_colors(img: Image) -> int:
	var seen: Dictionary = {}
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			seen[img.get_pixel(x, y).to_rgba32()] = true
	return seen.size()


func test_texgen_sizes() -> void:
	var textures: Dictionary = {
		"grass": Texgen.grass(),
		"stone_street": Texgen.stone_street(),
		"step_stone": Texgen.step_stone(),
		"wood_planks": Texgen.wood_planks(),
		"plaster": Texgen.plaster(),
		"roof_tiles": Texgen.roof_tiles(),
		"water": Texgen.water(),
		"window": Texgen.window(),
		"awning_stripes": Texgen.awning_stripes(),
	}
	for key in textures.keys():
		var img: Image = textures[key]
		assert_eq(img.get_width(), 16, "%s width" % key)
		assert_eq(img.get_height(), 16, "%s height" % key)
	var door_img: Image = Texgen.door()
	assert_eq(door_img.get_width(), 16, "door width")
	assert_eq(door_img.get_height(), 32, "door height")
	var tree_img: Image = Texgen.tree_sprite()
	assert_eq(tree_img.get_width(), 48, "tree width")
	assert_eq(tree_img.get_height(), 64, "tree height")
	var shadow_img: Image = Texgen.blob_shadow()
	assert_eq(shadow_img.get_width(), 16, "shadow width")
	assert_eq(shadow_img.get_height(), 8, "shadow height")


func test_texgen_deterministic() -> void:
	assert_true(
		Texgen.grass().get_data() == Texgen.grass().get_data(), "grass is deterministic"
	)
	assert_true(
		Texgen.stone_street().get_data() == Texgen.stone_street().get_data(),
		"stone street is deterministic"
	)
	assert_true(
		Texgen.roof_tiles().get_data() == Texgen.roof_tiles().get_data(),
		"roof tiles are deterministic"
	)
	assert_true(
		Texgen.tree_sprite().get_data() == Texgen.tree_sprite().get_data(),
		"tree sprite is deterministic"
	)
	assert_true(
		Texgen.mountain_layer(64, 24, 5, Color.BLUE).get_data()
		== Texgen.mountain_layer(64, 24, 5, Color.BLUE).get_data(),
		"mountain layer is deterministic"
	)


func test_texgen_not_flat() -> void:
	var textures: Dictionary = {
		"grass": Texgen.grass(),
		"stone_street": Texgen.stone_street(),
		"step_stone": Texgen.step_stone(),
		"wood_planks": Texgen.wood_planks(),
		"plaster": Texgen.plaster(),
		"roof_tiles": Texgen.roof_tiles(),
		"water": Texgen.water(),
		"window": Texgen.window(),
		"awning_stripes": Texgen.awning_stripes(),
	}
	for key in textures.keys():
		var img: Image = textures[key]
		assert_true(_distinct_colors(img) >= 4, "%s has at least four colours" % key)


func test_tree_sprite_has_transparent_corners() -> void:
	var img: Image = Texgen.tree_sprite()
	assert_eq(img.get_pixel(0, 0).a, 0.0, "top-left is transparent")
	assert_eq(img.get_pixel(47, 0).a, 0.0, "top-right is transparent")
	assert_eq(img.get_pixel(0, 63).a, 0.0, "bottom-left is transparent")
	assert_eq(img.get_pixel(47, 63).a, 0.0, "bottom-right is transparent")
	var trunk_opaque := false
	for y in range(48, 64):
		if img.get_pixel(24, y).a > 0.0:
			trunk_opaque = true
	assert_true(trunk_opaque, "centre column has opaque trunk pixels near the bottom")


func test_mountain_layer_size_and_transparency() -> void:
	var img: Image = Texgen.mountain_layer(128, 32, 1, Color.BLUE)
	assert_eq(img.get_width(), 128, "mountain layer width")
	assert_eq(img.get_height(), 32, "mountain layer height")
	assert_eq(img.get_pixel(0, 0).a, 0.0, "top-left is transparent")
	var bottom_opaque := true
	for x in range(128):
		if img.get_pixel(x, 31).a <= 0.0:
			bottom_opaque = false
	assert_true(bottom_opaque, "bottom row is fully opaque")


func test_town_data_loads_clean() -> void:
	var loaded: Dictionary = TownData.load_town(TOWN_PATH)
	var errors: Array = loaded["errors"]
	assert_eq(errors.size(), 0, str(errors))
	var town_data: Dictionary = loaded["data"]
	var buildings: Array = town_data.get("buildings", [])
	var npcs: Array = town_data.get("npcs", [])
	assert_eq(buildings.size(), 10, "ten buildings")
	assert_eq(npcs.size(), 21, "twenty-one npcs")


func test_town_data_detects_overlap() -> void:
	var town_data: Dictionary = {
		"bounds": {"x0": -20.0, "x1": 20.0, "z0": -20.0, "z1": 20.0},
		"buildings": [
			{
				"id": "a",
				"kind": "house",
				"x0": -4.0,
				"x1": 0.0,
				"z_front": 0.0,
				"depth": 5.0,
			},
			{
				"id": "b",
				"kind": "shop",
				"x0": -2.0,
				"x1": 2.0,
				"z_front": -1.0,
				"depth": 5.0,
			},
		],
		"props": [],
		"npcs": [],
	}
	var errors: Array = TownData.validate(town_data)
	assert_true(errors.size() > 0, "overlapping buildings are reported")


func test_town_data_detects_npc_in_building() -> void:
	var town_data: Dictionary = {
		"bounds": {"x0": -20.0, "x1": 20.0, "z0": -20.0, "z1": 20.0},
		"buildings": [
			{
				"id": "a",
				"kind": "house",
				"x0": 0.0,
				"x1": 5.0,
				"z_front": 0.0,
				"depth": 5.0,
			},
		],
		"props": [],
		"npcs": [
			{"id": "inside", "sprite": "vendor", "x": 2.5, "z": -2.5, "facing": "down"},
		],
	}
	var errors: Array = TownData.validate(town_data)
	assert_true(errors.size() > 0, "an npc inside a building is reported")


func test_town_data_detects_unknown_kind() -> void:
	var town_data: Dictionary = {
		"bounds": {"x0": -20.0, "x1": 20.0, "z0": -20.0, "z1": 20.0},
		"buildings": [
			{
				"id": "castle",
				"kind": "castle",
				"x0": 0.0,
				"x1": 5.0,
				"z_front": 0.0,
				"depth": 5.0,
			},
		],
		"props": [],
		"npcs": [],
	}
	var errors: Array = TownData.validate(town_data)
	assert_true(errors.size() > 0, "an unknown building kind is reported")


func test_footprints_cover_buildings() -> void:
	var loaded: Dictionary = TownData.load_town(TOWN_PATH)
	var town_data: Dictionary = loaded["data"]
	var footprints: Array = TownData.footprints(town_data)
	assert_true(footprints.size() >= 7, "footprints include six buildings and a stall")
	var buildings: Array = town_data.get("buildings", [])
	for building_value in buildings:
		var building: Dictionary = building_value
		var expected := Rect2(
			float(building["x0"]),
			float(building["z_front"]) - float(building["depth"]),
			float(building["x1"]) - float(building["x0"]),
			float(building["depth"])
		)
		var found := false
		for footprint_value in footprints:
			var footprint: Rect2 = footprint_value
			if footprint.position.is_equal_approx(expected.position) \
					and footprint.size.is_equal_approx(expected.size):
				found = true
				break
		assert_true(found, "footprint covers building %s" % str(building.get("id", "")))


func test_town_builds() -> void:
	var town = _new_town()
	town.build()
	assert_eq(town.npc_nodes.size(), 21, "twenty-one npc nodes")
	assert_true(town.camera != null, "camera exists")
	if town.camera != null:
		assert_near(town.camera.fov, 28.0, 0.01, "camera fov is 28")
	assert_true(town.sun != null, "sun exists")
	if town.sun != null:
		assert_true(town.sun.shadow_enabled, "sun casts shadows")
	var mesh_count := _count_nodes(town, "MeshInstance3D")
	assert_true(mesh_count > 40, "mesh count %d is above 40" % mesh_count)
	var sprite_count := _count_nodes(town, "Sprite3D")
	assert_true(sprite_count >= 40, "sprite count %d is at least 40" % sprite_count)
	var label_count := _count_nodes(town, "Label3D")
	assert_true(label_count >= 1, "label count %d is at least 1" % label_count)
	var light_count := _count_nodes(town, "OmniLight3D")
	assert_true(light_count >= 5, "omni light count %d is at least 5" % light_count)
	town.free()


func test_build_is_idempotent() -> void:
	var town = _new_town()
	town.build()
	var before := _count_nodes(town, "MeshInstance3D")
	town.build()
	var after := _count_nodes(town, "MeshInstance3D")
	assert_eq(after, before, "a second build does not add meshes")
	town.free()


func test_water_material_scrolls() -> void:
	var town = _new_town()
	town.build()
	var water: Variant = town.find_child("WaterSurface", true, false)
	assert_true(water != null, "water surface exists")
	if water != null:
		var material = water.material_override
		assert_true(material is StandardMaterial3D, "water uses a standard material")
		if material is StandardMaterial3D:
			var before: float = material.uv1_offset.x
			town._process(1.0)
			assert_true(
				absf(material.uv1_offset.x - before) > 0.00001,
				"water uv offset scrolls"
			)
	town.free()


func test_camera_follows_target() -> void:
	var town = _new_town()
	town.build()
	var target := Node3D.new()
	target.position = Vector3(10.0, 0.0, 5.0)
	town.follow_target = target
	for i in range(40):
		town.update_camera(0.1)
	var expected := Vector3(10.0, 0.0, 5.0) + CAMERA_OFFSET
	assert_true(
		town.camera.position.distance_to(expected) < 0.5,
		"camera settles above the follow target"
	)
	target.free()
	town.free()

extends "res://tests/test_case.gd"

const AiAssets = preload("res://world/ai_assets.gd")
const TownData = preload("res://world/town_data.gd")

const TOWN_PATH := "res://data/town.json"
const DECOR_KINDS: Array[String] = [
	"shrub", "grass_tuft", "peony", "chrysanthemum", "bamboo", "rocks"
]

const ASSET_FILES: Array[String] = [
	"facade_tavern.png",
	"facade_general_store.png",
	"facade_blacksmith.png",
	"facade_residence.png",
	"facade_baozi_stall.png",
	"prop_barrel.png",
	"prop_crates.png",
	"prop_jars.png",
	"prop_baskets.png",
	"prop_stone_lantern.png",
	"prop_lantern_post.png",
	"prop_bench.png",
	"prop_stall.png",
	"prop_willow.png",
	"prop_boat.png",
	"prop_tavern_sign.png",
	"prop_shrub.png",
	"prop_grass.png",
	"prop_peony.png",
	"prop_chrysanthemum.png",
	"prop_bamboo.png",
	"prop_rocks.png",
	"tex_cobblestone.png",
	"tex_gray_roof_tiles.png",
	"tex_aged_plaster.png",
	"tex_dark_wood.png",
	"tex_grass.png",
	"tex_water.png",
	"tex_stone_wall.png",
	"bg_mountains.png",
]


func test_load_texture_every_asset() -> void:
	for file in ASSET_FILES:
		var texture := AiAssets.load_texture(file)
		assert_true(texture != null, "%s loads" % file)
		if texture != null:
			assert_true(texture.get_width() > 0, "%s has width" % file)
			assert_true(texture.get_height() > 0, "%s has height" % file)


func test_load_texture_missing_returns_null() -> void:
	assert_true(
		AiAssets.load_texture("does_not_exist_12345.png") == null,
		"a missing asset returns null"
	)


func test_load_texture_caches() -> void:
	var first := AiAssets.load_texture("prop_barrel.png")
	var second := AiAssets.load_texture("prop_barrel.png")
	assert_true(first == second, "textures are cached")


func test_make_sprite_bottom_and_pixel_size() -> void:
	var sprite := AiAssets.make_sprite(
		"prop_barrel.png", 1.2, Vector3(3.0, 0.0, -2.0), "TestBarrel"
	)
	assert_true(sprite != null, "sprite is created")
	if sprite == null:
		return
	var texture := AiAssets.load_texture("prop_barrel.png")
	var image_height := float(texture.get_height())
	assert_eq(str(sprite.name), "TestBarrel", "sprite keeps its name")
	assert_near(
		sprite.pixel_size,
		1.2 / image_height,
		0.000001,
		"pixel size matches world height"
	)
	assert_true(
		sprite.position.is_equal_approx(Vector3(3.0, 0.0, -2.0)), "sprite sits at pos"
	)
	assert_true(sprite.centered, "sprite is centered")
	assert_near(
		sprite.offset.y,
		image_height * 0.5,
		0.001,
		"offset is half the image height in pixels"
	)
	# With centered = true and offset.y = image_height / 2, the bottom edge of the
	# sprite lands exactly on the node position.
	var bottom_y: float = sprite.position.y + (sprite.offset.y - image_height * 0.5) * sprite.pixel_size
	assert_near(bottom_y, 0.0, 0.001, "sprite bottom edge sits on the ground")
	assert_near(
		image_height * sprite.pixel_size, 1.2, 0.01, "sprite world height"
	)
	assert_near(
		float(texture.get_width()) * sprite.pixel_size,
		1.2 * float(texture.get_width()) / image_height,
		0.01,
		"sprite world width keeps the image aspect"
	)
	sprite.free()


func test_make_wall_quad_bottom_and_aspect() -> void:
	var facade := AiAssets.make_wall_quad(
		"facade_tavern.png", 10.0, Vector3(1.0, 0.0, -3.0), "TestFacade"
	)
	assert_true(facade != null, "wall quad is created")
	if facade == null:
		return
	var texture := AiAssets.load_texture("facade_tavern.png")
	var expected_height: float = 10.0 * float(texture.get_height()) / float(texture.get_width())
	var quad := facade.mesh as QuadMesh
	assert_true(quad != null, "wall quad uses a QuadMesh")
	if quad != null:
		assert_near(quad.size.x, 10.0, 0.001, "wall width")
		assert_near(quad.size.y, expected_height, 0.001, "wall height keeps the image aspect")
		assert_near(
			facade.position.y - quad.size.y * 0.5, 0.0, 0.001, "wall bottom sits on the ground"
		)
	assert_near(facade.position.z, -3.0, 0.001, "wall sits at z_front")
	facade.free()


func test_town_builds_facades_and_boats() -> void:
	var town = load("res://world/town.gd").new()
	town.build()
	var facades: Array = town.find_children("Facade_*", "MeshInstance3D", true, false)
	assert_eq(facades.size(), 6, "six building facades")
	var boats: Array = town.find_children("Boat*", "Sprite3D", true, false)
	assert_eq(boats.size(), 3, "three boats on the river")
	for boat_value in boats:
		var boat := boat_value as Sprite3D
		if boat == null:
			continue
		assert_true(
			boat.position.z >= 9.0 and boat.position.z <= 12.0,
			"boat z %.2f is inside the river" % boat.position.z
		)
		assert_near(boat.position.y, -0.15, 0.001, "boat bottom sits just below the water")
	town.free()


func test_town_builds_tavern_sign_and_mountain_backdrop() -> void:
	var town = load("res://world/town.gd").new()
	town.build()
	var signs: Array = town.find_children("TavernSign", "Sprite3D", true, false)
	assert_eq(signs.size(), 1, "the tavern sign is created")
	if not signs.is_empty():
		var sign := signs[0] as Sprite3D
		if sign != null:
			assert_near(sign.position.x, 8.7, 0.001, "tavern sign hangs right of the door")
			assert_near(sign.position.y, 1.5, 0.001, "tavern sign bottom edge height")
			assert_near(sign.position.z, -2.5, 0.001, "tavern sign sits in front of the facade")
	var backdrops: Array = town.find_children("MountainBackdrop", "MeshInstance3D", true, false)
	assert_eq(backdrops.size(), 1, "the AI mountain backdrop is used")
	if not backdrops.is_empty():
		var backdrop := backdrops[0] as MeshInstance3D
		if backdrop != null:
			var quad := backdrop.mesh as QuadMesh
			assert_true(quad != null, "mountain backdrop uses a QuadMesh")
			if quad != null:
				assert_near(quad.size.x, 240.0, 0.001, "mountain backdrop width")
				assert_near(quad.size.y, 60.0, 0.001, "mountain backdrop height")
			assert_true(
				backdrop.position.is_equal_approx(Vector3(12.0, 19.0, -29.6)),
				"mountain backdrop sits just beyond the town edge"
			)
	town.free()


func test_town_builds_building_volumes() -> void:
	var town = load("res://world/town.gd").new()
	town.build()
	var volumes: Array = town.find_children("Volume_*", "Node3D", true, false)
	assert_eq(volumes.size(), 6, "six building volumes")
	var loaded: Dictionary = TownData.load_town(TOWN_PATH)
	var buildings: Array = loaded["data"].get("buildings", [])
	for building_value in buildings:
		var building: Dictionary = building_value
		var id := str(building.get("id", ""))
		var volume: Node = town.find_child("Volume_%s" % id, true, false)
		assert_true(volume != null, "Volume_%s exists" % id)
		if volume == null:
			continue
		var parts: Array = volume.find_children("*", "MeshInstance3D", false, false)
		assert_true(
			parts.size() >= 5,
			"Volume_%s has at least 5 parts (%d)" % [id, parts.size()]
		)
		var facade_node: Node = town.find_child("Facade_%s" % id, true, false)
		assert_true(facade_node != null, "Facade_%s exists" % id)
		if facade_node == null:
			continue
		var facade_quad := (facade_node as MeshInstance3D).mesh as QuadMesh
		assert_true(facade_quad != null, "Facade_%s uses a QuadMesh" % id)
		if facade_quad == null:
			continue
		var max_y := -INF
		var z_min := INF
		var z_max := -INF
		for part_value in parts:
			var part := part_value as MeshInstance3D
			if part == null or part.mesh == null:
				continue
			var aabb: AABB = part.transform * part.mesh.get_aabb()
			max_y = maxf(max_y, aabb.end.y)
			z_min = minf(z_min, aabb.position.z)
			z_max = maxf(z_max, aabb.end.z)
		assert_near(max_y, facade_quad.size.y, 0.3, "Volume_%s ridge reaches the facade top" % id)
		var z_front := float(building["z_front"])
		var depth := float(building["depth"])
		assert_near(
			z_min, z_front - depth, 0.2, "Volume_%s reaches the back of the house" % id
		)
		assert_near(z_max, z_front, 0.2, "Volume_%s stops at the facade plane" % id)
	town.free()


func test_decor_props_avoid_river_bridge_and_landmarks() -> void:
	var loaded: Dictionary = TownData.load_town(TOWN_PATH)
	var town_data: Dictionary = loaded["data"]
	var props: Array = town_data.get("props", [])
	var decor: Array = []
	var landmarks: Array = []
	for prop_value in props:
		var prop: Dictionary = prop_value
		var kind := str(prop.get("kind", ""))
		if DECOR_KINDS.has(kind):
			decor.append(prop)
		elif kind == "tree" or kind == "boat":
			landmarks.append(prop)
	assert_true(decor.size() >= 25, "at least 25 decor props (%d)" % decor.size())
	for prop_value in decor:
		var prop: Dictionary = prop_value
		var x := float(prop["x"])
		var z := float(prop["z"])
		assert_true(
			z < 9.0 or z > 12.0,
			"decor at (%.1f, %.1f) stays off the river" % [x, z]
		)
		assert_true(
			x < -14.0 or x > -10.0 or z < 4.0 or z > 16.0,
			"decor at (%.1f, %.1f) stays off the bridge" % [x, z]
		)
		for landmark_value in landmarks:
			var landmark: Dictionary = landmark_value
			var lx := float(landmark["x"])
			var lz := float(landmark["z"])
			var dist := sqrt((x - lx) * (x - lx) + (z - lz) * (z - lz))
			assert_true(
				dist >= 1.0,
				"decor at (%.1f, %.1f) clears %s at (%.1f, %.1f)" % [
					x, z, str(landmark.get("kind", "")), lx, lz
				]
			)

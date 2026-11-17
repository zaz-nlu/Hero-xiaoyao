extends "res://tests/test_case.gd"

const AiAssets = preload("res://world/ai_assets.gd")

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
	"tex_cobblestone.png",
	"tex_gray_roof_tiles.png",
	"tex_aged_plaster.png",
	"tex_dark_wood.png",
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

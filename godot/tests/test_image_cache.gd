extends "res://tests/test_case.gd"

const ImageCache = preload("res://ui/image_cache.gd")

const PORTRAIT_PATH := "res://assets/portraits/ren_xiaoyao.png"
const MISSING_PATH := "res://assets/portraits/not_a_real_portrait.png"


func test_loads_portrait() -> void:
	var portrait: Texture2D = ImageCache.texture(PORTRAIT_PATH)
	assert_true(portrait != null, "the portrait texture loads")
	if portrait != null:
		assert_true(portrait.get_width() > 100, "the portrait is wider than 100 pixels")


func test_same_instance_cached() -> void:
	var first: Texture2D = ImageCache.texture(PORTRAIT_PATH)
	var second: Texture2D = ImageCache.texture(PORTRAIT_PATH)
	assert_true(first != null, "the first lookup loads")
	assert_true(second != null, "the second lookup succeeds")
	assert_true(is_same(first, second), "the cache returns the same texture instance")


func test_missing_returns_null() -> void:
	var missing: Texture2D = ImageCache.texture(MISSING_PATH)
	assert_true(missing == null, "a missing portrait returns null")

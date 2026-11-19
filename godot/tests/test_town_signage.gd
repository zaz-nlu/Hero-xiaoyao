extends "res://tests/test_case.gd"

# 小镇招牌字体与头顶任务标记徽章。

const GameState = preload("res://core/game_state.gd")
const Quests = preload("res://core/quests.gd")
const Progression = preload("res://core/progression.gd")
const TownFonts = preload("res://shared/scenery/town/town_fonts.gd")
const TownMarkerIcons = preload("res://shared/scenery/town/town_marker_icons.gd")

const BRUSH_PATH := "res://assets/fonts/MaShanZheng-Regular.ttf"


func _reset() -> void:
	GameState.reset()
	Quests.reload()
	Progression.reload_items()


func test_brush_font_loads() -> void:
	assert_true(FileAccess.file_exists(BRUSH_PATH), "the brush font file is readable")
	var font := TownFonts.brush()
	assert_true(font != null, "the brush font loads without the import pipeline")
	assert_true(TownFonts.brush() == font, "the brush font is cached")


func test_marker_text_maps_to_badge_icons() -> void:
	var available := TownMarkerIcons.texture_for("!")
	var ready := TownMarkerIcons.texture_for("?")
	var active := TownMarkerIcons.texture_for("…")
	assert_true(available != null, "'!' has an available badge")
	assert_true(ready != null, "'?' has a ready badge")
	assert_true(active != null, "'…' has an active badge")
	if available != null and ready != null and active != null:
		assert_eq(available.get_size(), Vector2(128.0, 128.0), "badges are 128x128")
		assert_true(available != ready, "each marker text uses its own texture")
		assert_true(ready != active, "each marker text uses its own texture")
	assert_eq(TownMarkerIcons.texture_for(""), null, "no marker text means no icon")
	assert_eq(TownMarkerIcons.texture_for("x"), null, "unknown marker text means no icon")


func test_town_marker_is_a_sprite_badge() -> void:
	_reset()
	var town: Variant = load("res://features/town/town.gd").new()
	town.build()
	var node: Node = town.find_child("QuestMarker_bun_vendor", true, false)
	assert_true(node is Sprite3D, "the quest marker is a sprite badge")
	if node is Sprite3D:
		var sprite: Sprite3D = node
		assert_eq(str(sprite.get_meta("marker_text", "")), "!", "the badge offers the quest")
		assert_true(sprite.visible, "the available badge is visible")
		assert_true(sprite.texture != null, "the available badge has its icon texture")
		assert_eq(
			sprite.billboard,
			BaseMaterial3D.BILLBOARD_ENABLED,
			"the badge faces the camera"
		)
		assert_eq(
			sprite.texture_filter,
			BaseMaterial3D.TEXTURE_FILTER_LINEAR,
			"the badge uses linear filtering"
		)
	town.free()
	_reset()

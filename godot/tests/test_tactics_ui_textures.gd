extends "res://tests/test_case.gd"

# 战旗 UI 素材：layout.json 完整性、九宫格边距、缺素材回退，
# 以及 1152×648 下单位卡 / 技能栏 / 行动条不越界、不互相压住。

const GameState = preload("res://core/game_state.gd")
const UI = preload("res://features/tactics/tactics_ui_style.gd")
const Metrics = preload("res://features/tactics/tactics_panel_metrics.gd")

const LAYOUT_PATH := "res://assets/ui/tactics/layout.json"
const MISSING_DIR := "res://assets/ui/__missing_tactics__/"
const REQUIRED := [
	"turn_card.png", "turn_card_active.png",
	"skill_button.png", "skill_button_selected.png", "skill_button_disabled.png",
	"unit_card.png", "panel_frame.png",
	"bar_hp.png", "bar_hp_bg.png", "bar_toughness.png",
	"pip_toughness.png", "pip_toughness_empty.png",
	"pip_jianyi.png", "pip_jianyi_empty.png",
	"energy_neili.png", "energy_ziqi.png", "energy_xianqi.png",
	"release.png",
]


func test_layout_json_lists_every_texture() -> void:
	assert_true(FileAccess.file_exists(LAYOUT_PATH),
		"layout.json ships next to the tactics UI art")
	if not FileAccess.file_exists(LAYOUT_PATH):
		return
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(LAYOUT_PATH))
	assert_true(parsed is Dictionary, "layout.json parses")
	if not (parsed is Dictionary):
		return
	var entries: Dictionary = parsed
	for key in REQUIRED:
		assert_true(entries.has(key), "layout.json lists %s" % key)
	var entry: Dictionary = UI.layout_for("turn_card")
	assert_true(entry.has("size") and entry.has("margins"),
		"turn_card carries size and margins")


func test_textured_styles_use_layout_margins() -> void:
	UI.reset_texture_dir()
	_check_margins("turn_card", UI.turn_card_style("player", false))
	_check_margins("turn_card_active", UI.turn_card_style("player", true))
	_check_margins("skill_button", UI.button_style("normal"))
	_check_margins("skill_button_selected", UI.button_style("normal", true))
	_check_margins("skill_button_disabled", UI.button_style("disabled"))
	_check_margins("unit_card", UI.unit_card_style())


func _check_margins(key: String, style: StyleBox) -> void:
	assert_true(style is StyleBoxTexture, "%s style uses its texture" % key)
	if not (style is StyleBoxTexture):
		return
	var box := style as StyleBoxTexture
	var margins: Dictionary = UI.layout_for(key).get("margins", {})
	assert_true(absf(box.texture_margin_left - float(margins.get("left", -1))) < 0.01,
		"%s left margin follows layout.json" % key)
	assert_true(absf(box.texture_margin_right - float(margins.get("right", -1))) < 0.01,
		"%s right margin follows layout.json" % key)
	assert_true(absf(box.texture_margin_top - float(margins.get("top", -1))) < 0.01,
		"%s top margin follows layout.json" % key)
	assert_true(absf(box.texture_margin_bottom - float(margins.get("bottom", -1))) < 0.01,
		"%s bottom margin follows layout.json" % key)


func test_missing_assets_fall_back_to_flat_styles() -> void:
	UI.set_texture_dir(MISSING_DIR)
	assert_true(UI.button_style("normal") is StyleBoxFlat,
		"a missing skill button falls back to StyleBoxFlat")
	assert_true(UI.button_style("normal", true) is StyleBoxFlat,
		"a missing selected button falls back to StyleBoxFlat")
	assert_true(UI.button_style("disabled") is StyleBoxFlat,
		"a missing disabled button falls back to StyleBoxFlat")
	assert_true(UI.panel_style() is StyleBoxFlat,
		"a missing panel frame falls back to StyleBoxFlat")
	assert_true(UI.unit_card_style() is StyleBoxFlat,
		"a missing unit card falls back to StyleBoxFlat")
	assert_true(UI.turn_card_style("player", true) is StyleBoxFlat,
		"a missing active turn card falls back to StyleBoxFlat")
	UI.reset_texture_dir()
	assert_true(UI.button_style("normal") is StyleBoxTexture,
		"resetting the texture dir restores the shipped texture")


func test_missing_assets_turn_cards_fall_back_to_flat_frames() -> void:
	UI.set_texture_dir(MISSING_DIR)
	var built := _make_view(1152.0, 648.0)
	var view: Variant = built["view"]
	view.start()
	var bar: Variant = view.turn_bar
	assert_true(bar.card_count() > 0, "the turn bar still shows cards")
	if bar.card_count() > 0:
		assert_true(bar.card_style(0) is StyleBoxFlat,
			"a missing turn card texture falls back to StyleBoxFlat")
	_finish(built["holder"])
	UI.reset_texture_dir()


func test_hud_keeps_clear_of_the_unit_card_at_1152x648() -> void:
	UI.reset_texture_dir()
	var built := _make_view(1152.0, 648.0)
	var view: Variant = built["view"]
	view.start()
	var card: Control = view.unit_card
	assert_true(card != null, "the unit card exists")
	if card == null:
		_finish(built["holder"])
		return
	assert_true(float(card.offset_right) <= 320.0,
		"the unit card right edge stays at or before x=320")
	assert_true(648.0 + float(card.offset_bottom) <= 648.0,
		"the unit card stays inside the window")
	# 无头模式下控件尺寸为 0，直接用几何公式在 1152x648 下验证技能栏位置。
	var bar: Rect2 = Metrics.bar_rect(
		view.panel.get("_bar").get_combined_minimum_size(), Vector2(1152.0, 648.0))
	assert_true(bar.position.x >= Metrics.BAR_LEFT_MIN,
		"the skill bar starts after the unit card")
	assert_true(bar.end.x <= 1152.0,
		"the skill bar stays inside the right window edge")
	assert_true(view.turn_bar.contents_width() <= 1152.0,
		"eight turn cards fit the window width")
	_finish(built["holder"])


func _make_view(width: float, height: float) -> Dictionary:
	GameState.reset()
	var tree: Variant = Engine.get_meta("test_tree", null)
	var holder := Control.new()
	holder.size = Vector2(width, height)
	if tree != null:
		tree.root.add_child(holder)
	var view: Variant = load("res://features/tactics/tactics_view.gd").new()
	view.use_3d = false
	holder.add_child(view)
	view.size = Vector2(width, height)
	return {"holder": holder, "view": view}


func _finish(holder: Control) -> void:
	holder.free()
	GameState.reset()

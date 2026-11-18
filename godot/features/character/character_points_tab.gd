extends RefCounted

# 加点页签：可分配点数、逐点加减、未提交点数与确认/重置。
# pending_points 随页签生命周期保留，切换页签不会重置未提交的操作。

signal refresh_requested

const CharacterData = preload("res://features/character/character_panel_data.gd")
const CharacterPanelStyle = preload("res://features/character/character_panel_style.gd")
const GameState = preload("res://core/game_state.gd")
const Hud = preload("res://shared/ui/battle_hud_style.gd")
const IconLib = preload("res://shared/ui/icon_lib.gd")
const Progression = preload("res://core/progression.gd")
const Realms = preload("res://core/realms.gd")

var pending_points: Dictionary = {}

var _content: Control = null
var _data: Variant = null


func _init(content: Control, data: Variant) -> void:
	_content = content
	_data = data


func build() -> void:
	var available := GameState.unspent_points
	var title := CharacterPanelStyle.make_label(
		_content, "PointsAvailable", Vector2(0.0, 0.0), Vector2(240.0, 26.0), 18, Hud.GOLD_BRIGHT
	)
	title.text = "可分配点数 %d" % available
	CharacterPanelStyle.make_label(
		_content, "PointWarning", Vector2(232.0, 4.0), Vector2(320.0, 20.0), 12,
		CharacterPanelStyle.WARN_COLOR
	).text = "加点确认后无法撤销"

	var final_values: Dictionary = _data.final_stats()
	var total_assigned := _total_pending()
	var y := 40.0
	for key in CharacterData.STAT_KEYS:
		var pending := _pending(key)
		var point_icon: Texture2D = IconLib.stat_icon(key)
		if point_icon != null:
			var icon_rect := TextureRect.new()
			icon_rect.name = "PointIcon_%s" % key
			icon_rect.position = Vector2(0.0, y - 3.0)
			icon_rect.size = Vector2(28.0, 28.0)
			icon_rect.texture = point_icon
			icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_content.add_child(icon_rect)
		else:
			var fallback := Panel.new()
			fallback.name = "PointIcon_%s" % key
			fallback.position = Vector2(0.0, y - 3.0)
			fallback.size = Vector2(28.0, 28.0)
			fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
			fallback.add_theme_stylebox_override(
				"panel", Hud.circle_style(CharacterPanelStyle.STAT_COLORS[key], 14)
			)
			_content.add_child(fallback)
		var name_label := CharacterPanelStyle.make_label(
			_content, "PointName_%s" % key, Vector2(34.0, y), Vector2(60.0, 22.0), 15, Hud.TEXT
		)
		name_label.text = str(CharacterData.STAT_NAMES[key])
		var value_label := CharacterPanelStyle.make_label(
			_content, "PointValue_%s" % key, Vector2(104.0, y), Vector2(110.0, 22.0), 15, Hud.TEXT
		)
		value_label.text = str(int(final_values.get(key, 0)))

		var minus := CharacterPanelStyle.make_small_button(
			_content, "PointMinus_%s" % key, "－", Vector2(234.0, y - 2.0), Vector2(34.0, 26.0)
		)
		minus.disabled = pending <= 0
		minus.pressed.connect(_on_point_minus.bind(key))

		var plus := CharacterPanelStyle.make_small_button(
			_content, "PointPlus_%s" % key, "＋", Vector2(274.0, y - 2.0), Vector2(34.0, 26.0)
		)
		plus.disabled = available <= 0 \
				or total_assigned >= available \
				or int(final_values.get(key, 0)) + pending >= Progression.STAT_CAP
		plus.pressed.connect(_on_point_plus.bind(key))

		var pending_label := CharacterPanelStyle.make_label(
			_content, "PointPending_%s" % key, Vector2(318.0, y), Vector2(60.0, 22.0), 14,
			CharacterPanelStyle.BONUS_COLOR
		)
		if pending > 0:
			pending_label.text = "+%d" % pending
		if key == "constitution":
			CharacterPanelStyle.make_label(
				_content,
				"ConstitutionHpHint",
				Vector2(390.0, y + 2.0),
				Vector2(190.0, 20.0),
				12,
				Hud.MUTED
			).text = "+1 体质 = +%d 气血" % Realms.hp_per_con(GameState.realm_id)
		y += 38.0

	var total_pending := _total_pending()
	var confirm := CharacterPanelStyle.make_small_button(
		_content, "ConfirmPoints", "确认", Vector2(0.0, 288.0), Vector2(96.0, 32.0)
	)
	confirm.disabled = total_pending <= 0
	confirm.pressed.connect(_on_points_confirm)

	var reset := CharacterPanelStyle.make_small_button(
		_content, "ResetPoints", "重置", Vector2(110.0, 288.0), Vector2(96.0, 32.0)
	)
	reset.disabled = total_pending <= 0
	reset.pressed.connect(_on_points_reset)

	if available <= 0 and total_pending <= 0:
		CharacterPanelStyle.make_label(
			_content, "NoPointsMessage", Vector2(40.0, 262.0), Vector2(480.0, 22.0), 13, Hud.MUTED
		).text = "暂无可分配的点数。完成任务或突破境界可获得点数。"


func _on_point_plus(stat: String) -> void:
	if GameState.unspent_points <= 0:
		return
	var pending := _pending(stat)
	if _total_pending() >= GameState.unspent_points:
		return
	if int(_data.final_stats().get(stat, 0)) + pending >= Progression.STAT_CAP:
		return
	pending_points[stat] = pending + 1
	refresh_requested.emit()


func _on_point_minus(stat: String) -> void:
	var pending := _pending(stat)
	if pending <= 0:
		return
	if pending <= 1:
		pending_points.erase(stat)
	else:
		pending_points[stat] = pending - 1
	refresh_requested.emit()


func _on_points_confirm() -> void:
	var had_pending := _total_pending() > 0
	for key in pending_points.keys():
		var count := int(pending_points[key])
		for i in range(count):
			Progression.spend_point(str(key))
	pending_points.clear()
	if had_pending:
		Progression.push_toast("加点完成")
	refresh_requested.emit()


func _on_points_reset() -> void:
	pending_points.clear()
	refresh_requested.emit()


func _pending(stat: String) -> int:
	return int(pending_points.get(stat, 0))


func _total_pending() -> int:
	var total := 0
	for key in pending_points.keys():
		total += int(pending_points[key])
	return total

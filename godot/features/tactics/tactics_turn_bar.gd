extends Control

# 顶部行动条：把 battle.queue.preview(8) 画成一排 84×98 的卡片（头像 + 名字）。
# 玩家方蓝灰底、敌方暗红底；当前行动者换 turn_card_active 素材（不再放大）。
# 头像取单位立绘图集的正面第一帧，取不到时退回名字首字色块。

const UI = preload("res://features/tactics/tactics_ui_style.gd")

const MAX_CARDS := 8
const CARD_SIZE := Vector2(84.0, 98.0)
# 头像留在九宫格内容区内，下沿让出名字条（位于下边框之上）。
const AVATAR_SIZE := Vector2(52.0, 50.0)
const CARD_GAP := 4

var _backdrop: PanelContainer = null
var _center: CenterContainer = null
var _box: HBoxContainer = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop = PanelContainer.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.add_theme_stylebox_override("panel", UI.turn_band_style())
	add_child(_backdrop)

	_center = CenterContainer.new()
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_center)

	_box = HBoxContainer.new()
	_box.add_theme_constant_override("separation", CARD_GAP)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center.add_child(_box)


func refresh(battle) -> void:
	for child in _box.get_children():
		_box.remove_child(child)
		child.free()
	if battle == null or battle.queue == null:
		return
	var ids: Array = battle.queue.preview(MAX_CARDS)
	for raw_id in ids:
		var uid := str(raw_id)
		var unit = battle.get_unit(uid)
		if unit == null:
			continue
		var card := _make_card(unit, uid == str(battle.current_actor))
		card.set_meta("unit_id", uid)
		_box.add_child(card)


func card_count() -> int:
	return _box.get_child_count() if _box != null else 0


# 行动条内容总宽；测试用来确认 8 张卡片不会超出窗口。
func contents_width() -> float:
	if _box == null:
		return 0.0
	return _box.get_combined_minimum_size().x


# 测试用：第 index 张卡片的根控件；越界返回 null。
func card_at(index: int) -> Control:
	if _box == null or index < 0 or index >= _box.get_child_count():
		return null
	return _box.get_child(index) as Control


# 测试用：第 index 张卡片的背景样式；越界返回 null。
func card_style(index: int) -> StyleBox:
	var card := card_at(index)
	if card == null or card.get_child_count() == 0:
		return null
	var frame := card.get_child(0) as Panel
	if frame == null:
		return null
	return frame.get_theme_stylebox("panel")


func _make_card(unit, current: bool) -> Control:
	var side := str(unit.side)
	var card := Control.new()
	card.custom_minimum_size = CARD_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var frame := Panel.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", UI.turn_card_style(side, current))
	card.add_child(frame)

	var avatar := _make_avatar(unit, side, AVATAR_SIZE)
	avatar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	avatar.offset_left = 16.0
	avatar.offset_top = 18.0
	avatar.offset_right = 68.0
	avatar.offset_bottom = 68.0
	card.add_child(avatar)

	var name_label := Label.new()
	name_label.text = str(unit.unit.name)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	name_label.offset_left = 3.0
	name_label.offset_top = -31.0
	name_label.offset_right = -3.0
	name_label.offset_bottom = -17.0
	name_label.clip_text = true
	UI.configure_label(name_label, 10, UI.turn_name_color(side, current))
	card.add_child(name_label)

	if current:
		card.z_index = 1
	return card


# 头像底色始终铺在底下（玩家蓝灰 / 敌方暗红），有立绘时叠在上面；
# 缺图时在底色上显示名字首字。
func _make_avatar(unit, side: String, view_size: Vector2) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = view_size
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var block := ColorRect.new()
	block.color = UI.avatar_bg(side)
	block.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(block)

	var texture := UI.portrait_texture(unit)
	if texture != null:
		var rect := TextureRect.new()
		rect.texture = texture
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(rect)
		return holder

	var name_text := str(unit.unit.name)
	var initial := Label.new()
	initial.text = name_text.substr(0, 1) if name_text != "" else "?"
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UI.configure_label(initial, 22, UI.TEXT)
	holder.add_child(initial)
	return holder

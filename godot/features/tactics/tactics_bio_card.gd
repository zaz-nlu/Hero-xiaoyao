extends Control

# 人物介绍卡（默认隐藏）：战中点击单位或右键时打开，居中偏右、约 360×240。
# 显示头像、名字、称号、简介正文与当前气血/韧性/剑意；右上角关闭按钮，
# 点击卡片外任意处或按 Esc 关闭。简介按单位 id / 敌人 def id 读取 data/tactics_bios.json。

const UI = preload("res://features/tactics/tactics_ui_style.gd")

const BIOS_PATH := "res://data/tactics_bios.json"
# 玩家在战斗里的单位 id 是 "player"，人物简介用其角色 id。
const PLAYER_BIO_ID := "ren_xiaoyao"
const CARD_SIZE := Vector2(360.0, 240.0)
const AVATAR_SIZE := Vector2(64.0, 82.0)

static var _bios: Dictionary = {}
static var _bios_loaded: bool = false

var _card: Control = null
var _avatar: Control = null
var _avatar_for: String = ""
var _name_label: Label = null
var _title_label: Label = null
var _bio_label: Label = null
var _stats_label: Label = null
var _unit_id: String = ""


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()


func open_for(unit) -> void:
	if unit == null:
		return
	var key := bio_key(unit)
	var entry: Dictionary = entry_for(key)
	_unit_id = key
	_name_label.text = str(unit.unit.name)
	_title_label.text = str(entry.get("title", "江湖无名"))
	_bio_label.text = str(entry.get("bio", "此人来历不明，江湖上尚无记载。"))
	_stats_label.text = _stats_text(unit)
	_set_avatar(unit)
	visible = true


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


func unit_id() -> String:
	return _unit_id


# Esc 关闭；返回 true 表示按键已被卡片消费。
func handle_key(keycode: int) -> bool:
	if not visible:
		return false
	if keycode == KEY_ESCAPE:
		close()
		return true
	return false


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	# 卡片内部由 _card 接收，能到这里的是卡片外的点击。
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
			close()


# ---- 数据 ----------------------------------------------------------------

# 玩家用角色 id，敌人用 enemy def id；取不到时退回战术单位 id。
static func bio_key(unit) -> String:
	if unit == null:
		return ""
	if str(unit.side) == "player":
		return PLAYER_BIO_ID
	if unit.unit != null and unit.unit.def != null:
		return str(unit.unit.def.id)
	return str(unit.unit.id) if unit.unit != null else ""


static func load_bios() -> Dictionary:
	if _bios_loaded:
		return _bios
	_bios_loaded = true
	_bios = {}
	var text := FileAccess.get_file_as_string(BIOS_PATH)
	if text == "":
		return _bios
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		_bios = parsed
	return _bios


static func entry_for(unit_id: String) -> Dictionary:
	var raw = load_bios().get(unit_id, {})
	return raw if raw is Dictionary else {}


func _stats_text(unit) -> String:
	var parts: Array[String] = []
	parts.append("气血 %d/%d" % [
		maxi(0, int(unit.unit.hp)), maxi(1, int(unit.unit.max_hp))])
	if int(unit.unit.toughness_max) > 0:
		parts.append("韧性 %d/%d" % [
			int(ceil(float(unit.unit.toughness_left))),
			int(unit.unit.toughness_max)])
	else:
		parts.append("韧性 —")
	parts.append("剑意 %d/%d" % [
		int(unit.unit.jianyi_points), int(unit.unit.jianyi_max)])
	return "   ".join(PackedStringArray(parts))


# ---- 控件 ----------------------------------------------------------------

func _build() -> void:
	_card = Control.new()
	_card.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_card.offset_left = -CARD_SIZE.x - 20.0
	_card.offset_right = -20.0
	_card.offset_top = -CARD_SIZE.y * 0.5
	_card.offset_bottom = CARD_SIZE.y * 0.5
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_card)

	# 框体贴图中间是透明的，先垫一层不透明的深色底，字才看得清。
	var backing := Panel.new()
	backing.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var backing_style := StyleBoxFlat.new()
	backing_style.bg_color = Color(0.085, 0.06, 0.04, 0.985)
	backing_style.set_corner_radius_all(4)
	backing.add_theme_stylebox_override("panel", backing_style)
	_card.add_child(backing)

	var background := PanelContainer.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	background.add_theme_stylebox_override("panel", UI.panel_style())
	_card.add_child(background)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(header)

	_avatar = Control.new()
	_avatar.custom_minimum_size = AVATAR_SIZE
	_avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(_avatar)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 3)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(info)

	_name_label = Label.new()
	UI.configure_label(_name_label, 18, UI.GOLD_BRIGHT)
	info.add_child(_name_label)

	_title_label = Label.new()
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UI.configure_label(_title_label, 12, UI.MUTED)
	info.add_child(_title_label)

	_bio_label = Label.new()
	_bio_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bio_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bio_label.custom_minimum_size = Vector2(0.0, 76.0)
	UI.configure_label(_bio_label, 12, UI.TEXT)
	column.add_child(_bio_label)

	_stats_label = Label.new()
	UI.configure_label(_stats_label, 12, UI.JIANYI_PURPLE)
	column.add_child(_stats_label)

	var close_button := Button.new()
	close_button.text = "×"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	close_button.offset_left = -32.0
	close_button.offset_top = 6.0
	close_button.offset_right = -6.0
	close_button.offset_bottom = 32.0
	close_button.add_theme_font_size_override("font_size", 14)
	close_button.add_theme_color_override("font_color", UI.TEXT)
	close_button.add_theme_color_override("font_hover_color", UI.GOLD_BRIGHT)
	close_button.add_theme_stylebox_override("normal", UI.button_style("normal"))
	close_button.add_theme_stylebox_override("hover", UI.button_style("hover"))
	close_button.add_theme_stylebox_override("pressed", UI.button_style("pressed"))
	close_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	close_button.pressed.connect(close)
	_card.add_child(close_button)


func _set_avatar(unit) -> void:
	var key := UI.unit_sprite_id(unit)
	if key == _avatar_for:
		return
	_avatar_for = key
	for child in _avatar.get_children():
		_avatar.remove_child(child)
		child.free()

	var texture := UI.portrait_texture(unit)
	if texture != null:
		var rect := TextureRect.new()
		rect.texture = texture
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_avatar.add_child(rect)
		return

	var block := ColorRect.new()
	block.color = UI.name_color(str(unit.unit.name))
	block.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_avatar.add_child(block)

	var name_text := str(unit.unit.name)
	var initial := Label.new()
	initial.text = name_text.substr(0, 1) if name_text != "" else "?"
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UI.configure_label(initial, 28, UI.TEXT)
	_avatar.add_child(initial)

extends Control

# 左下角的单位卡：显示当前选中 / 悬停的单位（默认当前行动者）。
# 玩家：头像、名字、气血条 + 数字、韧性点、剑意点、反应点与三种能量（图标 + 数字）；
# 敌方只显示气血条与韧性。只读战斗状态，不调用规则。

const UI = preload("res://features/tactics/tactics_ui_style.gd")
const TacticsEnergy = preload("res://core/tactics/tactics_energy.gd")

const CARD_SIZE := Vector2(300.0, 185.0)
const AVATAR_SIZE := Vector2(84.0, 108.0)
const TOUGH_BLUE := Color(0.3, 0.62, 1.0)
const MAX_PIPS := 12
const PIP_SIZE := Vector2(14.0, 14.0)
const ENERGY_ICON_SIZE := Vector2(16.0, 16.0)
const WEAK_ICON_SIZE := Vector2(24.0, 24.0)

var _avatar: Control = null
var _avatar_for: String = ""
var _name_label: Label = null
var _hp_bar: ProgressBar = null
var _hp_label: Label = null
var _tough_row: HBoxContainer = null
var _tough_bar: ProgressBar = null
var _tough_ticks: Control = null
var _tough_label: Label = null
var _weak_row: HBoxContainer = null
var _weak_pips: HBoxContainer = null
var _jianyi_row: HBoxContainer = null
var _jianyi_pips: HBoxContainer = null
var _reaction_label: Label = null
var _energy_row: HBoxContainer = null
var _energy_labels: Dictionary = {}


func _init() -> void:
	custom_minimum_size = CARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	var background := PanelContainer.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.add_theme_stylebox_override("panel", UI.unit_card_style())
	add_child(background)

	# 内边距由 unit_card 的九宫格 content_margin 提供，不再叠加一层 MarginContainer。
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.add_child(row)

	_avatar = Control.new()
	_avatar.custom_minimum_size = AVATAR_SIZE
	_avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_avatar)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)

	_name_label = Label.new()
	UI.configure_label(_name_label, 16, UI.GOLD_BRIGHT)
	info.add_child(_name_label)

	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 5)
	hp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(hp_row)

	var hp_caption := Label.new()
	hp_caption.text = "气血"
	UI.configure_label(hp_caption, 11, UI.MUTED)
	hp_row.add_child(hp_caption)

	var hp_holder := Control.new()
	hp_holder.custom_minimum_size = Vector2(100.0, 15.0)
	hp_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_row.add_child(hp_holder)

	_hp_bar = ProgressBar.new()
	_hp_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hp_bar.show_percentage = false
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_bar.add_theme_stylebox_override("background", UI.bar_bg_style())
	_hp_bar.add_theme_stylebox_override("fill", UI.bar_fill_style("hp"))
	hp_holder.add_child(_hp_bar)

	_hp_label = Label.new()
	_hp_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UI.configure_label(_hp_label, 10, UI.TEXT)
	_hp_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	_hp_label.add_theme_constant_override("outline_size", 3)
	hp_holder.add_child(_hp_label)

	_tough_row = HBoxContainer.new()
	_tough_row.add_theme_constant_override("separation", 5)
	_tough_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(_tough_row)

	var tough_caption := Label.new()
	tough_caption.text = "韧性"
	UI.configure_label(tough_caption, 11, UI.MUTED)
	_tough_row.add_child(tough_caption)

	# 韧性是一条蓝条，按点数分段；只有 Boss / 精英（有韧性的敌人）才显示。
	var tough_holder := Control.new()
	tough_holder.custom_minimum_size = Vector2(100.0, 12.0)
	tough_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tough_holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tough_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tough_row.add_child(tough_holder)
	_tough_bar = ProgressBar.new()
	_tough_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tough_bar.show_percentage = false
	_tough_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tough_bar.add_theme_stylebox_override("background", UI.bar_bg_style())
	var blue := StyleBoxFlat.new()
	blue.bg_color = TOUGH_BLUE
	blue.set_corner_radius_all(3)
	_tough_bar.add_theme_stylebox_override("fill", blue)
	tough_holder.add_child(_tough_bar)
	_tough_ticks = Control.new()
	_tough_ticks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tough_ticks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tough_holder.add_child(_tough_ticks)
	_tough_label = Label.new()
	_tough_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tough_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_tough_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UI.configure_label(_tough_label, 9, UI.TEXT)
	_tough_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	_tough_label.add_theme_constant_override("outline_size", 3)
	tough_holder.add_child(_tough_label)

	_weak_row = HBoxContainer.new()
	_weak_row.add_theme_constant_override("separation", 5)
	_weak_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(_weak_row)

	var weak_caption := Label.new()
	weak_caption.text = "弱点"
	UI.configure_label(weak_caption, 11, UI.GOLD_BRIGHT)
	_weak_row.add_child(weak_caption)

	_weak_pips = HBoxContainer.new()
	_weak_pips.add_theme_constant_override("separation", 2)
	_weak_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weak_row.add_child(_weak_pips)

	_jianyi_row = HBoxContainer.new()
	_jianyi_row.add_theme_constant_override("separation", 5)
	_jianyi_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(_jianyi_row)

	var jianyi_caption := Label.new()
	jianyi_caption.text = "剑意"
	UI.configure_label(jianyi_caption, 11, UI.JIANYI_PURPLE)
	_jianyi_row.add_child(jianyi_caption)

	_jianyi_pips = HBoxContainer.new()
	_jianyi_pips.add_theme_constant_override("separation", 2)
	_jianyi_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_jianyi_row.add_child(_jianyi_pips)

	_reaction_label = Label.new()
	UI.configure_label(_reaction_label, 11, UI.REACTION_CYAN)
	info.add_child(_reaction_label)

	_energy_row = HBoxContainer.new()
	_energy_row.add_theme_constant_override("separation", 6)
	_energy_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(_energy_row)
	for raw_color in TacticsEnergy.colors():
		var color := str(raw_color)
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 2)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_energy_row.add_child(cell)

		var icon := TextureRect.new()
		icon.custom_minimum_size = ENERGY_ICON_SIZE
		icon.texture = UI.energy_icon(color)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(icon)

		var value := Label.new()
		UI.configure_label(value, 10, UI.TEXT)
		cell.add_child(value)
		_energy_labels[color] = value


func show_unit(battle, uid: String) -> void:
	if battle == null or uid == "":
		visible = false
		return
	var unit = battle.get_unit(uid)
	if unit == null:
		visible = false
		return
	visible = true
	_name_label.text = str(unit.unit.name)

	var max_hp := maxi(1, int(unit.unit.max_hp))
	_hp_bar.max_value = float(max_hp)
	_hp_bar.value = float(clampi(int(unit.unit.hp), 0, max_hp))
	_hp_label.text = "%d/%d" % [maxi(0, int(unit.unit.hp)), max_hp]

	_update_toughness(unit)
	_update_jianyi(unit)
	_update_weakness(unit)

	var is_player := str(unit.side) == "player"
	_jianyi_row.visible = is_player
	_reaction_label.visible = is_player
	_energy_row.visible = is_player
	if is_player:
		_reaction_label.text = "反应点 %d" % int(unit.reactions_left)
		for raw_color in TacticsEnergy.colors():
			var color := str(raw_color)
			var value: Label = _energy_labels.get(color, null)
			if value != null:
				value.text = "%d/%d" % [
					int(unit.energy_left.get(color, 0)),
					int(unit.energy_max.get(color, 0))]

	_set_avatar(unit)


func _update_toughness(unit) -> void:
	var total := int(unit.unit.toughness_max)
	var shown: bool = str(unit.side) == "enemy" and total > 0
	_tough_row.visible = shown
	for child in _tough_ticks.get_children():
		_tough_ticks.remove_child(child)
		child.free()
	if not shown:
		return
	var left := int(ceil(float(unit.unit.toughness_left)))
	_tough_bar.max_value = float(total)
	_tough_bar.value = float(clampi(left, 0, total))
	_tough_label.text = "%d/%d" % [maxi(0, left), total]
	for i in range(1, total):
		var tick := ColorRect.new()
		tick.color = Color(0.0, 0.0, 0.0, 0.55)
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tick.anchor_left = float(i) / float(total)
		tick.anchor_right = tick.anchor_left
		tick.anchor_bottom = 1.0
		tick.offset_right = 1.0
		_tough_ticks.add_child(tick)


func toughness_visible() -> bool:
	return _tough_row.visible


func _update_jianyi(unit) -> void:
	_clear(_jianyi_pips)
	var total := maxi(0, int(unit.unit.jianyi_max))
	if total <= 0:
		_add_dash(_jianyi_pips)
		return
	_add_pips(_jianyi_pips, total, int(unit.unit.jianyi_points), "jianyi")


func _update_weakness(unit) -> void:
	_clear(_weak_pips)
	var shown := 0
	for raw in unit.weaknesses:
		var color := str(raw)
		if color == "" or color == "none":
			continue
		var texture := UI.texture_for("weak_" + color)
		if texture != null:
			var icon := TextureRect.new()
			icon.custom_minimum_size = WEAK_ICON_SIZE
			icon.texture = texture
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_weak_pips.add_child(icon)
		else:
			var block := ColorRect.new()
			block.custom_minimum_size = WEAK_ICON_SIZE
			block.color = UI.GOLD_DIM
			block.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_weak_pips.add_child(block)
		shown += 1
	_weak_row.visible = str(unit.side) == "enemy" and shown > 0


func weakness_icon_count() -> int:
	return _weak_pips.get_child_count()


func weakness_row_visible() -> bool:
	return _weak_row.visible


func _clear(box: HBoxContainer) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.free()


func _add_dash(box: HBoxContainer) -> void:
	var none := Label.new()
	none.text = "—"
	UI.configure_label(none, 11, UI.MUTED)
	box.add_child(none)


func _add_pips(box: HBoxContainer, total: int, left: int, kind: String) -> void:
	var filled_tex := UI.pip_texture(kind, true)
	var empty_tex := UI.pip_texture(kind, false)
	for i in range(total):
		var filled := i < left
		var texture := filled_tex if filled else empty_tex
		if texture != null:
			var pip := TextureRect.new()
			pip.custom_minimum_size = PIP_SIZE
			pip.texture = texture
			pip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pip.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(pip)
		else:
			var block := ColorRect.new()
			block.custom_minimum_size = Vector2(PIP_SIZE.x, PIP_SIZE.y - 2.0)
			block.color = _pip_color(kind, filled)
			block.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(block)


func _pip_color(kind: String, filled: bool) -> Color:
	if kind == "jianyi":
		return UI.JIANYI_PURPLE if filled else Color(0.24, 0.2, 0.32, 0.9)
	return UI.TOUGH_GOLD if filled else UI.TOUGH_OFF


func _set_avatar(unit) -> void:
	var key := UI.unit_sprite_id(unit)
	if key == _avatar_for:
		return
	_avatar_for = key
	for child in _avatar.get_children():
		_avatar.remove_child(child)
		child.free()

	var texture := UI.card_portrait_texture(unit)
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

extends Control

# 底部技能栏：panel_frame 背板 + 一排 64×64 方形按钮
# 「移动 / 各武学 / 剑意 / 运功 / 待机 / 结束」。武学按钮用 36×36 图标，
# 右下角标剩余次数，左上角标快捷键；悬停显示武学 tooltip。
# 能量切换是三个「图标 + left/max」标签，整体相对窗口中轴偏右以避开单位卡。
# 只发信号，不调用规则。

signal mode_selected(mode: String, martial_id: String)
signal energy_changed(energy: String)

const UI = preload("res://features/tactics/tactics_ui_style.gd")
const Metrics = preload("res://features/tactics/tactics_panel_metrics.gd")
const TacticsEnergy = preload("res://core/tactics/tactics_energy.gd")
const TacticsRelease = preload("res://core/tactics/tactics_release.gd")
const MoveTypes = preload("res://core/move_types.gd")

const BUTTON_SIZE := Vector2(64.0, 64.0)
const ICON_SIZE := 36
const ENERGY_ICON_SIZE := 28
const ENERGY_SIZE := Vector2(88.0, 30.0)
const DEFAULT_SEPARATION := 8
const ENERGY_ORDER: Array[String] = ["neili", "ziqi", "xianqi"]
const GRADE_NAMES := {
	"common": "凡品",
	"fine": "精品",
	"rare": "珍品",
	"epic": "秘传",
	"legendary": "绝世",
}

var battle: Variant = null
var actor_id: String = ""
var energy: String = "neili"
var energy_buttons: Dictionary = {}

var message_label: Label = null
var move_button: Button = null
var jianyi_button: Button = null
var release_button: Button = null
var wait_button: Button = null
var end_button: Button = null
var martial_buttons: Array[Button] = []
var martial_ids: Array[String] = []
# 移动 + 各武学 + 剑意 + 待机 + 结束，顺序与显示一致。
var skill_buttons: Array[Button] = []

var _bar: PanelContainer = null
var _center: CenterContainer = null
var _button_box: HBoxContainer = null
var _energy_box: HBoxContainer = null
var _tooltip: PanelContainer = null
var _tooltip_name: Label = null
var _tooltip_stats: Label = null
var _tooltip_desc: Label = null
var _uses_badges: Dictionary = {}
var _built_for: String = ""
var _selected_mode: String = ""
var _selected_martial: String = ""
var _interactive: bool = false
var _hover_text: String = ""


func _init() -> void:
	# 面板本身不拦截点击，只有居中的技能条与提示卡接收输入。
	mouse_filter = Control.MOUSE_FILTER_PASS

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	center.offset_left = Metrics.BAR_SHIFT_PX * 2.0
	center.offset_top = -188.0
	center.offset_bottom = -8.0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_center = center
	resized.connect(func() -> void: Metrics.place_center(_center, _bar, size.x))

	var stack := VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_END
	stack.add_theme_constant_override("separation", 4)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(stack)

	message_label = Label.new()
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.custom_minimum_size = Vector2(0.0, 18.0)
	UI.configure_label(message_label, 13, Color(0.92, 0.72, 0.45))
	stack.add_child(message_label)

	_energy_box = HBoxContainer.new()
	_energy_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_energy_box.add_theme_constant_override("separation", 6)
	_energy_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(_energy_box)
	for raw_color in ENERGY_ORDER:
		var color := str(raw_color)
		var button := _make_energy_button(color)
		_energy_box.add_child(button)
		energy_buttons[color] = button

	_bar = PanelContainer.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_bar.add_theme_stylebox_override("panel", UI.panel_style())
	stack.add_child(_bar)

	_button_box = HBoxContainer.new()
	_button_box.add_theme_constant_override("separation", DEFAULT_SEPARATION)
	_button_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(_button_box)

	_tooltip = PanelContainer.new()
	_tooltip.visible = false
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.add_theme_stylebox_override("panel", UI.tooltip_style())
	add_child(_tooltip)

	var tooltip_box := VBoxContainer.new()
	tooltip_box.add_theme_constant_override("separation", 2)
	tooltip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.add_child(tooltip_box)

	_tooltip_name = Label.new()
	UI.configure_label(_tooltip_name, 15, UI.GOLD_BRIGHT)
	tooltip_box.add_child(_tooltip_name)

	_tooltip_stats = Label.new()
	UI.configure_label(_tooltip_stats, 12, UI.TEXT)
	tooltip_box.add_child(_tooltip_stats)

	_tooltip_desc = Label.new()
	UI.configure_label(_tooltip_desc, 11, UI.MUTED)
	tooltip_box.add_child(_tooltip_desc)


func setup(p_battle, p_actor_id: String) -> void:
	battle = p_battle
	actor_id = p_actor_id
	if _built_for != actor_id:
		_rebuild_buttons()
		_built_for = actor_id
	refresh(p_battle, p_actor_id)


func refresh(p_battle, p_actor_id: String) -> void:
	if p_actor_id != actor_id:
		setup(p_battle, p_actor_id)
		return
	battle = p_battle
	var unit = _actor()
	if unit == null:
		_update_buttons(null)
		return
	_update_buttons(unit)


func set_interactive(value: bool) -> void:
	_interactive = value
	refresh(battle, actor_id)


func set_selected(mode: String, martial_id: String) -> void:
	_selected_mode = mode
	_selected_martial = martial_id
	_apply_selected()


func show_message(text: String) -> void:
	if message_label != null:
		message_label.text = text


# 悬停信息行已并入 tactics_unit_card；保留入口以兼容现有调用点。
func show_unit_info(text: String) -> void:
	_hover_text = text


func _actor() -> Variant:
	if battle == null or actor_id == "":
		return null
	return battle.get_unit(actor_id)


func _rebuild_buttons() -> void:
	for child in _button_box.get_children():
		_button_box.remove_child(child)
		child.free()
	martial_buttons.clear()
	martial_ids.clear()
	skill_buttons.clear()
	_uses_badges.clear()
	_selected_mode = ""
	_selected_martial = ""

	move_button = _make_skill_button("移动", "M", null)
	move_button.pressed.connect(_on_mode_pressed.bind("move", ""))
	skill_buttons.append(move_button)

	var unit = _actor()
	if unit != null and unit.side == "player":
		for raw_id in unit.loadout:
			var martial_id := str(raw_id)
			var button := _make_skill_button(
				_short_name(martial_id), str(martial_buttons.size() + 1),
				UI.martial_icon(martial_id))
			button.pressed.connect(_on_mode_pressed.bind("attack", martial_id))
			button.mouse_entered.connect(_on_martial_hover.bind(button, martial_id))
			button.mouse_exited.connect(_hide_tooltip)
			_add_uses_badge(button, martial_id)
			martial_buttons.append(button)
			martial_ids.append(martial_id)
			skill_buttons.append(button)

	jianyi_button = _make_skill_button("剑意", "J", null)
	jianyi_button.pressed.connect(_on_mode_pressed.bind("jianyi", ""))
	skill_buttons.append(jianyi_button)
	release_button = _make_skill_button("运功", "H", UI.release_icon())
	release_button.pressed.connect(_on_mode_pressed.bind("release", ""))
	_add_cost_badge(release_button, TacticsRelease.cost())
	wait_button = _make_skill_button("待机", "空", null)
	wait_button.pressed.connect(_on_mode_pressed.bind("wait", ""))
	skill_buttons.append(wait_button)
	end_button = _make_skill_button("结束", "空", null)
	end_button.pressed.connect(_on_mode_pressed.bind("end", ""))
	skill_buttons.append(end_button)

	_apply_selected()
	Metrics.fit_separation(_button_box, UI.panel_style(), size.x, BUTTON_SIZE.x,
		DEFAULT_SEPARATION)
	Metrics.place_center(_center, _bar, size.x)


func _make_skill_button(text: String, key_text: String, icon: Texture2D) -> Button:
	var button := Button.new()
	button.custom_minimum_size = BUTTON_SIZE
	button.focus_mode = Control.FOCUS_NONE
	button.clip_text = true
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_color_override("font_color", UI.TEXT)
	button.add_theme_color_override("font_hover_color", UI.GOLD_BRIGHT)
	button.add_theme_color_override("font_pressed_color", UI.GOLD_BRIGHT)
	button.add_theme_color_override("font_disabled_color", UI.MUTED)
	button.add_theme_stylebox_override("normal", UI.button_style("normal"))
	button.add_theme_stylebox_override("hover", UI.button_style("hover"))
	button.add_theme_stylebox_override("pressed", UI.button_style("pressed"))
	button.add_theme_stylebox_override("disabled", UI.button_style("disabled"))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if icon != null:
		button.icon = icon
		button.text = ""
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_theme_constant_override("icon_max_width", ICON_SIZE)
	else:
		button.text = text
	button.set_meta("selected", false)
	_button_box.add_child(button)

	var badge := Label.new()
	badge.text = key_text
	badge.set_anchors_preset(Control.PRESET_TOP_LEFT)
	badge.offset_left = 2.0
	badge.offset_top = 2.0
	badge.offset_right = 4.0 + (16.0 if key_text.length() <= 1 else 22.0)
	badge.offset_bottom = 16.0
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UI.configure_label(badge, 9, UI.GOLD_BRIGHT)
	badge.add_theme_stylebox_override("normal", UI.badge_style())
	button.add_child(badge)
	return button


func _make_energy_button(color: String) -> Button:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = ENERGY_SIZE
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_color_override("font_color", UI.TEXT)
	button.add_theme_color_override("font_hover_color", UI.GOLD_BRIGHT)
	button.add_theme_color_override("font_pressed_color", UI.GOLD_BRIGHT)
	button.add_theme_color_override("font_disabled_color", UI.MUTED)
	button.add_theme_stylebox_override("normal", UI.energy_style(false))
	button.add_theme_stylebox_override("hover", UI.energy_style(true))
	button.add_theme_stylebox_override("pressed", UI.energy_style(true))
	button.add_theme_stylebox_override("disabled", UI.energy_style(false))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var icon := UI.energy_icon(color)
	if icon != null:
		button.icon = icon
		button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		button.add_theme_constant_override("icon_max_width", ENERGY_ICON_SIZE)
	button.text = TacticsEnergy.name_of(color)
	button.tooltip_text = TacticsEnergy.name_of(color)
	button.pressed.connect(select_energy.bind(color))
	return button


# 切换出招能量；锁定的能量（当前是仙气）不可选。
func select_energy(color: String) -> void:
	if not _interactive:
		return
	if not ENERGY_ORDER.has(color) or TacticsEnergy.is_locked(color):
		return
	energy = color
	_apply_energy()
	if battle != null:
		refresh(battle, actor_id)
	energy_changed.emit(energy)


func cycle_energy() -> void:
	var start := ENERGY_ORDER.find(energy)
	for step in range(1, ENERGY_ORDER.size() + 1):
		var color := ENERGY_ORDER[(start + step) % ENERGY_ORDER.size()]
		if not TacticsEnergy.is_locked(color):
			select_energy(color)
			return


func _apply_energy() -> void:
	for raw_color in energy_buttons.keys():
		var color := str(raw_color)
		var button: Button = energy_buttons[color]
		var selected := color == energy
		button.set_meta("selected", selected)
		button.add_theme_stylebox_override("normal", UI.energy_style(selected))
		button.modulate = Color.WHITE
		if TacticsEnergy.is_locked(color):
			button.modulate = Color(0.55, 0.55, 0.55, 0.9)


func _update_energy_buttons(unit) -> void:
	for raw_color in energy_buttons.keys():
		var color := str(raw_color)
		var button: Button = energy_buttons[color]
		var locked := TacticsEnergy.is_locked(color)
		var left := 0
		var maximum := 0
		if unit != null:
			left = int(unit.energy_left.get(color, 0))
			maximum = int(unit.energy_max.get(color, 0))
		button.text = "%d/%d" % [left, maximum]
		button.disabled = locked or not _interactive
	_apply_energy()


func _add_uses_badge(button: Button, martial_id: String) -> void:
	var uses := Label.new()
	uses.text = "∞"
	uses.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	uses.offset_left = -30.0
	uses.offset_top = -18.0
	uses.offset_right = -3.0
	uses.offset_bottom = -2.0
	uses.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	uses.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UI.configure_label(uses, 10, UI.TEXT)
	uses.add_theme_stylebox_override("normal", UI.badge_style())
	button.add_child(uses)
	_uses_badges[martial_id] = uses


func _add_cost_badge(button: Button, cost: int) -> void:
	var badge := Label.new()
	badge.text = str(cost)
	badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	badge.offset_left = -18.0
	badge.offset_top = -18.0
	badge.offset_right = -3.0
	badge.offset_bottom = -2.0
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UI.configure_label(badge, 10, UI.JIANYI_PURPLE)
	badge.add_theme_stylebox_override("normal", UI.badge_style())
	button.add_child(badge)


func _short_name(martial_id: String) -> String:
	var text := martial_id
	if battle != null and battle.martials.has(martial_id):
		text = str(battle.martials[martial_id].name)
	return text.substr(0, 4) if text.length() > 4 else text


func _cost(martial_id: String) -> int:
	if battle == null or not battle.martials.has(martial_id):
		return 1
	return TacticsEnergy.cost_for(battle.martials[martial_id])


# 技能角标：显示所选能量下的消耗，基础剑术为 ∞。
func _uses_text(martial_id: String) -> String:
	var cost := _cost(martial_id)
	return "∞" if cost <= 0 else str(cost)


func _on_martial_hover(button: Button, martial_id: String) -> void:
	if battle == null or not battle.martials.has(martial_id):
		return
	var data: Dictionary = battle.martials[martial_id]
	var range_data: Dictionary = data.get("range", {})
	var min_range := int(range_data.get("min", 1))
	var max_range := int(range_data.get("max", min_range))
	var range_text := str(max_range)
	if min_range != max_range:
		range_text = "%d-%d" % [min_range, max_range]
	_tooltip_name.text = str(data.get("name", martial_id))
	_tooltip_stats.text = "威力 %d   ·   射程 %s   ·   %s消耗 %s" % [
		int(data.get("power", 0)), range_text, TacticsEnergy.name_of(energy),
		_uses_text(martial_id)]
	_tooltip_desc.text = _describe(data)
	_tooltip.visible = true
	_tooltip.reset_size()
	var origin := button.get_global_rect().position - get_global_rect().position
	_tooltip.position = origin + Vector2(0.0, -_tooltip.size.y - 8.0)


func _hide_tooltip() -> void:
	if _tooltip != null:
		_tooltip.visible = false


# 用 martials 数据里已有的字段拼一句描述：品阶 + 克制的招式类型。
func _describe(data: Dictionary) -> String:
	var grade := str(data.get("grade", "common"))
	var parts: Array[String] = [str(GRADE_NAMES.get(grade, "凡品")) + "武学"]
	var counters: Variant = data.get("counters", [])
	if counters is Array and not counters.is_empty():
		var names := PackedStringArray()
		for raw in counters:
			names.append(str(MoveTypes.NAMES.get(str(raw), str(raw))))
		parts.append("克制" + "、".join(names))
	return "，".join(PackedStringArray(parts)) + "。"


func _on_mode_pressed(mode: String, martial_id: String) -> void:
	if not _interactive:
		return
	mode_selected.emit(mode, martial_id)


func _update_buttons(unit) -> void:
	_update_energy_buttons(unit)
	var can_move: bool = _interactive and unit != null and not unit.has_moved
	var can_act: bool = _interactive and unit != null and not unit.has_acted
	if move_button != null:
		_set_disabled(move_button, not can_move)
	for i in range(martial_buttons.size()):
		var martial_id := martial_ids[i]
		var button := martial_buttons[i]
		var disabled: bool = not can_act or unit == null \
				or not unit.can_pay(energy, _cost(martial_id))
		_set_disabled(button, disabled)
		var badge: Label = _uses_badges.get(martial_id, null)
		if badge != null:
			badge.text = _uses_text(martial_id)
	if jianyi_button != null:
		var points := 0
		if unit != null:
			points = int(unit.unit.jianyi_points)
		_set_disabled(jianyi_button, not can_act or points <= 0)
	if release_button != null:
		var can_release := false
		if can_act and unit != null and unit.side == "player":
			var full_hp := int(unit.unit.hp) >= int(unit.unit.max_hp) - int(unit.unit.wound)
			can_release = not full_hp and unit.can_pay("ziqi", TacticsRelease.cost())
		_set_disabled(release_button, not can_release)
	if wait_button != null:
		_set_disabled(wait_button, not can_act)
	if end_button != null:
		_set_disabled(end_button, not _interactive)


# 次数为 0 或已行动时置灰。
func _set_disabled(button: Button, disabled: bool) -> void:
	button.disabled = disabled
	button.modulate = Color(0.55, 0.55, 0.55, 0.9) if disabled else Color.WHITE


func _apply_selected() -> void:
	_set_selected_style(move_button, _selected_mode == "move")
	for i in range(martial_buttons.size()):
		var selected := _selected_mode == "attack" and martial_ids[i] == _selected_martial
		_set_selected_style(martial_buttons[i], selected)
	_set_selected_style(jianyi_button, _selected_mode == "jianyi")
	_set_selected_style(wait_button, false)
	_set_selected_style(end_button, false)


func _set_selected_style(button: Button, selected: bool) -> void:
	if button == null:
		return
	button.set_meta("selected", selected)
	button.add_theme_stylebox_override("normal", UI.button_style("normal", selected))


# 技能栏在窗口中的实际外框（测试与调试用）。
func bar_bounds() -> Rect2:
	return Metrics.bar_rect_for(_bar, size)

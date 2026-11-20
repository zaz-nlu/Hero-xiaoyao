extends PanelContainer

# 被攻击时的反制菜单（默认隐藏）。视图一次处理一个防守者；多个防守者时逐个
# 重新 open_for。选择武学、基础格挡或“不反制”后发出 chosen(defender_id, martial_id)，
# 空字符串代表不反制。标题行给出敌招形态，选项行给出结果徽章、效果与内力消耗；
# 数字键 1~9 选中对应行。

signal chosen(defender_id: String, martial_id: String)

const TacticsEnergy = preload("res://core/tactics/tactics_energy.gd")
const TacticsForms = preload("res://core/tactics/tactics_forms.gd")
const TacticsRuleData = preload("res://core/tactics/tactics_rule_data.gd")
const UI = preload("res://features/tactics/tactics_ui_style.gd")

const FORM_ICON_SIZE := 40
const MARTIAL_ICON_SIZE := 26
const COST_ICON_SIZE := 18
const MARTIAL_ROW_HEIGHT := 60.0
const FIXED_ROW_HEIGHT := 54.0

var title_label: Label = null
var form_name_label: Label = null
var form_icon_rect: TextureRect = null
var form_text_block: Label = null
var unblockable_label: Label = null
var options_box: VBoxContainer = null
var block_button: Button = null
var skip_button: Button = null

var _buttons: Array[Button] = []
var _choice_ids: Array[String] = []
var _defender_id: String = ""


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(460.0, 0.0)
	add_theme_stylebox_override("panel", UI.panel_filled_style())

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	root.add_child(title_row)

	form_icon_rect = TextureRect.new()
	form_icon_rect.custom_minimum_size = Vector2(FORM_ICON_SIZE, FORM_ICON_SIZE)
	form_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	form_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	form_icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	form_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	form_icon_rect.visible = false
	title_row.add_child(form_icon_rect)

	form_text_block = Label.new()
	form_text_block.custom_minimum_size = Vector2(FORM_ICON_SIZE, FORM_ICON_SIZE)
	form_text_block.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	form_text_block.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	form_text_block.add_theme_stylebox_override("normal", UI.badge_style())
	UI.configure_label(form_text_block, 18, UI.GOLD_BRIGHT)
	form_text_block.visible = false
	title_row.add_child(form_text_block)

	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.add_theme_color_override("font_color", UI.GOLD_BRIGHT)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(title_label)

	form_name_label = Label.new()
	UI.configure_label(form_name_label, 20, UI.GOLD)
	title_row.add_child(form_name_label)

	unblockable_label = Label.new()
	unblockable_label.text = "不可破"
	unblockable_label.add_theme_stylebox_override("normal", UI.badge_style(UI.HP_RED))
	unblockable_label.add_theme_font_size_override("font_size", 14)
	unblockable_label.add_theme_color_override("font_color", UI.LOG_KILL)
	unblockable_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	unblockable_label.visible = false
	title_row.add_child(unblockable_label)

	options_box = VBoxContainer.new()
	options_box.add_theme_constant_override("separation", 4)
	root.add_child(options_box)


func open_for(
	attacker_name: String,
	move_name: String,
	relation_text: String,
	defender_id: String,
	options: Array,
	martials: Dictionary,
	energy_left: Dictionary,
	move: Dictionary = {}
) -> void:
	_defender_id = defender_id
	_set_form(TacticsForms.move_form(move))
	title_label.text = "%s 的 %s 来袭（%s）" % [attacker_name, move_name, relation_text]
	var unblockable := bool(move.get("unblockable", false))
	unblockable_label.visible = unblockable
	_clear_buttons()
	var block_id := str(TacticsRuleData.basic_block().get("id", ""))
	var neili_left := int(energy_left.get("neili", 0))
	if not unblockable:
		for raw_option in options:
			if not (raw_option is Dictionary):
				continue
			var option: Dictionary = raw_option
			var martial_id := str(option.get("id", ""))
			if martial_id == "" or martial_id == block_id:
				continue
			_add_martial_row(martial_id, martials.get(martial_id), option, neili_left)
	_add_block_row(block_id)
	_add_skip_row()
	visible = true


func close() -> void:
	visible = false
	_clear_buttons()


func _on_option(defender_id: String, martial_id: String) -> void:
	chosen.emit(defender_id, martial_id)


func _clear_buttons() -> void:
	for button in _buttons:
		if is_instance_valid(button):
			button.free()
	_buttons.clear()
	_choice_ids.clear()
	block_button = null
	skip_button = null


# 数字键 1~9 选中第 N 行；置灰的行不可选。返回是否处理。
func handle_key(keycode: int) -> bool:
	if not visible:
		return false
	var index := int(keycode) - int(KEY_1)
	if index < 0 or index > 8 or index >= _buttons.size():
		return false
	var button := _buttons[index]
	if button == null or not is_instance_valid(button) or button.disabled:
		return false
	_on_option(_defender_id, _choice_ids[index])
	return true


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if key_event.pressed and not key_event.echo:
		handle_key(key_event.keycode)


func _set_form(form: String) -> void:
	var form_text := TacticsForms.form_name(form)
	var texture: Texture2D = null
	if form != "":
		texture = UI.form_icon(form)
	form_icon_rect.visible = texture != null
	form_icon_rect.texture = texture
	form_text_block.visible = texture == null and form_text != ""
	form_text_block.text = form_text
	form_name_label.text = form_text


func _add_martial_row(martial_id: String, martial, option: Dictionary, neili_left: int) -> void:
	var outcome := str(option.get("outcome", "none"))
	var cost := TacticsEnergy.cost_for(martial)
	var poor := cost > neili_left
	var row: Array = _add_row(martial_id, MARTIAL_ROW_HEIGHT)
	var button: Button = row[0]
	var content: VBoxContainer = row[1]
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(line)
	var icon := UI.martial_icon(martial_id)
	if icon != null:
		_add_icon(line, icon, MARTIAL_ICON_SIZE)
	line.add_child(_label(_martial_name(martial_id, martial), 14, UI.TEXT))
	var badge_color := _badge_color(outcome)
	var badge := _label(_badge_text(outcome), 11, badge_color)
	badge.add_theme_stylebox_override("normal", UI.badge_style(badge_color))
	line.add_child(badge)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(spacer)
	var energy_icon := UI.energy_icon("neili")
	if energy_icon != null:
		_add_icon(line, energy_icon, COST_ICON_SIZE)
	var cost_label := _label(str(cost), 12, UI.MUTED if poor else UI.TEXT)
	line.add_child(cost_label)
	var poor_label: Label = null
	if poor:
		poor_label = _label("内力不足", 11, UI.MUTED)
		line.add_child(poor_label)
	content.add_child(_label(_effect_text(outcome), 11, UI.MUTED))
	button.set_meta("outcome", outcome)
	button.set_meta("cost", cost)
	button.set_meta("badge", badge)
	button.set_meta("cost_label", cost_label)
	button.set_meta("poor_label", poor_label)
	button.set_meta("poor", poor)
	if poor:
		button.disabled = true
		button.modulate = Color(0.55, 0.55, 0.55, 0.9)


# 基础格挡固定行：不耗内力、不反击，永远可选。
func _add_block_row(block_id: String) -> void:
	if block_id == "":
		return
	var block := TacticsRuleData.basic_block()
	var row: Array = _add_row(block_id, FIXED_ROW_HEIGHT)
	block_button = row[0]
	var content: VBoxContainer = row[1]
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(line)
	line.add_child(_label(str(block.get("name", "基础格挡")), 14, UI.TEXT))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(spacer)
	line.add_child(_label("不耗内力", 11, UI.MUTED))
	content.add_child(_label("减半伤害，不耗内力，不反击", 11, UI.MUTED))


func _add_skip_row() -> void:
	var row: Array = _add_row("", FIXED_ROW_HEIGHT)
	skip_button = row[0]
	var content: VBoxContainer = row[1]
	content.add_child(_label("不反制", 14, UI.TEXT))


# 一行选项：Button 负责悬停/置灰外观，内容放在铺满按钮的 VBox 里。
func _add_row(martial_id: String, row_height: float) -> Array:
	var button := _make_button()
	button.custom_minimum_size = Vector2(0.0, row_height)
	button.pressed.connect(_on_option.bind(_defender_id, martial_id))
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 5)
	button.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 0)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(content)
	options_box.add_child(button)
	_buttons.append(button)
	_choice_ids.append(martial_id)
	return [button, content]


func _make_button() -> Button:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", UI.TEXT)
	button.add_theme_color_override("font_hover_color", UI.GOLD_BRIGHT)
	button.add_theme_color_override("font_pressed_color", UI.GOLD_BRIGHT)
	button.add_theme_stylebox_override("normal", UI.button_style("normal"))
	button.add_theme_stylebox_override("hover", UI.button_style("hover"))
	button.add_theme_stylebox_override("pressed", UI.button_style("pressed"))
	button.add_theme_stylebox_override("disabled", UI.button_style("disabled"))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return button


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	UI.configure_label(label, font_size, color)
	return label


func _add_icon(line: HBoxContainer, texture: Texture2D, icon_size: int) -> void:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.custom_minimum_size = Vector2(float(icon_size), float(icon_size))
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(rect)


func _field(value, key: String) -> Variant:
	if value is Dictionary:
		return value.get(key, null)
	if value is Object:
		return value.get(key)
	return null


func _martial_name(martial_id: String, martial) -> String:
	var name_value: Variant = _field(martial, "name") if martial != null else null
	if name_value == null:
		return martial_id
	var name_text := str(name_value)
	return name_text if name_text != "" else martial_id


func _badge_text(outcome: String) -> String:
	match outcome:
		"perfect":
			return "完美破招"
		"counter":
			return "克制"
		"scrape":
			return "勉强"
		_:
			return "无"


func _badge_color(outcome: String) -> Color:
	match outcome:
		"perfect":
			return UI.GOLD_BRIGHT
		"counter":
			return UI.REACTION_CYAN
		"scrape":
			return UI.MUTED
		_:
			return UI.GOLD_DIM


# 结果说明取自 data/tactics_rules.json 的 result_table，数值不写死。
func _effect_text(outcome: String) -> String:
	var table := TacticsRuleData.result(outcome)
	var counter_pct := int(table.get("counter_pct", 0))
	var jianyi_points := int(table.get("jianyi", 0))
	var parts: Array[String] = []
	if counter_pct > 0:
		parts.append("抵消并反击 %d%% 伤害" % counter_pct)
	else:
		parts.append("承受 %d%% 伤害" % int(table.get("damage_pct", 100)))
	if jianyi_points > 0:
		parts.append("回 %d 点剑意" % jianyi_points)
	return "，".join(PackedStringArray(parts))

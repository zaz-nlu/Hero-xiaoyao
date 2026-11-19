extends PanelContainer

# 被攻击时的反制菜单（默认隐藏）。视图一次处理一个防守者；多个防守者时逐个
# 重新 open_for。选择武学或“不反制”后发出 chosen(defender_id, martial_id)，
# 空字符串代表不反制。

signal chosen(defender_id: String, martial_id: String)

const Counter = preload("res://core/counter.gd")
const TacticsEnergy = preload("res://core/tactics/tactics_energy.gd")
const TacticsRuleData = preload("res://core/tactics/tactics_rule_data.gd")
const UI = preload("res://features/tactics/tactics_ui_style.gd")

var title_label: Label = null
var options_box: VBoxContainer = null
var _buttons: Array[Button] = []


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(420.0, 0.0)
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

	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.add_theme_color_override("font_color", UI.GOLD_BRIGHT)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title_label)

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
	energy_left: Dictionary
) -> void:
	title_label.text = "%s 的 %s 来袭（%s）" % [attacker_name, move_name, relation_text]
	_clear_buttons()
	for raw_option in options:
		if not (raw_option is Dictionary):
			continue
		var option: Dictionary = raw_option
		var martial_id := str(option.get("id", ""))
		var martial_name := martial_id
		var martial = martials.get(martial_id)
		if martial != null:
			martial_name = str(martial.name)
		var uses_text := "不耗内力"
		if martial_id != str(TacticsRuleData.basic_block().get("id", "")):
			var cost := TacticsEnergy.cost_for(martial)
			uses_text = "内力 -%d（剩 %d）" % [cost, int(energy_left.get("neili", 0))]
		var text := "%s [%s]（%s）" % [
			martial_name, _verdict_text(option), uses_text]
		var button := _make_button(text, UI.martial_icon(martial_id))
		button.pressed.connect(_on_option.bind(defender_id, martial_id))
		options_box.add_child(button)
		_buttons.append(button)
	var skip := _make_button("不反制", null)
	skip.pressed.connect(_on_option.bind(defender_id, ""))
	options_box.add_child(skip)
	_buttons.append(skip)
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


func _make_button(text: String, icon: Texture2D) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0.0, 40.0)
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", UI.TEXT)
	button.add_theme_color_override("font_hover_color", UI.GOLD_BRIGHT)
	button.add_theme_color_override("font_pressed_color", UI.GOLD_BRIGHT)
	button.add_theme_stylebox_override("normal", UI.button_style("normal"))
	button.add_theme_stylebox_override("hover", UI.button_style("hover"))
	button.add_theme_stylebox_override("pressed", UI.button_style("pressed"))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if icon != null:
		button.icon = icon
		button.add_theme_constant_override("icon_max_width", 26)
	return button


func _verdict_text(option: Dictionary) -> String:
	if bool(option.get("perfect", false)):
		return "完美"
	var verdict := int(option.get("verdict", 0))
	if verdict == Counter.Verdict.ADVANTAGE:
		return "优势"
	if verdict == Counter.Verdict.BARELY:
		return "勉强"
	return "不可行"

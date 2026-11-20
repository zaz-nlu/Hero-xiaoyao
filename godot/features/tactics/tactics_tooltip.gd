extends PanelContainer

# 技能栏的悬停提示卡：武学名、威力/射程/当前能量消耗、可破形态图标与一句描述。
# 只负责显示；武学数据、当前能量与消耗文本由 tactics_panel 传入。

const UI = preload("res://features/tactics/tactics_ui_style.gd")
const MoveTypes = preload("res://core/move_types.gd")
const TacticsForms = preload("res://core/tactics/tactics_forms.gd")

const FORM_ICON_SIZE := 24
const GRADE_NAMES := {
	"common": "凡品",
	"fine": "精品",
	"rare": "珍品",
	"epic": "秘传",
	"legendary": "绝世",
}

var forms_label: Label = null
var _name_label: Label = null
var _stats_label: Label = null
var _desc_label: Label = null
var _forms_box: HBoxContainer = null
var _form_icons: Array[TextureRect] = []


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UI.tooltip_style())

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	_name_label = _make_label(15, UI.GOLD_BRIGHT)
	box.add_child(_name_label)

	_stats_label = _make_label(12, UI.TEXT)
	box.add_child(_stats_label)

	var forms_row := HBoxContainer.new()
	forms_row.add_theme_constant_override("separation", 4)
	forms_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(forms_row)

	forms_label = _make_label(11, UI.MUTED)
	forms_label.text = "可破形态："
	forms_row.add_child(forms_label)

	_forms_box = HBoxContainer.new()
	_forms_box.add_theme_constant_override("separation", 2)
	_forms_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	forms_row.add_child(_forms_box)

	_desc_label = _make_label(11, UI.MUTED)
	box.add_child(_desc_label)


# 填好内容并显示；位置由调用方按按钮位置摆放。
func show_for(data, martial_id: String, energy_name: String, cost_text: String) -> void:
	_name_label.text = _field_text(data, "name", martial_id)
	_stats_label.text = "威力 %d   ·   射程 %s   ·   %s消耗 %s" % [
		int(_field_value(data, "power", 0)), _range_text(data), energy_name, cost_text]
	_fill_forms(data)
	_desc_label.text = _describe(data)
	visible = true
	reset_size()


func form_icon_count() -> int:
	return _form_icons.size()


# 形态格数：有素材时是图标，缺素材时是中文名文字块，总是等于 martial_forms 数。
func form_slot_count() -> int:
	return _forms_box.get_child_count() if _forms_box != null else 0


func _fill_forms(data) -> void:
	for child in _forms_box.get_children():
		_forms_box.remove_child(child)
		child.free()
	_form_icons.clear()
	for raw_form in TacticsForms.martial_forms(data):
		var form := str(raw_form)
		var texture := UI.form_icon(form)
		if texture != null:
			var rect := TextureRect.new()
			rect.texture = texture
			rect.custom_minimum_size = Vector2(FORM_ICON_SIZE, FORM_ICON_SIZE)
			rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_forms_box.add_child(rect)
			_form_icons.append(rect)
			continue
		var text := TacticsForms.form_name(form)
		var label := _make_label(12, UI.TEXT)
		label.text = text if text != "" else form
		_forms_box.add_child(label)


func _range_text(data) -> String:
	var range_data: Variant = _field_value(data, "range", {})
	var min_range := 1
	var max_range := 1
	if range_data is Dictionary:
		var typed_range: Dictionary = range_data
		min_range = int(typed_range.get("min", 1))
		max_range = int(typed_range.get("max", min_range))
	if min_range != max_range:
		return "%d-%d" % [min_range, max_range]
	return str(max_range)


# 用 martials 数据里已有的字段拼一句描述：品阶 + 克制的招式类型。
func _describe(data) -> String:
	var grade := _field_text(data, "grade", "common")
	var parts: Array[String] = [str(GRADE_NAMES.get(grade, "凡品")) + "武学"]
	var counters: Variant = _field_value(data, "counters", [])
	if counters is Array and not counters.is_empty():
		var names := PackedStringArray()
		for raw in counters:
			names.append(str(MoveTypes.NAMES.get(str(raw), str(raw))))
		parts.append("克制" + "、".join(names))
	return "，".join(PackedStringArray(parts)) + "。"


func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	UI.configure_label(label, font_size, color)
	return label


func _field_value(value, key: String, fallback: Variant) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).get(key, fallback)
	if value is Object:
		return value.get(key)
	return fallback


func _field_text(value, key: String, fallback: String) -> String:
	var raw: Variant = _field_value(value, key, fallback)
	var text := str(raw) if raw != null else ""
	return text if text != "" else fallback

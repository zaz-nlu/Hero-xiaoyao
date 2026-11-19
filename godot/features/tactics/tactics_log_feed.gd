extends Control

# 左侧偏上的滚动日志：最近 5 条逐条飘出，每条 4 秒后淡出。
# 伤害类关键词着色：背面 / 侧面黄色，反制青色，击杀红色。

const UI = preload("res://features/tactics/tactics_ui_style.gd")

const MAX_LINES := 5
const FADE_DELAY := 4.0
const FADE_TIME := 0.6

var _box: VBoxContainer = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box = VBoxContainer.new()
	_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_box.add_theme_constant_override("separation", 4)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)


func add_line(text: String) -> void:
	_add_line(text, UI.TEXT)


# 淡色提示（键位、操作说明），与战斗日志共用滚动与淡出。
func add_hint(text: String) -> void:
	_add_line(text, UI.MUTED)


func _add_line(text: String, color: Color) -> void:
	if text == "":
		return
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.text = _format(text, color)
	label.fit_content = true
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("normal_font_size", 13)
	label.add_theme_color_override("default_color", UI.TEXT)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	_box.add_child(label)
	while _box.get_child_count() > MAX_LINES:
		_remove_oldest()
	_schedule_fade(label)


func line_count() -> int:
	return _box.get_child_count() if _box != null else 0


func clear() -> void:
	for child in _box.get_children():
		_box.remove_child(child)
		child.free()


func _format(text: String, color: Color) -> String:
	if text.contains("倒下") or text.contains("击杀") or text.contains("阵亡"):
		color = UI.LOG_KILL
	elif text.contains("反制") or text.contains("反击"):
		color = UI.LOG_REACTION
	elif text.contains("背面") or text.contains("侧面"):
		color = UI.LOG_SIDE
	return "[color=#%s]%s[/color]" % [color.to_html(false), _escape(text)]


func _escape(text: String) -> String:
	return text.replace("[", "[lb]")


func _schedule_fade(label: RichTextLabel) -> void:
	if not is_inside_tree():
		return
	var tween := label.create_tween()
	tween.tween_interval(FADE_DELAY)
	tween.tween_property(label, "modulate:a", 0.0, FADE_TIME)
	tween.tween_callback(Callable(label, "queue_free"))


func _remove_oldest() -> void:
	var oldest := _box.get_child(0)
	_box.remove_child(oldest)
	oldest.free()

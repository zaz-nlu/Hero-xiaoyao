extends RefCounted

# 战棋结算层：构建覆盖层、胜负统计与结果按钮（游戏内「继续」/沙盒「重来」）。日志已移到左侧的
# tactics_log_feed；本类只做结算展示，不调用战斗规则。

const UI = preload("res://features/tactics/tactics_ui_style.gd")

var overlay: Control = null
var result_label: Label = null
var stats_label: Label = null
var restart_button: Button = null


func build_overlay(parent: Control, restart_callback: Callable) -> void:
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.03, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)

	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", UI.panel_filled_style())
	center.add_child(plate)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(260.0, 0.0)
	plate.add_child(box)

	result_label = Label.new()
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 40)
	result_label.add_theme_color_override("font_color", UI.GOLD_BRIGHT)
	box.add_child(result_label)

	stats_label = Label.new()
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_label.add_theme_font_size_override("font_size", 16)
	stats_label.add_theme_color_override("font_color", UI.TEXT)
	box.add_child(stats_label)

	restart_button = Button.new()
	restart_button.text = "重来"
	restart_button.focus_mode = Control.FOCUS_NONE
	restart_button.custom_minimum_size = Vector2(120.0, 40.0)
	restart_button.add_theme_font_size_override("font_size", 16)
	restart_button.add_theme_color_override("font_color", UI.TEXT)
	restart_button.add_theme_color_override("font_hover_color", UI.GOLD_BRIGHT)
	restart_button.add_theme_stylebox_override("normal", UI.button_style("normal"))
	restart_button.add_theme_stylebox_override("hover", UI.button_style("hover"))
	restart_button.add_theme_stylebox_override("pressed", UI.button_style("pressed"))
	restart_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	restart_button.pressed.connect(restart_callback)
	box.add_child(restart_button)


func hide_result() -> void:
	if overlay != null:
		overlay.visible = false


func show_result(battle, action_text: String = "重来") -> void:
	if overlay == null:
		return
	restart_button.text = action_text
	var outcome: String = battle.result()
	var headline := "结束"
	if outcome == "win":
		headline = "胜利"
	elif outcome == "lose":
		headline = "战败"
	result_label.text = headline
	var lines: Array[String] = ["行动数：%d" % int(battle.round)]
	var hero = battle.get_unit("player")
	var percent := 0
	if hero != null and int(hero.unit.max_hp) > 0:
		percent = int(round(
			float(maxi(0, int(hero.unit.hp))) / float(hero.unit.max_hp) * 100.0))
	lines.append("剩余气血：%d%%" % percent)
	stats_label.text = "\n".join(lines)
	overlay.visible = true

extends RefCounted

# 角色面板各页签共用的样式与控件工具；视觉仍直接复用 shared/ui 的 Hud 样式。

const Hud = preload("res://shared/ui/battle_hud_style.gd")

const STAT_COLORS := {
	"power": Color(0.8, 0.34, 0.3),
	"speed": Color(0.86, 0.57, 0.3),
	"defense": Color(0.45, 0.56, 0.76),
	"recovery": Color(0.4, 0.7, 0.45),
	"skill": Color(0.86, 0.76, 0.42),
	"constitution": Color(0.62, 0.5, 0.72),
}
const BONUS_COLOR := Color(0.32, 0.82, 0.66)
const WARN_COLOR := Color(0.95, 0.85, 0.45)


static func make_label(
	parent: Node,
	node_name: String,
	pos: Vector2,
	label_size: Vector2,
	font_size: int,
	color: Color
) -> Label:
	var label := Label.new()
	label.name = node_name
	label.position = pos
	label.size = label_size
	Hud.configure_label(label, font_size, color)
	parent.add_child(label)
	return label


static func make_small_button(
	parent: Node, node_name: String, text: String, pos: Vector2, button_size: Vector2
) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.position = pos
	button.size = button_size
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override("normal", Hud.card_style(0.8))
	button.add_theme_stylebox_override("hover", Hud.card_hover_style())
	button.add_theme_stylebox_override("pressed", Hud.card_pressed_style())
	button.add_theme_stylebox_override("disabled", Hud.card_disabled_style())
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", Hud.TEXT)
	button.add_theme_color_override("font_hover_color", Hud.GOLD_BRIGHT)
	button.add_theme_color_override("font_pressed_color", Hud.GOLD_BRIGHT)
	button.add_theme_color_override("font_disabled_color", Hud.MUTED)
	button.add_theme_font_size_override("font_size", 14)
	parent.add_child(button)
	return button

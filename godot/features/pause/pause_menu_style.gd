extends RefCounted

# 暂停菜单的共用控件：标签、菜单按钮与选中/禁用态样式。

const Hud = preload("res://shared/ui/battle_hud_style.gd")


static func make_label(
	parent: Node, node_name: String, text: String, pos: Vector2,
	label_size: Vector2, font_size: int, color: Color
) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.position = pos
	label.size = label_size
	Hud.configure_label(label, font_size, color)
	parent.add_child(label)
	return label


static func make_menu_button(
	parent: Node, node_name: String, text: String, pos: Vector2, button_size: Vector2
) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.position = pos
	button.size = button_size
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", Hud.TEXT)
	button.add_theme_color_override("font_hover_color", Hud.GOLD_BRIGHT)
	button.add_theme_color_override("font_pressed_color", Hud.GOLD_BRIGHT)
	button.add_theme_color_override("font_disabled_color", Hud.MUTED)
	button.add_theme_stylebox_override("disabled", Hud.card_disabled_style())
	style_button(button, false)
	parent.add_child(button)
	return button


static func style_button(button: Button, selected: bool) -> void:
	var normal := Hud.card_hover_style() if selected else Hud.card_style(
		0.52, Color(0.78, 0.65, 0.35, 0.45)
	)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", Hud.card_hover_style())
	button.add_theme_stylebox_override("pressed", Hud.card_pressed_style())
	button.add_theme_stylebox_override("focus", Hud.card_style(0.0, Color(0.0, 0.0, 0.0, 0.0)))
	button.add_theme_color_override("font_color", Hud.GOLD_BRIGHT if selected else Hud.TEXT)


static func style_card(button: Button, selected: bool, disabled: bool) -> void:
	if disabled:
		button.add_theme_stylebox_override("normal", Hud.card_disabled_style())
		button.add_theme_stylebox_override("hover", Hud.card_disabled_style())
		return
	button.add_theme_stylebox_override(
		"normal", Hud.card_hover_style() if selected else Hud.card_style(0.82)
	)
	button.add_theme_stylebox_override("hover", Hud.card_hover_style())
	button.add_theme_stylebox_override("pressed", Hud.card_pressed_style())

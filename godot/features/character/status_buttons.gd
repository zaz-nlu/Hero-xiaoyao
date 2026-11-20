extends HBoxContainer

# 地图右上角的快捷按钮：角色 C / 任务 J / 背包 K。点击发出 pressed_key(key)，
# 由 status_overlay.gd 统一打开面板（与键盘快捷键走同一条路径）。

signal pressed_key(key: String)

const Hud = preload("res://shared/ui/battle_hud_style.gd")

const ENTRIES := [
	{"key": "C", "text": "角色"},
	{"key": "J", "text": "任务"},
	{"key": "K", "text": "背包"},
]
const BUTTON_SIZE := Vector2(86.0, 34.0)


func _init() -> void:
	name = "StatusButtons"
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_right = -14.0
	offset_left = -14.0 - (BUTTON_SIZE.x + 8.0) * float(ENTRIES.size())
	offset_top = 10.0
	offset_bottom = 10.0 + BUTTON_SIZE.y
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 8)
	for entry in ENTRIES:
		var key := str(entry["key"])
		var button := Button.new()
		button.name = "Btn_%s" % key
		button.text = "%s [%s]" % [entry["text"], key]
		button.custom_minimum_size = BUTTON_SIZE
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_stylebox_override("normal", Hud.card_style(0.85))
		button.add_theme_stylebox_override("hover", Hud.card_hover_style())
		button.add_theme_stylebox_override("pressed", Hud.card_pressed_style())
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		button.add_theme_color_override("font_color", Hud.TEXT)
		button.add_theme_color_override("font_hover_color", Hud.GOLD_BRIGHT)
		button.add_theme_font_size_override("font_size", 15)
		button.pressed.connect(pressed_key.emit.bind(key))
		add_child(button)

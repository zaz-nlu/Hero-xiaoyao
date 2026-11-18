extends RefCounted

# 战斗界面里跨模块共用的文案常量与小工具。

const HERB_COLOR := Color(0.45, 0.8, 0.4)
const HERB_HEAL_BASE := 30

const STAT_NAMES := {
	"power": "力道",
	"speed": "身法",
	"defense": "护体",
	"recovery": "养气",
	"skill": "剑术",
	"constitution": "体质",
}


# 气血数字在条上居中显示；位数多时自动缩小字号，避免大数字（如 5290）挤出标签。
static func fit_hp_label(label: Label, hp: int, max_hp: int, base_size: int) -> void:
	var text := "%d/%d" % [hp, max_hp]
	label.text = text
	var size := base_size
	if text.length() > 8:
		size = maxi(7, base_size - 3)
	elif text.length() > 5:
		size = maxi(8, base_size - 2)
	label.add_theme_font_size_override("font_size", size)

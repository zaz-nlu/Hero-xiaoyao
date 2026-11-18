extends RefCounted

# 属性页签：六项属性的数值条、加成段、最强标记与派生说明。

const CharacterData = preload("res://features/character/character_panel_data.gd")
const CharacterPanelStyle = preload("res://features/character/character_panel_style.gd")
const Hud = preload("res://shared/ui/battle_hud_style.gd")
const IconLib = preload("res://shared/ui/icon_lib.gd")
const Progression = preload("res://core/progression.gd")
const Stats = preload("res://core/stats.gd")

const STAT_DESC := {
	"power": "力量：提高武学伤害",
	"speed": "速度：决定出手快慢与先手",
	"defense": "防御：减少受到的伤害",
	"recovery": "恢复：每回合自然恢复气血",
	"skill": "技巧：决定反制是否来得及",
	"constitution": "体质：决定气血上限（气血 = 40 + 体质 × 每点气血）",
}

var _content: Control = null
var _data: Variant = null


func _init(content: Control, data: Variant) -> void:
	_content = content
	_data = data


func build() -> void:
	var base: Dictionary = _data.base_stats()
	var final_values: Dictionary = _data.final_stats()
	var top: Array = Stats.top_keys(final_values)
	var y := 2.0
	for key in CharacterData.STAT_KEYS:
		var base_value := int(base.get(key, 0))
		var total_value := int(final_values.get(key, 0))
		var bonus := total_value - base_value

		var stat_icon: Texture2D = IconLib.stat_icon(key)
		var icon_shift := 0.0
		if stat_icon != null:
			var icon_rect := TextureRect.new()
			icon_rect.name = "AttrIcon_%s" % key
			icon_rect.position = Vector2(0.0, y - 3.0)
			icon_rect.size = Vector2(28.0, 28.0)
			icon_rect.texture = stat_icon
			icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_content.add_child(icon_rect)
			icon_shift = 14.0
		else:
			var fallback := Panel.new()
			fallback.name = "AttrIcon_%s" % key
			fallback.position = Vector2(0.0, y + 3.0)
			fallback.size = Vector2(14.0, 14.0)
			fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
			fallback.add_theme_stylebox_override(
				"panel", Hud.circle_style(CharacterPanelStyle.STAT_COLORS[key], 7)
			)
			_content.add_child(fallback)

		var name_label := CharacterPanelStyle.make_label(
			_content,
			"AttrName_%s" % key,
			Vector2(22.0 + icon_shift, y),
			Vector2(42.0, 20.0),
			15,
			Hud.TEXT
		)
		name_label.text = str(CharacterData.STAT_NAMES[key])

		var bar_bg := Panel.new()
		bar_bg.name = "AttrBar_%s" % key
		bar_bg.position = Vector2(70.0 + icon_shift, y + 4.0)
		bar_bg.size = Vector2(230.0, 12.0)
		bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar_bg.add_theme_stylebox_override("panel", Hud.bar_bg_style())
		_content.add_child(bar_bg)

		var inner := 228.0
		var base_width := inner * clampf(float(base_value) / float(Progression.STAT_CAP), 0.0, 1.0)
		var total_width := inner * clampf(float(total_value) / float(Progression.STAT_CAP), 0.0, 1.0)
		if base_width > 0.0:
			var base_fill := ColorRect.new()
			base_fill.name = "AttrBaseFill_%s" % key
			base_fill.position = Vector2(1.0, 1.0)
			base_fill.size = Vector2(base_width, 10.0)
			base_fill.color = CharacterPanelStyle.STAT_COLORS[key]
			base_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bar_bg.add_child(base_fill)
		if total_width > base_width:
			var bonus_fill := ColorRect.new()
			bonus_fill.name = "AttrBonusFill_%s" % key
			bonus_fill.position = Vector2(1.0 + base_width, 1.0)
			bonus_fill.size = Vector2(total_width - base_width, 10.0)
			bonus_fill.color = CharacterPanelStyle.BONUS_COLOR
			bonus_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bar_bg.add_child(bonus_fill)

		var value_label := RichTextLabel.new()
		value_label.name = "AttrValue_%s" % key
		value_label.position = Vector2(312.0 + icon_shift, y)
		value_label.size = Vector2(116.0, 20.0)
		value_label.bbcode_enabled = true
		value_label.scroll_active = false
		value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		value_label.add_theme_font_size_override("normal_font_size", 15)
		value_label.add_theme_color_override("default_color", Hud.TEXT)
		if bonus != 0:
			value_label.text = "%d [color=%s](%s)[/color]" % [
				total_value, CharacterPanelStyle.BONUS_COLOR.to_html(false), _data.signed(bonus)
			]
		else:
			value_label.text = str(total_value)
		_content.add_child(value_label)

		var best_mark := CharacterPanelStyle.make_label(
			_content,
			"BestMark_%s" % key,
			Vector2(432.0 + icon_shift, y),
			Vector2(100.0, 20.0),
			14,
			Hud.GOLD_BRIGHT
		)
		if top.has(key):
			best_mark.text = "★ 最强"

		var desc := CharacterPanelStyle.make_label(
			_content,
			"AttrDesc_%s" % key,
			Vector2(70.0 + icon_shift, y + 20.0),
			Vector2(500.0, 16.0),
			12,
			Hud.MUTED
		)
		desc.text = str(STAT_DESC[key])
		y += 50.0

	var player: Dictionary = _data.player()
	var derived := CharacterPanelStyle.make_label(
		_content, "DerivedRow", Vector2(0.0, y + 2.0), Vector2(592.0, 20.0), 14, Hud.GOLD
	)
	derived.text = "派生：气血上限 %d · 剑意上限 %d · 料敌上限 %d" % [
		Progression.max_hp(_data.base_stats()),
		int(player.get("jianyi_max", 1)),
		int(player.get("foresight_max", 2)),
	]
	var hint := CharacterPanelStyle.make_label(
		_content, "PerfectHint", Vector2(0.0, y + 26.0), Vector2(592.0, 18.0), 12, Hud.MUTED
	)
	hint.text = "最强属性与武学的优势属性一致，且命中敌人弱点时，可打出『完美破招』"

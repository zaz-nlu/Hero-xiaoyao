extends RefCounted

# 武学页签：已装备槽、已学列表与选中武学的熟练度详情。
# 选中项随页签生命周期保留；交互后只发刷新请求，不直接驱动控制器。

signal refresh_requested

const CharacterPanelStyle = preload("res://features/character/character_panel_style.gd")
const Balance = preload("res://core/balance.gd")
const GameState = preload("res://core/game_state.gd")
const Hud = preload("res://shared/ui/battle_hud_style.gd")
const IconLib = preload("res://shared/ui/icon_lib.gd")
const Mastery = preload("res://core/mastery.gd")
const MoveTypes = preload("res://core/move_types.gd")
const Realms = preload("res://core/realms.gd")
const Stats = preload("res://core/stats.gd")

var _content: Control = null
var _data: Variant = null
var _selected_martial: String = ""


func _init(content: Control, data: Variant) -> void:
	_content = content
	_data = data


func build() -> void:
	CharacterPanelStyle.make_label(
		_content, "LoadoutHeader", Vector2(0.0, 0.0), Vector2(300.0, 22.0), 16, Hud.GOLD
	).text = "已装备武学"

	var player: Dictionary = _data.player()
	var loadout: Array = []
	var raw_loadout: Variant = player.get("loadout", [])
	if raw_loadout is Array:
		loadout = raw_loadout
	for i in range(4):
		var martial_id := ""
		if i < loadout.size():
			martial_id = str(loadout[i])
		var card := _build_martial_slot_card(i, martial_id)
		card.position = Vector2(float(i) * 114.0, 24.0)
		_content.add_child(card)

	CharacterPanelStyle.make_label(
		_content, "LearnedHeader", Vector2(0.0, 142.0), Vector2(220.0, 22.0), 16, Hud.GOLD
	).text = "武学列表"

	var learned: Array = []
	var raw_learned: Variant = player.get("learned", [])
	if raw_learned is Array:
		learned = raw_learned
	if _selected_martial == "" or not learned.has(_selected_martial):
		_selected_martial = str(learned[0]) if not learned.is_empty() else ""

	for i in range(learned.size()):
		var martial_id := str(learned[i])
		var button := Button.new()
		button.name = "MartialLearned_%s" % martial_id
		var learned_icon: Texture2D = IconLib.martial_icon(martial_id)
		button.text = str(_data.martial_name(martial_id))
		button.position = Vector2(0.0, 168.0 + float(i) * 32.0)
		button.size = Vector2(212.0, 26.0)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_NONE
		_style_list_button(button, martial_id == _selected_martial)
		if learned_icon != null:
			# leave room for the 32 px icon: widen the left content margin of every state style
			for state in ["normal", "hover", "pressed", "focus", "disabled"]:
				var base_style: StyleBox = button.get_theme_stylebox(state)
				if base_style is StyleBoxFlat:
					var padded: StyleBoxFlat = (base_style as StyleBoxFlat).duplicate()
					padded.content_margin_left = 42.0
					button.add_theme_stylebox_override(state, padded)
			var row_icon := TextureRect.new()
			row_icon.name = "MartialIcon_%s" % martial_id
			row_icon.position = Vector2(3.0, -3.0)
			row_icon.size = Vector2(32.0, 32.0)
			row_icon.texture = learned_icon
			row_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			row_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			row_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			row_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(row_icon)
		var grade := str(_data.martial_grade(martial_id))
		var grade_color := Mastery.grade_color(grade)
		button.add_theme_color_override("font_color", grade_color)
		button.add_theme_color_override("font_hover_color", grade_color.lightened(0.25))
		var grade_label := CharacterPanelStyle.make_label(
			button,
			"MartialGrade_%s" % martial_id,
			Vector2(150.0, 4.0),
			Vector2(56.0, 18.0),
			11,
			grade_color
		)
		grade_label.text = Mastery.grade_name(grade)
		grade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		button.pressed.connect(_on_martial_selected.bind(martial_id))
		_content.add_child(button)

	_build_martial_detail(_selected_martial)


func _build_martial_slot_card(index: int, martial_id: String) -> Control:
	var card := Panel.new()
	card.name = "MartialSlot_%d" % index
	card.size = Vector2(104.0, 104.0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", Hud.card_style(0.9))

	var key_label := CharacterPanelStyle.make_label(
		card, "SlotKey_%d" % index, Vector2(8.0, 3.0), Vector2(30.0, 16.0), 11, Hud.MUTED
	)
	key_label.text = str(index + 1)

	var icon_color: Color = Hud.MUTED
	if martial_id != "":
		icon_color = _martial_color(martial_id)
	var martial_icon: Texture2D = null
	if martial_id != "":
		martial_icon = IconLib.martial_icon(martial_id)
	if martial_icon != null:
		var icon_rect := TextureRect.new()
		icon_rect.name = "SlotIcon_%d" % index
		icon_rect.position = Vector2(24.0, 12.0)
		icon_rect.size = Vector2(56.0, 56.0)
		icon_rect.texture = martial_icon
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(icon_rect)
	else:
		var circle := Panel.new()
		circle.name = "SlotIcon_%d" % index
		circle.position = Vector2(30.0, 20.0)
		circle.size = Vector2(44.0, 44.0)
		circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		circle.add_theme_stylebox_override("panel", Hud.circle_style(icon_color, 22))
		card.add_child(circle)

		var glyph := CharacterPanelStyle.make_label(
			circle, "SlotGlyph_%d" % index, Vector2.ZERO, Vector2(44.0, 44.0), 20, Hud.TEXT
		)
		glyph.text = "空" if martial_id == "" else str(_data.martial_glyph(martial_id))
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var name_label := CharacterPanelStyle.make_label(
		card, "SlotName_%d" % index, Vector2(4.0, 72.0), Vector2(96.0, 24.0), 13, Hud.TEXT
	)
	name_label.text = "空" if martial_id == "" else str(_data.martial_name(martial_id))
	if martial_id != "":
		name_label.add_theme_color_override(
			"font_color", Mastery.grade_color(_data.martial_grade(martial_id))
		)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return card


func _build_martial_detail(martial_id: String) -> void:
	var panel := Panel.new()
	panel.name = "MartialDetail"
	panel.position = Vector2(236.0, 142.0)
	panel.size = Vector2(356.0, 300.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override(
		"panel", Hud.card_style(0.85, Color(0.78, 0.65, 0.35, 0.35))
	)
	_content.add_child(panel)

	var def: Variant = _data.martial_def(martial_id)
	if def == null:
		CharacterPanelStyle.make_label(
			panel, "DetailEmpty", Vector2(14.0, 14.0), Vector2(320.0, 24.0), 15, Hud.MUTED
		).text = "未习得任何武学"
		return

	var grade := str(def.grade)
	var grade_color := Mastery.grade_color(grade)
	var name_label := CharacterPanelStyle.make_label(
		panel, "DetailName", Vector2(14.0, 10.0), Vector2(328.0, 26.0), 20, grade_color
	)
	name_label.text = str(def.name)

	var per_level := Mastery.grade_per_level(grade)
	var cap := mini(Realms.mastery_cap(GameState.realm_id), Balance.MAX_LEVEL)
	var exp := maxi(int(GameState.mastery_total.get(martial_id, 0)), per_level)
	var progress: Dictionary = Mastery.progress_in_level(exp, grade, cap)
	var level := int(progress.get("level", 0))
	var into := int(progress.get("into", 0))
	var need := int(progress.get("need", 0))
	var capped := bool(progress.get("capped", false))

	CharacterPanelStyle.make_label(
		panel, "DetailLevel", Vector2(14.0, 40.0), Vector2(220.0, 20.0), 15, Hud.FORESIGHT_CYAN
	).text = "熟练度 Lv.%d（%s）" % [level, Mastery.grade_name(grade)]

	var bar := ProgressBar.new()
	bar.name = "DetailExpBar"
	bar.position = Vector2(14.0, 64.0)
	bar.size = Vector2(328.0, 12.0)
	bar.show_percentage = false
	bar.max_value = float(maxi(1, need))
	bar.value = float(into) if need > 0 else float(maxi(1, need))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", Hud.bar_bg_style())
	bar.add_theme_stylebox_override("fill", Hud.bar_fill_style(Hud.JIANYI_PURPLE))
	panel.add_child(bar)

	var exp_label := CharacterPanelStyle.make_label(
		panel, "DetailExp", Vector2(14.0, 78.0), Vector2(328.0, 18.0), 12, Hud.MUTED
	)
	if capped:
		exp_label.text = "已达当前境界上限（Lv.%d），突破后可继续" % level
	elif need <= 0:
		exp_label.text = "已满级"
	else:
		exp_label.text = "%d / %d" % [into, need]

	CharacterPanelStyle.make_label(
		panel, "DetailPower", Vector2(14.0, 100.0), Vector2(328.0, 20.0), 14, Hud.TEXT
	).text = "威力：%d" % int(def.power)
	CharacterPanelStyle.make_label(
		panel, "DetailCounters", Vector2(14.0, 124.0), Vector2(328.0, 20.0), 14, Hud.TEXT
	).text = "克制：%s" % _counter_names(def)

	var advantage := RichTextLabel.new()
	advantage.name = "DetailAdvantage"
	advantage.position = Vector2(14.0, 148.0)
	advantage.size = Vector2(328.0, 20.0)
	advantage.bbcode_enabled = true
	advantage.scroll_active = false
	advantage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	advantage.add_theme_font_size_override("normal_font_size", 14)
	advantage.add_theme_color_override("default_color", Hud.TEXT)
	var advantage_name: String = _data.stat_name(str(def.advantage_stat))
	if Stats.top_keys(_data.final_stats()).has(str(def.advantage_stat)):
		advantage.text = "优势属性：%s[color=%s]（你的最强属性）[/color]" % [
			advantage_name, Hud.GOLD_BRIGHT.to_html(false)
		]
	else:
		advantage.text = "优势属性：%s" % advantage_name
	panel.add_child(advantage)

	CharacterPanelStyle.make_label(
		panel, "DetailInitiative", Vector2(14.0, 172.0), Vector2(328.0, 20.0), 14, Hud.TEXT
	).text = "先手加成：%s" % _data.signed(int(def.initiative))
	CharacterPanelStyle.make_label(
		panel, "DetailCounterLevel", Vector2(14.0, 196.0), Vector2(328.0, 20.0), 14, Hud.TEXT
	).text = "反制等级：%d" % int(def.counter_level)

	CharacterPanelStyle.make_label(
		panel, "DetailCounterBonus", Vector2(14.0, 220.0), Vector2(328.0, 20.0), 14,
		CharacterPanelStyle.BONUS_COLOR
	).text = "反制强度 +%d" % Mastery.counter_bonus_at_level(level)

	var y := 244.0
	var effect_text := _effect_text(def)
	if effect_text != "":
		CharacterPanelStyle.make_label(
			panel, "DetailEffect", Vector2(14.0, y), Vector2(328.0, 20.0), 14,
			CharacterPanelStyle.WARN_COLOR
		).text = effect_text
		y += 24.0

	var bonus_percent := int(roundf(Mastery.damage_bonus_at_level(level) * 100.0))
	CharacterPanelStyle.make_label(
		panel, "DetailBonus", Vector2(14.0, y), Vector2(328.0, 20.0), 14,
		CharacterPanelStyle.BONUS_COLOR
	).text = "伤害加成 +%d%%" % bonus_percent


func _on_martial_selected(martial_id: String) -> void:
	_selected_martial = martial_id
	refresh_requested.emit()


func _counter_names(def: Variant) -> String:
	var names := PackedStringArray()
	for raw_type in def.counters:
		var type_id := str(raw_type)
		names.append(str(MoveTypes.NAMES.get(type_id, type_id)))
	return "、".join(names)


func _effect_text(def: Variant) -> String:
	for raw_effect in def.effects:
		if not (raw_effect is Dictionary):
			continue
		var effect: Dictionary = raw_effect
		if str(effect.get("kind", "")) == "reflect":
			var percent := int(roundf(float(effect.get("value", 0.0)) * 100.0))
			return "特殊效果：反震 %d%%" % percent
	return ""


func _martial_color(martial_id: String) -> Color:
	var def: Variant = _data.martial_def(martial_id)
	if def != null and not def.counters.is_empty():
		return Hud.move_type_color(str(def.counters[0]))
	return Color(0.52, 0.54, 0.62)


func _style_list_button(button: Button, selected: bool) -> void:
	if selected:
		button.add_theme_stylebox_override("normal", Hud.card_hover_style())
	else:
		button.add_theme_stylebox_override(
			"normal", Hud.card_style(0.55, Color(0.78, 0.65, 0.35, 0.35))
		)
	button.add_theme_stylebox_override("hover", Hud.card_hover_style())
	button.add_theme_stylebox_override("pressed", Hud.card_pressed_style())
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", Hud.GOLD_BRIGHT if selected else Hud.TEXT)
	button.add_theme_color_override("font_hover_color", Hud.GOLD_BRIGHT)
	button.add_theme_color_override("font_pressed_color", Hud.GOLD_BRIGHT)
	button.add_theme_font_size_override("font_size", 15)

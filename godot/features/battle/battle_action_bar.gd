extends RefCounted

# 战斗动作栏：武学卡与特殊动作卡（剑意/试探/预判/草药），含 badge 与 tooltip。
# 按键与点击只发信号，不直接驱动控制器。

signal martial_pressed(index: int)
signal special_pressed(kind: String)

const Battle = preload("res://core/battle.gd")
const BattleText = preload("res://features/battle/battle_text.gd")
const Counter = preload("res://core/counter.gd")
const Hud = preload("res://shared/ui/battle_hud_style.gd")
const HudDivider = preload("res://shared/ui/hud_divider.gd")
const IconLib = preload("res://shared/ui/icon_lib.gd")
const AiAssets = preload("res://shared/resources/ai_assets.gd")
const Jianyi = preload("res://core/jianyi.gd")
const Mastery = preload("res://core/mastery.gd")
const MoveTypes = preload("res://core/move_types.gd")
const OrnateBox = preload("res://shared/ui/ornate_box.gd")
const SkillSlot = preload("res://features/battle/skill_slot.gd")

const CARD_WIDTH := 82.0
const CARD_HEIGHT := 104.0
const SPECIAL_SLOT_JIANYI := 4
const SPECIAL_SLOT_PROBE := 5
const SPECIAL_SLOT_FORESIGHT := 6
const SPECIAL_SLOT_HERB := 7

var plate: OrnateBox = null
var martial_row: HBoxContainer = null
var martial_buttons: Array = []
var martial_badges: Array = []
var jianyi_button: Button = null
var probe_button: Button = null
var foresight_button: Button = null
var herb_button: Button = null
var jianyi_badge: Label = null
var probe_badge: Label = null
var foresight_badge: Label = null
var herb_badge: Label = null


# The hotbar: martial slots, a divider, then the special actions, on one lacquered plate.
func build(row: Container) -> void:
	plate = OrnateBox.new()
	plate.name = "SkillBar"
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_CENTER
	plate.add_theme_stylebox_override("panel", Hud.plate_style())
	row.add_child(plate)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(margin)

	var strip := HBoxContainer.new()
	strip.name = "CardStrip"
	strip.alignment = BoxContainer.ALIGNMENT_CENTER
	strip.add_theme_constant_override("separation", 6)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(strip)

	martial_row = HBoxContainer.new()
	martial_row.name = "MartialRow"
	martial_row.alignment = BoxContainer.ALIGNMENT_CENTER
	martial_row.add_theme_constant_override("separation", 8)
	martial_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(martial_row)

	strip.add_child(HudDivider.new())

	var special_row := HBoxContainer.new()
	special_row.name = "SpecialRow"
	special_row.add_theme_constant_override("separation", 8)
	special_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(special_row)
	_build_special_cards(special_row)


func rebuild(battle: Variant) -> void:
	for child in martial_row.get_children():
		child.free()
	martial_buttons.clear()
	martial_badges.clear()
	if battle == null:
		return
	for i in range(battle.loadout.size()):
		var id: String = str(battle.loadout[i])
		var button := _build_card_button(
			i, _martial_color(battle, id), _martial_glyph(battle, id), _martial_name(battle, id),
			"", Hud.GOLD, id
		)
		button.name = "MartialCard%d" % i
		button.tooltip_text = _martial_tooltip(battle, id)
		button.pressed.connect(_on_martial_pressed.bind(i))
		martial_row.add_child(button)
		martial_buttons.append(button)
		martial_badges.append(button.get_node("VerdictBadge"))


func refresh(battle: Variant, selected_target: int, dialogue_active: bool) -> void:
	if battle == null:
		return
	refresh_martials(battle, selected_target, dialogue_active)
	refresh_specials(battle, selected_target, dialogue_active)


func refresh_martials(battle: Variant, selected_target: int, dialogue_active: bool) -> void:
	var over: bool = battle.state() != Battle.State.ONGOING
	var target_alive: bool = _target_alive(battle, selected_target)
	var locked: bool = over or dialogue_active
	var intent_known: bool = battle.is_move_known(selected_target)
	for i in range(martial_buttons.size()):
		var button: Button = martial_buttons[i]
		var id: String = str(battle.loadout[i])
		var verdict: int = battle.preview(id, selected_target)
		if i < martial_badges.size():
			var badge: Label = martial_badges[i]
			if intent_known:
				_set_badge(badge, _verdict_mark(verdict), _verdict_color(verdict))
			else:
				_set_badge(badge, "？", Hud.MUTED)
		if intent_known:
			button.tooltip_text = _martial_tooltip(battle, id)
		else:
			button.tooltip_text = "%s\n出招未知，无法判断" % _martial_tooltip(battle, id)
		button.disabled = locked or not target_alive
		_set_card_look(button, button.disabled)


func refresh_specials(battle: Variant, selected_target: int, dialogue_active: bool) -> void:
	var over: bool = battle.state() != Battle.State.ONGOING
	var target_alive: bool = _target_alive(battle, selected_target)
	var locked: bool = over or dialogue_active
	var points: int = int(battle.player.jianyi_points)
	var cap: int = int(battle.player.jianyi_max)
	var can_strike := false
	if selected_target >= 0 and selected_target < battle.enemies.size():
		can_strike = Jianyi.can_strike(battle.player, battle.enemies[selected_target])
	jianyi_button.disabled = locked or not target_alive or not can_strike
	probe_button.disabled = locked or not target_alive
	_set_card_look(jianyi_button, jianyi_button.disabled)
	_set_card_look(probe_button, probe_button.disabled)
	if jianyi_badge != null:
		_set_badge(jianyi_badge, "%d/%d" % [points, cap], Hud.JIANYI_PURPLE.lightened(0.3))
	if probe_badge != null:
		_set_badge(probe_badge, "", Hud.TOUGH_GOLD)
	if foresight_button != null:
		foresight_button.disabled = locked or not battle.foresight_available()
		_set_card_look(foresight_button, foresight_button.disabled)
		foresight_button.tooltip_text = _foresight_tooltip(battle)
	if foresight_badge != null:
		_set_badge(
			foresight_badge,
			"%d/%d" % [int(battle.player.foresight_points), int(battle.player.foresight_max)],
			Hud.FORESIGHT_CYAN.lightened(0.3)
		)
	if herb_button != null:
		var herb_count: int = int(battle.inventory.get("herb", 0))
		var hp_full: bool = int(battle.player.hp) \
				>= int(battle.player.max_hp) - int(battle.player.wound)
		herb_button.disabled = locked or herb_count <= 0 or hp_full
		_set_card_look(herb_button, herb_button.disabled)
		herb_button.tooltip_text = _herb_tooltip(battle)
	if herb_badge != null:
		_set_badge(
			herb_badge,
			"×%d" % int(battle.inventory.get("herb", 0)),
			BattleText.HERB_COLOR.lightened(0.3)
		)


# ---------------------------------------------------------------- cards

func _build_special_cards(parent: Container) -> void:
	jianyi_button = _build_card_button(
		SPECIAL_SLOT_JIANYI, Hud.JIANYI_PURPLE, "剑", "剑意",
		"icon_special_jianyi.png", Hud.JIANYI_PURPLE
	)
	jianyi_button.name = "JianyiCard"
	jianyi_button.tooltip_text = "剑意：消耗一点剑意，对当前目标造成必中重伤。"
	jianyi_button.pressed.connect(_on_special_pressed.bind("jianyi"))
	parent.add_child(jianyi_button)
	jianyi_badge = jianyi_button.get_node("VerdictBadge")

	probe_button = _build_card_button(
		SPECIAL_SLOT_PROBE, Hud.TOUGH_GOLD, "探", "试探",
		"icon_special_probe.png", Hud.TOUGH_GOLD
	)
	probe_button.name = "ProbeCard"
	probe_button.tooltip_text = "试探：揭示当前目标下一招的弱点。"
	probe_button.pressed.connect(_on_special_pressed.bind("probe"))
	parent.add_child(probe_button)
	probe_badge = probe_button.get_node("VerdictBadge")

	foresight_button = _build_card_button(
		SPECIAL_SLOT_FORESIGHT, Hud.FORESIGHT_CYAN, "算", "预判",
		"icon_special_foresight.png", Hud.FORESIGHT_CYAN
	)
	foresight_button.name = "ForesightCard"
	foresight_button.tooltip_text = "料敌机先：花一回合看清所有敌人接下来两次出招（剩余 0 次）"
	foresight_button.pressed.connect(_on_special_pressed.bind("foresight"))
	parent.add_child(foresight_button)
	foresight_badge = foresight_button.get_node("VerdictBadge")

	herb_button = _build_card_button(
		SPECIAL_SLOT_HERB, BattleText.HERB_COLOR, "药", "草药",
		"icon_item_herbs.png", BattleText.HERB_COLOR
	)
	herb_button.name = "HerbCard"
	herb_button.tooltip_text = "草药：恢复气血（药效 %d，受恢复属性加成，剩余 0 份）" % BattleText.HERB_HEAL_BASE
	herb_button.pressed.connect(_on_special_pressed.bind("herb"))
	parent.add_child(herb_button)
	herb_badge = herb_button.get_node("VerdictBadge")


func _build_card_button(
	slot: int, icon_color: Color, glyph: String, title: String,
	icon_file: String = "", frame: Color = Hud.GOLD, martial_id: String = ""
) -> Button:
	var button := SkillSlot.new()
	button.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.text = ""
	button.clip_contents = false
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var texture: Texture2D = null
	var martial_icon: Texture2D = null
	if martial_id != "":
		martial_icon = IconLib.martial_icon(martial_id)
		if martial_icon != null:
			# 图标由下面的 TextureRect 绘制，SkillSlot 自绘的彩色圆/首字不再显示。
			texture = _empty_texture()
	elif icon_file != "":
		texture = AiAssets.load_texture(icon_file)
	button.setup(texture, icon_color, frame, glyph)
	if martial_icon != null:
		var icon_rect := TextureRect.new()
		icon_rect.name = "Icon"
		icon_rect.texture = martial_icon
		icon_rect.position = Vector2(15.0, 15.0)
		icon_rect.size = Vector2(52.0, 52.0)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(icon_rect)

	var key_label := Label.new()
	key_label.name = "KeyLabel"
	key_label.text = str(slot + 1)
	key_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	key_label.offset_left = 4.0
	key_label.offset_top = 4.0
	key_label.offset_right = 20.0
	key_label.offset_bottom = 20.0
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	key_label.add_theme_stylebox_override("normal", Hud.badge_style(frame))
	Hud.configure_label(key_label, 11, Hud.GOLD_BRIGHT)
	button.add_child(key_label)

	var badge := Label.new()
	badge.name = "VerdictBadge"
	badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	badge.offset_left = -42.0
	badge.offset_top = 4.0
	badge.offset_right = -4.0
	badge.offset_bottom = 20.0
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_stylebox_override("normal", Hud.badge_style(frame))
	Hud.configure_label(badge, 11, Hud.GOLD_BRIGHT)
	badge.visible = false
	button.add_child(badge)

	var name_label := Label.new()
	name_label.name = "CardName"
	name_label.text = title
	name_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	name_label.offset_top = -28.0
	name_label.offset_bottom = -4.0
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Hud.configure_label(name_label, 13, Hud.TEXT)
	button.add_child(name_label)

	return button


func _empty_texture() -> Texture2D:
	var image := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	image.set_pixel(0, 0, Color(0.0, 0.0, 0.0, 0.0))
	return ImageTexture.create_from_image(image)


func _set_badge(label: Label, text: String, color: Color) -> void:
	if label == null:
		return
	label.text = text
	label.visible = text != ""
	label.add_theme_color_override("font_color", color)


func _set_card_look(button: Button, dimmed: bool) -> void:
	if button == null:
		return
	button.modulate = Color(0.55, 0.55, 0.62, 0.8) if dimmed else Color.WHITE


func _target_alive(battle: Variant, selected_target: int) -> bool:
	if selected_target < 0 or selected_target >= battle.enemies.size():
		return false
	var target: Variant = battle.enemies[selected_target]
	return not target.is_dead()


# ---------------------------------------------------------------- text

func _martial_name(battle: Variant, id: String) -> String:
	if battle != null and battle.martials.has(id):
		return str(battle.martials[id].name)
	return id


func _martial_glyph(battle: Variant, id: String) -> String:
	var name_text: String = _martial_name(battle, id)
	if name_text.is_empty():
		return "?"
	return name_text.substr(0, 1)


func _martial_color(battle: Variant, id: String) -> Color:
	if battle != null and battle.martials.has(id):
		var counters: Variant = battle.martials[id].counters
		if counters is Array and not counters.is_empty():
			return Hud.move_type_color(str(counters[0]))
	return Color(0.52, 0.54, 0.62)


func _martial_tooltip(battle: Variant, id: String) -> String:
	if battle == null or not battle.martials.has(id):
		return id
	var martial: Variant = battle.martials[id]
	var lines := PackedStringArray()
	lines.append(str(martial.name))
	var mastery_level := 0
	if battle.mastery != null:
		mastery_level = int(battle.mastery.level(id))
	lines.append("品阶：%s · Lv.%d" % [Mastery.grade_name(str(martial.grade)), mastery_level])
	lines.append("伤害 %d · 先手 %d" % [int(martial.power), int(martial.initiative)])
	var counters := PackedStringArray()
	for raw_counter_id in martial.counters:
		var counter_id: String = str(raw_counter_id)
		counters.append(str(MoveTypes.NAMES.get(counter_id, counter_id)))
	if not counters.is_empty():
		lines.append("反制：%s" % ", ".join(counters))
	lines.append(
		"比试：%s（%d 级）" % [_stat_name(str(martial.advantage_stat)), int(martial.counter_level)]
	)
	for raw_effect in martial.effects:
		var effect: Dictionary = raw_effect
		if str(effect.get("kind", "")) == "reflect":
			lines.append(
				"效果：反弹 %d%% 伤害" % int(roundf(float(effect.get("value", 0.0)) * 100.0))
			)
	return "\n".join(lines)


func _foresight_tooltip(battle: Variant) -> String:
	var left: int = 0
	if battle != null and battle.player != null:
		left = int(battle.player.foresight_points)
	return "料敌机先：花一回合看清所有敌人接下来两次出招（剩余 %d 次）" % left


func _herb_tooltip(battle: Variant) -> String:
	var left: int = 0
	if battle != null:
		left = int(battle.inventory.get("herb", 0))
	return "草药：恢复气血（药效 %d，受恢复属性加成，剩余 %d 份）" % [
		BattleText.HERB_HEAL_BASE, left
	]


func _stat_name(stat_id: String) -> String:
	return str(BattleText.STAT_NAMES.get(stat_id, stat_id))


func _verdict_mark(verdict: int) -> String:
	match verdict:
		Counter.Verdict.ADVANTAGE:
			return "✅"
		Counter.Verdict.BARELY:
			return "⚠"
		_:
			return "❌"


func _verdict_color(verdict: int) -> Color:
	match verdict:
		Counter.Verdict.ADVANTAGE:
			return Color(0.55, 0.95, 0.65)
		Counter.Verdict.BARELY:
			return Color(0.95, 0.9, 0.7)
		_:
			return Color(0.95, 0.45, 0.4)


func _on_martial_pressed(index: int) -> void:
	martial_pressed.emit(index)


func _on_special_pressed(kind: String) -> void:
	special_pressed.emit(kind)

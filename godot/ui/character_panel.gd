extends Panel

# 角色面板：四页签（属性 / 技能 / 装备 / 加点）。
# 由 status_overlay.gd 持有；对外提供 refresh()/select_tab()/advance() 与 tab_index、pending_points。

const Progression = preload("res://core/progression.gd")
const GameState = preload("res://core/game_state.gd")
const Mastery = preload("res://core/mastery.gd")
const DataLoader = preload("res://core/data_loader.gd")
const MoveTypes = preload("res://core/move_types.gd")
const Balance = preload("res://core/balance.gd")
const Stats = preload("res://core/stats.gd")
const Realms = preload("res://core/realms.gd")
const ImageCache = preload("res://ui/image_cache.gd")
const Hud = preload("res://ui/battle_hud_style.gd")

const PLAYER_PATH := "res://data/player.json"
const MARTIALS_PATH := "res://data/martials.json"
const PORTRAIT_PATH := "res://assets/portraits/ren_xiaoyao.png"

const PANEL_WIDTH := 880.0
const PANEL_HEIGHT := 540.0
const LEFT_WIDTH := 240.0
const CONTENT_X := 264.0
const CONTENT_Y := 64.0
const CONTENT_WIDTH := 592.0
const CONTENT_HEIGHT := 452.0

const TAB_COUNT := 4
const TAB_NAMES := ["属性", "技能", "装备", "加点"]
const TAB_WIDTH := 100.0
const TAB_STEP := 108.0
const TAB_HEIGHT := 32.0
const FADE_TIME := 0.12

const STAT_KEYS: Array[String] = ["power", "speed", "defense", "recovery", "skill", "constitution"]
const STAT_NAMES := {
	"power": "力量",
	"speed": "速度",
	"defense": "防御",
	"recovery": "恢复",
	"skill": "技巧",
	"constitution": "体质",
}
const STAT_COLORS := {
	"power": Color(0.8, 0.34, 0.3),
	"speed": Color(0.86, 0.57, 0.3),
	"defense": Color(0.45, 0.56, 0.76),
	"recovery": Color(0.4, 0.7, 0.45),
	"skill": Color(0.86, 0.76, 0.42),
	"constitution": Color(0.62, 0.5, 0.72),
}
const STAT_DESC := {
	"power": "力量：提高武学伤害",
	"speed": "速度：决定出手快慢与先手",
	"defense": "防御：减少受到的伤害",
	"recovery": "恢复：每回合自然恢复气血",
	"skill": "技巧：决定反制是否来得及",
	"constitution": "体质：决定气血上限（气血 = 40 + 体质 × 每点气血）",
}
const SLOT_KEYS: Array[String] = ["weapon", "armor", "accessory"]
const SLOT_NAMES := {
	"weapon": "武器",
	"armor": "防具",
	"accessory": "饰品",
}
const KIND_NAMES := {
	"weapon": "武器",
	"armor": "防具",
	"accessory": "饰品",
	"material": "材料",
	"consumable": "丹药",
}
const SLOT_COLORS := {
	"weapon": Color(0.72, 0.6, 0.38),
	"armor": Color(0.42, 0.58, 0.72),
	"accessory": Color(0.62, 0.46, 0.72),
}

const BONUS_COLOR := Color(0.32, 0.82, 0.66)
const WARN_COLOR := Color(0.95, 0.85, 0.45)
const RED_DOT_COLOR := Color(0.9, 0.32, 0.3)

var tab_index: int = 0
var pending_points: Dictionary = {}

var _content_root: Control = null
var _tab_buttons: Array[Button] = []
var _name_label: Label = null
var _realm_label: Label = null
var _age_label: Label = null
var _hp_bar: ProgressBar = null
var _hp_label: Label = null
var _jianyi_label: Label = null
var _foresight_label: Label = null
var _unspent_label: Label = null
var _selected_martial: String = ""
var _martial_def_cache: Dictionary = {}
var _content_fade: float = 1.0


func _init() -> void:
	name = "CharacterPanel"
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -PANEL_WIDTH * 0.5
	offset_right = PANEL_WIDTH * 0.5
	offset_top = -PANEL_HEIGHT * 0.5
	offset_bottom = PANEL_HEIGHT * 0.5
	add_theme_stylebox_override("panel", Hud.panel_style(0.94, Hud.GOLD, 8))
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_static()


func refresh() -> void:
	_update_left_column()
	_update_tab_bar()
	_rebuild_content()
	_content_fade = 1.0
	if _content_root != null:
		_content_root.modulate = Color(1.0, 1.0, 1.0, 1.0)


func select_tab(index: int) -> void:
	tab_index = clampi(index, 0, TAB_COUNT - 1)
	_update_tab_bar()
	_rebuild_content()
	_content_fade = 0.0
	if _content_root != null:
		_content_root.modulate = Color(1.0, 1.0, 1.0, 0.0)


func advance(delta: float) -> void:
	if _content_root == null or _content_fade >= 1.0:
		return
	_content_fade = minf(1.0, _content_fade + delta / FADE_TIME)
	_content_root.modulate = Color(1.0, 1.0, 1.0, _content_fade)


func handle_key(code: int) -> bool:
	match code:
		KEY_TAB:
			select_tab((tab_index + 1) % TAB_COUNT)
			return true
		KEY_E:
			select_tab((tab_index + 1) % TAB_COUNT)
			return true
		KEY_Q:
			select_tab((tab_index + TAB_COUNT - 1) % TAB_COUNT)
			return true
		KEY_1, KEY_2, KEY_3, KEY_4:
			select_tab(code - KEY_1)
			return true
	return false


# ---------------------------------------------------------------- static shell

func _build_static() -> void:
	_build_portrait()
	_name_label = _make_label(self, "CharName", Vector2(22.0, 316.0), Vector2(196.0, 34.0), 26, Hud.GOLD_BRIGHT)
	_realm_label = _make_label(self, "CharRealm", Vector2(22.0, 350.0), Vector2(196.0, 20.0), 15, Hud.MUTED)
	_realm_label.text = "初出茅庐"
	_age_label = _make_label(self, "CharAge", Vector2(22.0, 368.0), Vector2(196.0, 14.0), 12, Hud.MUTED)

	_hp_bar = ProgressBar.new()
	_hp_bar.name = "HpBar"
	_hp_bar.position = Vector2(22.0, 384.0)
	_hp_bar.custom_minimum_size = Vector2(140.0, 12.0)
	_hp_bar.size = Vector2(140.0, 12.0)
	_hp_bar.show_percentage = false
	_hp_bar.max_value = 100.0
	_hp_bar.value = 100.0
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_bar.add_theme_stylebox_override("background", Hud.bar_bg_style())
	_hp_bar.add_theme_stylebox_override("fill", Hud.bar_fill_style(Hud.HP_RED))
	add_child(_hp_bar)

	_hp_label = _make_label(self, "HpValue", Vector2(166.0, 381.0), Vector2(56.0, 20.0), 12, Hud.TEXT)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_jianyi_label = _make_label(self, "JianyiValue", Vector2(22.0, 418.0), Vector2(200.0, 20.0), 14, Hud.JIANYI_PURPLE)
	_foresight_label = _make_label(self, "ForesightValue", Vector2(22.0, 442.0), Vector2(200.0, 20.0), 14, Hud.FORESIGHT_CYAN)
	_unspent_label = _make_label(self, "UnspentPoints", Vector2(22.0, 504.0), Vector2(196.0, 18.0), 12, Hud.MUTED)
	_unspent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var divider := ColorRect.new()
	divider.name = "Divider"
	divider.position = Vector2(250.0, 20.0)
	divider.size = Vector2(1.0, 500.0)
	divider.color = Color(0.78, 0.65, 0.35, 0.35)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(divider)

	_build_tab_bar()

	_content_root = Control.new()
	_content_root.name = "TabContent"
	_content_root.position = Vector2(CONTENT_X, CONTENT_Y)
	_content_root.size = Vector2(CONTENT_WIDTH, CONTENT_HEIGHT)
	add_child(_content_root)


func _build_portrait() -> void:
	var texture: Texture2D = ImageCache.texture(PORTRAIT_PATH)
	if texture != null:
		var portrait := TextureRect.new()
		portrait.name = "Portrait"
		portrait.position = Vector2(22.0, 72.0)
		portrait.size = Vector2(196.0, 240.0)
		portrait.texture = texture
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(portrait)
	else:
		var fallback := ColorRect.new()
		fallback.name = "PortraitFallback"
		fallback.position = Vector2(22.0, 72.0)
		fallback.size = Vector2(196.0, 240.0)
		fallback.color = Color(0.16, 0.14, 0.2, 1.0)
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(fallback)


func _build_tab_bar() -> void:
	for i in range(TAB_COUNT):
		var button := Button.new()
		button.name = "Tab_%d" % i
		button.text = str(TAB_NAMES[i])
		button.position = Vector2(CONTENT_X + float(i) * TAB_STEP, 16.0)
		button.size = Vector2(TAB_WIDTH, TAB_HEIGHT)
		button.focus_mode = Control.FOCUS_NONE
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		_style_tab_button(button)
		button.pressed.connect(select_tab.bind(i))
		add_child(button)
		_tab_buttons.append(button)

		var underline := ColorRect.new()
		underline.name = "Underline"
		underline.position = Vector2(10.0, TAB_HEIGHT - 3.0)
		underline.size = Vector2(TAB_WIDTH - 20.0, 2.0)
		underline.color = Hud.GOLD_BRIGHT
		underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		underline.visible = i == 0
		button.add_child(underline)

		if i == 3:
			var dot := Label.new()
			dot.name = "PointsDot"
			dot.text = "●"
			dot.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			dot.offset_left = -18.0
			dot.offset_top = 0.0
			dot.offset_right = -4.0
			dot.offset_bottom = 16.0
			dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			dot.add_theme_font_size_override("font_size", 10)
			dot.add_theme_color_override("font_color", RED_DOT_COLOR)
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(dot)


# ---------------------------------------------------------------- shared refresh

func _update_left_column() -> void:
	var player: Dictionary = _player()
	if _name_label != null:
		_name_label.text = str(player.get("name", "任逍遥"))
	if _realm_label != null:
		var realm_text := Realms.name_of(GameState.realm_id)
		var stage_text := Realms.stage_name(GameState.realm_stage)
		if stage_text != "":
			realm_text += "·" + stage_text
		_realm_label.text = realm_text
	if _age_label != null:
		_age_label.text = "年龄 %d" % GameState.age
	var max_hp := Progression.max_hp(_base_stats())
	if _hp_bar != null:
		_hp_bar.max_value = maxf(1.0, float(max_hp))
		_hp_bar.value = float(max_hp)
	if _hp_label != null:
		_hp_label.text = "%d/%d" % [max_hp, max_hp]
	if _jianyi_label != null:
		var jianyi_max := int(player.get("jianyi_max", 1))
		_jianyi_label.text = "剑意 " + "●".repeat(maxi(0, jianyi_max))
	if _foresight_label != null:
		var foresight_max := int(player.get("foresight_max", 2))
		_foresight_label.text = "料敌 " + "●".repeat(maxi(0, foresight_max))
	if _unspent_label != null:
		var points := GameState.unspent_points
		_unspent_label.text = "可分配点数：%d" % points
		_unspent_label.add_theme_color_override(
			"font_color", Hud.GOLD_BRIGHT if points > 0 else Hud.MUTED
		)


func _update_tab_bar() -> void:
	for i in range(_tab_buttons.size()):
		var button: Button = _tab_buttons[i]
		var selected := i == tab_index
		button.add_theme_color_override("font_color", Hud.GOLD_BRIGHT if selected else Hud.MUTED)
		button.add_theme_color_override("font_hover_color", Hud.GOLD_BRIGHT)
		button.add_theme_color_override("font_pressed_color", Hud.GOLD_BRIGHT)
		var underline: Variant = button.get_node_or_null("Underline")
		if underline is ColorRect:
			var line: ColorRect = underline
			line.visible = selected
		var dot: Variant = button.get_node_or_null("PointsDot")
		if dot is Label:
			var dot_label: Label = dot
			dot_label.visible = i == 3 and GameState.unspent_points > 0


func _rebuild_content() -> void:
	if _content_root == null:
		return
	_clear_children(_content_root)
	match tab_index:
		0:
			_build_attributes_tab()
		1:
			_build_skills_tab()
		2:
			_build_equipment_tab()
		3:
			_build_points_tab()


# ---------------------------------------------------------------- attributes tab

func _build_attributes_tab() -> void:
	var base: Dictionary = _base_stats()
	var final_values: Dictionary = Progression.final_stats(base)
	var top: Array = Stats.top_keys(final_values)
	var y := 2.0
	for key in STAT_KEYS:
		var base_value := int(base.get(key, 0))
		var total_value := int(final_values.get(key, 0))
		var bonus := total_value - base_value

		var icon := Panel.new()
		icon.name = "AttrIcon_%s" % key
		icon.position = Vector2(0.0, y + 3.0)
		icon.size = Vector2(14.0, 14.0)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.add_theme_stylebox_override("panel", Hud.circle_style(STAT_COLORS[key], 7))
		_content_root.add_child(icon)

		var name_label := _make_label(
			_content_root, "AttrName_%s" % key, Vector2(22.0, y), Vector2(42.0, 20.0), 15, Hud.TEXT
		)
		name_label.text = str(STAT_NAMES[key])

		var bar_bg := Panel.new()
		bar_bg.name = "AttrBar_%s" % key
		bar_bg.position = Vector2(70.0, y + 4.0)
		bar_bg.size = Vector2(230.0, 12.0)
		bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar_bg.add_theme_stylebox_override("panel", Hud.bar_bg_style())
		_content_root.add_child(bar_bg)

		var inner := 228.0
		var base_width := inner * clampf(float(base_value) / float(Progression.STAT_CAP), 0.0, 1.0)
		var total_width := inner * clampf(float(total_value) / float(Progression.STAT_CAP), 0.0, 1.0)
		if base_width > 0.0:
			var base_fill := ColorRect.new()
			base_fill.name = "AttrBaseFill_%s" % key
			base_fill.position = Vector2(1.0, 1.0)
			base_fill.size = Vector2(base_width, 10.0)
			base_fill.color = STAT_COLORS[key]
			base_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bar_bg.add_child(base_fill)
		if total_width > base_width:
			var bonus_fill := ColorRect.new()
			bonus_fill.name = "AttrBonusFill_%s" % key
			bonus_fill.position = Vector2(1.0 + base_width, 1.0)
			bonus_fill.size = Vector2(total_width - base_width, 10.0)
			bonus_fill.color = BONUS_COLOR
			bonus_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bar_bg.add_child(bonus_fill)

		var value_label := RichTextLabel.new()
		value_label.name = "AttrValue_%s" % key
		value_label.position = Vector2(312.0, y)
		value_label.size = Vector2(116.0, 20.0)
		value_label.bbcode_enabled = true
		value_label.scroll_active = false
		value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		value_label.add_theme_font_size_override("normal_font_size", 15)
		value_label.add_theme_color_override("default_color", Hud.TEXT)
		if bonus != 0:
			value_label.text = "%d [color=%s](%s)[/color]" % [
				total_value, BONUS_COLOR.to_html(false), _signed(bonus)
			]
		else:
			value_label.text = str(total_value)
		_content_root.add_child(value_label)

		var best_mark := _make_label(
			_content_root, "BestMark_%s" % key, Vector2(432.0, y), Vector2(100.0, 20.0), 14, Hud.GOLD_BRIGHT
		)
		if top.has(key):
			best_mark.text = "★ 最强"

		var desc := _make_label(
			_content_root, "AttrDesc_%s" % key, Vector2(70.0, y + 20.0), Vector2(500.0, 16.0), 12, Hud.MUTED
		)
		desc.text = str(STAT_DESC[key])
		y += 50.0

	var player: Dictionary = _player()
	var derived := _make_label(
		_content_root, "DerivedRow", Vector2(0.0, y + 2.0), Vector2(592.0, 20.0), 14, Hud.GOLD
	)
	derived.text = "派生：气血上限 %d · 剑意上限 %d · 料敌上限 %d" % [
		Progression.max_hp(_base_stats()),
		int(player.get("jianyi_max", 1)),
		int(player.get("foresight_max", 2)),
	]
	var hint := _make_label(
		_content_root, "PerfectHint", Vector2(0.0, y + 26.0), Vector2(592.0, 18.0), 12, Hud.MUTED
	)
	hint.text = "最强属性与武学的优势属性一致，且命中敌人弱点时，可打出『完美破招』"


# ---------------------------------------------------------------- skills tab

func _build_skills_tab() -> void:
	_make_label(
		_content_root, "LoadoutHeader", Vector2(0.0, 0.0), Vector2(300.0, 22.0), 16, Hud.GOLD
	).text = "已装备武学"

	var player: Dictionary = _player()
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
		_content_root.add_child(card)

	_make_label(
		_content_root, "LearnedHeader", Vector2(0.0, 142.0), Vector2(220.0, 22.0), 16, Hud.GOLD
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
		button.text = _martial_name(martial_id)
		button.position = Vector2(0.0, 168.0 + float(i) * 32.0)
		button.size = Vector2(212.0, 26.0)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_NONE
		_style_list_button(button, martial_id == _selected_martial)
		var grade := _martial_grade(martial_id)
		var grade_color := Mastery.grade_color(grade)
		button.add_theme_color_override("font_color", grade_color)
		button.add_theme_color_override("font_hover_color", grade_color.lightened(0.25))
		var grade_label := _make_label(
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
		_content_root.add_child(button)

	_build_martial_detail(_selected_martial)


func _build_martial_slot_card(index: int, martial_id: String) -> Control:
	var card := Panel.new()
	card.name = "MartialSlot_%d" % index
	card.size = Vector2(104.0, 104.0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", Hud.card_style(0.9))

	var key_label := _make_label(card, "SlotKey_%d" % index, Vector2(8.0, 3.0), Vector2(30.0, 16.0), 11, Hud.MUTED)
	key_label.text = str(index + 1)

	var icon_color: Color = Hud.MUTED
	if martial_id != "":
		icon_color = _martial_color(martial_id)
	var circle := Panel.new()
	circle.name = "SlotIcon_%d" % index
	circle.position = Vector2(30.0, 20.0)
	circle.size = Vector2(44.0, 44.0)
	circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	circle.add_theme_stylebox_override("panel", Hud.circle_style(icon_color, 22))
	card.add_child(circle)

	var glyph := _make_label(circle, "SlotGlyph_%d" % index, Vector2.ZERO, Vector2(44.0, 44.0), 20, Hud.TEXT)
	glyph.text = "空" if martial_id == "" else _martial_glyph(martial_id)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var name_label := _make_label(card, "SlotName_%d" % index, Vector2(4.0, 72.0), Vector2(96.0, 24.0), 13, Hud.TEXT)
	name_label.text = "空" if martial_id == "" else _martial_name(martial_id)
	if martial_id != "":
		name_label.add_theme_color_override(
			"font_color", Mastery.grade_color(_martial_grade(martial_id))
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
	_content_root.add_child(panel)

	var def: Variant = _martial_def(martial_id)
	if def == null:
		_make_label(panel, "DetailEmpty", Vector2(14.0, 14.0), Vector2(320.0, 24.0), 15, Hud.MUTED).text = "未习得任何武学"
		return

	var grade := str(def.grade)
	var grade_color := Mastery.grade_color(grade)
	var name_label := _make_label(panel, "DetailName", Vector2(14.0, 10.0), Vector2(328.0, 26.0), 20, grade_color)
	name_label.text = str(def.name)

	var per_level := Mastery.grade_per_level(grade)
	var cap := mini(Realms.mastery_cap(GameState.realm_id), Balance.MAX_LEVEL)
	var exp := maxi(int(GameState.mastery_total.get(martial_id, 0)), per_level)
	var progress: Dictionary = Mastery.progress_in_level(exp, grade, cap)
	var level := int(progress.get("level", 0))
	var into := int(progress.get("into", 0))
	var need := int(progress.get("need", 0))
	var capped := bool(progress.get("capped", false))

	_make_label(panel, "DetailLevel", Vector2(14.0, 40.0), Vector2(220.0, 20.0), 15, Hud.FORESIGHT_CYAN).text = \
		"熟练度 Lv.%d（%s）" % [level, Mastery.grade_name(grade)]

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

	var exp_label := _make_label(panel, "DetailExp", Vector2(14.0, 78.0), Vector2(328.0, 18.0), 12, Hud.MUTED)
	if capped:
		exp_label.text = "已达当前境界上限（Lv.%d），突破后可继续" % level
	elif need <= 0:
		exp_label.text = "已满级"
	else:
		exp_label.text = "%d / %d" % [into, need]

	_make_label(panel, "DetailPower", Vector2(14.0, 100.0), Vector2(328.0, 20.0), 14, Hud.TEXT).text = \
		"威力：%d" % int(def.power)
	_make_label(panel, "DetailCounters", Vector2(14.0, 124.0), Vector2(328.0, 20.0), 14, Hud.TEXT).text = \
		"克制：%s" % _counter_names(def)

	var advantage := RichTextLabel.new()
	advantage.name = "DetailAdvantage"
	advantage.position = Vector2(14.0, 148.0)
	advantage.size = Vector2(328.0, 20.0)
	advantage.bbcode_enabled = true
	advantage.scroll_active = false
	advantage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	advantage.add_theme_font_size_override("normal_font_size", 14)
	advantage.add_theme_color_override("default_color", Hud.TEXT)
	var advantage_name := _stat_name(str(def.advantage_stat))
	if Stats.top_keys(_final_stats()).has(str(def.advantage_stat)):
		advantage.text = "优势属性：%s[color=%s]（你的最强属性）[/color]" % [
			advantage_name, Hud.GOLD_BRIGHT.to_html(false)
		]
	else:
		advantage.text = "优势属性：%s" % advantage_name
	panel.add_child(advantage)

	_make_label(panel, "DetailInitiative", Vector2(14.0, 172.0), Vector2(328.0, 20.0), 14, Hud.TEXT).text = \
		"先手加成：%s" % _signed(int(def.initiative))
	_make_label(panel, "DetailCounterLevel", Vector2(14.0, 196.0), Vector2(328.0, 20.0), 14, Hud.TEXT).text = \
		"反制等级：%d" % int(def.counter_level)

	_make_label(panel, "DetailCounterBonus", Vector2(14.0, 220.0), Vector2(328.0, 20.0), 14, BONUS_COLOR).text = \
		"反制强度 +%d" % Mastery.counter_bonus_at_level(level)

	var y := 244.0
	var effect_text := _effect_text(def)
	if effect_text != "":
		_make_label(panel, "DetailEffect", Vector2(14.0, y), Vector2(328.0, 20.0), 14, WARN_COLOR).text = effect_text
		y += 24.0

	var bonus_percent := int(roundf(Mastery.damage_bonus_at_level(level) * 100.0))
	_make_label(panel, "DetailBonus", Vector2(14.0, y), Vector2(328.0, 20.0), 14, BONUS_COLOR).text = \
		"伤害加成 +%d%%" % bonus_percent


func _on_martial_selected(martial_id: String) -> void:
	_selected_martial = martial_id
	refresh()


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


# ---------------------------------------------------------------- equipment tab

func _build_equipment_tab() -> void:
	for i in range(SLOT_KEYS.size()):
		var slot := SLOT_KEYS[i]
		var card := Panel.new()
		card.name = "EquipSlotCard_%s" % slot
		card.position = Vector2(float(i) * 198.0, 0.0)
		card.size = Vector2(182.0, 104.0)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_theme_stylebox_override("panel", Hud.card_style(0.9))
		_content_root.add_child(card)

		var icon := Panel.new()
		icon.name = "SlotIcon_%s" % slot
		icon.position = Vector2(12.0, 12.0)
		icon.size = Vector2(38.0, 38.0)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.add_theme_stylebox_override("panel", Hud.circle_style(SLOT_COLORS[slot], 19))
		card.add_child(icon)
		var glyph := _make_label(icon, "SlotGlyph_%s" % slot, Vector2.ZERO, Vector2(38.0, 38.0), 16, Hud.TEXT)
		glyph.text = str(SLOT_NAMES[slot]).substr(0, 1)
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

		_make_label(card, "SlotLabel_%s" % slot, Vector2(58.0, 10.0), Vector2(112.0, 20.0), 15, Hud.GOLD).text = \
			str(SLOT_NAMES[slot])

		var item_id := str(GameState.equipment.get(slot, ""))
		var item_label := _make_label(
			card, "SlotItem_%s" % slot, Vector2(58.0, 32.0), Vector2(116.0, 20.0), 14,
			Hud.MUTED if item_id == "" else Hud.TEXT
		)
		var bonus_label := _make_label(
			card, "SlotBonus_%s" % slot, Vector2(12.0, 68.0), Vector2(160.0, 20.0), 12, BONUS_COLOR
		)
		if item_id == "":
			item_label.text = "未装备"
			bonus_label.text = ""
		else:
			var item: Dictionary = Progression.item_def(item_id)
			item_label.text = str(item.get("name", item_id))
			bonus_label.text = _item_bonus_text(item)

	_make_label(
		_content_root, "BagHeader", Vector2(0.0, 116.0), Vector2(300.0, 22.0), 16, Hud.GOLD
	).text = "行囊"

	var ids: Array = GameState.inventory.keys()
	ids.sort()
	var shown := 0
	for raw_id in ids:
		var item_id := str(raw_id)
		var count := int(GameState.inventory[item_id])
		if count <= 0:
			continue
		_build_bag_row(item_id, count, 142.0 + float(shown) * 60.0)
		shown += 1

	if shown == 0:
		_make_label(
			_content_root, "BagEmpty", Vector2(0.0, 142.0), Vector2(400.0, 22.0), 15, Hud.MUTED
		).text = "行囊空空如也"


func _build_bag_row(item_id: String, count: int, y: float) -> void:
	var item: Dictionary = Progression.item_def(item_id)
	var row := Panel.new()
	row.name = "BagItem_%s" % item_id
	row.position = Vector2(0.0, y)
	row.size = Vector2(592.0, 54.0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_stylebox_override(
		"panel", Hud.card_style(0.55, Color(0.78, 0.65, 0.35, 0.25))
	)
	_content_root.add_child(row)

	var name_label := _make_label(row, "BagName_%s" % item_id, Vector2(10.0, 4.0), Vector2(140.0, 20.0), 15, Hud.TEXT)
	name_label.text = str(item.get("name", item_id))
	var count_label := _make_label(row, "BagCount_%s" % item_id, Vector2(150.0, 6.0), Vector2(44.0, 18.0), 12, Hud.MUTED)
	count_label.text = "×%d" % count
	var kind := str(item.get("kind", ""))
	var kind_label := _make_label(row, "BagKind_%s" % item_id, Vector2(200.0, 6.0), Vector2(60.0, 18.0), 12, Hud.GOLD)
	kind_label.text = str(KIND_NAMES.get(kind, kind))
	var desc := _make_label(row, "BagDesc_%s" % item_id, Vector2(10.0, 27.0), Vector2(480.0, 18.0), 12, Hud.MUTED)
	desc.text = str(item.get("desc", ""))

	var raw_perm: Variant = item.get("perm", {})
	if raw_perm is Dictionary:
		var perm: Dictionary = raw_perm
		if not perm.is_empty():
			var use_button := _make_small_button(row, "Use_%s" % item_id, "服用", Vector2(506.0, 12.0), Vector2(76.0, 28.0))
			use_button.pressed.connect(_on_use_pressed.bind(item_id))
			return

	if not Progression.EQUIP_SLOTS.has(kind):
		return
	var slot := str(item.get("slot", kind))
	if slot == "" or not Progression.EQUIP_SLOTS.has(slot):
		slot = kind
	var equipped_here := str(GameState.equipment.get(slot, "")) == item_id
	if equipped_here:
		var unequip_button := _make_small_button(row, "Unequip_%s" % item_id, "卸下", Vector2(506.0, 12.0), Vector2(76.0, 28.0))
		unequip_button.pressed.connect(_on_unequip_pressed.bind(slot))
	else:
		var equip_button := _make_small_button(row, "Equip_%s" % item_id, "装备", Vector2(506.0, 12.0), Vector2(76.0, 28.0))
		equip_button.pressed.connect(_on_equip_pressed.bind(item_id))


func _on_equip_pressed(item_id: String) -> void:
	Progression.equip(item_id)
	refresh()


func _on_use_pressed(item_id: String) -> void:
	Progression.use_permanent_item(item_id)
	refresh()


func _on_unequip_pressed(slot: String) -> void:
	Progression.unequip(slot)
	refresh()


func _item_bonus_text(item: Dictionary) -> String:
	var parts := PackedStringArray()
	var bonus_value: Variant = item.get("bonus", {})
	if bonus_value is Dictionary:
		var bonus: Dictionary = bonus_value
		for key in bonus.keys():
			var stat_key := str(key)
			if not STAT_NAMES.has(stat_key):
				continue
			var amount := int(bonus[key])
			if amount == 0:
				continue
			parts.append("%s%s" % [str(STAT_NAMES[stat_key]), _signed(amount)])
	return " ".join(parts)


# ---------------------------------------------------------------- points tab

func _build_points_tab() -> void:
	var available := GameState.unspent_points
	var title := _make_label(
		_content_root, "PointsAvailable", Vector2(0.0, 0.0), Vector2(240.0, 26.0), 18, Hud.GOLD_BRIGHT
	)
	title.text = "可分配点数 %d" % available
	_make_label(
		_content_root, "PointWarning", Vector2(232.0, 4.0), Vector2(320.0, 20.0), 12, WARN_COLOR
	).text = "加点确认后无法撤销"

	var final_values: Dictionary = _final_stats()
	var total_assigned := _total_pending()
	var y := 40.0
	for key in STAT_KEYS:
		var pending := _pending(key)
		var name_label := _make_label(
			_content_root, "PointName_%s" % key, Vector2(0.0, y), Vector2(60.0, 22.0), 15, Hud.TEXT
		)
		name_label.text = str(STAT_NAMES[key])
		var value_label := _make_label(
			_content_root, "PointValue_%s" % key, Vector2(70.0, y), Vector2(110.0, 22.0), 15, Hud.TEXT
		)
		value_label.text = str(int(final_values.get(key, 0)))

		var minus := _make_small_button(
			_content_root, "PointMinus_%s" % key, "－", Vector2(200.0, y - 2.0), Vector2(34.0, 26.0)
		)
		minus.disabled = pending <= 0
		minus.pressed.connect(_on_point_minus.bind(key))

		var plus := _make_small_button(
			_content_root, "PointPlus_%s" % key, "＋", Vector2(240.0, y - 2.0), Vector2(34.0, 26.0)
		)
		plus.disabled = available <= 0 \
				or total_assigned >= available \
				or int(final_values.get(key, 0)) + pending >= Progression.STAT_CAP
		plus.pressed.connect(_on_point_plus.bind(key))

		var pending_label := _make_label(
			_content_root, "PointPending_%s" % key, Vector2(284.0, y), Vector2(60.0, 22.0), 14, BONUS_COLOR
		)
		if pending > 0:
			pending_label.text = "+%d" % pending
		if key == "constitution":
			_make_label(
				_content_root, "ConstitutionHpHint", Vector2(356.0, y + 2.0), Vector2(220.0, 20.0), 12, Hud.MUTED
			).text = "+1 体质 = +%d 气血" % Realms.hp_per_con(GameState.realm_id)
		y += 38.0

	var total_pending := _total_pending()
	var confirm := _make_small_button(
		_content_root, "ConfirmPoints", "确认", Vector2(0.0, 288.0), Vector2(96.0, 32.0)
	)
	confirm.disabled = total_pending <= 0
	confirm.pressed.connect(_on_points_confirm)

	var reset := _make_small_button(
		_content_root, "ResetPoints", "重置", Vector2(110.0, 288.0), Vector2(96.0, 32.0)
	)
	reset.disabled = total_pending <= 0
	reset.pressed.connect(_on_points_reset)

	if available <= 0 and total_pending <= 0:
		_make_label(
			_content_root, "NoPointsMessage", Vector2(40.0, 262.0), Vector2(480.0, 22.0), 13, Hud.MUTED
		).text = "暂无可分配的点数。完成任务或突破境界可获得点数。"


func _on_point_plus(stat: String) -> void:
	if GameState.unspent_points <= 0:
		return
	var pending := _pending(stat)
	if _total_pending() >= GameState.unspent_points:
		return
	if int(_final_stats().get(stat, 0)) + pending >= Progression.STAT_CAP:
		return
	pending_points[stat] = pending + 1
	refresh()


func _on_point_minus(stat: String) -> void:
	var pending := _pending(stat)
	if pending <= 0:
		return
	if pending <= 1:
		pending_points.erase(stat)
	else:
		pending_points[stat] = pending - 1
	refresh()


func _on_points_confirm() -> void:
	var had_pending := _total_pending() > 0
	for key in pending_points.keys():
		var count := int(pending_points[key])
		for i in range(count):
			Progression.spend_point(str(key))
	pending_points.clear()
	if had_pending:
		Progression.push_toast("加点完成")
	refresh()


func _on_points_reset() -> void:
	pending_points.clear()
	refresh()


func _pending(stat: String) -> int:
	return int(pending_points.get(stat, 0))


func _total_pending() -> int:
	var total := 0
	for key in pending_points.keys():
		total += int(pending_points[key])
	return total


# ---------------------------------------------------------------- data helpers

func _player() -> Dictionary:
	return DataLoader.load_player(PLAYER_PATH)


func _base_stats() -> Dictionary:
	var raw: Variant = _player().get("stats", {})
	if raw is Dictionary:
		var stats: Dictionary = raw
		return stats
	return {}


func _final_stats() -> Dictionary:
	return Progression.final_stats(_base_stats())


func _martial_def_map() -> Dictionary:
	if _martial_def_cache.is_empty():
		var loaded: Dictionary = DataLoader.load_martials(MARTIALS_PATH)
		var defs_value: Variant = loaded.get("defs", {})
		if defs_value is Dictionary:
			_martial_def_cache = defs_value
	return _martial_def_cache


func _martial_def(martial_id: String) -> Variant:
	return _martial_def_map().get(martial_id, null)


func _martial_name(martial_id: String) -> String:
	var def: Variant = _martial_def(martial_id)
	if def != null:
		return str(def.name)
	return martial_id


func _martial_grade(martial_id: String) -> String:
	var def: Variant = _martial_def(martial_id)
	if def != null:
		return str(def.grade)
	return "common"


func _martial_glyph(martial_id: String) -> String:
	var martial_name := _martial_name(martial_id)
	if martial_name.is_empty():
		return "?"
	return martial_name.substr(0, 1)


func _martial_color(martial_id: String) -> Color:
	var def: Variant = _martial_def(martial_id)
	if def != null and not def.counters.is_empty():
		return Hud.move_type_color(str(def.counters[0]))
	return Color(0.52, 0.54, 0.62)


func _stat_name(stat_id: String) -> String:
	return str(STAT_NAMES.get(stat_id, stat_id))


func _signed(amount: int) -> String:
	if amount >= 0:
		return "+%d" % amount
	return str(amount)


# ---------------------------------------------------------------- ui helpers

func _make_label(
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


func _make_small_button(
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


func _style_tab_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	button.add_theme_stylebox_override(
		"hover", Hud.card_style(0.5, Color(0.78, 0.65, 0.35, 0.4))
	)
	button.add_theme_stylebox_override(
		"pressed", Hud.card_style(0.6, Color(0.78, 0.65, 0.35, 0.6))
	)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_font_size_override("font_size", 16)


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


func _clear_children(parent: Node) -> void:
	if parent == null:
		return
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

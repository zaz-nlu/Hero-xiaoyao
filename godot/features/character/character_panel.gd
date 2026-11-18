extends Panel

# 角色面板：四页签（属性 / 技能 / 装备 / 加点）的外壳。
# 由 status_overlay.gd 持有；对外提供 refresh()/select_tab()/advance() 与 tab_index、pending_points。
# 页签内容与常驻状态由同 feature 的独立模块持有，控制器只做外壳、切换与生命周期编排。

const CharacterAttributesTab = preload("res://features/character/character_attributes_tab.gd")
const CharacterData = preload("res://features/character/character_panel_data.gd")
const CharacterEquipmentTab = preload("res://features/character/character_equipment_tab.gd")
const CharacterPanelStyle = preload("res://features/character/character_panel_style.gd")
const CharacterPointsTab = preload("res://features/character/character_points_tab.gd")
const CharacterSkillsTab = preload("res://features/character/character_skills_tab.gd")
const AssetPaths = preload("res://shared/resources/asset_paths.gd")
const GameState = preload("res://core/game_state.gd")
const Hud = preload("res://shared/ui/battle_hud_style.gd")
const ImageCache = preload("res://shared/resources/image_cache.gd")
const Progression = preload("res://core/progression.gd")
const Realms = preload("res://core/realms.gd")

const PORTRAIT_PATH := AssetPaths.PORTRAITS + "ren_xiaoyao.png"

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

const RED_DOT_COLOR := Color(0.9, 0.32, 0.3)

var tab_index: int = 0

var _data := CharacterData.new()
var _attributes_tab: Variant = null
var _skills_tab: Variant = null
var _equipment_tab: Variant = null
var _points_tab: Variant = null
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
var _content_fade: float = 1.0

# 兼容既有调用点/测试：未提交点数由加点页签持有，读写语义与原字段一致。
var pending_points: Dictionary:
	get:
		return _points_tab.pending_points
	set(value):
		_points_tab.pending_points = value


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
	_name_label = CharacterPanelStyle.make_label(
		self, "CharName", Vector2(22.0, 316.0), Vector2(196.0, 34.0), 26, Hud.GOLD_BRIGHT
	)
	_realm_label = CharacterPanelStyle.make_label(
		self, "CharRealm", Vector2(22.0, 350.0), Vector2(196.0, 20.0), 15, Hud.MUTED
	)
	_realm_label.text = "初出茅庐"
	_age_label = CharacterPanelStyle.make_label(
		self, "CharAge", Vector2(22.0, 368.0), Vector2(196.0, 14.0), 12, Hud.MUTED
	)

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

	_hp_label = CharacterPanelStyle.make_label(
		self, "HpValue", Vector2(166.0, 381.0), Vector2(56.0, 20.0), 12, Hud.TEXT
	)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_jianyi_label = CharacterPanelStyle.make_label(
		self, "JianyiValue", Vector2(22.0, 418.0), Vector2(200.0, 20.0), 14, Hud.JIANYI_PURPLE
	)
	_foresight_label = CharacterPanelStyle.make_label(
		self, "ForesightValue", Vector2(22.0, 442.0), Vector2(200.0, 20.0), 14, Hud.FORESIGHT_CYAN
	)
	_unspent_label = CharacterPanelStyle.make_label(
		self, "UnspentPoints", Vector2(22.0, 504.0), Vector2(196.0, 18.0), 12, Hud.MUTED
	)
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

	_attributes_tab = CharacterAttributesTab.new(_content_root, _data)
	_skills_tab = CharacterSkillsTab.new(_content_root, _data)
	_equipment_tab = CharacterEquipmentTab.new(_content_root, _data)
	_points_tab = CharacterPointsTab.new(_content_root, _data)
	_skills_tab.refresh_requested.connect(refresh)
	_equipment_tab.refresh_requested.connect(refresh)
	_points_tab.refresh_requested.connect(refresh)


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
	var player: Dictionary = _data.player()
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
	var max_hp := Progression.max_hp(_data.base_stats())
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
			_attributes_tab.build()
		1:
			_skills_tab.build()
		2:
			_equipment_tab.build()
		3:
			_points_tab.build()


# ---------------------------------------------------------------- ui helpers

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


func _clear_children(parent: Node) -> void:
	if parent == null:
		return
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

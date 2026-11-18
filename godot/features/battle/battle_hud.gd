extends RefCounted

# 战斗 HUD：调试顶栏、玩家卡与气/意 pips、结算横幅、返回按钮。
# 只负责构建与刷新这些控件，交互通过信号交给控制器。

signal scenario_selected(enemy_id: String, enemy_count: int, first_strike: bool)
signal return_requested

const Battle = preload("res://core/battle.gd")
const BattleText = preload("res://features/battle/battle_text.gd")
const Hud = preload("res://shared/ui/battle_hud_style.gd")
const HudBar = preload("res://shared/ui/hud_bar.gd")
const HudPips = preload("res://shared/ui/hud_pips.gd")
const ImageCache = preload("res://shared/resources/image_cache.gd")
const AssetPaths = preload("res://shared/resources/asset_paths.gd")
const OrnatePanel = preload("res://shared/ui/ornate_panel.gd")

const PLAYER_PORTRAIT_PATH := AssetPaths.PORTRAITS + "ren_xiaoyao.png"
const HUD_HEIGHT := 172.0

var top_bar: HBoxContainer = null
var player_label: Label = null
var player_hp_bar: ProgressBar = null
var player_hp_label: Label = null
var wound_label: Label = null
var jianyi_label: Label = null
var foresight_label: Label = null
var jianyi_pips: Control = null
var foresight_pips: Control = null
var result_label: Label = null
var return_button: Button = null


func build(parent: Control) -> HBoxContainer:
	_build_top_bar(parent)
	var row := _build_bottom_hud(parent)
	_build_return_button(parent)
	_build_result_banner(parent)
	return row


func set_top_bar_visible(value: bool) -> void:
	if top_bar != null:
		top_bar.visible = value


func refresh_player(battle: Variant) -> void:
	if battle == null or battle.player == null:
		return
	var player: Variant = battle.player
	if player_label != null:
		player_label.text = str(player.name)
	if player_hp_bar != null:
		player_hp_bar.max_value = maxf(1.0, float(player.max_hp))
		player_hp_bar.value = float(maxi(0, int(player.hp)))
	if player_hp_label != null:
		BattleText.fit_hp_label(player_hp_label, int(player.hp), int(player.max_hp), 11)
	if wound_label != null:
		var wound: int = int(player.wound)
		wound_label.visible = wound > 0
		wound_label.text = "伤 %d" % wound
	if jianyi_pips != null:
		jianyi_pips.call("set_pips", int(player.jianyi_points), int(player.jianyi_max))
	if foresight_pips != null:
		foresight_pips.call("set_pips", int(player.foresight_points), int(player.foresight_max))


func refresh_result(battle: Variant, last_error: String) -> void:
	if result_label == null or battle == null:
		return
	if battle.state() == Battle.State.ONGOING:
		result_label.text = ""
		result_label.visible = false
		return
	result_label.text = _result_text(battle, last_error)
	result_label.visible = result_label.text != ""


func refresh_return(battle: Variant, dialogue_active: bool) -> void:
	if return_button == null or battle == null:
		return
	return_button.visible = battle.state() != Battle.State.ONGOING and not dialogue_active


# ---------------------------------------------------------------- build

func _build_top_bar(parent: Control) -> void:
	top_bar = HBoxContainer.new()
	top_bar.name = "TopBar"
	top_bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	top_bar.position = Vector2(16.0, 12.0)
	top_bar.add_theme_constant_override("separation", 8)
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.visible = false
	parent.add_child(top_bar)

	var bandit_button := Button.new()
	bandit_button.text = "打马匪（先手）"
	bandit_button.pressed.connect(_on_scenario.bind("bandit", 1, true))
	top_bar.add_child(bandit_button)

	var two_bandits_button := Button.new()
	two_bandits_button.text = "打两个马匪"
	two_bandits_button.pressed.connect(_on_scenario.bind("bandit", 2, false))
	top_bar.add_child(two_bandits_button)

	var boss_button := Button.new()
	boss_button.text = "打马匪头子"
	boss_button.pressed.connect(_on_scenario.bind("ma_youwei", 1, false))
	top_bar.add_child(boss_button)


func _build_bottom_hud(parent: Control) -> HBoxContainer:
	var panel := Panel.new()
	panel.name = "BottomPanel"
	panel.anchor_left = 0.0
	panel.anchor_top = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 0.0
	panel.offset_top = -HUD_HEIGHT
	panel.offset_right = 0.0
	panel.offset_bottom = 0.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	parent.add_child(panel)

	# A soft dark fade so the HUD melts into the scene instead of cutting it off.
	var backdrop := TextureRect.new()
	backdrop.name = "Backdrop"
	backdrop.texture = Hud.vertical_gradient(Color(0.03, 0.02, 0.05, 0.0), Color(0.03, 0.02, 0.05, 0.93))
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(backdrop)

	var margin := MarginContainer.new()
	margin.name = "PanelMargin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.name = "PanelRow"
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

	row.add_child(_build_character_card())
	return row


func _build_character_card() -> Control:
	var card := OrnatePanel.new()
	card.name = "CharacterCard"
	card.custom_minimum_size = Vector2(268.0, 0.0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", Hud.plate_style())
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

	row.add_child(_build_portrait_frame())

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 3)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)

	player_label = Label.new()
	player_label.name = "PlayerLabel"
	Hud.configure_label(player_label, 20, Hud.TEXT)
	player_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	player_label.add_theme_constant_override("outline_size", 4)
	info.add_child(player_label)

	var rule := TextureRect.new()
	rule.texture = Hud.horizontal_fade_line(Hud.GOLD)
	rule.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rule.stretch_mode = TextureRect.STRETCH_SCALE
	rule.custom_minimum_size = Vector2(0.0, 2.0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(rule)

	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 6)
	hp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(hp_row)

	var hp_title := Label.new()
	hp_title.text = "气血"
	Hud.configure_label(hp_title, 12, Hud.MUTED)
	hp_row.add_child(hp_title)

	player_hp_bar = HudBar.new()
	player_hp_bar.name = "PlayerHpBar"
	player_hp_bar.custom_minimum_size = Vector2(96.0, 20.0)
	player_hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	player_hp_bar.max_value = 1.0
	player_hp_bar.value = 0.0
	player_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_row.add_child(player_hp_bar)

	player_hp_label = Label.new()
	player_hp_label.name = "PlayerHpLabel"
	player_hp_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	player_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Hud.configure_label(player_hp_label, 12, Color.WHITE)
	player_hp_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	player_hp_label.add_theme_constant_override("outline_size", 4)
	player_hp_bar.add_child(player_hp_label)

	wound_label = Label.new()
	wound_label.name = "WoundLabel"
	Hud.configure_label(wound_label, 11, Hud.WOUND_RED)
	wound_label.visible = false
	info.add_child(wound_label)

	var jianyi_row := _build_pip_row("JianyiLabel", "剑意", Hud.JIANYI_PURPLE)
	jianyi_label = jianyi_row.get_node("Title")
	jianyi_pips = jianyi_row.get_node("Pips")
	info.add_child(jianyi_row)

	var foresight_row := _build_pip_row("ForesightLabel", "料敌", Hud.FORESIGHT_CYAN)
	foresight_label = foresight_row.get_node("Title")
	foresight_pips = foresight_row.get_node("Pips")
	info.add_child(foresight_row)

	return card


func _build_pip_row(node_name: String, title: String, color: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title_label := Label.new()
	title_label.name = "Title"
	title_label.text = title
	title_label.custom_minimum_size = Vector2(30.0, 0.0)
	Hud.configure_label(title_label, 12, color)
	row.add_child(title_label)
	var pips := HudPips.new()
	pips.name = "Pips"
	pips.color = color
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(pips)
	row.name = node_name + "Row"
	return row


func _build_portrait_frame() -> Control:
	var frame := OrnatePanel.new()
	frame.name = "PortraitFrame"
	frame.custom_minimum_size = Vector2(92.0, 92.0)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", Hud.panel_style(1.0, Hud.GOLD, 6))

	var placeholder := ColorRect.new()
	placeholder.name = "PortraitPlaceholder"
	placeholder.color = Color(0.24, 0.2, 0.28, 1.0)
	placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	placeholder.offset_left = 3.0
	placeholder.offset_top = 3.0
	placeholder.offset_right = -3.0
	placeholder.offset_bottom = -3.0
	placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(placeholder)

	var portrait := TextureRect.new()
	portrait.name = "Portrait"
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait.offset_left = 3.0
	portrait.offset_top = 3.0
	portrait.offset_right = -3.0
	portrait.offset_bottom = -3.0
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.texture = _portrait_texture()
	frame.add_child(portrait)
	return frame


func _portrait_texture() -> Texture2D:
	if not FileAccess.file_exists(PLAYER_PORTRAIT_PATH):
		return null
	var texture: Texture2D = ImageCache.texture(PLAYER_PORTRAIT_PATH)
	if texture == null:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	var width: float = float(texture.get_width())
	var height: float = float(texture.get_height())
	var side: float = minf(width * 0.62, height * 0.42)
	var left: float = clampf(width * 0.44 - side * 0.5, 0.0, maxf(0.0, width - side))
	atlas.region = Rect2(left, height * 0.01, side, side)
	atlas.filter_clip = true
	return atlas


# Shown above the HUD once the fight is over.
func _build_return_button(parent: Control) -> void:
	return_button = Button.new()
	return_button.name = "ReturnButton"
	return_button.text = "返回小镇"
	return_button.anchor_left = 0.5
	return_button.anchor_right = 0.5
	return_button.anchor_top = 1.0
	return_button.anchor_bottom = 1.0
	return_button.offset_left = -90.0
	return_button.offset_right = 90.0
	return_button.offset_top = -HUD_HEIGHT - 52.0
	return_button.offset_bottom = -HUD_HEIGHT - 6.0
	return_button.visible = false
	return_button.pressed.connect(_on_return_pressed)
	_style_card_button(return_button)
	return_button.add_theme_font_size_override("font_size", 20)
	return_button.add_theme_color_override("font_color", Hud.GOLD_BRIGHT)
	parent.add_child(return_button)


func _build_result_banner(parent: Control) -> void:
	result_label = Label.new()
	result_label.name = "ResultLabel"
	result_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	result_label.offset_left = 0.0
	result_label.offset_top = 16.0
	result_label.offset_right = 0.0
	result_label.offset_bottom = 84.0
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 44)
	result_label.add_theme_color_override("font_color", Hud.GOLD_BRIGHT)
	result_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	result_label.add_theme_constant_override("outline_size", 8)
	result_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_label.text = ""
	result_label.visible = false
	parent.add_child(result_label)


func _style_card_button(button: Button) -> void:
	if button == null:
		return
	button.add_theme_stylebox_override("normal", Hud.card_style())
	button.add_theme_stylebox_override("hover", Hud.card_hover_style())
	button.add_theme_stylebox_override("pressed", Hud.card_pressed_style())
	button.add_theme_stylebox_override("disabled", Hud.card_disabled_style())
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", Hud.TEXT)
	button.add_theme_color_override("font_hover_color", Hud.GOLD_BRIGHT)
	button.add_theme_color_override("font_disabled_color", Hud.MUTED)
	button.add_theme_font_size_override("font_size", 14)


func _result_text(battle: Variant, last_error: String) -> String:
	var state_text := ""
	match battle.state():
		Battle.State.WON:
			state_text = "胜利"
		Battle.State.LOST:
			state_text = "战败"
		Battle.State.TIMEOUT:
			state_text = "僵局"
	if state_text != "":
		if last_error != "":
			return "%s（%s）" % [state_text, last_error]
		return state_text
	if last_error != "":
		return last_error
	return ""


func _on_scenario(enemy_id: String, enemy_count: int, first_strike: bool) -> void:
	scenario_selected.emit(enemy_id, enemy_count, first_strike)


func _on_return_pressed() -> void:
	return_requested.emit()

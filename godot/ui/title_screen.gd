extends Control

# 标题页：分镜式 3D 背景（TitleCinematic）+ Logo + 主菜单 / 读档页 / 设置页。
# 背景在无渲染（headless）环境下退化为纯色渐变，方便测试与 headless 冒烟。
# 只负责界面与信号，场景切换、读档、退出由 Game 处理。

signal new_game_requested
signal continue_requested(slot: String)
signal load_requested(slot: String)
signal quit_requested

const SaveSystem = preload("res://core/save_system.gd")
const Hud = preload("res://ui/battle_hud_style.gd")

const TITLE_CINEMATIC_SCENE := "res://ui/title_cinematic.gd"
const PAGES: Array[String] = ["main", "load", "settings"]
const MENU_LABELS: Array[String] = ["新的旅程", "继续", "读取存档", "设置", "退出游戏"]
const SLOT_LABELS := {
	"auto": "自动存档",
	"1": "存档 1",
	"2": "存档 2",
	"3": "存档 3",
}
const DEFAULT_MUSIC_VOLUME := 0.7
const DEFAULT_SFX_VOLUME := 0.8

const MENU_WIDTH := 260.0
const MENU_ITEM_HEIGHT := 44.0
const MENU_SPACING := 14.0
const MENU_BOTTOM_MARGIN := 74.0
const PANEL_WIDTH := 640.0
const PANEL_HEIGHT := 600.0

const LOGO_TOP := 64.0
const LOGO_BOTTOM := 300.0
const INTRO_DURATION := 1.5
const INTRO_RISE := 18.0
const HOVER_SCALE := 1.04

var game: Variant = null
var audio: Variant = null
var save_dir: String = SaveSystem.SAVE_DIR:
	set(value):
		save_dir = value
		_selection_initialized = false
		if _built:
			refresh_slots()

var menu_buttons: Array = []
var selected_index: int = 0
var current_page: String = "main"
var background_fallback: bool = false

var _built: bool = false
var _background_built: bool = false
var _background_root: Control = null
var _main_ui: Control = null
var _logo_box: Control = null
var _menu_box: Control = null
var _load_page: Panel = null
var _settings_page: Panel = null
var _error_label: Label = null
var _slot_cards: Dictionary = {}
var _load_order: Array[String] = []
var _load_index: int = 0
var _latest_slot: String = ""
var _selection_initialized: bool = false
var _intro_time: float = 0.0
var _cinematic: Variant = null

var _music_slider: HSlider = null
var _sfx_slider: HSlider = null
var _music_value: Label = null
var _sfx_value: Label = null
var _mute_box: CheckBox = null
var _settings_back: Button = null
var _setting_labels: Array = []
var _setting_index: int = 0
var _syncing_settings: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	anchor_right = 1.0
	anchor_bottom = 1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	build()


func _process(delta: float) -> void:
	_advance_intro(delta)
	if _cinematic != null and is_instance_valid(_cinematic):
		_cinematic.call("advance", delta)


# ---------------------------------------------------------------- public API

func build() -> void:
	_ensure_built()
	_setup_background()
	refresh_slots()
	_sync_settings()


func is_fallback_background() -> bool:
	return background_fallback


func press_new_game() -> void:
	new_game_requested.emit()


func press_continue() -> void:
	var slot := SaveSystem.latest_slot(save_dir)
	_latest_slot = slot
	if slot == "":
		return
	continue_requested.emit(slot)


func press_load(slot: String) -> bool:
	var item := _slot_item(slot)
	if item.is_empty():
		return false
	if not bool(item.get("exists", false)) or bool(item.get("corrupt", false)):
		return false
	load_requested.emit(slot)
	return true


func press_quit() -> void:
	quit_requested.emit()


func show_error(text: String) -> void:
	_ensure_built()
	if _error_label == null:
		return
	_error_label.text = text
	_error_label.visible = text != ""


func open_page(page: String) -> void:
	_ensure_built()
	if _error_label != null:
		_error_label.visible = false
	if not PAGES.has(page):
		page = "main"
	current_page = page
	if _main_ui != null:
		_main_ui.visible = page == "main"
	if _load_page != null:
		_load_page.visible = page == "load"
	if _settings_page != null:
		_settings_page.visible = page == "settings"
	if page == "load":
		_load_index = 0
		refresh_slots()
	elif page == "settings":
		_sync_settings()
	elif page == "main":
		_set_selected(selected_index)


func refresh_slots() -> void:
	_ensure_built()
	_latest_slot = SaveSystem.latest_slot(save_dir)
	if menu_buttons.size() > 1:
		var continue_button: Button = menu_buttons[1]
		continue_button.disabled = _latest_slot == ""
		_style_menu_button(continue_button, selected_index == 1)

	var items: Array = SaveSystem.list_slots(save_dir)
	_load_order.clear()
	for item_value in items:
		var item: Dictionary = item_value
		var slot := str(item.get("slot", ""))
		var record: Variant = _slot_cards.get(slot, null)
		if not (record is Dictionary):
			continue
		var card: Dictionary = record
		var button: Button = card["button"]
		var title: Label = card["title"]
		var info: Label = card["info"]
		var exists := bool(item.get("exists", false))
		var corrupt := bool(item.get("corrupt", false))
		var summary: Dictionary = {}
		var summary_value: Variant = item.get("summary", {})
		if summary_value is Dictionary:
			summary = summary_value
		title.text = str(SLOT_LABELS.get(slot, "存档 %s" % slot))
		if exists and not corrupt and not summary.is_empty():
			var place := str(summary.get("place", ""))
			if place != "":
				title.text += " · " + place
		if corrupt:
			title.text += " · 存档损坏"
			info.text = "存档损坏，无法读取"
		elif exists:
			var realm := str(summary.get("realm", "—"))
			var age := int(summary.get("age", 0))
			var playtime := SaveSystem.format_playtime(float(item.get("playtime", 0.0)))
			var saved_at := SaveSystem.format_time(int(item.get("saved_at", 0)))
			var quests_done := int(summary.get("quests_done", 0))
			info.text = "境界 %s · 年龄 %d · %s · 任务 %d\n%s" % [
				realm, age, playtime, quests_done, saved_at
			]
		else:
			info.text = "空"
		var enabled := exists and not corrupt
		button.disabled = not enabled
		_style_card(button, false, not enabled)
		if enabled:
			_load_order.append(slot)

	if _load_order.is_empty():
		_load_index = 0
	else:
		_load_index = clampi(_load_index, 0, _load_order.size() - 1)
	_update_load_selection()

	if not _selection_initialized:
		_selection_initialized = true
		_set_selected(1 if _latest_slot != "" else 0)
	else:
		_set_selected(selected_index)


# ---------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event: InputEventKey = event
	if not key_event.pressed or key_event.echo:
		return
	var key := key_event.keycode
	if key == KEY_NONE:
		key = key_event.physical_keycode
	match current_page:
		"main":
			match key:
				KEY_UP:
					_move_selection(-1)
					_consume_input()
				KEY_DOWN:
					_move_selection(1)
					_consume_input()
				KEY_ENTER, KEY_KP_ENTER:
					_consume_input()
					_activate_selected()
				KEY_ESCAPE:
					# 标题页上 Esc 无作用，但吞掉它以免打开暂停菜单。
					_consume_input()
				_:
					pass
		"load":
			match key:
				KEY_UP:
					_move_load_selection(-1)
					_consume_input()
				KEY_DOWN:
					_move_load_selection(1)
					_consume_input()
				KEY_ENTER, KEY_KP_ENTER:
					_consume_input()
					_activate_load_selection()
				KEY_ESCAPE:
					open_page("main")
					_consume_input()
				_:
					pass
		"settings":
			match key:
				KEY_UP:
					_setting_index = clampi(_setting_index - 1, 0, 3)
					_update_setting_selection()
					_consume_input()
				KEY_DOWN:
					_setting_index = clampi(_setting_index + 1, 0, 3)
					_update_setting_selection()
					_consume_input()
				KEY_LEFT:
					_adjust_setting(-0.05)
					_consume_input()
				KEY_RIGHT:
					_adjust_setting(0.05)
					_consume_input()
				KEY_ENTER, KEY_KP_ENTER:
					_activate_setting()
					_consume_input()
				KEY_ESCAPE:
					open_page("main")
					_consume_input()
				_:
					pass


func _move_selection(offset: int) -> void:
	if menu_buttons.is_empty():
		return
	var next := selected_index
	for _i in range(menu_buttons.size()):
		next = posmod(next + offset, menu_buttons.size())
		if not (menu_buttons[next] as Button).disabled:
			break
	_set_selected(next)


func _activate_selected() -> void:
	match selected_index:
		0:
			press_new_game()
		1:
			press_continue()
		2:
			open_page("load")
		3:
			open_page("settings")
		4:
			press_quit()


func _move_load_selection(offset: int) -> void:
	if _load_order.is_empty():
		return
	_load_index = clampi(_load_index + offset, 0, _load_order.size() - 1)
	_update_load_selection()


func _activate_load_selection() -> void:
	if _load_order.is_empty():
		return
	press_load(_load_order[_load_index])


func _activate_setting() -> void:
	if _setting_index == 2:
		_mute_box.button_pressed = not _mute_box.button_pressed
	elif _setting_index == 3:
		open_page("main")


func _adjust_setting(delta: float) -> void:
	if current_page != "settings":
		return
	if _setting_index == 0:
		_music_slider.value = clampf(_music_slider.value + delta, 0.0, 1.0)
	elif _setting_index == 1:
		_sfx_slider.value = clampf(_sfx_slider.value + delta, 0.0, 1.0)


func _consume_input() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _on_menu_hover(index: int) -> void:
	if index < 0 or index >= menu_buttons.size():
		return
	if (menu_buttons[index] as Button).disabled:
		return
	_set_selected(index)


func _on_menu_pressed(index: int) -> void:
	_set_selected(index)
	match index:
		0:
			press_new_game()
		1:
			press_continue()
		2:
			open_page("load")
		3:
			open_page("settings")
		4:
			press_quit()


func _on_slot_pressed(slot: String) -> void:
	press_load(slot)


func _on_back_pressed() -> void:
	open_page("main")


# ---------------------------------------------------------------- construction

func _ensure_built() -> void:
	if _built:
		return
	_built = true

	_background_root = Control.new()
	_background_root.name = "Background"
	_background_root.anchor_right = 1.0
	_background_root.anchor_bottom = 1.0
	_background_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background_root)

	var shade_top := TextureRect.new()
	shade_top.name = "ShadeTop"
	shade_top.anchor_right = 1.0
	shade_top.anchor_bottom = 0.42
	shade_top.offset_bottom = 0.0
	shade_top.texture = _vertical_gradient(
		Color(0.02, 0.02, 0.03, 0.66), Color(0.02, 0.02, 0.03, 0.0)
	)
	shade_top.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade_top.stretch_mode = TextureRect.STRETCH_SCALE
	shade_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade_top)

	var shade_bottom := TextureRect.new()
	shade_bottom.name = "ShadeBottom"
	shade_bottom.anchor_right = 1.0
	shade_bottom.anchor_top = 0.75
	shade_bottom.anchor_bottom = 1.0
	shade_bottom.offset_top = 0.0
	shade_bottom.texture = _vertical_gradient(
		Color(0.02, 0.02, 0.03, 0.0), Color(0.02, 0.02, 0.03, 0.82)
	)
	shade_bottom.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade_bottom.stretch_mode = TextureRect.STRETCH_SCALE
	shade_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade_bottom)

	# A darker band behind the logo and menu so the text stays readable on bright scenery.
	var veil := TextureRect.new()
	veil.name = "CentreVeil"
	veil.anchor_left = 0.12
	veil.anchor_right = 0.88
	veil.anchor_bottom = 1.0
	var veil_gradient := Gradient.new()
	veil_gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	veil_gradient.colors = PackedColorArray([
		Color(0.02, 0.02, 0.03, 0.0), Color(0.02, 0.02, 0.03, 0.42), Color(0.02, 0.02, 0.03, 0.0)
	])
	var veil_texture := GradientTexture2D.new()
	veil_texture.gradient = veil_gradient
	veil_texture.fill_from = Vector2(0.0, 0.0)
	veil_texture.fill_to = Vector2(1.0, 0.0)
	veil_texture.width = 256
	veil_texture.height = 4
	veil.texture = veil_texture
	veil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	veil.stretch_mode = TextureRect.STRETCH_SCALE
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)

	_main_ui = Control.new()
	_main_ui.name = "MainUI"
	_main_ui.anchor_right = 1.0
	_main_ui.anchor_bottom = 1.0
	_main_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_main_ui)

	_build_logo()
	_build_menu()
	_build_footer()
	_error_label = _make_label(
		self, "ErrorLabel", "", Vector2(0.0, 232.0), Vector2(0.0, 26.0),
		17, Color(0.9, 0.48, 0.38)
	)
	_error_label.anchor_right = 1.0
	_error_label.offset_left = 0.0
	_error_label.offset_right = 0.0
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error_label.visible = false
	_load_page = _build_load_page()
	_settings_page = _build_settings_page()


func _build_logo() -> void:
	_logo_box = Control.new()
	_logo_box.name = "Logo"
	_logo_box.anchor_right = 1.0
	_logo_box.offset_top = LOGO_TOP
	_logo_box.offset_bottom = LOGO_BOTTOM
	_logo_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo_box.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_main_ui.add_child(_logo_box)

	var title := _make_label(
		_logo_box, "LogoTitle", "任逍遥", Vector2(0.0, 0.0),
		Vector2(0.0, 132.0), 96, Color(0.95, 0.8, 0.4)
	)
	title.anchor_right = 1.0
	title.offset_left = 0.0
	title.offset_right = 0.0
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.55))
	title.add_theme_constant_override("shadow_offset_x", 4)
	title.add_theme_constant_override("shadow_offset_y", 5)

	var subtitle := _make_label(
		_logo_box, "LogoSubtitle", "一 剑 ， 一 念 ， 一 江 湖",
		Vector2(0.0, 142.0), Vector2(0.0, 34.0), 22, Color(0.95, 0.92, 0.85)
	)
	subtitle.anchor_right = 1.0
	subtitle.offset_left = 0.0
	subtitle.offset_right = 0.0
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var demo := _make_label(
		_logo_box, "LogoDemo", "Demo · 第一章",
		Vector2(0.0, 180.0), Vector2(0.0, 26.0), 16, Hud.MUTED
	)
	demo.anchor_right = 1.0
	demo.offset_left = 0.0
	demo.offset_right = 0.0
	demo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _build_menu() -> void:
	var count := MENU_LABELS.size()
	var height := MENU_ITEM_HEIGHT * float(count) + MENU_SPACING * float(count - 1)
	_menu_box = Control.new()
	_menu_box.name = "Menu"
	_menu_box.anchor_left = 0.5
	_menu_box.anchor_right = 0.5
	_menu_box.anchor_top = 1.0
	_menu_box.anchor_bottom = 1.0
	_menu_box.offset_left = -MENU_WIDTH * 0.5
	_menu_box.offset_right = MENU_WIDTH * 0.5
	_menu_box.offset_top = -(height + MENU_BOTTOM_MARGIN)
	_menu_box.offset_bottom = -MENU_BOTTOM_MARGIN
	_menu_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_main_ui.add_child(_menu_box)

	for i in range(count):
		var button := Button.new()
		button.name = "Menu_%d" % i
		button.text = str(MENU_LABELS[i])
		button.position = Vector2(
			0.0, (MENU_ITEM_HEIGHT + MENU_SPACING) * float(i)
		)
		button.size = Vector2(MENU_WIDTH, MENU_ITEM_HEIGHT)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 20)
		button.pressed.connect(_on_menu_pressed.bind(i))
		button.mouse_entered.connect(_on_menu_hover.bind(i))
		_style_menu_button(button, false)
		_menu_box.add_child(button)
		menu_buttons.append(button)


func _build_footer() -> void:
	var version := _make_label(
		self, "Version", "v0.1 Demo", Vector2(18.0, -34.0),
		Vector2(0.0, 22.0), 14, Hud.MUTED
	)
	version.anchor_top = 1.0
	version.anchor_bottom = 1.0
	version.anchor_right = 1.0
	version.offset_left = 18.0
	version.offset_top = -34.0
	version.offset_right = 0.0
	version.offset_bottom = -12.0

	var mute := _make_label(
		self, "MuteHint", "M 静音", Vector2(18.0, -34.0),
		Vector2(0.0, 22.0), 14, Hud.MUTED
	)
	mute.anchor_top = 1.0
	mute.anchor_bottom = 1.0
	mute.anchor_right = 1.0
	mute.offset_left = 18.0
	mute.offset_top = -34.0
	mute.offset_right = -18.0
	mute.offset_bottom = -12.0
	mute.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _build_load_page() -> Panel:
	var page := _make_page("LoadPage")

	var title := _make_label(
		page, "LoadTitle", "读档", Vector2(0.0, 58.0),
		Vector2(PANEL_WIDTH, 30.0), 22, Hud.GOLD
	)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	for i in range(SaveSystem.SLOTS.size()):
		var slot: String = SaveSystem.SLOTS[i]
		var button := Button.new()
		button.name = "Slot_%s" % slot
		button.position = Vector2(80.0, 92.0 + 100.0 * float(i))
		button.size = Vector2(480.0, 90.0)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_stylebox_override("normal", Hud.card_style(0.82))
		button.add_theme_stylebox_override("hover", Hud.card_hover_style())
		button.add_theme_stylebox_override("pressed", Hud.card_pressed_style())
		button.add_theme_stylebox_override(
			"focus", Hud.card_style(0.0, Color(0.0, 0.0, 0.0, 0.0))
		)
		button.add_theme_stylebox_override("disabled", Hud.card_disabled_style())
		button.pressed.connect(_on_slot_pressed.bind(slot))
		page.add_child(button)
		var slot_title := _make_label(
			button, "SlotTitle_%s" % slot, str(SLOT_LABELS.get(slot, slot)),
			Vector2(16.0, 8.0), Vector2(448.0, 26.0), 18, Hud.GOLD
		)
		var info := _make_label(
			button, "SlotInfo_%s" % slot, "", Vector2(16.0, 34.0),
			Vector2(448.0, 52.0), 14, Hud.MUTED
		)
		_slot_cards[slot] = {"button": button, "title": slot_title, "info": info}

	var back := _make_menu_button(
		page, "LoadBack", "返回", Vector2(270.0, 520.0), Vector2(100.0, 38.0)
	)
	back.pressed.connect(_on_back_pressed)

	var hint := _make_label(
		page, "LoadHint", "↑↓ 选择    Enter 确认    Esc 返回",
		Vector2(0.0, 560.0), Vector2(PANEL_WIDTH, 22.0), 14, Hud.MUTED
	)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return page


func _build_settings_page() -> Panel:
	var page := _make_page("SettingsPage")

	_setting_labels.append(_make_label(
		page, "MusicLabel", "音乐音量", Vector2(110.0, 96.0),
		Vector2(180.0, 26.0), 18, Hud.TEXT
	))
	_music_slider = HSlider.new()
	_music_slider.name = "MusicSlider"
	_music_slider.min_value = 0.0
	_music_slider.max_value = 1.0
	_music_slider.step = 0.01
	_music_slider.position = Vector2(110.0, 128.0)
	_music_slider.size = Vector2(340.0, 24.0)
	_music_slider.focus_mode = Control.FOCUS_NONE
	_music_slider.value_changed.connect(_on_music_changed)
	page.add_child(_music_slider)
	_music_value = _make_label(
		page, "MusicValue", "", Vector2(460.0, 126.0),
		Vector2(80.0, 26.0), 16, Hud.MUTED
	)

	_setting_labels.append(_make_label(
		page, "SfxLabel", "音效音量", Vector2(110.0, 180.0),
		Vector2(180.0, 26.0), 18, Hud.TEXT
	))
	_sfx_slider = HSlider.new()
	_sfx_slider.name = "SfxSlider"
	_sfx_slider.min_value = 0.0
	_sfx_slider.max_value = 1.0
	_sfx_slider.step = 0.01
	_sfx_slider.position = Vector2(110.0, 212.0)
	_sfx_slider.size = Vector2(340.0, 24.0)
	_sfx_slider.focus_mode = Control.FOCUS_NONE
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	page.add_child(_sfx_slider)
	_sfx_value = _make_label(
		page, "SfxValue", "", Vector2(460.0, 210.0),
		Vector2(80.0, 26.0), 16, Hud.MUTED
	)

	_mute_box = CheckBox.new()
	_mute_box.name = "MuteCheck"
	_mute_box.text = "静音"
	_mute_box.position = Vector2(106.0, 264.0)
	_mute_box.size = Vector2(160.0, 30.0)
	_mute_box.focus_mode = Control.FOCUS_NONE
	_mute_box.add_theme_font_size_override("font_size", 17)
	_mute_box.add_theme_color_override("font_color", Hud.TEXT)
	_mute_box.toggled.connect(_on_mute_toggled)
	page.add_child(_mute_box)

	_settings_back = _make_menu_button(
		page, "SettingsBack", "返回", Vector2(270.0, 512.0), Vector2(100.0, 38.0)
	)
	_settings_back.pressed.connect(_on_back_pressed)

	var hint := _make_label(
		page, "SettingsHint", "↑↓ 选择    ←→ 调整    Esc 返回",
		Vector2(0.0, 460.0), Vector2(PANEL_WIDTH, 22.0), 14, Hud.MUTED
	)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return page


func _make_page(page_name: String) -> Panel:
	var page := Panel.new()
	page.name = page_name
	page.anchor_left = 0.5
	page.anchor_right = 0.5
	page.anchor_top = 0.5
	page.anchor_bottom = 0.5
	page.offset_left = -PANEL_WIDTH * 0.5
	page.offset_right = PANEL_WIDTH * 0.5
	page.offset_top = -PANEL_HEIGHT * 0.5
	page.offset_bottom = PANEL_HEIGHT * 0.5
	page.add_theme_stylebox_override("panel", Hud.panel_style(0.96, Hud.GOLD, 8))
	page.mouse_filter = Control.MOUSE_FILTER_STOP
	page.visible = false
	add_child(page)
	return page


func _make_label(
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


func _make_menu_button(
	parent: Node, node_name: String, text: String, pos: Vector2, button_size: Vector2
) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.position = pos
	button.size = button_size
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_hover_color", Hud.GOLD_BRIGHT)
	button.add_theme_color_override("font_pressed_color", Hud.GOLD_BRIGHT)
	_style_menu_button(button, false)
	parent.add_child(button)
	return button


# ---------------------------------------------------------------- background

func _setup_background() -> void:
	if _background_built:
		return
	_background_built = true
	background_fallback = false
	if _is_headless() or get_viewport() == null:
		_build_fallback_background()
		return
	var cinematic_script: Variant = load(TITLE_CINEMATIC_SCENE)
	if cinematic_script == null:
		_build_fallback_background()
		return
	_cinematic = cinematic_script.new()
	_cinematic.name = "TitleCinematic"
	_background_root.add_child(_cinematic)
	_cinematic.call("build")
	if bool(_cinematic.call("is_fallback")):
		if _cinematic.is_inside_tree():
			_cinematic.queue_free()
		else:
			_cinematic.free()
		_cinematic = null
		_build_fallback_background()


func _is_headless() -> bool:
	var server_name := DisplayServer.get_name()
	return server_name == "headless" or server_name == "dummy"


func _build_fallback_background() -> void:
	background_fallback = true
	var rect := TextureRect.new()
	rect.name = "FallbackBackground"
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	rect.texture = _vertical_gradient(Color("#27303b"), Color("#080a0d"))
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background_root.add_child(rect)


func _advance_intro(delta: float) -> void:
	if _logo_box == null:
		return
	if _intro_time >= INTRO_DURATION:
		return
	_intro_time = minf(_intro_time + maxf(delta, 0.0), INTRO_DURATION)
	var weight := _intro_time / INTRO_DURATION
	var eased := 1.0 - pow(1.0 - weight, 2.0)
	_logo_box.modulate.a = eased
	var offset := INTRO_RISE * (1.0 - eased)
	_logo_box.offset_top = LOGO_TOP - offset
	_logo_box.offset_bottom = LOGO_BOTTOM - offset


func _vertical_gradient(top: Color, bottom: Color) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, top)
	gradient.set_color(1, bottom)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 4
	texture.height = 64
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, 1.0)
	return texture


# ---------------------------------------------------------------- selection / styling

func _set_selected(index: int) -> void:
	if menu_buttons.is_empty():
		return
	selected_index = clampi(index, 0, menu_buttons.size() - 1)
	if (menu_buttons[selected_index] as Button).disabled:
		selected_index = 0
	for i in range(menu_buttons.size()):
		_style_menu_button(menu_buttons[i], i == selected_index)


func _update_load_selection() -> void:
	for item_value in _slot_cards.values():
		var card: Dictionary = item_value
		var button: Button = card["button"]
		_style_card(button, false, button.disabled)
	if _load_order.is_empty() or _load_index < 0 or _load_index >= _load_order.size():
		return
	var selected := _load_order[_load_index]
	var record: Variant = _slot_cards.get(selected, null)
	if record is Dictionary:
		var card: Dictionary = record
		_style_card(card["button"], true, false)


func _style_menu_button(button: Button, selected: bool) -> void:
	var normal: StyleBoxFlat
	if selected:
		normal = Hud.card_hover_style()
	else:
		normal = Hud.card_style(0.52, Color(0.78, 0.65, 0.35, 0.45))
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", Hud.card_hover_style())
	button.add_theme_stylebox_override("pressed", Hud.card_pressed_style())
	button.add_theme_stylebox_override(
		"focus", Hud.card_style(0.0, Color(0.0, 0.0, 0.0, 0.0))
	)
	button.add_theme_stylebox_override("disabled", Hud.card_disabled_style())
	button.add_theme_color_override(
		"font_color", Hud.GOLD_BRIGHT if selected else Hud.TEXT
	)
	button.add_theme_color_override("font_hover_color", Hud.GOLD_BRIGHT)
	button.add_theme_color_override("font_pressed_color", Hud.GOLD_BRIGHT)
	button.add_theme_color_override("font_disabled_color", Color(0.52, 0.49, 0.44))
	button.pivot_offset = button.size * 0.5
	if button.disabled:
		button.scale = Vector2.ONE
	elif selected:
		button.scale = Vector2(HOVER_SCALE, HOVER_SCALE)
	else:
		button.scale = Vector2.ONE


func _style_card(button: Button, selected: bool, disabled: bool) -> void:
	if disabled:
		button.add_theme_stylebox_override("normal", Hud.card_disabled_style())
		button.add_theme_stylebox_override("hover", Hud.card_disabled_style())
		button.add_theme_stylebox_override("pressed", Hud.card_disabled_style())
		button.add_theme_stylebox_override("disabled", Hud.card_disabled_style())
		return
	var normal: StyleBoxFlat
	if selected:
		normal = Hud.card_hover_style()
	else:
		normal = Hud.card_style(0.82)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", Hud.card_hover_style())
	button.add_theme_stylebox_override("pressed", Hud.card_pressed_style())


func _slot_item(slot: String) -> Dictionary:
	for item_value in SaveSystem.list_slots(save_dir):
		var item: Dictionary = item_value
		if str(item.get("slot", "")) == slot:
			return item
	return {}


# ---------------------------------------------------------------- settings

func _sync_settings() -> void:
	if not _built or _music_slider == null:
		return
	_syncing_settings = true
	var music := DEFAULT_MUSIC_VOLUME
	var sfx := DEFAULT_SFX_VOLUME
	var muted := false
	if audio != null:
		music = float(audio.get_music_volume())
		sfx = float(audio.get_sfx_volume())
		muted = bool(audio.is_muted())
	_music_slider.value = music
	_sfx_slider.value = sfx
	_mute_box.button_pressed = muted
	_refresh_volume_labels()
	_syncing_settings = false
	_update_setting_selection()


func _on_music_changed(value: float) -> void:
	if _syncing_settings:
		return
	if audio != null:
		audio.set_music_volume(value)
	_refresh_volume_labels()


func _on_sfx_changed(value: float) -> void:
	if _syncing_settings:
		return
	if audio != null:
		audio.set_sfx_volume(value)
	_refresh_volume_labels()


func _on_mute_toggled(pressed: bool) -> void:
	if _syncing_settings:
		return
	if audio != null:
		audio.set_muted(pressed)


func _refresh_volume_labels() -> void:
	if _music_value != null:
		_music_value.text = "%d%%" % int(round(_music_slider.value * 100.0))
	if _sfx_value != null:
		_sfx_value.text = "%d%%" % int(round(_sfx_slider.value * 100.0))


func _update_setting_selection() -> void:
	for i in range(_setting_labels.size()):
		var label: Label = _setting_labels[i]
		if label == null:
			continue
		label.add_theme_color_override(
			"font_color", Hud.GOLD_BRIGHT if i == _setting_index else Hud.MUTED
		)
	if _mute_box != null:
		if _setting_index == 2:
			_mute_box.modulate = Color(1.0, 1.0, 1.0, 1.0)
		else:
			_mute_box.modulate = Color(0.82, 0.82, 0.82, 1.0)
	if _settings_back != null:
		_style_menu_button(_settings_back, _setting_index == 3)

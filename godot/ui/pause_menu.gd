extends CanvasLayer

# 暂停菜单：Esc 打开（仅地图场景、非对话/战斗/面板中），含存档、读档、设置、
# 返回标题与退出。整个菜单 process_mode = ALWAYS，所以暂停时键盘和鼠标仍然可用。

const SaveSystem = preload("res://core/save_system.gd")
const Hud = preload("res://ui/battle_hud_style.gd")

const PAGES: Array[String] = ["main", "save", "load", "settings"]
const MAIN_ITEMS: Array[String] = ["继续", "存档", "读档", "设置", "返回标题", "退出游戏"]
const SLOT_LABELS := {
	"auto": "自动存档",
	"1": "存档 1",
	"2": "存档 2",
	"3": "存档 3",
}
const DEFAULT_MUSIC_VOLUME := 0.7
const DEFAULT_SFX_VOLUME := 0.8

var game: Variant = null
var current_page: String = "main"
var slot_cards: Dictionary = {}

var _open: bool = false
var _built: bool = false
var _root: Control = null
var _pages: Dictionary = {}
var _main_page: Control = null
var _slot_page: Control = null
var _settings_page: Control = null

var _main_buttons: Array[Button] = []
var _main_index: int = 0
var _slot_title: Label = null
var _slot_back: Button = null
var _slot_index: int = 0
var _slot_order: Array[String] = []

var _music_slider: HSlider = null
var _sfx_slider: HSlider = null
var _music_value: Label = null
var _sfx_value: Label = null
var _mute_box: CheckBox = null
var _settings_back: Button = null
var _syncing_settings: bool = false
var _setting_index: int = 0
var _setting_labels: Array[Label] = []

var _confirm_panel: Panel = null
var _confirm_label: Label = null
var _confirm_action: Callable = Callable()


func _init() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_ensure_built()


# ---------------------------------------------------------------- public API

func open() -> void:
	_ensure_built()
	if _open:
		return
	_open = true
	_root.visible = true
	show_page("main")
	var tree := get_tree()
	if tree != null:
		tree.paused = true


func close() -> void:
	if not _open:
		return
	_open = false
	if _root != null:
		_root.visible = false
	_hide_confirm()
	var tree := get_tree()
	if tree != null:
		tree.paused = false


func is_open() -> bool:
	return _open


func show_page(page: String) -> void:
	_ensure_built()
	if not PAGES.has(page):
		page = "main"
	current_page = page
	var target := "slots" if page == "save" or page == "load" else page
	for key in _pages.keys():
		var node: Control = _pages[key]
		node.visible = str(key) == target
	if page == "save" or page == "load":
		_slot_title.text = "存档" if page == "save" else "读档"
		_slot_index = 0
		refresh_slots()
	elif page == "settings":
		_setting_index = 0
		_sync_settings()
	elif page == "main":
		_set_main_index(_main_index)


func press_slot(slot: String) -> bool:
	_ensure_built()
	var item := _slot_item(slot)
	if current_page == "save":
		if slot == "auto":
			return false
		var exists := bool(item.get("exists", false))
		var corrupt := bool(item.get("corrupt", false))
		if exists and not corrupt:
			_show_confirm("覆盖该存档？", Callable(self, "_do_save").bind(slot))
			return false
		return _do_save(slot)
	if current_page == "load":
		if item.is_empty() or not bool(item.get("exists", false)):
			return false
		if bool(item.get("corrupt", false)):
			return false
		return _do_load(slot)
	return false


func refresh_slots() -> void:
	if not _built:
		return
	var save_mode := current_page == "save"
	var items: Array = SaveSystem.list_slots(_save_dir())
	_slot_order.clear()
	for item_value in items:
		var item: Dictionary = item_value
		var slot := str(item.get("slot", ""))
		var record: Variant = slot_cards.get(slot, null)
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
		var enabled := false
		if save_mode:
			enabled = slot != "auto"
		else:
			enabled = exists and not corrupt
		button.disabled = not enabled
		_style_card(button, false, not enabled)
		if enabled:
			_slot_order.append(slot)
	if _slot_order.is_empty():
		_slot_index = 0
	else:
		_slot_index = clampi(_slot_index, 0, _slot_order.size() - 1)
	_update_slot_selection()


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
	if _open:
		_handle_open_key(key)
		_consume_input()
		return
	if key == KEY_ESCAPE and _can_open():
		open()
		_consume_input()


func _can_open() -> bool:
	if game == null:
		return true
	return bool(game.can_save())


func _handle_open_key(key: int) -> void:
	if _confirm_panel != null and _confirm_panel.visible:
		if key == KEY_ESCAPE:
			_hide_confirm()
		elif key == KEY_ENTER or key == KEY_KP_ENTER:
			_confirm_yes()
		return
	match key:
		KEY_ESCAPE:
			if current_page == "main":
				close()
			else:
				show_page("main")
		KEY_UP:
			_move_selection(-1)
		KEY_DOWN:
			_move_selection(1)
		KEY_LEFT:
			_adjust_setting(-0.05)
		KEY_RIGHT:
			_adjust_setting(0.05)
		KEY_ENTER, KEY_KP_ENTER:
			_activate_selection()
		_:
			pass


func _move_selection(offset: int) -> void:
	if current_page == "main":
		_set_main_index(posmod(_main_index + offset, _main_buttons.size()))
	elif current_page == "save" or current_page == "load":
		if _slot_order.is_empty():
			return
		_slot_index = clampi(_slot_index + offset, 0, _slot_order.size() - 1)
		_update_slot_selection()
	elif current_page == "settings":
		_setting_index = clampi(_setting_index + offset, 0, 3)
		_update_setting_selection()


func _activate_selection() -> void:
	if current_page == "main":
		_activate_main(_main_index)
	elif current_page == "save" or current_page == "load":
		if _slot_order.is_empty():
			return
		press_slot(_slot_order[_slot_index])
	elif current_page == "settings":
		if _setting_index == 2:
			_mute_box.button_pressed = not _mute_box.button_pressed
		elif _setting_index == 3:
			show_page("main")


func _adjust_setting(delta: float) -> void:
	if current_page != "settings":
		return
	if _setting_index == 0:
		_music_slider.value = clampf(_music_slider.value + delta, 0.0, 1.0)
	elif _setting_index == 1:
		_sfx_slider.value = clampf(_sfx_slider.value + delta, 0.0, 1.0)


# ---------------------------------------------------------------- construction

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_root = Control.new()
	_root.name = "PauseRoot"
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	add_child(_root)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.color = Color(0.0, 0.0, 0.0, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var panel := Panel.new()
	panel.name = "Panel"
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -320.0
	panel.offset_right = 320.0
	panel.offset_top = -300.0
	panel.offset_bottom = 300.0
	panel.add_theme_stylebox_override("panel", Hud.panel_style(0.96, Hud.GOLD, 8))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(panel)

	var title := _make_label(panel, "PauseTitle", "暂停", Vector2(0.0, 18.0), Vector2(640.0, 34.0), 26, Hud.GOLD_BRIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_build_main_page(panel)
	_build_slot_page(panel)
	_build_settings_page(panel)
	_build_confirm_panel()
	_pages = {
		"main": _main_page,
		"slots": _slot_page,
		"settings": _settings_page,
	}
	show_page("main")


func _build_main_page(panel: Control) -> void:
	_main_page = Control.new()
	_main_page.name = "MainPage"
	_main_page.anchor_right = 1.0
	_main_page.anchor_bottom = 1.0
	_main_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_main_page)
	for i in range(MAIN_ITEMS.size()):
		var button := _make_menu_button(
			_main_page, "Main_%d" % i, str(MAIN_ITEMS[i]),
			Vector2(170.0, 76.0 + 58.0 * float(i)), Vector2(300.0, 42.0)
		)
		button.pressed.connect(_on_main_pressed.bind(i))
		_main_buttons.append(button)
	var hint := _make_label(
		_main_page, "MainHint", "↑↓ 选择    Enter 确认    Esc 返回",
		Vector2(0.0, 520.0), Vector2(640.0, 24.0), 15, Hud.MUTED
	)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _build_slot_page(panel: Control) -> void:
	_slot_page = Control.new()
	_slot_page.name = "SlotPage"
	_slot_page.anchor_right = 1.0
	_slot_page.anchor_bottom = 1.0
	_slot_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_slot_page)

	_slot_title = _make_label(
		_slot_page, "SlotTitle", "存档", Vector2(0.0, 58.0), Vector2(640.0, 28.0), 20, Hud.GOLD
	)
	_slot_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

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
		button.add_theme_stylebox_override("focus", Hud.card_style(0.0, Color(0.0, 0.0, 0.0, 0.0)))
		button.add_theme_stylebox_override("disabled", Hud.card_disabled_style())
		button.pressed.connect(_on_slot_pressed.bind(slot))
		_slot_page.add_child(button)
		var title := _make_label(
			button, "SlotTitle_%s" % slot, str(SLOT_LABELS.get(slot, slot)),
			Vector2(16.0, 8.0), Vector2(448.0, 26.0), 18, Hud.GOLD
		)
		var info := _make_label(
			button, "SlotInfo_%s" % slot, "", Vector2(16.0, 34.0),
			Vector2(448.0, 52.0), 14, Hud.MUTED
		)
		slot_cards[slot] = {"button": button, "title": title, "info": info}

	_slot_back = _make_menu_button(
		_slot_page, "SlotBack", "返回", Vector2(270.0, 520.0), Vector2(100.0, 38.0)
	)
	_slot_back.pressed.connect(_on_slot_back_pressed)


func _build_settings_page(panel: Control) -> void:
	_settings_page = Control.new()
	_settings_page.name = "SettingsPage"
	_settings_page.anchor_right = 1.0
	_settings_page.anchor_bottom = 1.0
	_settings_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_settings_page)

	_setting_labels.append(_make_label(
		_settings_page, "MusicLabel", "音乐音量", Vector2(110.0, 96.0),
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
	_settings_page.add_child(_music_slider)
	_music_value = _make_label(
		_settings_page, "MusicValue", "", Vector2(460.0, 126.0),
		Vector2(80.0, 26.0), 16, Hud.MUTED
	)

	_setting_labels.append(_make_label(
		_settings_page, "SfxLabel", "音效音量", Vector2(110.0, 180.0),
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
	_settings_page.add_child(_sfx_slider)
	_sfx_value = _make_label(
		_settings_page, "SfxValue", "", Vector2(460.0, 210.0),
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
	_settings_page.add_child(_mute_box)

	_settings_back = _make_menu_button(
		_settings_page, "SettingsBack", "返回", Vector2(270.0, 512.0), Vector2(100.0, 38.0)
	)
	_settings_back.pressed.connect(_on_slot_back_pressed)
	var hint := _make_label(
		_settings_page, "SettingsHint", "↑↓ 选择    ←→ 调整    Esc 返回",
		Vector2(0.0, 460.0), Vector2(640.0, 22.0), 14, Hud.MUTED
	)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _build_confirm_panel() -> void:
	_confirm_panel = Panel.new()
	_confirm_panel.name = "ConfirmPanel"
	_confirm_panel.anchor_left = 0.5
	_confirm_panel.anchor_right = 0.5
	_confirm_panel.anchor_top = 0.5
	_confirm_panel.anchor_bottom = 0.5
	_confirm_panel.offset_left = -220.0
	_confirm_panel.offset_right = 220.0
	_confirm_panel.offset_top = -90.0
	_confirm_panel.offset_bottom = 90.0
	_confirm_panel.add_theme_stylebox_override("panel", Hud.panel_style(0.98, Hud.GOLD, 8))
	_confirm_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm_panel.visible = false
	_root.add_child(_confirm_panel)

	_confirm_label = _make_label(
		_confirm_panel, "ConfirmText", "", Vector2(20.0, 34.0),
		Vector2(400.0, 60.0), 18, Hud.TEXT
	)
	_confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var yes := _make_menu_button(
		_confirm_panel, "ConfirmYes", "确定", Vector2(60.0, 116.0), Vector2(120.0, 38.0)
	)
	yes.pressed.connect(_confirm_yes)
	var no := _make_menu_button(
		_confirm_panel, "ConfirmNo", "取消", Vector2(240.0, 116.0), Vector2(120.0, 38.0)
	)
	no.pressed.connect(_hide_confirm)


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
	button.add_theme_color_override("font_color", Hud.TEXT)
	button.add_theme_color_override("font_hover_color", Hud.GOLD_BRIGHT)
	button.add_theme_color_override("font_pressed_color", Hud.GOLD_BRIGHT)
	_style_button(button, false)
	parent.add_child(button)
	return button


# ---------------------------------------------------------------- main actions

func _on_main_pressed(index: int) -> void:
	_set_main_index(index)
	_activate_main(index)


func _activate_main(index: int) -> void:
	match index:
		0:
			close()
		1:
			show_page("save")
		2:
			show_page("load")
		3:
			show_page("settings")
		4:
			_show_confirm("未存档的进度将丢失，确定吗？", Callable(self, "_do_return_title"))
		5:
			_show_confirm("确定退出游戏？", Callable(self, "_do_quit"))


func _set_main_index(index: int) -> void:
	if _main_buttons.is_empty():
		return
	_main_index = clampi(index, 0, _main_buttons.size() - 1)
	for i in range(_main_buttons.size()):
		_style_button(_main_buttons[i], i == _main_index)


func _do_return_title() -> void:
	if game != null and game.has_method("go_to_title"):
		game.go_to_title()
	else:
		close()


func _do_quit() -> void:
	_hide_confirm()
	var tree := get_tree()
	if tree != null:
		tree.paused = false
		tree.quit()


# ---------------------------------------------------------------- slots

func _on_slot_pressed(slot: String) -> void:
	press_slot(slot)


func _on_slot_back_pressed() -> void:
	show_page("main")


func _do_save(slot: String) -> bool:
	if game == null:
		return false
	var ok := bool(game.save_to_slot(slot))
	refresh_slots()
	return ok


func _do_load(slot: String) -> bool:
	if game == null:
		return false
	var ok := bool(game.load_from_slot(slot))
	if ok:
		close()
	return ok


func _slot_item(slot: String) -> Dictionary:
	for item_value in SaveSystem.list_slots(_save_dir()):
		var item: Dictionary = item_value
		if str(item.get("slot", "")) == slot:
			return item
	return {}


func _save_dir() -> String:
	if game != null:
		var value: Variant = game.get("save_dir")
		if value is String and value != "":
			return value
	return SaveSystem.SAVE_DIR


func _update_slot_selection() -> void:
	for item_value in slot_cards.values():
		var card: Dictionary = item_value
		var button: Button = card["button"]
		_style_card(button, false, button.disabled)
	if _slot_order.is_empty() or _slot_index < 0 or _slot_index >= _slot_order.size():
		return
	var selected := _slot_order[_slot_index]
	var record: Variant = slot_cards.get(selected, null)
	if record is Dictionary:
		var card: Dictionary = record
		_style_card(card["button"], true, false)


func _style_button(button: Button, selected: bool) -> void:
	var normal := Hud.card_hover_style() if selected else Hud.card_style(
		0.52, Color(0.78, 0.65, 0.35, 0.45)
	)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", Hud.card_hover_style())
	button.add_theme_stylebox_override("pressed", Hud.card_pressed_style())
	button.add_theme_stylebox_override("focus", Hud.card_style(0.0, Color(0.0, 0.0, 0.0, 0.0)))
	button.add_theme_color_override("font_color", Hud.GOLD_BRIGHT if selected else Hud.TEXT)


func _style_card(button: Button, selected: bool, disabled: bool) -> void:
	if disabled:
		button.add_theme_stylebox_override("normal", Hud.card_disabled_style())
		button.add_theme_stylebox_override("hover", Hud.card_disabled_style())
		return
	button.add_theme_stylebox_override(
		"normal", Hud.card_hover_style() if selected else Hud.card_style(0.82)
	)
	button.add_theme_stylebox_override("hover", Hud.card_hover_style())
	button.add_theme_stylebox_override("pressed", Hud.card_pressed_style())


# ---------------------------------------------------------------- settings

func _sync_settings() -> void:
	_syncing_settings = true
	var music := DEFAULT_MUSIC_VOLUME
	var sfx := DEFAULT_SFX_VOLUME
	var muted := false
	if game != null and game.audio != null:
		music = float(game.audio.get_music_volume())
		sfx = float(game.audio.get_sfx_volume())
		muted = bool(game.audio.is_muted())
	_music_slider.value = music
	_sfx_slider.value = sfx
	_mute_box.button_pressed = muted
	_refresh_volume_labels()
	_syncing_settings = false
	_update_setting_selection()


func _on_music_changed(value: float) -> void:
	if _syncing_settings:
		return
	if game != null and game.audio != null:
		game.audio.set_music_volume(value)
	_refresh_volume_labels()


func _on_sfx_changed(value: float) -> void:
	if _syncing_settings:
		return
	if game != null and game.audio != null:
		game.audio.set_sfx_volume(value)
	_refresh_volume_labels()


func _on_mute_toggled(pressed: bool) -> void:
	if _syncing_settings:
		return
	if game != null and game.audio != null:
		game.audio.set_muted(pressed)


func _refresh_volume_labels() -> void:
	if _music_value != null:
		_music_value.text = "%d%%" % int(round(_music_slider.value * 100.0))
	if _sfx_value != null:
		_sfx_value.text = "%d%%" % int(round(_sfx_slider.value * 100.0))


func _update_setting_selection() -> void:
	for i in range(_setting_labels.size()):
		var label := _setting_labels[i]
		if label == null:
			continue
		label.add_theme_color_override(
			"font_color", Hud.GOLD_BRIGHT if i == _setting_index else Hud.MUTED
		)
	if _mute_box != null:
		_mute_box.modulate = Color(1.0, 1.0, 1.0, 1.0) if _setting_index == 2 else Color(0.82, 0.82, 0.82, 1.0)
	if _settings_back != null:
		_style_button(_settings_back, _setting_index == 3)


# ---------------------------------------------------------------- confirm / helpers

func _show_confirm(text: String, action: Callable) -> void:
	_confirm_label.text = text
	_confirm_action = action
	_confirm_panel.visible = true


func _hide_confirm() -> void:
	if _confirm_panel != null:
		_confirm_panel.visible = false
	_confirm_action = Callable()


func _confirm_yes() -> void:
	_hide_confirm()
	if _confirm_action.is_valid():
		var action := _confirm_action
		_confirm_action = Callable()
		action.call()


func _consume_input() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()

extends "res://tests/test_case.gd"

const GameState = preload("res://core/game_state.gd")
const SaveSystem = preload("res://core/save_system.gd")
const PauseMenu = preload("res://ui/pause_menu.gd")


func _temp_dir(tag: String) -> String:
	return "user://test_pause_%s_%d" % [tag, Time.get_ticks_usec()]


func _cleanup(dir: String) -> void:
	var access := DirAccess.open(dir)
	if access == null:
		return
	access.list_dir_begin()
	var name := access.get_next()
	while name != "":
		if not access.current_is_dir():
			access.remove(name)
		name = access.get_next()
	access.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))


func _key(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event


func _new_game(dir: String) -> Variant:
	GameState.reset()
	var game: Variant = load("res://ui/game.gd").new()
	game.save_dir = dir
	game.show_town()
	return game


func test_menu_builds_without_game_and_esc_toggles() -> void:
	var menu: Variant = PauseMenu.new()
	menu._input(_key(KEY_ESCAPE))
	assert_true(bool(menu.is_open()), "Esc opens the menu")
	assert_eq(str(menu.current_page), "main", "the menu opens on the main page")
	menu._input(_key(KEY_ESCAPE))
	assert_true(not bool(menu.is_open()), "Esc closes the menu again")
	menu.free()


func test_page_switching_and_esc_back() -> void:
	var menu: Variant = PauseMenu.new()
	menu.open()
	menu.show_page("save")
	assert_eq(str(menu.current_page), "save", "the save page opens")
	menu.show_page("load")
	assert_eq(str(menu.current_page), "load", "the load page opens")
	menu.show_page("settings")
	assert_eq(str(menu.current_page), "settings", "the settings page opens")
	menu._input(_key(KEY_ESCAPE))
	assert_true(bool(menu.is_open()), "Esc on a sub page keeps the menu open")
	assert_eq(str(menu.current_page), "main", "Esc returns to the main page")
	menu._input(_key(KEY_ESCAPE))
	assert_true(not bool(menu.is_open()), "a second Esc closes the menu")
	menu.free()


func test_save_page_writes_slot_and_refreshes_card() -> void:
	var dir := _temp_dir("save")
	var game: Variant = _new_game(dir)
	var menu: Variant = PauseMenu.new()
	menu.game = game
	menu.open()
	menu.show_page("save")
	assert_true(menu.slot_cards.has("2"), "the save page has a card for slot 2")
	assert_true(bool(menu.press_slot("2")), "clicking an empty slot saves into it")
	assert_true(
		FileAccess.file_exists(SaveSystem.slot_path("2", dir)), "slot_2.json is written"
	)
	var card: Dictionary = menu.slot_cards["2"]
	var info: Label = card["info"]
	assert_true(not info.text.contains("空"), "the card refreshes after saving")

	assert_true(not bool(menu.press_slot("2")), "overwriting asks for confirmation first")
	assert_true(bool(menu._confirm_panel.visible), "the overwrite confirmation appears")
	menu._confirm_yes()
	assert_true(not bool(menu._confirm_panel.visible), "confirming closes the prompt")
	assert_true(
		FileAccess.file_exists(SaveSystem.slot_path("2", dir)), "the slot still exists"
	)
	menu.close()
	menu.free()
	game.free()
	_cleanup(dir)


func test_load_page_disables_empty_and_corrupt_slots() -> void:
	var dir := _temp_dir("load")
	var game: Variant = _new_game(dir)
	var menu: Variant = PauseMenu.new()
	menu.game = game
	menu.open()
	menu.show_page("load")
	var empty: Dictionary = menu.slot_cards["3"]
	var empty_button: Button = empty["button"]
	assert_true(empty_button.disabled, "an empty slot is disabled")
	assert_true(not bool(menu.press_slot("3")), "an empty slot cannot be loaded")

	menu.show_page("save")
	menu.press_slot("1")
	menu.show_page("load")
	var filled: Dictionary = menu.slot_cards["1"]
	var filled_button: Button = filled["button"]
	assert_true(not filled_button.disabled, "a valid slot is enabled")
	assert_true(bool(menu.press_slot("1")), "a valid slot loads")
	assert_true(not bool(menu.is_open()), "a successful load closes the menu")

	var path := SaveSystem.slot_path("2", dir)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	menu.open()
	menu.show_page("load")
	var corrupt: Dictionary = menu.slot_cards["2"]
	var corrupt_button: Button = corrupt["button"]
	assert_true(corrupt_button.disabled, "a corrupt slot is disabled")
	menu.close()
	menu.free()
	game.free()
	_cleanup(dir)


func test_settings_sliders_control_the_audio_manager() -> void:
	var dir := _temp_dir("settings")
	var game: Variant = _new_game(dir)
	game.audio.settings_path = dir.path_join("settings.cfg")
	var menu: Variant = PauseMenu.new()
	menu.game = game
	menu.open()
	menu.show_page("settings")
	menu._music_slider.value = 0.33
	assert_near(float(game.audio.get_music_volume()), 0.33, 0.001, "the music slider works")
	menu._sfx_slider.value = 0.44
	assert_near(float(game.audio.get_sfx_volume()), 0.44, 0.001, "the sfx slider works")
	menu._mute_box.button_pressed = true
	assert_true(bool(game.audio.is_muted()), "the mute checkbox works")
	menu.close()
	menu.free()
	game.free()
	_cleanup(dir)


func test_esc_does_not_open_blocked_menus() -> void:
	var dir := _temp_dir("blocked")
	var game: Variant = _new_game(dir)
	var town: Variant = game.current
	town.dialogue_view.start([{"speaker": "narrator", "text": "测试"}])
	var menu: Variant = PauseMenu.new()
	menu.game = game
	menu._input(_key(KEY_ESCAPE))
	assert_true(not bool(menu.is_open()), "Esc does not open the menu during a dialogue")

	game.overlay.toggle_character()
	menu._input(_key(KEY_ESCAPE))
	assert_true(not bool(menu.is_open()), "Esc does not open the menu with a panel open")

	game.overlay.close_all()
	game.show_battle("bandit", 1, false, false)
	menu._input(_key(KEY_ESCAPE))
	assert_true(not bool(menu.is_open()), "Esc does not open the menu in battle")
	menu.free()
	game.free()
	_cleanup(dir)

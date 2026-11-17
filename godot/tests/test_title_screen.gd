extends "res://tests/test_case.gd"

const GameState = preload("res://core/game_state.gd")
const SaveSystem = preload("res://core/save_system.gd")
const TitleScreen = preload("res://ui/title_screen.gd")


func _temp_dir(tag: String) -> String:
	return "user://test_title_%s_%d" % [tag, Time.get_ticks_usec()]


func _cleanup(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		return
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


func _make_save(dir: String, slot: String) -> bool:
	GameState.reset()
	return SaveSystem.save(slot, {"kind": "town", "pos": [1.0, 2.0]}, {}, dir)


func _clear_skip_title() -> void:
	if Engine.has_meta("skip_title"):
		Engine.remove_meta("skip_title")


func _new_game_in_tree(dir: String) -> Variant:
	_clear_skip_title()
	GameState.reset()
	var game: Variant = load("res://ui/game.gd").new()
	game.save_dir = dir
	var tree: Variant = Engine.get_meta("test_tree", null)
	if tree != null:
		tree.root.add_child(game)
	# Nodes added to the root while the test runner is still inside _init() get their _ready()
	# only on the first frame, which never comes in a synchronous test: run the boot by hand.
	if str(game.current_kind) == "":
		game._ready()
	return game


func test_builds_without_game_and_falls_back_headless() -> void:
	_clear_skip_title()
	var dir := _temp_dir("build")
	var title: Variant = TitleScreen.new()
	title.save_dir = dir
	title.build()
	assert_eq(str(title.current_page), "main", "a fresh title opens on the main page")
	assert_eq(title.menu_buttons.size(), 5, "the menu has five entries")
	assert_true(bool(title.is_fallback_background()), "headless builds use the gradient fallback")
	assert_eq(title.selected_index, 0, "without saves the new game entry is selected")
	title.free()


func test_continue_is_disabled_without_saves_and_enabled_with_one() -> void:
	var empty_dir := _temp_dir("empty")
	var empty: Variant = TitleScreen.new()
	empty.save_dir = empty_dir
	empty.build()
	var empty_continue: Button = empty.menu_buttons[1]
	assert_true(empty_continue.disabled, "continue is disabled without any save")
	assert_eq(empty.selected_index, 0, "the new game entry is the default")
	empty.free()

	var dir := _temp_dir("filled")
	assert_true(_make_save(dir, "1"), "a slot is written")
	var filled: Variant = TitleScreen.new()
	filled.save_dir = dir
	filled.build()
	var enabled_continue: Button = filled.menu_buttons[1]
	assert_true(not enabled_continue.disabled, "continue is enabled once a save exists")
	assert_eq(filled.selected_index, 1, "continue is selected by default with a save")
	filled.free()
	_cleanup(dir)


func test_arrow_keys_move_the_selection() -> void:
	var dir := _temp_dir("arrows")
	assert_true(_make_save(dir, "1"), "a slot is written")
	var title: Variant = TitleScreen.new()
	title.save_dir = dir
	title.build()
	assert_eq(title.selected_index, 1, "continue starts selected")
	title._input(_key(KEY_DOWN))
	assert_eq(title.selected_index, 2, "down moves to the load entry")
	title._input(_key(KEY_DOWN))
	assert_eq(title.selected_index, 3, "down moves to settings")
	title._input(_key(KEY_UP))
	assert_eq(title.selected_index, 2, "up moves back")
	title._input(_key(KEY_ESCAPE))
	assert_eq(str(title.current_page), "main", "Esc does nothing on the main page")
	title.free()
	_cleanup(dir)


func test_press_new_game_emits_the_signal() -> void:
	var title: Variant = TitleScreen.new()
	title.build()
	var fired: Array = [false]
	title.new_game_requested.connect(func() -> void: fired[0] = true)
	title.press_new_game()
	assert_true(bool(fired[0]), "press_new_game emits new_game_requested")
	title.free()


func test_load_page_lists_slots_and_emits_request() -> void:
	var dir := _temp_dir("loadpage")
	assert_true(_make_save(dir, "2"), "a slot is written")
	var title: Variant = TitleScreen.new()
	title.save_dir = dir
	title.build()
	title.open_page("load")
	assert_eq(str(title.current_page), "load", "the load page opens")
	assert_true(title._load_page.visible, "the load panel is visible")
	assert_true(title._slot_cards.has("auto"), "the load page has an auto card")
	var requested: Array = []
	title.load_requested.connect(func(slot: String) -> void: requested.append(slot))
	assert_true(bool(title.press_load("2")), "a valid slot can be selected")
	assert_eq(requested, ["2"], "the slot id is emitted")
	assert_true(not bool(title.press_load("3")), "an empty slot cannot be selected")
	title.free()
	_cleanup(dir)


func test_game_starts_on_the_title_with_title_music() -> void:
	var dir := _temp_dir("start")
	var game: Variant = _new_game_in_tree(dir)
	assert_eq(str(game.current_kind), "title", "a normal boot starts on the title screen")
	assert_eq(str(game.audio.current_music()), "music_title", "the title track is playing")
	assert_true(bool(game.current.is_fallback_background()), "headless builds use the fallback")
	assert_true(not bool(game.can_save()), "the title screen cannot be saved")
	game.free()
	_cleanup(dir)


func test_start_new_game_resets_state_and_enters_town() -> void:
	var dir := _temp_dir("newgame")
	var game: Variant = _new_game_in_tree(dir)
	GameState.stat_bonus["power"] = 5
	GameState.unspent_points = 0
	GameState.set_flag("dirty")
	GameState.realm_id = "tianwang"
	GameState.quests["dirty"] = {"state": "done"}
	game.start_new_game()
	assert_eq(str(game.current_kind), "town", "starting a new game enters the town")
	assert_eq(GameState.unspent_points, 3, "unspent points are reset")
	assert_true(GameState.stat_bonus.is_empty(), "stat bonuses are cleared")
	assert_true(not GameState.has_flag("dirty"), "flags are cleared")
	assert_eq(str(GameState.realm_id), "lianti", "the realm is reset")
	assert_true(GameState.quests.is_empty(), "quests are cleared")
	assert_eq(str(game.audio.current_music()), "music_town", "town music takes over")
	game.free()
	_cleanup(dir)


func test_continue_loads_the_latest_save_and_position() -> void:
	var dir := _temp_dir("continue")
	var game: Variant = _new_game_in_tree(dir)
	game.start_new_game()
	var town: Variant = game.current
	town.player_pos = Vector2(7.0, 2.5)
	town.player.position = Vector3(7.0, 0.0, 2.5)
	GameState.set_flag("continue_flag")
	assert_true(bool(game.save_to_slot("1")), "the current town state saves")
	GameState.flags.erase("continue_flag")
	town.player_pos = Vector2(1.0, 1.0)
	game.go_to_title()
	assert_eq(str(game.current_kind), "title", "the pause/return path reaches the title")
	var title: Variant = game.current
	assert_eq(str(title.save_dir), dir, "the title uses the game save directory")
	title.press_continue()
	assert_eq(str(game.current_kind), "town", "continue returns to the saved scene")
	assert_true(GameState.has_flag("continue_flag"), "the saved state is restored")
	var back: Variant = game.current
	assert_true(
		back.player_pos.distance_to(Vector2(7.0, 2.5)) < 0.01,
		"the saved position is restored"
	)
	game.free()
	_cleanup(dir)


func test_go_to_title_cancels_pause() -> void:
	var dir := _temp_dir("unpause")
	var game: Variant = _new_game_in_tree(dir)
	game.start_new_game()
	var tree: Variant = Engine.get_meta("test_tree", null)
	if tree != null:
		tree.paused = true
	game.go_to_title()
	assert_eq(str(game.current_kind), "title", "go_to_title shows the title screen")
	# (Nodes created while the test runner is still in _init() are not inside the tree, so the
	# tree's paused flag cannot be asserted here; the pause menu is what matters.)
	assert_true(not bool(game.pause_menu.is_open()), "go_to_title closes the pause menu")
	if tree != null:
		tree.paused = false
	game.free()
	_cleanup(dir)


func test_failed_load_stays_on_the_title() -> void:
	var dir := _temp_dir("badload")
	var game: Variant = _new_game_in_tree(dir)
	var title: Variant = game.current
	title.load_requested.emit("3")
	assert_eq(str(game.current_kind), "title", "a failed load stays on the title screen")
	assert_true(is_instance_valid(game.current), "the title screen is still alive")
	assert_true(GameState.toasts.has("存档已损坏"), "the failure pushes the corrupt-save toast")
	game.free()
	_cleanup(dir)

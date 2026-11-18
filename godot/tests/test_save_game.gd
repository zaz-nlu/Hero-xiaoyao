extends "res://tests/test_case.gd"

const GameState = preload("res://core/game_state.gd")
const SaveSystem = preload("res://core/save_system.gd")


func _temp_dir(tag: String) -> String:
	return "user://test_save_game_%s_%d" % [tag, Time.get_ticks_usec()]


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


func _new_game(dir: String) -> Variant:
	Engine.set_meta("skip_title", true)
	GameState.reset()
	var game: Variant = load("res://app/game.gd").new()
	game.save_dir = dir
	return game


func test_town_save_and_load_restores_state_and_position() -> void:
	var dir := _temp_dir("town")
	var game: Variant = _new_game(dir)
	game.show_town()
	var town: Variant = game.current
	town.player_pos = Vector2(7.0, 2.5)
	GameState.stat_bonus["power"] = 2
	GameState.unspent_points = 1
	GameState.set_flag("saved_in_town")
	assert_true(bool(game.can_save()), "the town is saveable")
	assert_true(bool(game.save_to_slot("1")), "saving to slot 1 succeeds")
	assert_true(
		FileAccess.file_exists(SaveSystem.slot_path("1", dir)), "the slot file exists"
	)

	GameState.stat_bonus["power"] = 9
	GameState.unspent_points = 3
	GameState.flags.erase("saved_in_town")
	town.player_pos = Vector2(1.0, 1.0)
	assert_true(bool(game.load_from_slot("1")), "loading slot 1 succeeds")
	assert_eq(int(GameState.stat_bonus.get("power", 0)), 2, "stat bonuses are restored")
	assert_eq(GameState.unspent_points, 1, "unspent points are restored")
	assert_true(GameState.has_flag("saved_in_town"), "flags are restored")
	assert_eq(str(game.current_kind), "town", "loading a town save returns to the town")
	var back: Variant = game.current
	assert_true(
		back.player_pos.distance_to(Vector2(7.0, 2.5)) < 0.01,
		"the player position is restored"
	)
	game.free()
	_cleanup(dir)


func test_tavern_save_and_load_restores_position() -> void:
	var dir := _temp_dir("tavern")
	var game: Variant = _new_game(dir)
	GameState.set_flag("bandits_entered")
	game.show_tavern()
	var tavern: Variant = game.current
	tavern.player_pos = Vector2(11.0, 3.5)
	assert_true(bool(game.save_to_slot("2")), "the tavern can be saved")
	GameState.flags.erase("bandits_entered")
	tavern.player_pos = Vector2(3.0, -1.0)
	assert_true(bool(game.load_from_slot("2")), "the tavern save loads")
	assert_eq(str(game.current_kind), "tavern", "loading a tavern save returns to the tavern")
	assert_true(GameState.has_flag("bandits_entered"), "the tavern state flag is restored")
	var back: Variant = game.current
	assert_true(
		back.player_pos.distance_to(Vector2(11.0, 3.5)) < 0.01,
		"the tavern position is restored"
	)
	assert_true(
		GameState.tavern_return_pos == null, "the tavern spawn override is consumed"
	)
	game.free()
	_cleanup(dir)


func test_forest_save_and_load_restores_position() -> void:
	var dir := _temp_dir("forest")
	var game: Variant = _new_game(dir)
	game.show_forest()
	var forest: Variant = game.current
	var pos := Vector2(0.0, 18.0)
	if not bool(forest._spawn_walkable(pos)):
		pos = Vector2(0.0, 21.5)
	forest.player_pos = pos
	assert_true(bool(game.save_to_slot("3")), "the forest can be saved")
	GameState.set_flag("forest_noise")
	forest.player_pos = Vector2(10.0, 10.0)
	assert_true(bool(game.load_from_slot("3")), "the forest save loads")
	assert_true(not GameState.has_flag("forest_noise"), "the old state is replaced")
	assert_eq(str(game.current_kind), "forest", "loading a forest save returns to the forest")
	var back: Variant = game.current
	assert_true(
		back.player_pos.distance_to(pos) < 0.01, "the forest position is restored"
	)
	game.free()
	_cleanup(dir)


func test_autosave_creates_auto_slot_on_scene_entry() -> void:
	var dir := _temp_dir("auto")
	var game: Variant = _new_game(dir)
	game.show_forest()
	assert_true(
		FileAccess.file_exists(SaveSystem.slot_path("auto", dir)),
		"entering the forest writes an auto save"
	)
	var data := SaveSystem.load_slot("auto", dir)
	var location: Dictionary = data.get("location", {})
	assert_eq(
		str(location.get("kind", "")), "forest",
		"the auto save records the forest"
	)
	game.free()
	_cleanup(dir)


func test_can_save_is_false_in_dialogue_battle_and_cutscene() -> void:
	var dir := _temp_dir("blocked")
	var game: Variant = _new_game(dir)
	game.show_town()
	var town: Variant = game.current
	town.dialogue_view.start([{"speaker": "narrator", "text": "测试"}])
	assert_true(bool(town.is_dialogue_active()), "the dialogue is running")
	assert_true(not bool(game.can_save()), "a dialogue blocks saving")
	assert_true(not bool(game.save_to_slot("1")), "saving during a dialogue fails")
	game.show_battle("bandit", 1, false, false)
	assert_true(not bool(game.can_save()), "a battle blocks saving")
	game.show_tavern()
	var tavern: Variant = game.current
	tavern.cutscene_running = true
	assert_true(not bool(game.can_save()), "a tavern cutscene blocks saving")
	game.show_town()
	game.overlay.toggle_character()
	assert_true(not bool(game.can_save()), "an open panel blocks saving")
	game.overlay.close_all()
	assert_true(bool(game.can_save()), "closing the panel makes saving possible again")
	game.free()
	_cleanup(dir)


func test_load_missing_slot_fails_with_toast() -> void:
	var dir := _temp_dir("missing")
	var game: Variant = _new_game(dir)
	game.show_town()
	assert_true(not bool(game.load_from_slot("3")), "loading an empty slot fails")
	assert_true(
		GameState.toasts.has("存档已损坏"), "the failure is explained with a toast"
	)
	game.free()
	_cleanup(dir)

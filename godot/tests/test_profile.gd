extends "res://tests/test_case.gd"

const Profile = preload("res://core/profile.gd")
const GameState = preload("res://core/game_state.gd")


func _temp_path(tag: String) -> String:
	return "user://test_profile_%s_%d.cfg" % [tag, Time.get_ticks_usec()]


func _temp_dir(tag: String) -> String:
	return "user://test_profile_saves_%s_%d" % [tag, Time.get_ticks_usec()]


func _cleanup_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _cleanup_dir(dir: String) -> void:
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


func _new_game(profile_path: String, save_dir: String) -> Variant:
	Engine.set_meta("skip_title", true)
	GameState.reset()
	var game: Variant = load("res://app/game.gd").new()
	game.profile_path = profile_path
	game.save_dir = save_dir
	return game


func test_default_profile_unlocks_town_and_tavern_outside() -> void:
	var path := _temp_path("defaults")
	assert_eq(Profile.unlocked_ids(path), ["town", "tavern_outside"], "fresh profile defaults")
	assert_true(Profile.is_unlocked("town", path), "town is always unlocked")
	assert_true(Profile.is_unlocked("tavern_outside", path), "tavern outside is always unlocked")
	assert_true(not Profile.is_unlocked("forest", path), "forest is locked by default")
	assert_eq(Profile.place_name("forest"), "紫霞林", "place names come from PLACES")
	_cleanup_file(path)


func test_unlock_rules_and_ordering() -> void:
	var path := _temp_path("unlock")
	assert_true(Profile.unlock("forest", path), "a locked known place unlocks")
	assert_true(not Profile.unlock("forest", path), "unlocking twice returns false")
	assert_true(not Profile.unlock("nowhere", path), "an unknown id returns false")
	assert_true(not Profile.unlock("town", path), "an always place is already unlocked")
	assert_true(Profile.unlock("west_street", path), "west street unlocks")
	assert_eq(
		Profile.unlocked_ids(path),
		["town", "tavern_outside", "west_street", "forest"],
		"ids follow the PLACES order"
	)
	_cleanup_file(path)


func test_profile_persists_across_reads() -> void:
	var path := _temp_path("persist")
	assert_true(Profile.unlock("tavern_inside", path), "tavern inside unlocks")
	assert_true(Profile.is_unlocked("tavern_inside", path), "a fresh read sees the unlock")
	assert_true(Profile.unlock("gate", path), "gate unlocks")
	assert_eq(
		Profile.unlocked_ids(path),
		["town", "tavern_outside", "tavern_inside", "gate"],
		"all stored unlocks are reported"
	)
	_cleanup_file(path)


func test_missing_and_corrupt_profile_fall_back_to_defaults() -> void:
	var missing := _temp_path("missing")
	assert_eq(Profile.unlocked_ids(missing), ["town", "tavern_outside"], "missing file defaults")

	var corrupt := _temp_path("corrupt")
	var file := FileAccess.open(corrupt, FileAccess.WRITE)
	assert_true(file != null, "the corrupt fixture is writable")
	if file != null:
		file.store_string("this is not a config file\n[[[\n")
		file.close()
	assert_eq(Profile.unlocked_ids(corrupt), ["town", "tavern_outside"], "corrupt file defaults")
	assert_true(not Profile.is_unlocked("forest", corrupt), "no bogus unlock leaks in")
	_cleanup_file(missing)
	_cleanup_file(corrupt)


func test_game_unlocks_forest_and_tavern_on_entry() -> void:
	var path := _temp_path("game_places")
	var dir := _temp_dir("places")
	var game: Variant = _new_game(path, dir)
	game.show_forest()
	assert_true(Profile.is_unlocked("forest", path), "entering the forest unlocks it")
	game.show_tavern()
	assert_true(Profile.is_unlocked("tavern_inside", path), "entering the tavern unlocks it")
	game.free()
	_cleanup_file(path)
	_cleanup_dir(dir)


func test_game_unlocks_gate_after_boss_and_west_street_by_position() -> void:
	var path := _temp_path("game_progress")
	var dir := _temp_dir("progress")
	var game: Variant = _new_game(path, dir)
	game.show_town()
	GameState.set_flag("boss_defeated")
	game._process(0.0)
	assert_true(Profile.is_unlocked("gate", path), "the boss flag unlocks the gate in any scene")

	var town: Variant = game.current
	town.player_pos = Vector2(-40.0, 0.0)
	game._process(0.5)
	assert_true(Profile.is_unlocked("west_street", path), "walking west unlocks the west street")
	assert_true(not Profile.is_unlocked("forest", path), "unrelated places stay locked")
	game.free()
	GameState.reset()
	_cleanup_file(path)
	_cleanup_dir(dir)

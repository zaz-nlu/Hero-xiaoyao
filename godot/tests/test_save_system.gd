extends "res://tests/test_case.gd"

const GameState = preload("res://core/game_state.gd")
const SaveSystem = preload("res://core/save_system.gd")
const Progression = preload("res://core/progression.gd")


func _temp_dir(tag: String) -> String:
	return "user://test_saves_%s_%d" % [tag, Time.get_ticks_usec()]


func _cleanup(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		return
	var access := DirAccess.open(dir)
	if access == null:
		return
	access.list_dir_begin()
	var name := access.get_next()
	while name != "":
		if access.current_is_dir():
			_cleanup(dir.path_join(name))
		else:
			access.remove(name)
		name = access.get_next()
	access.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))


func _write_raw(path: String, payload: Dictionary) -> void:
	_ensure_parent(path)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(payload))
	file.close()


func _ensure_parent(path: String) -> void:
	var parent := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(parent)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(parent))


func _slot_item(items: Array, slot: String) -> Dictionary:
	for item_value in items:
		var item: Dictionary = item_value
		if str(item.get("slot", "")) == slot:
			return item
	return {}


func test_game_state_round_trip() -> void:
	GameState.reset()
	GameState.set_flag("met_elder", true)
	GameState.flags["marker"] = Vector2(1.5, -2.25)
	GameState.flags["nested"] = {
		"where": Vector3(1.0, 2.0, 3.0),
		"tags": [1, 2, 3],
	}
	GameState.known_moves = {"basic_sword": 2}
	GameState.stat_bonus = {"power": 2, "speed": 1}
	GameState.equipment = {"weapon": "plain_sword"}
	GameState.inventory = {"herb": 3}
	GameState.quests = {"herbs": {"state": "active", "progress": {"herb": 1}}}
	GameState.mastery_exp = {"basic_sword": 40}
	GameState.mastery_total = {"basic_sword": 100}
	GameState.unspent_points = 5
	GameState.dialogue_counters = {"elder": 2}
	GameState.realm_id = "renjie"
	GameState.realm_stage = 2
	GameState.age = 12
	GameState.playtime = 123.5

	var saved := GameState.to_dict()
	GameState.reset()
	assert_true(GameState.flags.is_empty(), "reset clears the flags")
	assert_eq(GameState.unspent_points, 3, "reset restores the starting points")
	assert_eq(GameState.age, 9, "reset restores the starting age")

	GameState.from_dict(saved)
	assert_true(GameState.has_flag("met_elder"), "flags survive the round trip")
	assert_eq(GameState.flags["marker"], Vector2(1.5, -2.25), "Vector2 flags survive")
	var nested: Dictionary = GameState.flags["nested"]
	assert_eq(nested["where"], Vector3(1.0, 2.0, 3.0), "Vector3 flags survive")
	assert_eq(nested["tags"], [1, 2, 3], "plain arrays are not mistaken for vectors")
	assert_eq(int(GameState.known_moves["basic_sword"]), 2, "known moves survive")
	assert_eq(int(GameState.stat_bonus["power"]), 2, "stat bonuses survive")
	assert_eq(str(GameState.equipment["weapon"]), "plain_sword", "equipment survives")
	assert_eq(int(GameState.inventory["herb"]), 3, "inventory survives")
	var quest: Dictionary = GameState.quests["herbs"]
	var quest_progress: Dictionary = quest["progress"]
	assert_eq(str(quest["state"]), "active", "quest state survives")
	assert_eq(int(quest_progress["herb"]), 1, "nested quest progress survives")
	assert_eq(int(GameState.mastery_exp["basic_sword"]), 40, "mastery exp survives")
	assert_eq(int(GameState.mastery_total["basic_sword"]), 100, "mastery total survives")
	assert_eq(GameState.unspent_points, 5, "unspent points survive")
	assert_eq(int(GameState.dialogue_counters["elder"]), 2, "dialogue counters survive")
	assert_eq(GameState.realm_id, "renjie", "realm id survives")
	assert_eq(GameState.realm_stage, 2, "realm stage survives")
	assert_eq(GameState.age, 12, "age survives")
	assert_near(GameState.playtime, 123.5, 0.001, "playtime survives")


func test_from_dict_ignores_bad_types() -> void:
	GameState.reset()
	GameState.from_dict({
		"flags": [],
		"inventory": "nope",
		"unspent_points": "many",
		"realm_stage": [2],
		"age": {},
		"playtime": "long",
	})
	assert_true(GameState.flags.is_empty(), "a bad flags value is ignored")
	assert_true(GameState.inventory.is_empty(), "a bad inventory value is ignored")
	assert_eq(GameState.unspent_points, 3, "a bad point value keeps the default")
	assert_eq(GameState.realm_stage, 1, "a bad stage keeps the default")
	assert_eq(GameState.age, 9, "a bad age keeps the default")
	assert_near(GameState.playtime, 0.0, 0.001, "a bad playtime keeps the default")


func test_save_and_load_round_trip() -> void:
	var dir := _temp_dir("roundtrip")
	GameState.reset()
	GameState.set_flag("saved_here")
	GameState.unspent_points = 2
	GameState.playtime = 42.0
	var ok := SaveSystem.save(
		"1", {"kind": "forest", "pos": [3.25, 9.5]}, {"hp": 123}, dir
	)
	assert_true(ok, "save writes a file")
	assert_true(
		FileAccess.file_exists(SaveSystem.slot_path("1", dir)),
		"slot_1.json exists"
	)
	var data := SaveSystem.load_slot("1", dir)
	assert_eq(int(data.get("version", 0)), 1, "the version is written")
	var location: Dictionary = data.get("location", {})
	assert_eq(str(location.get("kind", "")), "forest", "location kind is kept")
	var pos: Array = location.get("pos", [])
	assert_near(float(pos[0]), 3.25, 0.001, "location x is kept")
	assert_near(float(pos[1]), 9.5, 0.001, "location y is kept")
	var summary: Dictionary = data.get("summary", {})
	assert_eq(int(summary.get("hp", 0)), 123, "summary extras override the defaults")
	assert_eq(str(summary.get("place", "")), "紫霞林", "summary names the forest")
	GameState.reset()
	GameState.from_dict(data.get("state", {}))
	assert_true(GameState.has_flag("saved_here"), "saved state can be restored")
	assert_eq(GameState.unspent_points, 2, "saved points are restored")
	assert_near(GameState.playtime, 42.0, 0.001, "saved playtime is restored")
	_cleanup(dir)


func test_atomic_write_failure_keeps_old_save() -> void:
	var dir := _temp_dir("atomic")
	GameState.reset()
	GameState.set_flag("old_state")
	var ok := SaveSystem.save("1", {"kind": "town", "pos": [1.0, 2.0]}, {}, dir)
	assert_true(ok, "the first save succeeds")
	var path := SaveSystem.slot_path("1", dir)
	var tmp_path := path + ".tmp"
	assert_true(
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(tmp_path)) == OK,
		"a directory blocks the temp file"
	)
	GameState.flags.erase("old_state")
	GameState.set_flag("new_state")
	var failed := SaveSystem.save("1", {"kind": "tavern", "pos": [4.0, 5.0]}, {}, dir)
	assert_true(not failed, "a blocked temp file makes the save fail")
	var data := SaveSystem.load_slot("1", dir)
	var location: Dictionary = data.get("location", {})
	assert_eq(str(location.get("kind", "")), "town", "the old save is still readable")
	GameState.from_dict(data.get("state", {}))
	assert_true(GameState.has_flag("old_state"), "the old state was not replaced")
	assert_true(not GameState.has_flag("new_state"), "the failed write left no partial state")
	_cleanup(dir)


func test_corrupt_json_falls_back_to_bak_then_reports_corrupt() -> void:
	var dir := _temp_dir("corrupt")
	GameState.reset()
	GameState.set_flag("backup_state")
	assert_true(
		SaveSystem.save("2", {"kind": "forest", "pos": [6.0, 7.0]}, {}, dir),
		"the save succeeds"
	)
	var path := SaveSystem.slot_path("2", dir)
	var bak_path := path + ".bak"
	var text := FileAccess.get_file_as_string(path)
	var bak := FileAccess.open(bak_path, FileAccess.WRITE)
	assert_true(bak != null, "the backup can be written")
	bak.store_string(text)
	bak.close()
	var broken := FileAccess.open(path, FileAccess.WRITE)
	assert_true(broken != null, "the primary file can be corrupted")
	broken.store_string("{not json")
	broken.close()

	var recovered := SaveSystem.load_slot("2", dir)
	assert_true(not recovered.is_empty(), "a corrupt primary falls back to .bak")
	var recovered_location: Dictionary = recovered.get("location", {})
	assert_eq(
		str(recovered_location.get("kind", "")), "forest",
		"the backup has the right location"
	)

	var broken_bak := FileAccess.open(bak_path, FileAccess.WRITE)
	broken_bak.store_string("[still, not, a, save]")
	broken_bak.close()
	assert_true(SaveSystem.load_slot("2", dir).is_empty(), "two bad files return an empty save")
	var item := _slot_item(SaveSystem.list_slots(dir), "2")
	assert_true(bool(item.get("exists", false)), "the slot still exists")
	assert_true(bool(item.get("corrupt", false)), "the slot is marked corrupt")
	_cleanup(dir)


func test_list_slots_is_fixed_at_four() -> void:
	var dir := _temp_dir("list")
	var items := SaveSystem.list_slots(dir)
	assert_eq(items.size(), 4, "there are always four slots")
	assert_eq(str(items[0].get("slot", "")), "auto", "auto is first")
	assert_eq(str(items[1].get("slot", "")), "1", "slot 1 is second")
	assert_eq(str(items[2].get("slot", "")), "2", "slot 2 is third")
	assert_eq(str(items[3].get("slot", "")), "3", "slot 3 is fourth")
	for item_value in items:
		var item: Dictionary = item_value
		assert_true(not bool(item.get("exists", true)), "empty slots do not exist")
		assert_true(not bool(item.get("corrupt", true)), "empty slots are not corrupt")
	assert_true(not SaveSystem.has_any(dir), "an empty directory has no saves")
	_cleanup(dir)


func test_latest_delete_and_has_any() -> void:
	var dir := _temp_dir("latest")
	_write_raw(SaveSystem.slot_path("1", dir), {
		"version": 1,
		"saved_at": 100,
		"playtime": 0.0,
		"location": {"kind": "town", "pos": [0.0, 0.0]},
		"summary": {},
		"state": {},
	})
	_write_raw(SaveSystem.slot_path("2", dir), {
		"version": 1,
		"saved_at": 200,
		"playtime": 0.0,
		"location": {"kind": "forest", "pos": [0.0, 0.0]},
		"summary": {},
		"state": {},
	})
	assert_true(SaveSystem.has_any(dir), "has_any sees the saves")
	assert_eq(SaveSystem.latest_slot(dir), "2", "the newest timestamp wins")
	assert_true(SaveSystem.delete_slot("2", dir), "delete removes a slot")
	assert_true(not FileAccess.file_exists(SaveSystem.slot_path("2", dir)), "the file is gone")
	assert_eq(SaveSystem.latest_slot(dir), "1", "the older save becomes the latest")
	assert_true(not SaveSystem.delete_slot("3", dir), "deleting an empty slot reports nothing removed")
	_cleanup(dir)


func test_format_playtime() -> void:
	assert_eq(SaveSystem.format_playtime(30.0), "不到1分", "under a minute")
	assert_eq(SaveSystem.format_playtime(720.0), "12分", "minutes")
	assert_eq(SaveSystem.format_playtime(4980.0), "1小时23分", "hours and minutes")
	assert_eq(SaveSystem.format_time(0).length(), 11, "time is formatted as MM-DD HH:MM")
	assert_true(SaveSystem.format_time(0).contains(":"), "the time contains a colon")
	assert_true(SaveSystem.format_time(0).contains("-"), "the date contains a dash")

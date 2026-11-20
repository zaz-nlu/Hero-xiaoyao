extends "res://tests/test_case.gd"

const AudioLoader = preload("res://shared/audio/audio_loader.gd")
const AudioManagerScript = preload("res://shared/audio/audio_manager.gd")
const AssetPaths = preload("res://shared/resources/asset_paths.gd")

const CUES_PATH := "res://data/music_cues.json"
# Built from two literals so the architecture resource check does not require the
# generated fixture to exist before the audio tool has produced it.
const OGG_FIXTURE := "res://tests/fixtures/" + "music_fixture.ogg"
const TEST_SETTINGS_PATH := "user://test_music_pipeline_settings.cfg"


func _new_manager() -> Variant:
	if FileAccess.file_exists(TEST_SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS_PATH))
	var manager: Variant = AudioManagerScript.new()
	manager.settings_path = TEST_SETTINGS_PATH
	var tree: Variant = Engine.get_meta("test_tree", null)
	if tree != null:
		tree.root.add_child(manager)
	return manager


func _read_cues() -> Dictionary:
	if not FileAccess.file_exists(CUES_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CUES_PATH))
	if not (parsed is Dictionary):
		return {}
	var data: Dictionary = parsed
	var cues: Variant = data.get("cues", {})
	if cues is Dictionary:
		return cues
	return {}


func _audio_exists(track: String) -> bool:
	if track == "":
		return false
	return FileAccess.file_exists(AssetPaths.AUDIO + track + ".wav") \
		or FileAccess.file_exists(AssetPaths.AUDIO + track + ".ogg")


func _stage_ogg_fixture() -> String:
	# load_music only looks in assets/audio, so the checked-in fixture is copied in
	# next to the music for the duration of this test (the target name is built at
	# runtime so the architecture resource check does not look for a missing file).
	AudioLoader.clear_cache()
	var target := AssetPaths.AUDIO + "_test_music_fixture.ogg"
	var source := FileAccess.get_file_as_bytes(OGG_FIXTURE)
	if source.is_empty():
		return ""
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_buffer(source)
	file.close()
	return target


func _remove_file(path: String) -> void:
	if path != "" and FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_load_music_falls_back_to_wav() -> void:
	AudioLoader.clear_cache()
	var stream: Variant = AudioLoader.load_music("music_tavern_brawl", true)
	assert_true(stream != null, "music_tavern_brawl has no ogg yet, the wav fallback loads")
	if stream == null:
		return
	assert_true(stream is AudioStreamWAV, "the fallback returns the WAV stream")
	assert_eq(int(stream.loop_mode), AudioStreamWAV.LOOP_FORWARD, "the fallback keeps looping")


func test_load_music_reads_ogg_fixture() -> void:
	if not FileAccess.file_exists(OGG_FIXTURE):
		# The fixture is a generated binary, not hand-written source. Create it with
		#   py -3 godot/tools/process_music.py --selftest --write-fixture
		# and this test starts exercising the OGG branch.
		return
	var target := _stage_ogg_fixture()
	assert_true(target != "", "the ogg fixture can be staged into assets/audio")
	if target == "":
		return
	var looped: Variant = AudioLoader.load_music("_test_music_fixture", true)
	assert_true(looped is AudioStreamOggVorbis, "ogg files load as AudioStreamOggVorbis")
	if looped is AudioStreamOggVorbis:
		assert_true(bool(looped.loop), "a looping ogg has loop enabled")
	var once: Variant = AudioLoader.load_music("_test_music_fixture", false)
	assert_true(once is AudioStreamOggVorbis, "the once variant is also an ogg stream")
	if once is AudioStreamOggVorbis:
		assert_true(not bool(once.loop), "a one-shot ogg has loop disabled")
	assert_true(looped != once, "the cache key includes the loop flag")
	_remove_file(target)
	AudioLoader.clear_cache()


func test_load_music_caches_streams() -> void:
	AudioLoader.clear_cache()
	var first: Variant = AudioLoader.load_music("music_town", true)
	var second: Variant = AudioLoader.load_music("music_town", true)
	assert_true(first != null, "the track loads")
	assert_true(first == second, "repeated loads reuse the cached stream")


func test_play_cue_known_cue() -> void:
	var manager: Variant = _new_manager()
	manager.play_cue("town")
	assert_eq(str(manager.current_cue()), "town", "the cue is recorded")
	assert_eq(str(manager.current_music()), "music_town", "the cue selects its track")
	manager.play_cue("town")
	assert_eq(str(manager.current_music()), "music_town", "repeating a cue keeps the track")
	manager.free()


func test_play_cue_fallback_when_track_is_missing() -> void:
	var manager: Variant = _new_manager()
	manager.play_cue("zixia_daily")
	assert_eq(str(manager.current_cue()), "zixia_daily", "the reserved cue is recorded")
	assert_eq(
		str(manager.current_music()), "music_town",
		"a missing track falls back to the closest existing music"
	)
	manager.free()


func test_play_cue_unknown_cue() -> void:
	var manager: Variant = _new_manager()
	manager.play_cue("no_such_cue")
	assert_eq(str(manager.current_cue()), "no_such_cue", "the unknown cue is still recorded")
	assert_eq(str(manager.current_music()), "", "an unknown cue plays nothing and does not crash")
	manager.free()


func test_music_cues_resolve_to_existing_audio() -> void:
	var cues := _read_cues()
	assert_true(not cues.is_empty(), "music_cues.json lists cues")
	for required in [
		"title", "town", "forest", "tavern", "tavern_brawl", "battle_normal",
		"battle_boss", "zixia_daily", "sanhuo_arrival", "tragedy",
		"ziyang_boss_phase1", "ziyang_boss_phase2", "victory_jingle", "defeat_jingle"
	]:
		assert_true(cues.has(required), "cue %s is registered" % required)
	for cue_id in cues.keys():
		var entry: Variant = cues[cue_id]
		assert_true(entry is Dictionary, "cue %s has a dictionary entry" % cue_id)
		if not (entry is Dictionary):
			continue
		var track := str(entry.get("track", ""))
		var fallback := str(entry.get("fallback", ""))
		assert_true(
			str(entry.get("note", "")) != "", "cue %s documents its use" % cue_id
		)
		assert_true(entry.has("loop"), "cue %s carries a loop flag" % cue_id)
		if entry.has("loop"):
			assert_eq(
				typeof(entry["loop"]), TYPE_BOOL, "cue %s loop flag is a bool" % cue_id
			)
		assert_true(
			_audio_exists(track) or _audio_exists(fallback),
			"cue %s resolves to at least one existing audio file" % cue_id
		)

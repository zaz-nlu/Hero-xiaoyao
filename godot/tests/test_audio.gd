extends "res://tests/test_case.gd"

const AudioLoader = preload("res://core/audio_loader.gd")
const AudioManagerScript = preload("res://ui/audio_manager.gd")
const GameState = preload("res://core/game_state.gd")

const TEST_SETTINGS_PATH := "user://test_audio_settings.cfg"


func _new_manager() -> Variant:
	if FileAccess.file_exists(TEST_SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS_PATH))
	var manager: Variant = AudioManagerScript.new()
	manager.settings_path = TEST_SETTINGS_PATH
	# Playback needs the players inside the scene tree; the test runner exposes its
	# SceneTree through Engine metadata. advance() is still driven manually.
	var tree: Variant = Engine.get_meta("test_tree", null)
	if tree != null:
		tree.root.add_child(manager)
	return manager


func _new_game() -> Variant:
	var game: Variant = load("res://ui/game.gd").new()
	game.show_town()
	return game


func _finish_dialogue(view: Variant) -> void:
	for i in range(60):
		if not bool(view.dialogue_view.is_active()):
			return
		view.dialogue_view.advance()


func test_load_wav_parses_music_town() -> void:
	AudioLoader.clear_cache()
	var stream: Variant = AudioLoader.load_wav("music_town", true)
	assert_true(stream != null, "music_town.wav loads")
	if stream == null:
		return
	assert_eq(int(stream.mix_rate), 22050, "the mix rate comes from the header")
	assert_eq(int(stream.loop_mode), AudioStreamWAV.LOOP_FORWARD, "looping streams use LOOP_FORWARD")
	assert_true(int(stream.loop_end) > 0, "the loop end is set to the sample count")
	assert_eq(bool(stream.stereo), false, "the files are mono")


func test_load_wav_missing_file_returns_null() -> void:
	assert_true(AudioLoader.load_wav("no_such_track", true) == null, "missing files return null")
	assert_true(AudioLoader.load_wav("", true) == null, "an empty name returns null")


func test_load_wav_without_loop_is_disabled() -> void:
	var stream: Variant = AudioLoader.load_wav("jingle_victory", false)
	assert_true(stream != null, "jingle_victory.wav loads")
	if stream == null:
		return
	assert_eq(int(stream.loop_mode), AudioStreamWAV.LOOP_DISABLED, "jingles do not loop")


func test_play_music_crossfades_and_stops_old_player() -> void:
	# Headless runs have no real audio device, so AudioStreamPlayer.playing is unreliable here;
	# check the streams and the volumes the manager drives instead.
	var manager: Variant = _new_manager()
	manager.play_music("music_town")
	assert_eq(str(manager.current_music()), "music_town", "the current track is reported")
	manager.advance(1.5)
	manager.play_music("music_forest")
	assert_eq(str(manager.current_music()), "music_forest", "the track switches")
	assert_true(manager.music_a.stream != null, "the old player keeps its stream while fading out")
	assert_true(float(manager.music_a.volume_db) > -60.0, "the old player is still audible right after the switch")
	assert_true(manager.music_b.stream != null, "the new player has the new stream")
	assert_true(float(manager.music_b.volume_db) < -20.0, "the new player starts almost silent")
	manager.advance(1.5)
	assert_true(float(manager.music_a.volume_db) <= -60.0 or not bool(manager.music_a.playing), "the old player is silent after the fade")
	assert_near(float(manager.music_b.volume_db), 0.0, 0.2, "the new player reaches full volume")
	manager.free()


func test_play_music_same_track_is_ignored() -> void:
	var manager: Variant = _new_manager()
	manager.play_music("music_town")
	manager.advance(1.5)
	manager.play_music("music_town")
	assert_eq(str(manager.current_music()), "music_town", "the track stays")
	assert_true(not bool(manager.music_b.playing), "no second player is started")
	manager.free()


func test_ambience_switch() -> void:
	var manager: Variant = _new_manager()
	manager.play_ambience("amb_forest_birds")
	assert_eq(str(manager.current_ambience()), "amb_forest_birds", "the ambience is reported")
	manager.advance(2.0)
	assert_near(float(manager.ambience.volume_db), 0.0, 0.2, "the ambience fades in")
	manager.play_ambience("")
	assert_eq(str(manager.current_ambience()), "", "an empty name stops the ambience")
	manager.advance(2.0)
	assert_true(not bool(manager.ambience.playing), "the ambience player stops")
	manager.free()


func test_volume_and_mute() -> void:
	var manager: Variant = _new_manager()
	manager.set_music_volume(0.35)
	manager.set_sfx_volume(0.45)
	assert_near(manager.get_music_volume(), 0.35, 0.0001, "music volume is stored")
	assert_near(manager.get_sfx_volume(), 0.45, 0.0001, "sfx volume is stored")
	var music_bus: int = AudioServer.get_bus_index("Music")
	var sfx_bus: int = AudioServer.get_bus_index("SFX")
	assert_near(
		float(AudioServer.get_bus_volume_db(music_bus)), linear_to_db(0.35), 0.01,
		"the music bus volume is the linear value in db"
	)
	assert_near(
		float(AudioServer.get_bus_volume_db(sfx_bus)), linear_to_db(0.45), 0.01,
		"the sfx bus volume is the linear value in db"
	)
	manager.set_muted(true)
	assert_true(bool(manager.is_muted()), "mute is stored")
	assert_true(bool(AudioServer.is_bus_mute(music_bus)), "the music bus is muted")
	assert_true(bool(AudioServer.is_bus_mute(sfx_bus)), "the sfx bus is muted")
	manager.set_muted(false)
	assert_true(not bool(manager.is_muted()), "unmute is stored")
	assert_true(not bool(AudioServer.is_bus_mute(music_bus)), "the music bus is unmuted")
	manager.free()


func test_settings_persist_to_a_file() -> void:
	var manager: Variant = _new_manager()
	manager.set_music_volume(0.42)
	manager.set_sfx_volume(0.24)
	manager.set_muted(true)
	manager.save_settings(TEST_SETTINGS_PATH)
	var loaded: Variant = AudioManagerScript.new()
	loaded.load_settings(TEST_SETTINGS_PATH)
	assert_near(loaded.get_music_volume(), 0.42, 0.0001, "music volume reloads")
	assert_near(loaded.get_sfx_volume(), 0.24, 0.0001, "sfx volume reloads")
	assert_true(bool(loaded.is_muted()), "mute reloads")
	manager.free()
	loaded.free()


func test_game_selects_music_for_each_scene() -> void:
	GameState.reset()
	var game: Variant = _new_game()
	assert_eq(str(game.audio.current_music()), "music_town", "the town plays town music")
	game.show_tavern()
	assert_eq(str(game.audio.current_music()), "music_tavern", "the normal tavern plays tavern music")
	game.current.set_state("brawl")
	assert_eq(
		str(game.audio.current_music()), "music_tavern_brawl",
		"the tavern state change switches to the brawl music"
	)
	game.show_forest()
	assert_eq(str(game.audio.current_music()), "music_forest", "the forest plays forest music")
	assert_eq(
		str(game.audio.current_ambience()), "amb_forest_birds",
		"the forest plays the bird ambience"
	)
	game.show_battle("bandit", 1, false, false)
	assert_eq(str(game.audio.current_music()), "music_battle", "regular fights play battle music")
	assert_eq(str(game.audio.current_ambience()), "", "the battle stops the ambience")
	game.show_battle("ma_youwei", 1, false, false)
	assert_eq(
		str(game.audio.current_music()), "music_battle_boss",
		"ma youwei gets the boss music"
	)
	game.free()


func test_game_tavern_opens_in_brawl_music() -> void:
	GameState.reset()
	GameState.set_flag("bandits_entered")
	var game: Variant = _new_game()
	game.show_tavern()
	assert_eq(
		str(game.audio.current_music()), "music_tavern_brawl",
		"a tavern that starts in the brawl state uses the brawl music"
	)
	game.free()


func test_battle_victory_plays_jingle_and_resumes_town_music() -> void:
	GameState.reset()
	var game: Variant = _new_game()
	game.show_battle("ma_youwei", 1, true, false)
	var view: Variant = game.current
	assert_eq(view.audio, game.audio, "the battle view plays through the game audio manager")
	view.battle.enemies[0].hp = 1
	view.press_action({"kind": "jianyi", "target": 0})
	_finish_dialogue(view)
	view.press_return()
	assert_eq(str(game.current_kind), "town", "a win returns to the town")
	var expected: Variant = AudioLoader.load_wav("jingle_victory", false)
	assert_true(expected != null, "the victory jingle file loads")
	assert_eq(
		str(game.audio.current_music()), "music_town",
		"the town music resumes while the jingle plays"
	)
	assert_eq(game.audio.jingle.stream, expected, "the victory jingle is playing")
	game.free()


func test_battle_view_without_game_is_silent() -> void:
	var view: Variant = load("res://ui/battle_view.gd").new()
	view.build_ui()
	view.start("bandit", 1, false, false)
	assert_true(view.audio == null, "a standalone battle view has no audio manager")
	view.press_action({"kind": "martial", "id": "basic_sword", "target": 0})
	view.tick(0.1)
	assert_true(view.battle != null, "the battle ran without an audio manager")
	view.free()

extends Node

# Runtime audio: two music players for crossfades, an ambience player, a jingle
# player and a small sfx pool. All fades are driven by advance(delta) so tests can
# step time without a real clock. Volume settings persist in user://settings.cfg.

const AudioLoader = preload("res://shared/audio/audio_loader.gd")

const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"
const DEFAULT_MUSIC_VOLUME := 0.7
const DEFAULT_SFX_VOLUME := 0.8
const DEFAULT_SETTINGS_PATH := "user://settings.cfg"
const MUSIC_CUES_PATH := "res://data/music_cues.json"
const SETTINGS_SECTION := "audio"
const JINGLE_DUCK_VOLUME := 0.2
const JINGLE_DUCK_TIME := 0.3
const SFX_POOL_SIZE := 4
const SILENT_DB := -80.0

var music_a: AudioStreamPlayer = null
var music_b: AudioStreamPlayer = null
var ambience: AudioStreamPlayer = null
var jingle: AudioStreamPlayer = null
var sfx_pool: Array[AudioStreamPlayer] = []
var settings_path: String = DEFAULT_SETTINGS_PATH

var _music_volume: float = DEFAULT_MUSIC_VOLUME
var _sfx_volume: float = DEFAULT_SFX_VOLUME
var _muted: bool = false
var _music_track: String = ""
var _music_cue: String = ""
var _cues: Dictionary = {}
var _cues_loaded: bool = false
var _ambience_track: String = ""
var _music_active: AudioStreamPlayer = null
var _player_volumes: Dictionary = {}
var _fades: Dictionary = {}
var _duck: float = 1.0
var _duck_target: float = 1.0
var _sfx_order: int = 0
var _sfx_started: Dictionary = {}


func _init() -> void:
	_ensure_buses()
	music_a = _make_player("MusicA", MUSIC_BUS)
	music_b = _make_player("MusicB", MUSIC_BUS)
	ambience = _make_player("Ambience", MUSIC_BUS)
	jingle = _make_player("Jingle", MUSIC_BUS)
	jingle.volume_db = 0.0
	jingle.finished.connect(Callable(self, "_on_jingle_finished"))
	for i in range(SFX_POOL_SIZE):
		sfx_pool.append(_make_player("Sfx%d" % i, SFX_BUS))
	for player in [music_a, music_b, ambience]:
		_player_volumes[player] = 0.0
	_apply_volumes()
	_apply_bus_volumes()


func _ready() -> void:
	load_settings()


func _process(delta: float) -> void:
	advance(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event: InputEventKey = event
	if not key_event.pressed or key_event.echo:
		return
	var key: int = key_event.keycode
	if key == KEY_NONE:
		key = key_event.physical_keycode
	if key == KEY_M:
		set_muted(not _muted)


# ---------------------------------------------------------------- public API

func play_music(track: String, fade: float = 1.0) -> void:
	if track == _music_track:
		return
	if track == "":
		_music_track = ""
		_music_cue = ""
		if _music_active != null:
			_fade_to(_music_active, 0.0, fade)
		_music_active = null
		return
	var stream := AudioLoader.load_music(track, true)
	if stream == null:
		return
	var old := _music_active
	var next: AudioStreamPlayer = _pick_music_player()
	next.stream = stream
	_player_volumes[next] = 0.0
	_start(next)
	_fade_to(next, 1.0, fade)
	if old != null and old != next:
		_fade_to(old, 0.0, fade)
	_music_active = next
	_music_track = track
	_apply_volumes()


func play_ambience(track: String, fade: float = 1.5) -> void:
	if track == _ambience_track:
		return
	if track == "":
		_ambience_track = ""
		if ambience != null:
			_fade_to(ambience, 0.0, fade)
		return
	var stream := AudioLoader.load_wav(track, true)
	if stream == null:
		return
	ambience.stream = stream
	_player_volumes[ambience] = 0.0
	_start(ambience)
	_fade_to(ambience, 1.0, fade)
	_ambience_track = track
	_apply_volumes()


func play_jingle(track: String) -> void:
	var stream := AudioLoader.load_music(track, false)
	if stream == null:
		return
	jingle.stream = stream
	_start(jingle)
	_duck_target = JINGLE_DUCK_VOLUME


# Story-state music: data/music_cues.json maps cue id -> track (plus an optional
# fallback used while the intended track does not exist yet). Unknown cue ids are
# played as track names, which simply stays silent until that file is added.
func play_cue(cue_id: String) -> void:
	if cue_id == "":
		return
	var track := _cue_track(cue_id)
	if cue_id == _music_cue and track == _music_track:
		return
	_music_cue = cue_id
	play_music(track)


func play_sfx(track: String, volume: float = 1.0) -> void:
	var stream := AudioLoader.load_wav(track, false)
	if stream == null:
		return
	var player: AudioStreamPlayer = _free_sfx_player()
	if player == null:
		return
	player.stream = stream
	player.volume_db = _volume_db(volume)
	_start(player)
	_sfx_order += 1
	_sfx_started[player] = _sfx_order


func set_music_volume(v: float) -> void:
	_music_volume = clampf(v, 0.0, 1.0)
	_apply_bus_volumes()
	save_settings()


func set_sfx_volume(v: float) -> void:
	_sfx_volume = clampf(v, 0.0, 1.0)
	_apply_bus_volumes()
	save_settings()


func get_music_volume() -> float:
	return _music_volume


func get_sfx_volume() -> float:
	return _sfx_volume


func set_muted(m: bool) -> void:
	_muted = m
	_apply_bus_volumes()
	save_settings()


func is_muted() -> bool:
	return _muted


func current_music() -> String:
	return _music_track


func current_cue() -> String:
	return _music_cue


func current_ambience() -> String:
	return _ambience_track


func advance(delta: float) -> void:
	if delta > 0.0:
		_advance_fades(delta)
		_advance_duck(delta)
	_apply_volumes()


# ---------------------------------------------------------------- settings

func load_settings(path: String = "") -> void:
	var target := settings_path if path == "" else path
	var config := ConfigFile.new()
	if config.load(target) != OK:
		return
	_music_volume = clampf(
		float(config.get_value(SETTINGS_SECTION, "music", DEFAULT_MUSIC_VOLUME)), 0.0, 1.0
	)
	_sfx_volume = clampf(
		float(config.get_value(SETTINGS_SECTION, "sfx", DEFAULT_SFX_VOLUME)), 0.0, 1.0
	)
	_muted = bool(config.get_value(SETTINGS_SECTION, "muted", false))
	_apply_bus_volumes()


func save_settings(path: String = "") -> void:
	var target := settings_path if path == "" else path
	var config := ConfigFile.new()
	config.set_value(SETTINGS_SECTION, "music", _music_volume)
	config.set_value(SETTINGS_SECTION, "sfx", _sfx_volume)
	config.set_value(SETTINGS_SECTION, "muted", _muted)
	config.save(target)


# ---------------------------------------------------------------- internals

func _ensure_cues() -> void:
	if _cues_loaded:
		return
	_cues_loaded = true
	if not FileAccess.file_exists(MUSIC_CUES_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MUSIC_CUES_PATH))
	if not (parsed is Dictionary):
		return
	var data: Dictionary = parsed
	var cues: Variant = data.get("cues", {})
	if cues is Dictionary:
		_cues = cues


func _cue_track(cue_id: String) -> String:
	_ensure_cues()
	var entry: Variant = _cues.get(cue_id)
	if not (entry is Dictionary):
		return cue_id
	var record: Dictionary = entry
	var track := str(record.get("track", ""))
	var fallback := str(record.get("fallback", ""))
	if track != "" and AudioLoader.has_music(track):
		return track
	if fallback != "" and AudioLoader.has_music(fallback):
		return fallback
	return track if track != "" else cue_id


func _ensure_buses() -> void:
	for bus_name in [MUSIC_BUS, SFX_BUS]:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		AudioServer.add_bus()
		var index := AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, "Master")


func _make_player(node_name: String, bus: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.bus = bus
	player.volume_db = SILENT_DB
	add_child(player)
	return player


func _apply_bus_volumes() -> void:
	for bus_name in [MUSIC_BUS, SFX_BUS]:
		var index := AudioServer.get_bus_index(bus_name)
		if index < 0:
			continue
		AudioServer.set_bus_mute(index, _muted)
		var value := _music_volume if bus_name == MUSIC_BUS else _sfx_volume
		AudioServer.set_bus_volume_db(index, _volume_db(value))


func _volume_db(v: float) -> float:
	var value := clampf(v, 0.0, 1.0)
	if value <= 0.0001:
		return SILENT_DB
	return linear_to_db(value)


func _pick_music_player() -> AudioStreamPlayer:
	if _music_active == music_a:
		return music_b
	if _music_active == music_b:
		return music_a
	if not music_a.playing:
		return music_a
	if not music_b.playing:
		return music_b
	return music_a


func _fade_to(player: AudioStreamPlayer, target: float, duration: float) -> void:
	if player == null:
		return
	if duration <= 0.0:
		_fades.erase(player)
		_player_volumes[player] = target
		_apply_volumes()
		if target <= 0.0 and _should_stop(player):
			_stop(player)
		return
	_fades[player] = {
		"from": float(_player_volumes.get(player, 0.0)),
		"to": target,
		"time": 0.0,
		"duration": duration,
	}


func _advance_fades(delta: float) -> void:
	var done: Array = []
	for player in _fades.keys():
		var record: Dictionary = _fades[player]
		var duration := maxf(float(record["duration"]), 0.0001)
		record["time"] = float(record["time"]) + delta
		var weight := clampf(float(record["time"]) / duration, 0.0, 1.0)
		_player_volumes[player] = lerpf(float(record["from"]), float(record["to"]), weight)
		if weight >= 1.0:
			done.append(player)
	for player in done:
		_fades.erase(player)
		if float(_player_volumes.get(player, 0.0)) <= 0.0 and _should_stop(player):
			_stop(player)


func _should_stop(player: AudioStreamPlayer) -> bool:
	if player == ambience:
		return _ambience_track == ""
	if player == music_a or player == music_b:
		return _music_active != player
	return true


func _advance_duck(delta: float) -> void:
	if _duck_target < 1.0 and (jingle == null or not jingle.playing):
		_duck_target = 1.0
	if is_equal_approx(_duck, _duck_target):
		return
	var step := (1.0 - JINGLE_DUCK_VOLUME) / JINGLE_DUCK_TIME * delta
	if _duck < _duck_target:
		_duck = minf(_duck_target, _duck + step)
	else:
		_duck = maxf(_duck_target, _duck - step)


func _apply_volumes() -> void:
	for player in _player_volumes.keys():
		if not (player is AudioStreamPlayer) or not is_instance_valid(player):
			continue
		var value := float(_player_volumes[player])
		if player == music_a or player == music_b:
			value *= _duck
		(player as AudioStreamPlayer).volume_db = _volume_db(value)


func _start(player: AudioStreamPlayer) -> void:
	if player == null or not player.is_inside_tree():
		return
	player.play()


func _stop(player: AudioStreamPlayer) -> void:
	if player == null or not player.is_inside_tree():
		return
	player.stop()


func _free_sfx_player() -> AudioStreamPlayer:
	if sfx_pool.is_empty():
		return null
	for player in sfx_pool:
		if not player.playing:
			return player
	var oldest: AudioStreamPlayer = sfx_pool[0]
	for player in sfx_pool:
		if int(_sfx_started.get(player, 0)) < int(_sfx_started.get(oldest, 0)):
			oldest = player
	return oldest


func _on_jingle_finished() -> void:
	_duck_target = 1.0

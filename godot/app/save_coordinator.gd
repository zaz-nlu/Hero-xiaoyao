extends RefCounted

# Save/load bookkeeping without UI or feature knowledge. The composition root
# turns the returned navigation result into scene changes, toasts and audio.

const GameState = preload("res://core/game_state.gd")
const SaveSystem = preload("res://core/save_system.gd")
const Profile = preload("res://core/profile.gd")
const DataLoader = preload("res://core/data_loader.gd")
const TownData = preload("res://shared/resources/town_data.gd")

const AUTOSAVE_INTERVAL := 120.0
const PROFILE_POLL_INTERVAL := 0.5
const SAVE_KINDS: Array[String] = ["town", "tavern", "forest"]

var save_dir: String = SaveSystem.SAVE_DIR
var profile_path: String = Profile.PROFILE_PATH
var loading_slot: bool = false
var autosave_timer: float = 0.0
var profile_timer: float = 0.0
var gate_profile_checked: bool = false
var _town_data: Dictionary = {}
var _town_data_loaded: bool = false


func is_save_kind(kind: String) -> bool:
	return SAVE_KINDS.has(kind)


# The game snapshots what it knows about the scene; the policy lives here.
func can_save(snapshot: Dictionary) -> bool:
	if not bool(snapshot.get("has_scene", false)):
		return false
	var kind := str(snapshot.get("kind", ""))
	if not SAVE_KINDS.has(kind):
		return false
	if bool(snapshot.get("dialogue_active", false)):
		return false
	if kind == "tavern" and bool(snapshot.get("cutscene_running", false)):
		return false
	if bool(snapshot.get("panel_open", false)):
		return false
	return true


func make_location(kind: String, value: Variant) -> Dictionary:
	var pos := Vector2.ZERO
	if value is Vector2:
		pos = value
	return {"kind": kind, "pos": [pos.x, pos.y]}


func write_slot(slot: String, location: Dictionary) -> bool:
	return SaveSystem.save(slot, location, {}, save_dir)


# Reads the slot and applies the persistent state. The caller shows the scene
# while loading_slot stays true (which suppresses autosave), then calls
# finish_load().
func begin_load(slot: String) -> Dictionary:
	var data := SaveSystem.load_slot(slot, save_dir)
	if data.is_empty():
		return {"ok": false, "message": "存档已损坏"}
	var state: Variant = data.get("state", {})
	if not (state is Dictionary):
		return {"ok": false, "message": "存档已损坏"}
	loading_slot = true
	autosave_timer = 0.0
	GameState.from_dict(state)
	if GameState.has_flag("boss_defeated"):
		Profile.unlock("gate", profile_path)
	var location: Variant = data.get("location", {})
	var kind := "town"
	var pos: Variant = null
	if location is Dictionary:
		kind = str((location as Dictionary).get("kind", "town"))
		pos = _read_location_pos((location as Dictionary).get("pos", null))
	return {"ok": true, "kind": kind, "pos": pos}


func finish_load() -> void:
	loading_slot = false


# Returns true when the autosave interval elapsed during this tick.
func tick_playtime(delta: float, counting: bool, paused: bool) -> bool:
	if not counting or paused:
		return false
	var step := maxf(0.0, delta)
	GameState.playtime += step
	autosave_timer += step
	if autosave_timer >= AUTOSAVE_INTERVAL:
		autosave_timer = 0.0
		return true
	return false


# Title-screen places unlock from real progress. The boss check runs in any scene
# (so a freshly loaded save is caught too); the town position checks are throttled.
func tick_profile(delta: float, kind: String, player_pos: Variant) -> void:
	if GameState.has_flag("boss_defeated") and not gate_profile_checked:
		# One write attempt is enough: Profile silently ignores IO failures.
		Profile.unlock("gate", profile_path)
		gate_profile_checked = true
	if kind != "town":
		return
	profile_timer += maxf(0.0, delta)
	if profile_timer < PROFILE_POLL_INTERVAL:
		return
	profile_timer = 0.0
	if not (player_pos is Vector2):
		return
	var pos: Vector2 = player_pos
	for zone_value in TownData.unlocked_zones(_read_town_data(), pos):
		Profile.unlock(str(zone_value), profile_path)


func _read_town_data() -> Dictionary:
	if not _town_data_loaded:
		_town_data_loaded = true
		var loaded: Dictionary = TownData.load_town(DataLoader.TOWN_PATH)
		var value: Variant = loaded.get("data", {})
		if value is Dictionary:
			_town_data = value
	return _town_data


func _read_location_pos(value: Variant) -> Variant:
	if value is Vector2:
		return value
	if value is Array and (value as Array).size() >= 2:
		var array: Array = value
		return Vector2(float(array[0]), float(array[1]))
	return null

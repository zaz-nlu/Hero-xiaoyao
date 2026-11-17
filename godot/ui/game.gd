extends Node

const GameState = preload("res://core/game_state.gd")
const Quests = preload("res://core/quests.gd")
const Progression = preload("res://core/progression.gd")
const Realms = preload("res://core/realms.gd")
const AudioManager = preload("res://ui/audio_manager.gd")
const SaveSystem = preload("res://core/save_system.gd")
const Profile = preload("res://core/profile.gd")

const TOWN_SCENE := "res://world/town.gd"
const TAVERN_SCENE := "res://world/tavern.gd"
const FOREST_SCENE := "res://world/forest.gd"
const BATTLE_SCENE := "res://ui/battle_view.gd"
const STATUS_OVERLAY_SCENE := "res://ui/status_overlay.gd"
const PAUSE_MENU_SCENE := "res://ui/pause_menu.gd"
const TITLE_SCREEN_SCENE := "res://ui/title_screen.gd"
const BOSS_ENEMY_ID := "ma_youwei"
const AUTOSAVE_INTERVAL := 120.0
const PROFILE_POLL_INTERVAL := 0.5
const SAVE_KINDS: Array[String] = ["town", "tavern", "forest"]

var current: Node = null
var current_kind: String = ""
var overlay: Variant = null
var audio: Variant = null
var pause_menu: Variant = null
var save_dir: String = SaveSystem.SAVE_DIR
var profile_path: String = Profile.PROFILE_PATH

var _battle_enemy: String = ""
var _battle_count: int = 0
var _battle_origin: String = ""
var _panel_was_open: bool = false
var _seen_toasts: Array = []
var _loading_slot: bool = false
var _autosave_timer: float = 0.0
var _profile_timer: float = 0.0
var _gate_profile_checked: bool = false


func _ready() -> void:
	_ensure_overlay()
	_ensure_pause_menu()
	# Tests and the frame-based smoke test set this meta to keep booting straight
	# into the town; normal startup always goes through the title screen.
	if Engine.has_meta("skip_title") and bool(Engine.get_meta("skip_title")):
		show_town()
		_show_intro_hints()
	else:
		show_title()


func _process(_delta: float) -> void:
	_process_toast_sfx()
	_tick_playtime(_delta)
	_tick_profile(_delta)
	if overlay == null or current == null:
		return
	var panel_open: bool = overlay.is_panel_open()
	if panel_open and not _panel_was_open:
		_play_sfx("sfx_select")
	_panel_was_open = panel_open
	if current_kind == "town" or current_kind == "tavern" or current_kind == "forest":
		current.set("input_blocked", panel_open)


func _process_toast_sfx() -> void:
	if audio == null or overlay == null:
		return
	# The overlay consumes GameState.toasts in its own _process (after this node), so
	# read the toast panels it actually popped and react to the ones we have not seen.
	var box: Variant = overlay.toast_box
	if not (box is Node):
		return
	var seen: Array = []
	for node in (box as Node).get_children():
		seen.append(node)
		if _seen_toasts.has(node):
			continue
		if _toast_text(node).begins_with("获得 "):
			_play_sfx("sfx_pickup")
	_seen_toasts = seen


func _toast_text(node: Node) -> String:
	for child in node.get_children():
		if child is Label:
			return (child as Label).text
	return ""


func _tick_playtime(delta: float) -> void:
	if current == null or not SAVE_KINDS.has(current_kind):
		return
	var tree := get_tree()
	if tree != null and tree.paused:
		return
	GameState.playtime += maxf(0.0, delta)
	_autosave_timer += maxf(0.0, delta)
	if _autosave_timer >= AUTOSAVE_INTERVAL:
		_autosave_timer = 0.0
		_autosave_now()


# Title-screen places unlock from real progress. The boss check runs in any scene
# (so a freshly loaded save is caught too); the town position checks are throttled.
func _tick_profile(delta: float) -> void:
	if GameState.has_flag("boss_defeated") and not _gate_profile_checked:
		# One write attempt is enough: Profile silently ignores IO failures.
		Profile.unlock("gate", profile_path)
		_gate_profile_checked = true
	if current == null or current_kind != "town":
		return
	_profile_timer += maxf(0.0, delta)
	if _profile_timer < PROFILE_POLL_INTERVAL:
		return
	_profile_timer = 0.0
	var value: Variant = current.get("player_pos")
	if not (value is Vector2):
		return
	var pos: Vector2 = value
	if pos.x < -36.0:
		Profile.unlock("west_street", profile_path)
	if pos.x > 22.0:
		Profile.unlock("gate", profile_path)


func _schedule_autosave() -> void:
	if _loading_slot:
		return
	if is_inside_tree():
		call_deferred("_autosave_now")
	else:
		_autosave_now()


func _autosave_now() -> void:
	if _loading_slot or not can_save():
		return
	save_to_slot("auto", true)


func can_save() -> bool:
	if current == null:
		return false
	if not SAVE_KINDS.has(current_kind):
		return false
	if current.has_method("is_dialogue_active") and bool(current.call("is_dialogue_active")):
		return false
	if current_kind == "tavern" and current.has_method("is_cutscene_running") \
			and bool(current.call("is_cutscene_running")):
		return false
	if overlay != null and overlay.is_panel_open():
		return false
	return true


func current_location() -> Dictionary:
	var pos := Vector2.ZERO
	if current != null:
		var value: Variant = current.get("player_pos")
		if value is Vector2:
			pos = value
	return {"kind": current_kind, "pos": [pos.x, pos.y]}


func save_to_slot(slot: String, silent: bool = false) -> bool:
	if not can_save():
		if not silent:
			Progression.push_toast("现在无法存档")
		return false
	var ok := SaveSystem.save(slot, current_location(), {}, save_dir)
	if ok:
		if not silent:
			Progression.push_toast("已存档")
			_play_sfx("sfx_confirm")
		if pause_menu != null:
			pause_menu.refresh_slots()
	elif not silent:
		Progression.push_toast("存档失败")
	return ok


func load_from_slot(slot: String) -> bool:
	var data := SaveSystem.load_slot(slot, save_dir)
	if data.is_empty():
		Progression.push_toast("存档已损坏")
		return false
	var state: Variant = data.get("state", {})
	if not (state is Dictionary):
		Progression.push_toast("存档已损坏")
		return false
	_loading_slot = true
	_autosave_timer = 0.0
	GameState.from_dict(state)
	if GameState.has_flag("boss_defeated"):
		Profile.unlock("gate", profile_path)
	var location: Variant = data.get("location", {})
	var kind := "town"
	var pos: Variant = null
	if location is Dictionary:
		kind = str((location as Dictionary).get("kind", "town"))
		pos = _read_location_pos((location as Dictionary).get("pos", null))
	match kind:
		"tavern":
			if pos is Vector2:
				GameState.tavern_return_pos = pos
			show_tavern()
		"forest":
			if pos is Vector2:
				GameState.forest_return_pos = pos
			show_forest()
		_:
			if pos is Vector2:
				GameState.town_return_pos = pos
			show_town()
	_loading_slot = false
	if pause_menu != null:
		pause_menu.close()
	Progression.push_toast("读档完成")
	return true


func _read_location_pos(value: Variant) -> Variant:
	if value is Vector2:
		return value
	if value is Array and (value as Array).size() >= 2:
		var array: Array = value
		return Vector2(float(array[0]), float(array[1]))
	return null


func show_title() -> void:
	_ensure_overlay()
	_ensure_audio()
	_ensure_pause_menu()
	overlay.close_all()
	overlay.enabled = false
	_release_current()
	var title: Variant = load(TITLE_SCREEN_SCENE).new()
	title.name = "TitleScreen"
	title.game = self
	title.audio = audio
	title.save_dir = save_dir
	add_child(title)
	if not title.is_inside_tree():
		title.build()
	title.connect("new_game_requested", Callable(self, "_on_title_new_game"))
	title.connect("continue_requested", Callable(self, "_on_title_continue"))
	title.connect("load_requested", Callable(self, "_on_title_continue"))
	title.connect("quit_requested", Callable(self, "_on_title_quit"))
	current = title
	current_kind = "title"
	var tree := get_tree()
	if tree != null:
		tree.paused = false
	_play_music("music_title")
	_play_ambience("")


func start_new_game() -> void:
	GameState.reset()
	Progression.reload_items()
	Quests.reload()
	Realms.reload()
	show_town()
	_show_intro_hints()
	_schedule_autosave()


func _show_intro_hints() -> void:
	if GameState.has_flag("intro_hint_shown"):
		return
	GameState.set_flag("intro_hint_shown")
	Progression.push_toast("按 C 打开角色面板，可以分配 3 点属性点")
	Progression.push_toast("按 J 查看任务，Shift 可以蹲伏")


func _on_title_new_game() -> void:
	start_new_game()


func _on_title_continue(slot: String) -> void:
	if load_from_slot(slot):
		return
	if current != null and current.has_method("show_error"):
		current.call("open_page", "main")
		current.call("show_error", "存档已损坏")


func _on_title_quit() -> void:
	var tree := get_tree()
	if tree != null:
		tree.paused = false
		tree.quit()


func go_to_title() -> void:
	if pause_menu != null:
		pause_menu.close()
	var tree := get_tree()
	if tree != null:
		tree.paused = false
	show_title()


func _ensure_pause_menu() -> void:
	if pause_menu != null:
		return
	pause_menu = load(PAUSE_MENU_SCENE).new()
	pause_menu.name = "PauseMenu"
	pause_menu.game = self
	add_child(pause_menu)


func _ensure_audio() -> void:
	if audio != null:
		return
	audio = AudioManager.new()
	audio.name = "Audio"
	audio.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(audio)


func _play_music(track: String) -> void:
	if audio != null:
		audio.play_music(track)


func _play_ambience(track: String) -> void:
	if audio != null:
		audio.play_ambience(track)


func _play_sfx(track: String, volume: float = 1.0) -> void:
	if audio != null:
		audio.play_sfx(track, volume)


func _is_boss_encounter(enemy_id: String) -> bool:
	return enemy_id == BOSS_ENEMY_ID


func _ensure_overlay() -> void:
	if overlay != null:
		return
	overlay = load(STATUS_OVERLAY_SCENE).new()
	overlay.name = "StatusOverlay"
	add_child(overlay)


func show_town() -> void:
	_ensure_overlay()
	_ensure_audio()
	_release_current()
	var town: Variant = load(TOWN_SCENE).new()
	add_child(town)
	if not town.is_inside_tree():
		town.build()
		town.build_hud()
	town.connect("encounter_requested", Callable(self, "_on_encounter_requested"))
	town.connect("enter_requested", Callable(self, "_on_enter_requested"))
	current = town
	current_kind = "town"
	GameState.town_return_pos = null
	overlay.enabled = true
	_play_music("music_town")
	_play_ambience("")
	_schedule_autosave()


func show_tavern() -> void:
	_ensure_overlay()
	_ensure_audio()
	_release_current()
	var tavern: Variant = load(TAVERN_SCENE).new()
	add_child(tavern)
	if not tavern.is_inside_tree():
		tavern.build()
		tavern.build_hud()
	tavern.connect("exit_requested", Callable(self, "_on_tavern_exit_requested"))
	tavern.connect("encounter_requested", Callable(self, "_on_encounter_requested"))
	tavern.connect("state_changed", Callable(self, "_on_tavern_state_changed"))
	current = tavern
	current_kind = "tavern"
	Profile.unlock("tavern_inside", profile_path)
	overlay.enabled = true
	_play_tavern_music(str(tavern.current_state()))
	_play_ambience("")
	_schedule_autosave()


func show_forest() -> void:
	_ensure_overlay()
	_ensure_audio()
	_release_current()
	var forest: Variant = load(FOREST_SCENE).new()
	add_child(forest)
	if not forest.is_inside_tree():
		forest.build()
		forest.build_hud()
	forest.connect("exit_requested", Callable(self, "_on_forest_exit_requested"))
	forest.connect("encounter_requested", Callable(self, "_on_encounter_requested"))
	current = forest
	current_kind = "forest"
	Profile.unlock("forest", profile_path)
	overlay.enabled = true
	_play_music("music_forest")
	_play_ambience("amb_forest_birds")
	_schedule_autosave()


func _on_tavern_state_changed(new_state: String) -> void:
	if current_kind != "tavern":
		return
	_play_tavern_music(new_state)


func _play_tavern_music(tavern_state: String) -> void:
	if tavern_state == "brawl":
		_play_music("music_tavern_brawl")
	else:
		_play_music("music_tavern")


func _on_enter_requested(place: String) -> void:
	if place == "forest":
		if current != null and current_kind == "town":
			GameState.town_return_pos = Vector2(0.0, 19.2)
		show_forest()
		return
	if place != "tavern":
		return
	if current != null and current_kind == "town":
		GameState.town_return_pos = current.tavern_return_pos()
	_play_sfx("sfx_door")
	show_tavern()


func _on_tavern_exit_requested() -> void:
	_play_sfx("sfx_door")
	show_town()


func _on_forest_exit_requested(place: String) -> void:
	if place == "town":
		show_town()
	elif place == "wasteland":
		Progression.push_toast("前方荒山，暂时过不去")


func _on_encounter_requested(enemy_id: String, count: int, first_strike: bool) -> void:
	if current != null:
		var origin: Variant = current
		match current_kind:
			"town":
				GameState.town_return_pos = origin.player_pos
				_battle_origin = "town"
				GameState.battle_backdrop = "town"
			"tavern":
				_battle_origin = "tavern"
				GameState.battle_backdrop = "town"
			"forest":
				GameState.forest_return_pos = origin.player_pos
				_battle_origin = "forest"
				GameState.battle_backdrop = "forest"
	show_battle(enemy_id, count, first_strike, false)


func show_battle(
	enemy_id: String, count: int, first_strike: bool, play_intro: bool
) -> void:
	_ensure_overlay()
	_ensure_audio()
	overlay.enabled = false
	overlay.close_all()
	_release_current()
	var view: Variant = load(BATTLE_SCENE).new()
	add_child(view)
	if not view.is_inside_tree():
		view.build_ui()
	# Must also reset the offsets: set_anchors_preset() alone keeps the current (0x0) rect.
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.set("audio", audio)
	view.start(enemy_id, count, first_strike, play_intro)
	view.connect("battle_finished", Callable(self, "_on_battle_finished"))
	current = view
	current_kind = "battle"
	_battle_enemy = enemy_id
	_battle_count = count
	if _is_boss_encounter(enemy_id):
		_play_music("music_battle_boss")
	else:
		_play_music("music_battle")
	_play_ambience("")


func _on_battle_finished(result: String) -> void:
	if audio != null:
		audio.play_jingle("jingle_victory" if result == "won" else "jingle_defeat")
	var origin := _battle_origin
	var pending: Variant = GameState.pending_forest_encounter
	if result == "won":
		Quests.notify("defeat", _battle_enemy, _battle_count)
		if _battle_enemy == BOSS_ENEMY_ID:
			GameState.set_flag("boss_defeated")
		if origin == "forest" and pending is Dictionary:
			var encounter: Dictionary = pending
			var kind := str(encounter.get("kind", ""))
			if kind == "patrol":
				GameState.set_flag("patrol_defeated_%d" % int(encounter.get("id", -1)))
			elif kind == "scout":
				GameState.set_flag("scout_defeated")
	_battle_origin = ""
	GameState.battle_backdrop = "town"
	GameState.pending_forest_encounter = null
	if origin == "forest":
		if result != "won":
			# A loss drops the player back at the forest spawn; the patrol resets.
			GameState.forest_return_pos = null
		show_forest()
	else:
		show_town()


func _release_current() -> void:
	if current == null:
		return
	var node: Node = current
	current = null
	current_kind = ""
	# Never free() synchronously: this is usually called from one of the node's own
	# signal callbacks ("locked object" error). Detach it, then free it at idle time.
	if node.get_parent() == self:
		remove_child(node)
	node.queue_free()

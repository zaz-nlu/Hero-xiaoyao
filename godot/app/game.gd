extends Node

const GameState = preload("res://core/game_state.gd")
const Quests = preload("res://core/quests.gd")
const Progression = preload("res://core/progression.gd")
const Realms = preload("res://core/realms.gd")
const AudioManager = preload("res://shared/audio/audio_manager.gd")
const SceneRouter = preload("res://app/scene_router.gd")
const SaveCoordinator = preload("res://app/save_coordinator.gd")
const BattleFlow = preload("res://app/battle_flow.gd")

const STATUS_OVERLAY_SCENE := "res://features/character/status_overlay.gd"
const PAUSE_MENU_SCENE := "res://features/pause/pause_menu.gd"

var overlay: Variant = null
var audio: Variant = null
var pause_menu: Variant = null

var _router: SceneRouter
var _save: SaveCoordinator
var _battle: BattleFlow
var _panel_was_open: bool = false
var _seen_toasts: Array = []

# The public facade and the tests keep using the original field names; these
# properties forward them to the services that now own the state.
var current: Node:
	get:
		return _router.current
var current_kind: String:
	get:
		return _router.current_kind
var save_dir: String:
	get:
		return _save.save_dir
	set(value):
		_save.save_dir = value
var profile_path: String:
	get:
		return _save.profile_path
	set(value):
		_save.profile_path = value
var _loading_slot: bool:
	get:
		return _save.loading_slot
	set(value):
		_save.loading_slot = value
var _autosave_timer: float:
	get:
		return _save.autosave_timer
	set(value):
		_save.autosave_timer = value
var _profile_timer: float:
	get:
		return _save.profile_timer
	set(value):
		_save.profile_timer = value
var _gate_profile_checked: bool:
	get:
		return _save.gate_profile_checked
	set(value):
		_save.gate_profile_checked = value


func _init() -> void:
	_router = SceneRouter.new()
	_save = SaveCoordinator.new()
	_battle = BattleFlow.new(_router)
	_router.setup(
		self,
		Callable(self, "_on_encounter_requested"),
		Callable(self, "start_new_game"),
		Callable(self, "_on_title_continue"),
		Callable(self, "_set_overlay_enabled"),
		Callable(self, "_schedule_autosave"),
		Callable(self, "_profile_path_value"),
	)
	_battle.jingle_requested.connect(_on_jingle_requested)


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
		audio.play_sfx("sfx_select")
	_panel_was_open = panel_open
	if current_kind == "town" or current_kind == "tavern" or current_kind == "forest":
		var blocked: bool = panel_open
		if current_kind == "tavern" and current.has_method("is_cutscene_running") \
				and bool(current.call("is_cutscene_running")):
			blocked = true
		current.set("input_blocked", blocked)


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
			audio.play_sfx("sfx_pickup")
	_seen_toasts = seen


func _toast_text(node: Node) -> String:
	for child in node.get_children():
		if child is Label:
			return (child as Label).text
	return ""


func _tick_playtime(delta: float) -> void:
	var counting: bool = current != null and _save.is_save_kind(current_kind)
	var in_tree := is_inside_tree()
	var paused: bool = in_tree and get_tree().paused
	if _save.tick_playtime(delta, counting, paused):
		_autosave_now()


func _tick_profile(delta: float) -> void:
	var pos: Variant = null
	if current != null:
		pos = current.get("player_pos")
	_save.tick_profile(delta, current_kind, pos)


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
	var has_scene: bool = current != null
	var dialogue_active := false
	var cutscene_running := false
	if has_scene and current.has_method("is_dialogue_active"):
		dialogue_active = bool(current.call("is_dialogue_active"))
	if has_scene and current_kind == "tavern" and current.has_method("is_cutscene_running"):
		cutscene_running = bool(current.call("is_cutscene_running"))
	var panel_open: bool = overlay != null and overlay.is_panel_open()
	return _save.can_save({
		"has_scene": has_scene,
		"kind": current_kind,
		"dialogue_active": dialogue_active,
		"cutscene_running": cutscene_running,
		"panel_open": panel_open,
	})


func current_location() -> Dictionary:
	var pos: Variant = null
	if current != null:
		pos = current.get("player_pos")
	return _save.make_location(current_kind, pos)


func save_to_slot(slot: String, silent: bool = false) -> bool:
	if not can_save():
		if not silent:
			Progression.push_toast("现在无法存档")
		return false
	var ok := _save.write_slot(slot, current_location())
	if ok:
		if not silent:
			Progression.push_toast("已存档")
			audio.play_sfx("sfx_confirm")
		if pause_menu != null:
			pause_menu.refresh_slots()
	elif not silent:
		Progression.push_toast("存档失败")
	return ok


func load_from_slot(slot: String) -> bool:
	var result := _save.begin_load(slot)
	if not bool(result.get("ok", false)):
		Progression.push_toast(str(result.get("message", "存档已损坏")))
		return false
	var kind := str(result.get("kind", "town"))
	var pos: Variant = result.get("pos", null)
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
	_save.finish_load()
	if pause_menu != null:
		pause_menu.close()
	Progression.push_toast("读档完成")
	return true


func show_title() -> void:
	_prepare_scene()
	_ensure_pause_menu()
	overlay.close_all()
	overlay.enabled = false
	_router.show_title(audio, save_dir)


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


func _on_title_continue(slot: String) -> void:
	if load_from_slot(slot):
		return
	if current != null and current.has_method("show_error"):
		current.call("open_page", "main")
		current.call("show_error", "存档已损坏")


func go_to_title() -> void:
	if pause_menu != null:
		pause_menu.close()
	if is_inside_tree():
		var tree := get_tree()
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


func _ensure_overlay() -> void:
	if overlay != null:
		return
	overlay = load(STATUS_OVERLAY_SCENE).new()
	overlay.name = "StatusOverlay"
	add_child(overlay)


func show_town() -> void:
	_router.show_town(_prepare_scene())


func show_tavern() -> void:
	_router.show_tavern(_prepare_scene())


func show_forest() -> void:
	_router.show_forest(_prepare_scene())

func show_layout(map_id: String, return_pos: Variant = null) -> void:
	_router.show_layout(_prepare_scene(), map_id, return_pos)

func _prepare_scene() -> Node:
	_ensure_overlay()
	_ensure_audio()
	return audio


func _set_overlay_enabled(enabled: bool) -> void:
	if overlay != null:
		overlay.enabled = enabled


func _profile_path_value() -> String:
	return _save.profile_path


func _on_encounter_requested(enemy_id: String, count: int, first_strike: bool) -> void:
	_battle.record_encounter_origin(current, current_kind)
	show_battle(enemy_id, count, first_strike, false)


func show_battle(
	enemy_id: String, count: int, first_strike: bool, play_intro: bool
) -> void:
	_prepare_scene()
	overlay.enabled = false
	overlay.close_all()
	_battle.show_battle(audio, enemy_id, count, first_strike, play_intro)


func _on_jingle_requested(track: String) -> void:
	if audio != null:
		audio.play_jingle(track)

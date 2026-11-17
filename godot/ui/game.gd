extends Node

const GameState = preload("res://core/game_state.gd")
const Quests = preload("res://core/quests.gd")
const Progression = preload("res://core/progression.gd")
const AudioManager = preload("res://ui/audio_manager.gd")

const TOWN_SCENE := "res://world/town.gd"
const TAVERN_SCENE := "res://world/tavern.gd"
const FOREST_SCENE := "res://world/forest.gd"
const BATTLE_SCENE := "res://ui/battle_view.gd"
const STATUS_OVERLAY_SCENE := "res://ui/status_overlay.gd"
const BOSS_ENEMY_ID := "ma_youwei"

var current: Node = null
var current_kind: String = ""
var overlay: Variant = null
var audio: Variant = null

var _battle_enemy: String = ""
var _battle_count: int = 0
var _battle_origin: String = ""
var _panel_was_open: bool = false
var _seen_toasts: Array = []


func _ready() -> void:
	_ensure_overlay()
	show_town()
	if not GameState.has_flag("intro_hint_shown"):
		GameState.set_flag("intro_hint_shown")
		Progression.push_toast("按 C 打开角色面板，可以分配 3 点属性点")
		Progression.push_toast("按 J 查看任务，Shift 可以蹲伏")


func _process(_delta: float) -> void:
	_process_toast_sfx()
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


func _ensure_audio() -> void:
	if audio != null:
		return
	audio = AudioManager.new()
	audio.name = "Audio"
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
	overlay.enabled = true
	_play_tavern_music(str(tavern.current_state()))
	_play_ambience("")


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
	overlay.enabled = true
	_play_music("music_forest")
	_play_ambience("amb_forest_birds")


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

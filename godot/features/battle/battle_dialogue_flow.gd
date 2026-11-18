extends RefCounted

# 战斗对话流程：拥有对话控件、当前遭遇 id 与胜利对话的“只播一次”状态。
# 从 encounters / speakers 数据里查询 intro / win，不依赖控制器。

signal finished

const DataLoader = preload("res://core/data_loader.gd")
const Dialogue = preload("res://core/dialogue.gd")

const ENCOUNTERS_PATH := DataLoader.ENCOUNTERS_PATH
const SPEAKERS_PATH := DataLoader.SPEAKERS_PATH

var view: Variant = null
var current_enemy_id: String = ""
var win_dialogue_played: bool = false


func build(parent: Control) -> void:
	view = load("res://shared/ui/dialogue_view.gd").new()
	view.name = "DialogueView"
	view.build_ui()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.visible = false
	view.z_index = 100
	view.connect("finished", _on_finished)
	parent.add_child(view)


func reset(enemy_id: String) -> void:
	current_enemy_id = enemy_id
	win_dialogue_played = false


func play_intro() -> void:
	var entry: Variant = _encounter_entry(current_enemy_id)
	if not (entry is Dictionary):
		return
	var intro_path: String = str(entry.get("intro", ""))
	if intro_path == "":
		return
	_play(intro_path)


func maybe_play_win(is_won: bool) -> void:
	if win_dialogue_played or not is_won:
		return
	win_dialogue_played = true
	var entry: Variant = _encounter_entry(current_enemy_id)
	if not (entry is Dictionary):
		return
	var win_path: String = str(entry.get("win", ""))
	if win_path == "":
		return
	_play(win_path)


func is_active() -> bool:
	return view != null and bool(view.is_active())


func advance() -> void:
	if view != null:
		view.advance()


func _on_finished() -> void:
	finished.emit()


func _encounter_entry(enemy_id: String) -> Variant:
	if enemy_id == "" or not FileAccess.file_exists(ENCOUNTERS_PATH):
		return null
	var text: String = FileAccess.get_file_as_string(ENCOUNTERS_PATH)
	if text == "":
		return null
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return null
	var data: Dictionary = parsed
	return data.get(enemy_id, null)


func _play(path: String) -> void:
	if view == null:
		return
	var speakers: Dictionary = Dialogue.load_speakers(SPEAKERS_PATH).get("defs", {})
	var loaded: Dictionary = Dialogue.load_file(path, speakers)
	var errors: Array = loaded.get("errors", [])
	if not errors.is_empty():
		push_warning("dialogue skipped: %s (%s)" % [path, str(errors)])
		return
	var lines: Array = loaded.get("lines", [])
	if lines.is_empty():
		return
	view.start(lines)

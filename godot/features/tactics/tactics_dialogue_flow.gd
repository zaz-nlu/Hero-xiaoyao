extends RefCounted

# 战旗胜利对话：拥有 shared 对话视图与当前遭遇 id 的“只播一次”状态。
# 遭遇表读 core/data_loader 的路径常量，对话文件解析沿用 core/dialogue。
# 参照 features/battle/battle_dialogue_flow，但不 import 旧战斗。

const DataLoader = preload("res://core/data_loader.gd")
const Dialogue = preload("res://core/dialogue.gd")
const DialogueView = preload("res://shared/ui/dialogue_view.gd")

const ENCOUNTERS_PATH := DataLoader.ENCOUNTERS_PATH
const SPEAKERS_PATH := DataLoader.SPEAKERS_PATH

var view: Variant = null
var current_enemy_id: String = ""
var win_dialogue_played: bool = false
# 遭遇表路径；默认读 DataLoader 的常量，测试可指向临时表。
var encounters_path: String = ENCOUNTERS_PATH

var _pending: Callable = Callable()


func build(parent: Control) -> void:
	if view != null or parent == null:
		return
	view = DialogueView.new()
	view.name = "TacticsDialogueView"
	view.build_ui()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.visible = false
	view.z_index = 100
	view.connect("finished", _on_finished)
	parent.add_child(view)


func reset(enemy_id: String) -> void:
	current_enemy_id = enemy_id
	win_dialogue_played = false
	_pending = Callable()


func is_active() -> bool:
	return view != null and bool(view.is_active())


func advance() -> void:
	if view != null:
		view.advance()


# 只在胜利且该遭遇有 win 路径时播放一次；其余情况（含对话文件缺失）立即回调。
func maybe_play_win(is_won: bool, on_finished: Callable) -> void:
	if win_dialogue_played or not is_won:
		on_finished.call()
		return
	win_dialogue_played = true
	var path: String = _win_path(current_enemy_id)
	if path == "":
		on_finished.call()
		return
	_pending = on_finished
	if not _play(path):
		_pending = Callable()
		on_finished.call()


func _on_finished() -> void:
	var callback: Callable = _pending
	_pending = Callable()
	if callback.is_valid():
		callback.call()


func _win_path(enemy_id: String) -> String:
	var entry: Variant = _encounter_entry(enemy_id)
	if not (entry is Dictionary):
		return ""
	return str((entry as Dictionary).get("win", ""))


func _encounter_entry(enemy_id: String) -> Variant:
	if enemy_id == "" or not FileAccess.file_exists(encounters_path):
		return null
	var text: String = FileAccess.get_file_as_string(encounters_path)
	if text == "":
		return null
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return null
	var data: Dictionary = parsed
	return data.get(enemy_id, null)


# 播放失败（缺文件、解析错误、空对话）时不留下半开的视图，返回 false。
func _play(path: String) -> bool:
	if view == null:
		return false
	var speakers: Dictionary = Dialogue.load_speakers(SPEAKERS_PATH).get("defs", {})
	var loaded: Dictionary = Dialogue.load_file(path, speakers)
	var errors: Array = loaded.get("errors", [])
	if not errors.is_empty():
		push_warning("dialogue skipped: %s (%s)" % [path, str(errors)])
		return false
	var lines: Array = loaded.get("lines", [])
	if lines.is_empty():
		return false
	view.start(lines)
	return true

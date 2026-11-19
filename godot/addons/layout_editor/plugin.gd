@tool
extends EditorPlugin

# 主屏幕插件：把“地图工坊”面板挂到编辑器主区域。
# 只有这里接触 EditorInterface；面板通过信号请求试跑，便于独立运行 main_panel.tscn。

const MainPanelScene := preload("res://addons/layout_editor/main_panel.tscn")
const PLAYTEST_SCENE := "res://tools/layout_playtest.tscn"

# 不写死控件类型：独立运行与编辑器内都通过信号/公开方法交互。
var _panel = null
var _screen: VBoxContainer = null


func _enter_tree() -> void:
	_screen = EditorInterface.get_editor_main_screen()
	_panel = MainPanelScene.instantiate()
	_panel.name = "地图工坊"
	_panel.play_requested.connect(_on_play_requested)
	_screen.add_child(_panel)
	_panel.visible = false


func _exit_tree() -> void:
	if is_instance_valid(_panel):
		if is_instance_valid(_screen):
			_screen.remove_child(_panel)
		_panel.queue_free()
	_panel = null
	_screen = null


func _has_main_screen() -> bool:
	return true


func _get_plugin_name() -> String:
	return "地图工坊"


func _make_visible(visible: bool) -> void:
	if _panel != null:
		_panel.visible = visible


# 编辑器退出/停用插件时的未保存提示，避免悄悄丢弃草稿。
func _get_unsaved_status(for_scene: String) -> String:
	if for_scene.is_empty() and _panel != null and _panel.has_unsaved_changes():
		return "地图工坊有未保存的地图修改，关闭将丢失这些修改。"
	return ""

func _save_external_data() -> void:
	if _panel != null and _panel.has_unsaved_changes():
		_panel.call("_on_save_pressed")


func _on_play_requested(scene_path: String) -> void:
	if _panel == null:
		return
	if EditorInterface.is_playing_scene():
		_panel.report_status("error", "已有游戏正在运行，请先停止再试跑。")
		return
	EditorInterface.play_custom_scene(scene_path)

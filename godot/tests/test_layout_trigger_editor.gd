extends "res://tests/test_case.gd"

# 工坊触发器面板：选中实例、应用/清空、撤销/重做、错误保留草稿、
# 同素材实例互不继承，以及试跑快照携带触发器。
# 面板测试允许在 SceneTree 就绪前手动调用 _ready（与地形编辑器测试一致）。

const LayoutDocument = preload("res://core/layouts/layout_document.gd")

const FIXTURE_PATH := "res://tests/fixtures/layout_training_yard.json"
const PANEL_PATH := "res://addons/layout_editor/main_panel.tscn"
const SNAPSHOT_PATH := "user://test_layout_trigger_editor_playtest.json"

const DISCIPLE_CELL := Vector2i(5, 6)


func _panel() -> Variant:
	var tree: Variant = Engine.get_meta("test_tree", null)
	var panel: Variant = load(PANEL_PATH).instantiate()
	if tree == null:
		panel.free()
		assert_true(false, "面板测试需要真实 SceneTree")
		return null
	tree.root.add_child(panel)
	if panel.state == null:
		panel._ready()
		panel._terrain_panel._ready()
		panel._environment_panel._ready()
		panel._trigger_panel._ready()
	panel.show()
	assert_true(panel.state != null, "面板应建立编辑状态")
	assert_true(bool(panel.state.load_map(FIXTURE_PATH).get("ok", false)),
		"面板应能打开测试布局：%s" % panel.state.last_error)
	return panel


func _remove_user_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _find_triggered_disciple(document: Dictionary) -> Dictionary:
	for object_value in document.get("objects", []):
		var object: Dictionary = object_value
		if str(object.get("asset", "")) == "disciple" and object.has("trigger"):
			return object
	return {}


func test_panel_apply_undo_redo_and_clear() -> void:
	var panel: Variant = _panel()
	if panel == null or panel.state == null:
		return
	var state: Variant = panel.state
	var tools: Variant = panel._trigger_panel
	assert_true(tools != null, "触发器小节应已创建")

	state.select_at(DISCIPLE_CELL)
	assert_eq(str(state.selection.get("kind", "")), "object", "应选中弟子实例")
	tools.refresh()
	assert_true(not tools._kind_option.disabled, "选中物件后表单应可编辑")

	tools._kind_option.select(0)
	tools._on_kind_changed(0)
	tools._target_edit.text = "npc_disciple"
	tools._on_apply_pressed()
	var trigger: Dictionary = state.selected_trigger()
	assert_eq(str(trigger.get("kind", "")), "dialogue")
	assert_eq(str(trigger.get("target", "")), "npc_disciple")
	assert_eq(str(trigger.get("activation", "")), "interact", "默认按键互动")

	panel._on_undo()
	assert_true(state.selected_trigger().is_empty(), "撤销应移除触发器")
	panel._on_redo()
	assert_eq(str(state.selected_trigger().get("target", "")), "npc_disciple",
		"重做应恢复触发器")

	tools._on_clear_pressed()
	assert_true(state.selected_trigger().is_empty(), "清空应移除触发器")

	panel.free()


func test_panel_error_keeps_draft() -> void:
	var panel: Variant = _panel()
	if panel == null or panel.state == null:
		return
	var state: Variant = panel.state
	var tools: Variant = panel._trigger_panel
	state.select_at(DISCIPLE_CELL)
	tools.refresh()
	tools._kind_option.select(0)
	tools._on_kind_changed(0)
	tools._target_edit.text = "no_such_dialogue"
	var snapshot := JSON.stringify(state.document)
	tools._on_apply_pressed()
	assert_eq(JSON.stringify(state.document), snapshot, "应用失败不能污染草稿")
	assert_true(state.last_error.contains("dialogue"), "状态栏应说明对话不存在")
	assert_eq(tools._target_edit.text, "no_such_dialogue", "失败后输入框内容不能丢")
	panel.free()


func test_panel_new_copy_does_not_inherit_trigger() -> void:
	var panel: Variant = _panel()
	if panel == null or panel.state == null:
		return
	var state: Variant = panel.state
	var tools: Variant = panel._trigger_panel
	state.select_at(DISCIPLE_CELL)
	tools.refresh()
	tools._kind_option.select(0)
	tools._on_kind_changed(0)
	tools._target_edit.text = "npc_disciple"
	tools._on_apply_pressed()
	assert_true(not state.selected_trigger().is_empty())

	var placed: Dictionary = state.place_object("disciple", Vector2i(1, 4))
	assert_true(bool(placed.get("ok", false)), "第二个弟子应能放到空地：%s" % state.last_error)
	assert_true(state.selected_trigger().is_empty(), "复制出来的实例不能继承触发器")
	panel.free()


func test_panel_target_browser_and_playtest_snapshot() -> void:
	var panel: Variant = _panel()
	if panel == null or panel.state == null:
		return
	var state: Variant = panel.state
	var tools: Variant = panel._trigger_panel
	state.select_at(DISCIPLE_CELL)
	tools.refresh()

	tools._kind_option.select(2)
	tools._on_kind_changed(2)
	var has_town := false
	for i in range(tools._target_option.item_count):
		if str(tools._target_option.get_item_metadata(i)) == "town":
			has_town = true
	assert_true(has_town, "出口目标下拉应包含 town")

	tools._kind_option.select(0)
	tools._on_kind_changed(0)
	tools._target_edit.text = "npc_disciple"
	tools._on_apply_pressed()

	_remove_user_file(SNAPSHOT_PATH)
	var exported: Dictionary = state.export_playtest(SNAPSHOT_PATH)
	assert_true(bool(exported.get("ok", false)), "试跑快照应写出：%s" % state.last_error)
	var loaded := LayoutDocument.load_document(SNAPSHOT_PATH)
	assert_true(bool(loaded.get("ok", false)), "快照应能完整校验加载")
	var doc: Dictionary = loaded.get("document", {})
	var triggered := _find_triggered_disciple(doc)
	assert_eq(str(triggered.get("trigger", {}).get("target", "")), "npc_disciple",
		"试跑快照应携带触发器")
	_remove_user_file(SNAPSHOT_PATH)
	panel.free()

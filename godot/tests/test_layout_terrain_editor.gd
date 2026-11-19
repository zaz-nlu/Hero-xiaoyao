extends "res://tests/test_case.gd"

# 地形编辑器测试：经 EditState 与 main_panel 真入口验证台地/水面/连接、
# 撤销/重做、试跑快照、失败保护、面板选择索引与旧地图回归。
# 只读写 user:// 临时文件，正式地图与紫霞派 JSON 不会被改动。

const EditState := preload("res://addons/layout_editor/edit_state.gd")
const LayoutDocument := preload("res://core/layouts/layout_document.gd")
const LayoutTerrain := preload("res://core/layouts/layout_terrain.gd")

const FIXTURE_PATH := "res://tests/fixtures/layout_workshop.json"
const SAMPLE_PATH := "res://data/layouts/zixia_sect.json"
const PANEL_PATH := "res://addons/layout_editor/main_panel.tscn"
const TEMP_PATH := "user://test_layout_terrain_editor.json"
const SNAPSHOT_PATH := "user://test_layout_terrain_editor_playtest.json"


func _fresh_state() -> EditState:
	var state := EditState.new()
	assert_true(
		bool(state.load_map(FIXTURE_PATH).get("ok", false)),
		"测试布局应能打开：%s" % state.last_error
	)
	return state


func _terrace_count(state) -> int:
	return (state.document.get("terraces", []) as Array).size()


func _water_count(state) -> int:
	return (state.document.get("water", []) as Array).size()


func _stairs(state, platform_index: int) -> Array:
	var terraces: Array = state.document.get("terraces", [])
	if platform_index < 0 or platform_index >= terraces.size():
		return []
	return (terraces[platform_index] as Dictionary).get("stairs", [])


func _remove_user_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# ---------------------------------------------------------------- state 入口


func test_add_update_terrace_keeps_connections() -> void:
	var state := _fresh_state()
	assert_eq(_terrace_count(state), 0, "测试布局默认没有台地")

	var added := state.add_terrace("一层", Vector2i(2, 12), Vector2i(6, 16), 1.0, 0.0, "stone")
	assert_true(bool(added.get("ok", false)), "台地应能添加：%s" % state.last_error)
	assert_eq(_terrace_count(state), 1)
	var entry: Dictionary = state.document["terraces"][0]
	assert_eq(entry["rect"], [4.0, 24.0, 14.0, 34.0], "格坐标应换算成世界矩形")
	assert_near(float(entry["y"]), 1.0)
	assert_eq(str(entry["top"]), "stone")

	var compiled := state.terrain()
	var platforms: Array = compiled.get("platforms", [])
	assert_eq(platforms.size(), 1, "地形编译应包含台地")
	assert_near(LayoutTerrain.height_at(compiled, Vector2(12, 30)), 1.0, 0.001,
		"台地内部高度来自编译结果")

	var connected := state.add_connector(0, "stairs", "south", Vector2i(4, 16), Vector2i(6, 16))
	assert_true(bool(connected.get("ok", false)), "楼梯应能添加：%s" % state.last_error)
	var stairs := _stairs(state, 0)
	assert_eq(stairs.size(), 1)
	var stair: Dictionary = stairs[0]
	assert_eq(str(stair["side"]), "south")
	assert_near(float(stair["x0"]), 8.0)
	assert_near(float(stair["x1"]), 14.0)
	assert_eq((state.terrain().get("connectors", []) as Array).size(), 1)

	var updated := state.update_terrace(0, "主平台", 1.5, 0.0, "dirt")
	assert_true(bool(updated.get("ok", false)), "台地应能更新：%s" % state.last_error)
	var changed: Dictionary = state.document["terraces"][0]
	assert_eq(str(changed["name"]), "主平台")
	assert_near(float(changed["y"]), 1.5)
	assert_eq(str(changed["top"]), "dirt")
	assert_eq(_stairs(state, 0).size(), 1, "应用不应清掉已有连接")

	var removed := state.remove_terrace(0)
	assert_true(bool(removed.get("ok", false)), "台地应能删除：%s" % state.last_error)
	assert_eq(_terrace_count(state), 0)
	assert_eq((state.terrain().get("platforms", []) as Array).size(), 0)


func test_connector_edge_resolution_and_errors() -> void:
	var state := _fresh_state()
	assert_true(bool(state.add_terrace("边测试", Vector2i(2, 4), Vector2i(6, 8), 1.0, 0.0, "").get("ok", false)),
		"边测试台地应能添加：%s" % state.last_error)

	var south := state.add_connector(0, "stairs", "", Vector2i(3, 8), Vector2i(3, 8))
	assert_true(bool(south.get("ok", false)), "自动方向应推断出南侧：%s" % state.last_error)
	assert_eq(str(south.get("side", "")), "south")
	assert_eq(_stairs(state, 0).size(), 1)

	var east := state.add_connector(0, "ramp", "east", Vector2i(6, 7), Vector2i(6, 8))
	assert_true(bool(east.get("ok", false)), "显式东侧坡道应能添加：%s" % state.last_error)
	assert_eq(str(east.get("side", "")), "east")
	assert_eq(str((_stairs(state, 0)[1] as Dictionary)["kind"]), "ramp")

	var depth := state.undo_stack.size()
	var corner := state.add_connector(0, "stairs", "", Vector2i(6, 8), Vector2i(6, 8))
	assert_true(not bool(corner.get("ok", false)), "角落自动方向应拒绝")
	assert_true(state.last_error.contains("角落"), "应提示角落歧义：%s" % state.last_error)
	assert_eq(state.undo_stack.size(), depth, "失败连接不应写入历史")

	var explicit := state.add_connector(0, "stairs", "south", Vector2i(6, 8), Vector2i(6, 8))
	assert_true(bool(explicit.get("ok", false)), "显式南侧应解除角落歧义：%s" % state.last_error)
	assert_eq(str(explicit.get("side", "")), "south")

	var bad := state.add_connector(0, "stairs", "", Vector2i(2, 4), Vector2i(3, 5))
	assert_true(not bool(bad.get("ok", false)), "不同边缘的两格应拒绝")
	assert_true(state.last_error.contains("同一条边缘"), "应说明不是同一条边缘：%s" % state.last_error)
	assert_eq(state.undo_stack.size(), depth + 1, "只有成功的显式连接进入历史")

	var removed := state.remove_connector(0, 0)
	assert_true(bool(removed.get("ok", false)), "连接应能删除：%s" % state.last_error)
	assert_eq(_stairs(state, 0).size(), 2)


func test_water_add_level_and_errors() -> void:
	var state := _fresh_state()
	var auto := state.add_water("池塘", Vector2i(1, 1), Vector2i(3, 3), null)
	assert_true(bool(auto.get("ok", false)), "自动水位应能添加：%s" % state.last_error)
	assert_eq(_water_count(state), 1)
	var entry: Dictionary = state.document["water"][0]
	assert_true(not entry.has("y"), "自动水位不写显式 y")
	var water: Array = state.terrain().get("water", [])
	assert_eq(water.size(), 1)
	assert_near(float((water[0] as Dictionary)["y"]), 0.05, 0.001, "自动水位在底面之上")

	var explicit := state.add_water("石井", Vector2i(5, 1), Vector2i(6, 2), 0.5)
	assert_true(bool(explicit.get("ok", false)), "显式水位应能添加：%s" % state.last_error)
	assert_near(float(state.document["water"][1]["y"]), 0.5)

	var snapshot := JSON.stringify(state.document)
	var depth := state.undo_stack.size()
	var shallow := state.add_water("坏水位", Vector2i(8, 1), Vector2i(9, 2), 0.0)
	assert_true(not bool(shallow.get("ok", false)), "不高于底面的水位应拒绝")
	assert_true(state.last_error.contains("above the water bottom"),
		"运行时校验应说明水位过低：%s" % state.last_error)
	assert_eq(JSON.stringify(state.document), snapshot, "失败水面不能污染草稿")
	assert_eq(state.undo_stack.size(), depth, "失败水面不能写入历史")

	var overlap := state.add_water("重叠", Vector2i(1, 1), Vector2i(2, 2), null)
	assert_true(not bool(overlap.get("ok", false)), "重叠水面应拒绝")
	assert_eq(JSON.stringify(state.document), snapshot, "重叠失败后草稿不变")


func test_terrain_undo_redo_and_playtest_reopen() -> void:
	var original := FileAccess.get_file_as_string(SAMPLE_PATH)
	var state := _fresh_state()
	assert_true(bool(state.add_terrace("草稿台", Vector2i(2, 12), Vector2i(6, 16), 1.0, 0.0, "stone").get("ok", false)),
		"台地应能添加：%s" % state.last_error)
	assert_true(bool(state.add_connector(0, "stairs", "south", Vector2i(4, 16), Vector2i(4, 16)).get("ok", false)),
		"楼梯应能添加：%s" % state.last_error)
	assert_true(bool(state.add_water("池塘", Vector2i(1, 1), Vector2i(3, 3), null).get("ok", false)),
		"水面应能添加：%s" % state.last_error)
	assert_eq(state.undo_stack.size(), 3)

	_remove_user_file(TEMP_PATH)
	var exported := state.export_playtest(TEMP_PATH)
	assert_true(bool(exported.get("ok", false)), "试跑快照应写出：%s" % state.last_error)
	assert_eq(FileAccess.get_file_as_string(SAMPLE_PATH), original, "正式地图不能被改动")

	var loaded := LayoutDocument.load_document(TEMP_PATH)
	assert_true(bool(loaded.get("ok", false)), "快照应能完整校验加载")
	var snapshot_doc: Dictionary = loaded.get("document", {})
	assert_eq((snapshot_doc.get("terraces", []) as Array).size(), 1)
	assert_eq((snapshot_doc.get("water", []) as Array).size(), 1)
	var compiled := LayoutTerrain.compile(snapshot_doc)
	assert_eq((compiled.get("platforms", []) as Array).size(), 1)
	assert_eq((compiled.get("connectors", []) as Array).size(), 1)

	var reopened := EditState.new()
	assert_true(bool(reopened.load_map(TEMP_PATH).get("ok", false)),
		"重开快照应成功：%s" % reopened.last_error)
	assert_eq(_terrace_count(reopened), 1)
	assert_near(reopened.terrain_height_at_cell(Vector2i(4, 13)), 1.0, 0.001,
		"重开后地形高度仍可查询")

	assert_true(state.undo(), "撤销应移除最后的水面")
	assert_eq(_water_count(state), 0)
	assert_true(state.redo(), "重做应恢复水面")
	assert_eq(_water_count(state), 1)
	_remove_user_file(TEMP_PATH)


func test_failed_terrain_edits_keep_draft_and_history() -> void:
	var state := _fresh_state()
	assert_true(bool(state.add_terrace("一层", Vector2i(2, 2), Vector2i(5, 4), 1.0, 0.0, "").get("ok", false)),
		"基准台地应能添加：%s" % state.last_error)
	var snapshot := JSON.stringify(state.document)
	var depth := state.undo_stack.size()

	var overlap := state.add_terrace("重叠", Vector2i(4, 3), Vector2i(7, 6), 1.0, 0.0, "")
	assert_true(not bool(overlap.get("ok", false)), "重叠台地应拒绝")
	var inverted := state.add_terrace("倒置", Vector2i(8, 8), Vector2i(9, 9), 1.0, 1.0, "")
	assert_true(not bool(inverted.get("ok", false)), "下层高度不小于顶部应拒绝")
	var outside := state.add_terrace("越界", Vector2i(-1, 0), Vector2i(2, 2), 1.0, 0.0, "")
	assert_true(not bool(outside.get("ok", false)), "越界台地应拒绝")

	assert_eq(JSON.stringify(state.document), snapshot, "失败操作必须保留原草稿")
	assert_eq(state.undo_stack.size(), depth, "失败操作不能写入历史")
	assert_true(state.undo(), "基准台地仍可撤销")
	assert_eq(_terrace_count(state), 0)


func test_legacy_map_opens_without_terrain() -> void:
	var state := EditState.new()
	assert_true(bool(state.load_map(SAMPLE_PATH).get("ok", false)),
		"旧地图应能打开：%s" % state.last_error)
	assert_eq((state.terrain().get("platforms", []) as Array).size(), 0)
	assert_near(state.terrain_height_at_cell(Vector2i(5, 5)), 0.0, 0.001,
		"没有地形字段时按平地读取")


# ---------------------------------------------------------------- 面板真入口


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
	panel.show()
	assert_true(panel.state != null, "面板应建立编辑状态")
	assert_true(panel.state.has_document(), "面板应载入默认地图")
	assert_true(bool(panel.state.load_map(FIXTURE_PATH).get("ok", false)),
		"面板应能打开测试布局：%s" % panel.state.last_error)
	return panel


func test_editor_panel_terrain_entry_paths() -> void:
	var panel: Variant = _panel()
	if panel == null or panel.state == null:
		return
	panel.set_terrain_tools_open(true)
	var tools: Variant = panel._terrain_panel
	assert_true(tools != null, "地形工具区应已创建")

	# 同一次点击路径：表单 + “圈台地” + 画布两角。
	tools._name_edit.text = "东南台"
	tools._y_spin.value = 1.5
	tools._from_spin.value = 0.0
	tools._select_top_asset("stone")
	tools._on_draw_terrace_pressed()
	panel._on_cell_clicked(Vector2i(2, 12), MOUSE_BUTTON_LEFT)
	panel._on_cell_hovered(Vector2i(6, 16))
	panel._on_cell_clicked(Vector2i(6, 16), MOUSE_BUTTON_LEFT)
	assert_eq(_terrace_count(panel.state), 1, "面板圈台地应写入文档")
	var entry: Dictionary = panel.state.document["terraces"][0]
	assert_eq(str(entry["name"]), "东南台")
	assert_near(float(entry["y"]), 1.5)
	assert_eq(str(entry["top"]), "stone")

	# 选中台地后从连接区点两格。
	tools._on_terrace_selected(0)
	tools._kind_option.select(0)
	tools._side_option.select(0)
	tools._on_add_connector_pressed()
	panel._on_cell_clicked(Vector2i(4, 16), MOUSE_BUTTON_LEFT)
	panel._on_cell_hovered(Vector2i(6, 16))
	panel._on_cell_clicked(Vector2i(6, 16), MOUSE_BUTTON_LEFT)
	assert_eq(_stairs(panel.state, 0).size(), 1, "面板放连接应写入 stairs")

	# 圈水面。
	tools._water_name.text = "测试池"
	tools._water_auto.button_pressed = true
	tools._on_draw_water_pressed()
	panel._on_cell_clicked(Vector2i(1, 1), MOUSE_BUTTON_LEFT)
	panel._on_cell_clicked(Vector2i(3, 3), MOUSE_BUTTON_LEFT)
	assert_eq(_water_count(panel.state), 1, "面板圈水面应写入文档")

	# 面板撤销按钮走 state 历史。
	panel._on_undo()
	assert_eq(_water_count(panel.state), 0, "面板撤销应移除水面")

	# Esc 清理点到一半的操作。
	tools._on_draw_terrace_pressed()
	panel._on_cell_clicked(Vector2i(1, 1), MOUSE_BUTTON_LEFT)
	assert_true(tools.is_pending(), "首角后应保持待完成状态")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	if panel.is_visible_in_tree():
		panel._shortcut_input(escape)
	else:
		panel._cancel_terrain_pending()
	assert_true(not tools.is_pending(), "Esc 应清理半途操作")

	# 草稿试跑快照走完整格式。
	_remove_user_file(SNAPSHOT_PATH)
	var exported: Dictionary = panel.state.export_playtest(SNAPSHOT_PATH)
	assert_true(bool(exported.get("ok", false)), "面板试跑快照应写出：%s" % panel.state.last_error)
	var loaded := LayoutDocument.load_document(SNAPSHOT_PATH)
	assert_true(bool(loaded.get("ok", false)), "面板快照应能完整校验")
	var compiled := LayoutTerrain.compile(loaded.get("document", {}))
	assert_eq((compiled.get("platforms", []) as Array).size(), 1)
	assert_eq((compiled.get("connectors", []) as Array).size(), 1)

	# 撤销/删除后，面板索引不能指到另一个台地。
	tools._name_edit.text = "台A"
	tools._y_spin.value = 1.0
	tools._from_spin.value = 0.0
	tools._on_draw_terrace_pressed()
	panel._on_cell_clicked(Vector2i(2, 2), MOUSE_BUTTON_LEFT)
	panel._on_cell_clicked(Vector2i(3, 3), MOUSE_BUTTON_LEFT)
	tools._name_edit.text = "台B"
	tools._on_draw_terrace_pressed()
	panel._on_cell_clicked(Vector2i(5, 2), MOUSE_BUTTON_LEFT)
	panel._on_cell_clicked(Vector2i(6, 3), MOUSE_BUTTON_LEFT)
	assert_eq(_terrace_count(panel.state), 3)
	tools._on_terrace_selected(0)
	var removed: Dictionary = panel.state.remove_terrace(0)
	assert_true(bool(removed.get("ok", false)), "删除选中台地应成功：%s" % panel.state.last_error)
	assert_eq(tools._terrace_index, -1,
		"删除后台地面板索引应清空，不能指向原索引 0 的另一个台地")

	panel.free()
	_remove_user_file(SNAPSHOT_PATH)
	_remove_user_file(TEMP_PATH)

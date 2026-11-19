extends "res://tests/test_case.gd"

# 地图工坊编辑模型测试：放置入口、物件操作、失败保护、撤销/重做、一笔刷涂、
# 试跑快照隔离与 spawn 坐标映射。全部使用内存草稿与 user:// 临时文件。

const EditState := preload("res://addons/layout_editor/edit_state.gd")
const LayoutDocument := preload("res://core/layouts/layout_document.gd")

const SAMPLE_PATH := "res://data/layouts/zixia_sect.json"
const FIXTURE_PATH := "res://tests/fixtures/layout_workshop.json"
const SNAPSHOT_PATH := "user://test_layout_editor_playtest.json"


func _fresh_state() -> EditState:
	var state := EditState.new()
	assert_true(bool(state.load_map(FIXTURE_PATH).get("ok", false)), "测试布局应能打开：%s" % state.last_error)
	return state


func _object_count(state: EditState) -> int:
	return (state.document.get("objects", []) as Array).size()


func _tile_count(state: EditState) -> int:
	return (state.document.get("tiles", []) as Array).size()


func _index_of_asset(document: Dictionary, asset: String) -> int:
	var objects: Array = document.get("objects", [])
	for i in range(objects.size()):
		var obj: Dictionary = objects[i]
		if str(obj.get("asset", "")) == asset:
			return i
	return -1


func _tile_asset_at(document: Dictionary, cell: Vector2i) -> String:
	for raw in document.get("tiles", []):
		var tile: Dictionary = raw
		if int(tile.get("x", -1)) == cell.x and int(tile.get("z", -1)) == cell.y:
			return str(tile.get("asset", ""))
	return ""


func _remove_user_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# ---------------------------------------------------------------- 放置入口
func test_click_and_drop_share_place_entry() -> void:
	var state := _fresh_state()
	# 点选路径：选中地面后点格子；拖放路径也调用同一个 place_asset。
	var click := state.place_asset("stone", Vector2i(2, 2))
	assert_true(bool(click.get("ok", false)), "地面放置应成功：%s" % state.last_error)
	assert_eq(_tile_asset_at(state.document, Vector2i(2, 2)), "stone")

	var before := _object_count(state)
	var drop := state.place_asset("rock", Vector2i(2, 3))
	assert_true(bool(drop.get("ok", false)), "物件放置应成功：%s" % state.last_error)
	assert_eq(_object_count(state), before + 1)
	var obj: Dictionary = state.selected_object()
	assert_eq(str(obj.get("asset", "")), "rock")
	assert_eq(int(obj.get("x", -1)), 2)
	assert_eq(int(obj.get("z", -1)), 3)
	assert_eq(int(obj.get("turn", -1)), 0)
	assert_eq(str(obj.get("label", "")), "")


func test_select_multicell_object_by_edge() -> void:
	var state := _fresh_state()
	var hall := _index_of_asset(state.document, "main_hall")
	assert_true(hall >= 0, "紫霞派应包含大殿")
	state.select_at(Vector2i(13, 4))
	assert_eq(str(state.selection.get("kind", "")), "object")
	assert_eq(int(state.selection.get("index", -1)), hall)

	var tree := _index_of_asset(state.document, "pine_tree")
	state.select_at(Vector2i(5, 5))
	assert_eq(int(state.selection.get("index", -1)), tree)


# ---------------------------------------------------------------- 物件操作
func test_rotate_move_delete() -> void:
	var state := _fresh_state()
	var before := _object_count(state)
	var placed := state.place_asset("pine_tree", Vector2i(2, 2))
	assert_true(bool(placed.get("ok", false)), "松树应能放到空地")
	assert_eq(_object_count(state), before + 1)

	assert_true(state.rotate_selected_object(), "旋转应成功")
	assert_eq(int(state.selected_object().get("turn", -1)), 1)

	assert_true(state.move_selected_object(Vector2i(3, 3)), "移动应成功")
	assert_eq(int(state.selected_object().get("x", -1)), 3)
	assert_eq(int(state.selected_object().get("z", -1)), 3)

	assert_true(state.delete_selected(), "删除应成功")
	assert_eq(_object_count(state), before)
	assert_eq(str(state.selection.get("kind", "none")), "none")


# ---------------------------------------------------------------- 失败保护
func test_failed_edits_keep_draft_and_history() -> void:
	var state := _fresh_state()
	var snapshot := JSON.stringify(state.document)
	var objects := _object_count(state)
	assert_eq(state.can_undo(), false)

	# 与原有物件重叠。
	var overlap := state.place_object("main_hall", Vector2i(9, 7))
	assert_true(not bool(overlap.get("ok", false)), "重叠放置应被拒绝")

	# 占地越界。
	var call := state.place_object("main_hall", Vector2i(22, 19))
	assert_true(not bool(call.get("ok", false)), "越界放置应被拒绝")

	# 挡住出生点（12,18）。
	var blocked := state.place_object("pine_tree", Vector2i(12, 18))
	assert_true(not bool(blocked.get("ok", false)), "压住出生点应被拒绝")

	# 缩小地图会裁掉已有地面/物件。
	var resize := state.apply_map_info("zixia_sect", "紫霞派", 10, 10)
	assert_true(not bool(resize.get("ok", false)), "裁剪数据的缩放应被拒绝")
	assert_true(state.last_error.contains("裁掉"), "应明确说明会裁掉数据")

	assert_eq(JSON.stringify(state.document), snapshot, "失败后草稿必须原样保留")
	assert_eq(_object_count(state), objects)
	assert_eq(state.can_undo(), false, "失败操作不能写入历史")


func test_failed_move_keeps_object() -> void:
	var state := _fresh_state()
	var hall := _index_of_asset(state.document, "main_hall")
	state.select_at(Vector2i(12, 3))
	assert_eq(int(state.selection.get("index", -1)), hall)
	assert_true(not state.move_selected_object(Vector2i(22, 19)), "越界移动应失败")
	assert_eq(int(state.selected_object().get("x", -1)), 9)
	assert_eq(int(state.selected_object().get("z", -1)), 2)


# ---------------------------------------------------------------- 撤销/重做
func test_undo_redo_and_single_stroke_undo() -> void:
	var state := _fresh_state()
	var before := _tile_count(state)

	# 一笔拖刷两格，只产生一条撤销记录。
	state.begin_ground_stroke()
	state.stroke_ground(Vector2i(2, 2), "stone")
	state.stroke_ground(Vector2i(3, 2), "stone")
	assert_true(state.end_ground_stroke(), "刷涂应提交")
	assert_eq(_tile_count(state), before + 2)
	assert_eq(state.undo_stack.size(), 1, "一笔刷涂只应有一条撤销记录")

	assert_true(state.undo(), "撤销应成功")
	assert_eq(_tile_count(state), before)
	assert_eq(_tile_asset_at(state.document, Vector2i(2, 2)), "")
	assert_true(state.can_redo())

	assert_true(state.redo(), "重做应成功")
	assert_eq(_tile_count(state), before + 2)

	# 撤销后再编辑会清空 redo。
	assert_true(state.undo())
	assert_true(bool(state.paint_ground(Vector2i(4, 4), "stone").get("ok", false)))
	assert_eq(state.can_redo(), false, "新编辑必须清空 redo")

	# 失败编辑不改变历史。
	var depth := state.undo_stack.size()
	state.place_object("main_hall", Vector2i(9, 7))
	assert_eq(state.undo_stack.size(), depth)


func test_ground_stroke_ignores_repeats_and_invalid_cells() -> void:
	var state := _fresh_state()
	var before := _tile_count(state)

	state.begin_ground_stroke()
	assert_true(state.stroke_ground(Vector2i(2, 2), "stone"), "首格应写入")
	assert_true(not state.stroke_ground(Vector2i(2, 2), "stone"), "同材质重复刷不应算修改")
	assert_true(not state.stroke_ground(Vector2i(-1, 2), "stone"), "越界格应被忽略")
	assert_true(not state.stroke_ground(Vector2i(2, 3), "rock"), "非地面素材应被忽略")
	assert_true(state.stroke_ground(Vector2i(3, 2), "stone"), "有效格应继续写入")
	assert_true(state.end_ground_stroke(), "笔划应提交")
	assert_eq(_tile_count(state), before + 2)
	assert_eq(_tile_asset_at(state.document, Vector2i(2, 3)), "", "无效格不能被污染")
	assert_eq(state.undo_stack.size(), 1, "整笔只应有一条撤销记录")

	# 只重复同材质的一笔不产生撤销记录。
	var depth := state.undo_stack.size()
	state.begin_ground_stroke()
	assert_true(not state.stroke_ground(Vector2i(2, 2), "stone"))
	assert_true(not state.end_ground_stroke(), "无变化的笔划不应提交")
	assert_eq(state.undo_stack.size(), depth, "重复笔划不应新增撤销")


# ---------------------------------------------------------------- 区域与 spawn
func test_region_add_select_delete() -> void:
	var state := _fresh_state()
	var before := (state.document.get("regions", []) as Array).size()
	var added := state.add_region(Vector2i(2, 2), Vector2i(4, 4), "试炼区")
	assert_true(bool(added.get("ok", false)), "区域应能添加：%s" % state.last_error)
	assert_eq(str(state.selection.get("kind", "")), "region")

	var picked := state.select_at(Vector2i(3, 3))
	assert_eq(str(picked.get("kind", "")), "region")
	var regions: Array = state.document.get("regions", [])
	var index := int(picked.get("index", -1))
	assert_true(index >= 0 and index < regions.size(), "选中的区域索引应有效")
	var region: Dictionary = regions[index]
	assert_eq(str(region.get("name", "")), "试炼区")

	assert_true(state.delete_selected(), "区域应能删除")
	assert_eq((state.document.get("regions", []) as Array).size(), before)


func test_spawn_world_to_cell_mapping() -> void:
	var state := _fresh_state()
	assert_eq(EditState.spawn_to_cell(state.document.get("spawn", {})), Vector2i(12, 18))
	var display := state.display_document()
	assert_eq(int(display.get("spawn", {}).get("x", -1)), 12)
	assert_eq(int(display.get("spawn", {}).get("z", -1)), 18)
	# 模型本身仍保存世界单位。
	assert_near(float(state.document.get("spawn", {}).get("x", 0.0)), 24.0)

	assert_true(state.set_spawn_cell(Vector2i(4, 4)), "出生点应能移动")
	assert_near(float(state.document.get("spawn", {}).get("x", 0.0)), 9.0)
	assert_near(float(state.document.get("spawn", {}).get("z", 0.0)), 9.0)
	assert_eq(str(state.select_at(Vector2i(4, 4)).get("kind", "")), "spawn")


# ---------------------------------------------------------------- 试跑快照
func test_playtest_snapshot_is_isolated() -> void:
	var original := FileAccess.get_file_as_string(SAMPLE_PATH)
	var state := _fresh_state()
	assert_eq(state.is_dirty(), false)
	assert_true(bool(state.paint_ground(Vector2i(2, 2), "stone").get("ok", false)))
	assert_true(state.is_dirty(), "未保存修改应标记 dirty")

	_remove_user_file(SNAPSHOT_PATH)
	var exported := state.export_playtest(SNAPSHOT_PATH)
	assert_true(bool(exported.get("ok", false)), "试跑快照应写出：%s" % state.last_error)
	assert_eq(FileAccess.get_file_as_string(SAMPLE_PATH), original, "正式地图不能被改动")
	assert_true(FileAccess.file_exists(SNAPSHOT_PATH))
	assert_true(state.is_dirty(), "写快照不等于保存")

	var loaded := LayoutDocument.load_document(SNAPSHOT_PATH)
	assert_true(bool(loaded.get("ok", false)), "快照应能被校验加载")
	var snapshot_doc: Dictionary = loaded.get("document", {})
	assert_eq(_tile_asset_at(snapshot_doc, Vector2i(2, 2)), "stone")
	assert_eq(_tile_asset_at(state.document, Vector2i(2, 2)), "stone")
	_remove_user_file(SNAPSHOT_PATH)

	var forbidden := state.export_playtest("res://data/layouts/forbidden_snapshot.json")
	assert_true(not bool(forbidden.get("ok", false)), "试跑快照不能写 res://")

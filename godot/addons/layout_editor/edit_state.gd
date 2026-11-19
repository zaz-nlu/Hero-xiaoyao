@tool
extends RefCounted

# 地图工坊编辑模型（无界面，@tool）。持有文档、保存快照、撤销/重做与选择；
# 提交修改时用 LayoutDocument.validate_document 校验；地面笔刷按整笔提交。
# 编辑过程绝不写盘；spawn 在文档里是世界单位，显示副本只把它换成格坐标。
signal changed
# kind: "ok" | "info" | "error"
signal status(kind: String, message: String)

const LayoutCatalog = preload("res://core/layouts/layout_catalog.gd")
const LayoutDocument = preload("res://core/layouts/layout_document.gd")
const LayoutTerrain = preload("res://core/layouts/layout_terrain.gd")
const LayoutTriggers = preload("res://core/layouts/layout_triggers.gd")
const EditQueries = preload("res://addons/layout_editor/edit_queries.gd")
const EditOps = preload("res://addons/layout_editor/edit_ops.gd")
const EditTerrainOps = preload("res://addons/layout_editor/edit_terrain_ops.gd")
const LayoutFiles = preload("res://addons/layout_editor/layout_files.gd")

const DEFAULT_MAP_PATH := "res://data/layouts/zixia_sect.json"
const TILE_SIZE: float = 2.0
const MAX_UNDO := 100
var catalog: Dictionary = {}
var document: Dictionary = {}
var saved_document: Dictionary = {}
var source_path: String = ""
var opened_id: String = ""
var selection: Dictionary = {"kind": "none", "index": -1, "cell": Vector2i(-1, -1)}
var undo_stack: Array = []
var redo_stack: Array = []
var last_error: String = ""
# 触发器目标数据（对话/敌人/任务/布局）整次编辑共享，不随鼠标移动重复读文件。
var trigger_context: Dictionary = LayoutTriggers.new_context()

var _stroke_active: bool = false
var _stroke_dirty: bool = false
var _stroke_snapshot: Dictionary = {}
var _stroke_tiles: Array = []
var _stroke_tile_index: Dictionary = {}

# 地形编译只在文档真正变化后重算；悬浮、预览与重绘都读缓存。
var _terrain_compiled: Dictionary = {}
var _terrain_dirty: bool = true

# ---------------------------------------------------------------- 生命周期
func setup() -> bool:
	var loaded := LayoutCatalog.load_catalog()
	if not bool(loaded.get("ok", false)):
		_emit_errors(loaded.get("errors", []))
		return false
	catalog = loaded
	return bool(load_map(DEFAULT_MAP_PATH).get("ok", false))


func has_document() -> bool:
	return not document.is_empty()


func is_dirty() -> bool:
	if document.is_empty():
		return false
	return JSON.stringify(document) != JSON.stringify(saved_document)


func document_id() -> String:
	return str(document.get("id", ""))


func can_undo() -> bool:
	return not undo_stack.is_empty()


func can_redo() -> bool:
	return not redo_stack.is_empty()


# 打开地图。成功时清空历史，失败时保留当前界面与草稿。
func load_map(path: String) -> Dictionary:
	var loaded := LayoutDocument.load_document(path)
	if not bool(loaded.get("ok", false)):
		_emit_errors(loaded.get("errors", []))
		return {"ok": false, "errors": loaded.get("errors", [])}
	catalog = loaded.get("catalog", catalog)
	document = (loaded.get("document", {}) as Dictionary).duplicate(true)
	_terrain_dirty = true
	saved_document = document.duplicate(true)
	source_path = path
	opened_id = document_id()
	selection = EditQueries.empty_selection()
	undo_stack.clear()
	redo_stack.clear()
	_end_stroke_silently()
	changed.emit()
	status.emit("ok", "已打开：%s" % str(document.get("name", path)))
	return {"ok": true, "errors": []}


func create_new(id: String, display_name: String, width: int, depth: int) -> Dictionary:
	var built := LayoutFiles.build_new_document(catalog, id, display_name, width, depth)
	if not bool(built.get("ok", false)):
		_emit_errors(built.get("errors", []))
		return {"ok": false, "errors": built.get("errors", [])}
	document = built.get("document", {})
	_terrain_dirty = true
	saved_document = {}
	source_path = ""
	opened_id = document_id()
	selection = EditQueries.empty_selection()
	undo_stack.clear()
	redo_stack.clear()
	_end_stroke_silently()
	changed.emit()
	status.emit("ok", "已新建草稿：%s（未保存）" % str(document.get("name", "")))
	return {"ok": true, "errors": []}


# ---------------------------------------------------------------- 保存/试跑
func save() -> Dictionary:
	var saved := LayoutFiles.save(document, catalog, source_path)
	if not bool(saved.get("ok", false)):
		_emit_errors(saved.get("errors", []))
		return {"ok": false, "errors": saved.get("errors", [])}
	source_path = str(saved.get("path", source_path))
	opened_id = document_id()
	saved_document = document.duplicate(true)
	changed.emit()
	status.emit("ok", "已保存到 %s" % source_path)
	return saved


func export_playtest(path: String = LayoutFiles.PLAYTEST_PATH) -> Dictionary:
	var result := LayoutFiles.export_playtest(document, catalog, path)
	if not bool(result.get("ok", false)):
		_emit_errors(result.get("errors", []))
		return result
	status.emit("info", "已生成试跑快照：%s" % path)
	return result


func list_maps() -> Array[String]:
	return LayoutFiles.list_maps()


# ---------------------------------------------------------------- 显示映射
# 画布只认识格坐标；这里只把 spawn 从世界单位换算成格，其余 schema 不变。
func display_document() -> Dictionary:
	var copy := document.duplicate(true)
	if not copy.is_empty():
		var cell := EditQueries.spawn_to_cell(copy.get("spawn", {}))
		copy["spawn"] = {"x": cell.x, "z": cell.y}
	return copy


static func spawn_to_cell(spawn_value: Variant) -> Vector2i:
	return EditQueries.spawn_to_cell(spawn_value)


static func cell_center(cell: Vector2i) -> Vector2:
	return EditQueries.cell_center(cell)


func current_spawn_cell() -> Vector2i:
	return EditQueries.spawn_to_cell(document.get("spawn", {}))


# ---------------------------------------------------------------- 选择
func select_at(cell: Vector2i) -> Dictionary:
	if not EditQueries.in_bounds(document, cell):
		clear_selection()
		return selection
	var object_index := EditQueries.object_index_at(document, catalog, cell)
	if object_index >= 0:
		var obj: Dictionary = (document.get("objects", []) as Array)[object_index]
		selection = {
			"kind": "object", "index": object_index, "cell": EditQueries.cell_from(obj)
		}
	elif current_spawn_cell() == cell:
		selection = {"kind": "spawn", "index": -1, "cell": cell}
	else:
		var region_index := EditQueries.region_index_at(document, cell)
		if region_index >= 0:
			var region: Dictionary = (document.get("regions", []) as Array)[region_index]
			selection = {
				"kind": "region", "index": region_index, "cell": EditQueries.cell_from(region)
			}
		else:
			selection = {"kind": "tile", "index": -1, "cell": cell}
	changed.emit()
	return selection


func clear_selection() -> void:
	if str(selection.get("kind", "none")) == "none":
		return
	selection = EditQueries.empty_selection()
	changed.emit()


func selected_object_index() -> int:
	if str(selection.get("kind", "")) != "object":
		return -1
	var index := int(selection.get("index", -1))
	var objects: Array = document.get("objects", [])
	if index < 0 or index >= objects.size():
		return -1
	return index


func selected_object() -> Dictionary:
	var index := selected_object_index()
	if index < 0:
		return {}
	return (document.get("objects", []) as Array)[index]


func selected_item() -> Dictionary:
	var obj := selected_object()
	if obj.is_empty():
		return {}
	return LayoutCatalog.item(catalog, str(obj.get("asset", "")))


# ---------------------------------------------------------------- 放置/绘制
# 拖放与点选共用这一个入口：地面写入 tiles，其余写入 objects。
func place_asset(asset_id: String, cell: Vector2i, turn: int = 0) -> Dictionary:
	var item := LayoutCatalog.item(catalog, asset_id)
	if item.is_empty():
		return _fail("未知素材：%s" % asset_id)
	if str(item.get("kind", "")) == "ground":
		return paint_ground(cell, asset_id)
	return place_object(asset_id, cell, turn)


func can_place(asset_id: String, cell: Vector2i, turn: int = 0) -> Dictionary:
	return EditOps.can_place(document, catalog, asset_id, cell, turn)


func place_object(asset_id: String, cell: Vector2i, turn: int = 0) -> Dictionary:
	var result := EditOps.place_object(document, catalog, asset_id, cell, turn)
	var item := LayoutCatalog.item(catalog, asset_id)
	if not _commit(result, "已放置：%s" % str(item.get("name", asset_id))):
		return {"ok": false, "errors": [last_error]}
	selection = {
		"kind": "object", "index": int(result.get("index", -1)), "cell": cell
	}
	changed.emit()
	return {"ok": true, "errors": []}


func paint_ground(cell: Vector2i, asset_id: String) -> Dictionary:
	var result := EditOps.paint_ground(document, catalog, cell, asset_id)
	var shown := str(LayoutCatalog.item(catalog, asset_id).get("name", asset_id))
	if not bool(result.get("ok", false)):
		_emit_errors(result.get("errors", []))
		return {"ok": false, "errors": result.get("errors", [])}
	if bool(result.get("unchanged", false)):
		status.emit("info", "该格已是 %s" % shown)
		return {"ok": true, "errors": []}
	if not _commit(result, "已铺地面：%s" % shown):
		return {"ok": false, "errors": [last_error]}
	return {"ok": true, "errors": []}


# 按住拖动刷地面：整笔只产生一条撤销记录。
func begin_ground_stroke() -> void:
	if _stroke_active:
		return
	_stroke_active = true
	_stroke_dirty = false
	_stroke_snapshot = _snapshot()
	_stroke_tiles = document.get("tiles", [])
	_stroke_tile_index = EditQueries.tile_index_by_cell(_stroke_tiles)


# 连续刷地面：每格只查边界与素材，直接改草稿 tiles；整笔结束再统一完整校验。
func stroke_ground(cell: Vector2i, asset_id: String) -> bool:
	if not _stroke_active:
		begin_ground_stroke()
	var result := EditOps.paint_ground_tile(
		document, catalog, _stroke_tiles, _stroke_tile_index, cell, asset_id
	)
	if not bool(result.get("ok", false)) or bool(result.get("unchanged", false)):
		return false
	document["tiles"] = _stroke_tiles
	_stroke_dirty = true
	changed.emit()
	return true


func end_ground_stroke() -> bool:
	if not _stroke_active:
		return false
	var snapshot := _stroke_snapshot
	var dirty := _stroke_dirty
	_end_stroke_silently()
	if not dirty:
		return false
	var errors := LayoutDocument.validate_document(document, catalog, trigger_context)
	if not errors.is_empty():
		document = snapshot.get("document", document)
		selection = snapshot.get("selection", selection)
		_terrain_dirty = true
		_emit_errors(errors)
		changed.emit()
		return false
	redo_stack.clear()
	_push_undo(snapshot)
	status.emit("ok", "刷涂完成")
	changed.emit()
	return true


# 右键：擦掉该格地面，以及包含该格的物件。
func erase_cell(cell: Vector2i) -> Dictionary:
	var result := EditOps.erase_cell(document, catalog, cell)
	if not bool(result.get("ok", false)):
		_emit_errors(result.get("errors", []))
		return {"ok": false, "errors": result.get("errors", [])}
	var removed: Array = result.get("removed", [])
	var message := "已擦除：" + "、".join(PackedStringArray(removed))
	if not _commit(result, message):
		return {"ok": false, "errors": [last_error]}
	var object_index := int(result.get("object_index", -1))
	if str(selection.get("kind", "")) == "object" and object_index >= 0:
		var selected := int(selection.get("index", -1))
		if selected == object_index:
			selection = EditQueries.empty_selection()
		elif selected > object_index:
			selection["index"] = selected - 1
	elif str(selection.get("kind", "")) == "tile" \
			and selection.get("cell", Vector2i(-1, -1)) == cell:
		selection = EditQueries.empty_selection()
	changed.emit()
	return {"ok": true, "errors": []}


# ---------------------------------------------------------------- 物件操作
func move_selected_object(cell: Vector2i) -> bool:
	var index := selected_object_index()
	if index < 0:
		return _fail_bool("请先选中一个物件")
	var result := EditOps.move_object(document, index, cell)
	if not _commit(result, "已移动物件到 (%d, %d)" % [cell.x, cell.y]):
		return false
	selection["cell"] = cell
	changed.emit()
	return true


func rotate_selected_object() -> bool:
	var index := selected_object_index()
	if index < 0:
		return _fail_bool("请先选中一个物件")
	var result := EditOps.rotate_object(document, index)
	var obj: Dictionary = (document.get("objects", []) as Array)[index]
	var turn := posmod(int(obj.get("turn", 0)) + 1, 4)
	return _commit(result, "已旋转到 %d°" % (turn * 90))


func delete_selected() -> bool:
	var kind := str(selection.get("kind", "none"))
	var result: Dictionary
	if kind == "object":
		var index := selected_object_index()
		if index < 0:
			return _fail_bool("请先选中一个物件")
		result = EditOps.remove_object(document, index)
	elif kind == "region":
		result = EditOps.remove_region(document, int(selection.get("index", -1)))
	else:
		return _fail_bool("当前选择不能删除（出生点只能移动）")
	if not _commit(result, "已删除%s" % ("物件" if kind == "object" else "区域")):
		return false
	selection = EditQueries.empty_selection()
	changed.emit()
	return true


func set_selected_label(text: String) -> bool:
	var index := selected_object_index()
	if index < 0:
		return _fail_bool("请先选中一个物件")
	return _commit(EditOps.set_label(document, index, text), "已更新标签")


# ---------------------------------------------------------------- 物件触发器
func selected_trigger() -> Dictionary:
	var obj := selected_object()
	if obj.is_empty():
		return {}
	var value: Variant = obj.get("trigger", null)
	return value if value is Dictionary else {}


func set_selected_trigger(trigger: Dictionary) -> Dictionary:
	var index := selected_object_index()
	if index < 0:
		return _fail("请先选中一个物件")
	var result := EditOps.set_trigger(document, index, trigger)
	if not _commit(result, "已应用物件触发器"):
		return {"ok": false, "errors": [last_error]}
	return {"ok": true, "errors": []}


func clear_selected_trigger() -> Dictionary:
	var index := selected_object_index()
	if index < 0:
		return _fail("请先选中一个物件")
	var result := EditOps.clear_trigger(document, index)
	if not _commit(result, "已清除物件触发器"):
		return {"ok": false, "errors": [last_error]}
	return {"ok": true, "errors": []}


func trigger_targets(kind: String) -> Array[Dictionary]:
	return LayoutTriggers.targets(kind, trigger_context)


func set_spawn_cell(cell: Vector2i) -> bool:
	var result := EditOps.set_spawn(document, cell)
	if not _commit(result, "出生点已放到 (%d, %d)" % [cell.x, cell.y]):
		return false
	selection = {"kind": "spawn", "index": -1, "cell": cell}
	changed.emit()
	return true


# ---------------------------------------------------------------- 区域/地图信息
func add_region(corner_a: Vector2i, corner_b: Vector2i, region_name: String) -> Dictionary:
	var result := EditOps.add_region(document, corner_a, corner_b, region_name)
	if not _commit(result, "已添加区域：%s" % region_name.strip_edges()):
		return {"ok": false, "errors": [last_error]}
	var index := int(result.get("index", -1))
	var regions: Array = document.get("regions", [])
	var origin := Vector2i(-1, -1)
	if index >= 0 and index < regions.size():
		origin = EditQueries.cell_from(regions[index])
	selection = {"kind": "region", "index": index, "cell": origin}
	changed.emit()
	return {"ok": true, "errors": []}


func apply_map_info(id: String, display_name: String, width: int, depth: int) -> Dictionary:
	var result := EditOps.apply_map_info(
		document, catalog, id, display_name, width, depth
	)
	if not _commit(result, "地图信息已更新"):
		return {"ok": false, "errors": [last_error]}
	return {"ok": true, "errors": []}


# ---------------------------------------------------------------- 地形
# 所有地形操作都经 _commit：草稿副本、一次完整校验、历史快照与 changed 信号。
func terrain() -> Dictionary:
	if _terrain_dirty:
		_terrain_compiled = LayoutTerrain.compile(document)
		_terrain_dirty = false
	return _terrain_compiled


func terrain_height_at_cell(cell: Vector2i) -> float:
	if not has_document():
		return 0.0
	return LayoutTerrain.height_at(terrain(), EditQueries.cell_center(cell))


func add_terrace(
	display_name: String,
	corner_a: Vector2i,
	corner_b: Vector2i,
	y: float,
	from_y: float,
	top_asset: String
) -> Dictionary:
	var result := EditTerrainOps.add_terrace(
		document, display_name, corner_a, corner_b, y, from_y, top_asset
	)
	var label := display_name.strip_edges()
	if label.is_empty():
		label = "台地"
	if not _commit(result, "已添加台地：%s" % label):
		return {"ok": false, "errors": [last_error]}
	return {"ok": true, "errors": [], "index": int(result.get("index", -1))}


func update_terrace(
	index: int,
	display_name: String,
	y: float,
	from_y: float,
	top_asset: String
) -> Dictionary:
	var result := EditTerrainOps.update_terrace(
		document, index, display_name, y, from_y, top_asset
	)
	if not _commit(result, "台地已更新"):
		return {"ok": false, "errors": [last_error]}
	return {"ok": true, "errors": []}


func remove_terrace(index: int) -> Dictionary:
	var result := EditTerrainOps.remove_terrace(document, index)
	if not _commit(result, "已删除台地"):
		return {"ok": false, "errors": [last_error]}
	return {"ok": true, "errors": []}


func add_water(
	display_name: String,
	corner_a: Vector2i,
	corner_b: Vector2i,
	level: Variant
) -> Dictionary:
	var result := EditTerrainOps.add_water(
		document, display_name, corner_a, corner_b, level
	)
	var label := display_name.strip_edges()
	if label.is_empty():
		label = "水面"
	if not _commit(result, "已添加水面：%s" % label):
		return {"ok": false, "errors": [last_error]}
	return {"ok": true, "errors": [], "index": int(result.get("index", -1))}


func remove_water(index: int) -> Dictionary:
	var result := EditTerrainOps.remove_water(document, index)
	if not _commit(result, "已删除水面"):
		return {"ok": false, "errors": [last_error]}
	return {"ok": true, "errors": []}


func add_connector(
	platform_index: int,
	kind: String,
	side: String,
	cell_a: Vector2i,
	cell_b: Vector2i
) -> Dictionary:
	var result := EditTerrainOps.add_connector(
		document, platform_index, kind, side, cell_a, cell_b
	)
	if not _commit(result, "已添加连接"):
		return {"ok": false, "errors": [last_error]}
	return {
		"ok": true,
		"errors": [],
		"stairs_index": int(result.get("stairs_index", -1)),
		"side": str(result.get("side", side)),
	}


func remove_connector(platform_index: int, stairs_index: int) -> Dictionary:
	var result := EditTerrainOps.remove_connector(document, platform_index, stairs_index)
	if not _commit(result, "已删除连接"):
		return {"ok": false, "errors": [last_error]}
	return {"ok": true, "errors": []}


# ---------------------------------------------------------------- 环境
# 天空/光照/相机范围/边界林一次提交：草稿副本 → 完整校验 → 撤销历史。
# camera_clamp 传空数组表示清除；border 传空字典表示关闭边界林。
func apply_environment(
	sky: String,
	lighting: String,
	camera_clamp: Array,
	border: Dictionary
) -> Dictionary:
	var candidate: Dictionary = document.duplicate(true)
	var env_value: Variant = candidate.get("environment", null)
	var env: Dictionary = {}
	if env_value is Dictionary:
		env = (env_value as Dictionary).duplicate(true)
	env["sky"] = sky
	env["lighting"] = lighting
	if camera_clamp.size() == 4:
		env["camera_clamp"] = [
			float(camera_clamp[0]), float(camera_clamp[1]),
			float(camera_clamp[2]), float(camera_clamp[3]),
		]
	else:
		env.erase("camera_clamp")
	if border.is_empty():
		env.erase("border")
	else:
		env["border"] = border.duplicate(true)
	candidate["environment"] = env
	if not _commit({"ok": true, "document": candidate}, "环境设置已更新"):
		return {"ok": false, "errors": [last_error]}
	return {"ok": true, "errors": []}


func clear_environment() -> Dictionary:
	var candidate: Dictionary = document.duplicate(true)
	candidate.erase("environment")
	if not _commit({"ok": true, "document": candidate}, "环境设置已清空"):
		return {"ok": false, "errors": [last_error]}
	return {"ok": true, "errors": []}


# ---------------------------------------------------------------- 撤销/重做
func undo() -> bool:
	if undo_stack.is_empty():
		return false
	_abort_stroke()
	redo_stack.append(_snapshot())
	_restore(undo_stack.pop_back())
	status.emit("info", "已撤销")
	return true


func redo() -> bool:
	if redo_stack.is_empty():
		return false
	_abort_stroke()
	undo_stack.append(_snapshot())
	_restore(redo_stack.pop_back())
	status.emit("info", "已重做")
	return true


# ---------------------------------------------------------------- 内部
func _commit(result: Dictionary, message: String) -> bool:
	if not bool(result.get("ok", false)):
		_emit_errors(result.get("errors", []))
		return false
	var candidate: Dictionary = result.get("document", {})
	if candidate.is_empty():
		return _fail_bool("没有可提交的修改")
	if catalog.is_empty():
		return _fail_bool("素材目录尚未加载")
	var errors := LayoutDocument.validate_document(candidate, catalog, trigger_context)
	if not errors.is_empty():
		_emit_errors(errors)
		return false
	if _stroke_active:
		end_ground_stroke()
	_push_undo(_snapshot())
	redo_stack.clear()
	document = candidate
	_terrain_dirty = true
	_fix_selection()
	if not message.is_empty():
		status.emit("ok", message)
	changed.emit()
	return true


func _restore(entry: Variant) -> void:
	if not (entry is Dictionary):
		return
	var snapshot: Dictionary = entry
	document = (snapshot.get("document", {}) as Dictionary).duplicate(true)
	_terrain_dirty = true
	selection = (snapshot.get("selection", EditQueries.empty_selection()) as Dictionary).duplicate(true)
	_fix_selection()
	changed.emit()


func _push_undo(snapshot: Dictionary) -> void:
	undo_stack.append(snapshot)
	if undo_stack.size() > MAX_UNDO:
		undo_stack.pop_front()


func _snapshot() -> Dictionary:
	return {"document": document.duplicate(true), "selection": selection.duplicate(true)}


func _fix_selection() -> void:
	selection = EditQueries.fixed_selection(document, selection)


func _end_stroke_silently() -> void:
	_stroke_active = false
	_stroke_dirty = false
	_stroke_snapshot = {}
	_stroke_tiles = []
	_stroke_tile_index.clear()


# 未提交的笔划直接丢弃，回到笔划前的快照（撤销/重做会再覆盖文档）。
func _abort_stroke() -> void:
	if not _stroke_active:
		return
	document = (_stroke_snapshot.get("document", document) as Dictionary).duplicate(true)
	_terrain_dirty = true
	selection = (_stroke_snapshot.get("selection", selection) as Dictionary).duplicate(true)
	_end_stroke_silently()


func _fail(message: String) -> Dictionary:
	_emit_error(message)
	return {"ok": false, "errors": [message]}


func _fail_bool(message: String) -> bool:
	_emit_error(message)
	return false


func _emit_error(message: String) -> void:
	last_error = message
	status.emit("error", message)


func _emit_errors(errors: Variant) -> void:
	var lines: Array[String] = []
	if errors is Array:
		for message in errors:
			lines.append(str(message))
	if lines.is_empty():
		lines.append("未知错误")
	last_error = lines[0]
	status.emit("error", "\n".join(PackedStringArray(lines)))

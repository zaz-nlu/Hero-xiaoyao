@tool
extends RefCounted

# 地图文档的编辑操作（纯函数）：输入旧文档，返回新文档或错误，不碰状态/历史。
# 是否合法统一交给 LayoutDocument.validate_document，EditState 负责提交或丢弃。

const LayoutCatalog = preload("res://core/layouts/layout_catalog.gd")
const LayoutDocument = preload("res://core/layouts/layout_document.gd")
const EditQueries = preload("res://addons/layout_editor/edit_queries.gd")

const MIN_SPAN := 4
const MAX_SPAN := 96


static func can_place(
	document: Dictionary, catalog: Dictionary, asset_id: String, cell: Vector2i, turn: int = 0
) -> Dictionary:
	if not EditQueries.in_bounds(document, cell):
		return {"ok": false, "reason": "超出地图范围"}
	var item := LayoutCatalog.item(catalog, asset_id)
	if item.is_empty():
		return {"ok": false, "reason": "未知素材"}
	if str(item.get("kind", "")) == "ground":
		return {"ok": true, "reason": ""}
	var cells := LayoutDocument.footprint_cells(item, cell.x, cell.y, turn)
	if not EditQueries.rect_in_bounds(document, cells):
		return {"ok": false, "reason": "占地超出地图范围"}
	var objects: Array = document.get("objects", [])
	for raw in objects:
		var other: Dictionary = raw
		var other_item := LayoutCatalog.item(catalog, str(other.get("asset", "")))
		var other_cells := LayoutDocument.footprint_cells(
			other_item, int(other.get("x", 0)), int(other.get("z", 0)), int(other.get("turn", 0))
		)
		if other_cells.intersects(cells):
			return {"ok": false, "reason": "与其他物件重叠"}
	if bool(item.get("blocking", false)):
		var world := LayoutDocument.footprint_world(item, cell.x, cell.y, turn)
		if world.grow(LayoutDocument.PLAYER_RADIUS).has_point(
				LayoutDocument.spawn_point(document)
		):
			return {"ok": false, "reason": "会挡住出生点"}
	return {"ok": true, "reason": ""}


static func place_object(
	document: Dictionary, catalog: Dictionary, asset_id: String, cell: Vector2i, turn: int = 0
) -> Dictionary:
	var check := can_place(document, catalog, asset_id, cell, turn)
	if not bool(check.get("ok", false)):
		return _fail(str(check.get("reason", "无法放置")))
	var candidate := document.duplicate(true)
	var objects: Array = candidate.get("objects", [])
	objects.append({
		"asset": asset_id,
		"x": cell.x,
		"z": cell.y,
		"turn": posmod(turn, 4),
		"label": "",
	})
	candidate["objects"] = objects
	return {"ok": true, "errors": [], "document": candidate, "index": objects.size() - 1}


static func paint_ground(
	document: Dictionary, catalog: Dictionary, cell: Vector2i, asset_id: String
) -> Dictionary:
	if not EditQueries.in_bounds(document, cell):
		return _fail("坐标超出地图范围")
	var item := LayoutCatalog.item(catalog, asset_id)
	if item.is_empty() or str(item.get("kind", "")) != "ground":
		return _fail("'%s' 不是地面材料" % asset_id)
	var index := EditQueries.find_tile_index(document, cell)
	if index >= 0:
		var current: Dictionary = (document.get("tiles", []) as Array)[index]
		if str(current.get("asset", "")) == asset_id:
			return {"ok": true, "errors": [], "document": {}, "unchanged": true}
	var candidate := document.duplicate(true)
	var tiles: Array = candidate.get("tiles", [])
	var found := EditQueries.find_tile_index(document, cell)
	if found >= 0:
		(tiles[found] as Dictionary)["asset"] = asset_id
	else:
		tiles.append({"asset": asset_id, "x": cell.x, "z": cell.y})
	candidate["tiles"] = tiles
	return {"ok": true, "errors": [], "document": candidate, "unchanged": false}


# 连续刷地专用：只检查本格，就地改已打开的 tiles 与索引；整笔结束再统一完整校验。
static func paint_ground_tile(
	document: Dictionary, catalog: Dictionary, tiles: Array, index_by_cell: Dictionary,
	cell: Vector2i, asset_id: String
) -> Dictionary:
	if not EditQueries.in_bounds(document, cell):
		return _fail("坐标超出地图范围")
	var item := LayoutCatalog.item(catalog, asset_id)
	if item.is_empty() or str(item.get("kind", "")) != "ground":
		return _fail("'%s' 不是地面材料" % asset_id)
	if index_by_cell.has(cell):
		var tile: Dictionary = tiles[int(index_by_cell[cell])]
		if str(tile.get("asset", "")) == asset_id:
			return {"ok": true, "errors": [], "unchanged": true}
		tile["asset"] = asset_id
		return {"ok": true, "errors": [], "unchanged": false}
	tiles.append({"asset": asset_id, "x": cell.x, "z": cell.y})
	index_by_cell[cell] = tiles.size() - 1
	return {"ok": true, "errors": [], "unchanged": false}


# 右键擦除：该格地面与包含该格的物件一起清掉。
static func erase_cell(
	document: Dictionary, catalog: Dictionary, cell: Vector2i
) -> Dictionary:
	if not EditQueries.in_bounds(document, cell):
		return _fail("坐标超出地图范围")
	var candidate := document.duplicate(true)
	var removed: Array[String] = []
	var tile_index := EditQueries.find_tile_index(document, cell)
	if tile_index >= 0:
		(candidate.get("tiles", []) as Array).remove_at(tile_index)
		removed.append("地面")
	var object_index := EditQueries.object_index_at(document, catalog, cell)
	if object_index >= 0:
		var objects: Array = candidate.get("objects", [])
		var obj: Dictionary = objects[object_index]
		var item := LayoutCatalog.item(catalog, str(obj.get("asset", "")))
		removed.append(str(item.get("name", obj.get("asset", "物件"))))
		objects.remove_at(object_index)
		candidate["objects"] = objects
	if removed.is_empty():
		return _fail("该格没有可擦除的内容")
	return {
		"ok": true,
		"errors": [],
		"document": candidate,
		"removed": removed,
		"object_index": object_index,
	}


static func move_object(document: Dictionary, index: int, cell: Vector2i) -> Dictionary:
	if not EditQueries.in_bounds(document, cell):
		return _fail("目标格超出地图范围")
	var candidate := document.duplicate(true)
	var obj: Dictionary = (candidate.get("objects", []) as Array)[index]
	obj["x"] = cell.x
	obj["z"] = cell.y
	return {"ok": true, "errors": [], "document": candidate}


static func rotate_object(document: Dictionary, index: int) -> Dictionary:
	var candidate := document.duplicate(true)
	var obj: Dictionary = (candidate.get("objects", []) as Array)[index]
	obj["turn"] = posmod(int(obj.get("turn", 0)) + 1, 4)
	return {"ok": true, "errors": [], "document": candidate}


static func remove_object(document: Dictionary, index: int) -> Dictionary:
	var candidate := document.duplicate(true)
	(candidate.get("objects", []) as Array).remove_at(index)
	return {"ok": true, "errors": [], "document": candidate}


static func remove_region(document: Dictionary, index: int) -> Dictionary:
	var candidate := document.duplicate(true)
	var regions: Array = candidate.get("regions", [])
	if index < 0 or index >= regions.size():
		return _fail("请先选中一个区域")
	regions.remove_at(index)
	candidate["regions"] = regions
	return {"ok": true, "errors": [], "document": candidate}


static func set_label(document: Dictionary, index: int, text: String) -> Dictionary:
	var candidate := document.duplicate(true)
	var obj: Dictionary = (candidate.get("objects", []) as Array)[index]
	obj["label"] = text
	return {"ok": true, "errors": [], "document": candidate}


# 只改被选中实例自己的 trigger；同一素材的其他实例不受影响。
static func set_trigger(document: Dictionary, index: int, trigger: Dictionary) -> Dictionary:
	var objects: Array = document.get("objects", [])
	if index < 0 or index >= objects.size():
		return _fail("请先选中一个物件")
	var candidate := document.duplicate(true)
	var obj: Dictionary = (candidate.get("objects", []) as Array)[index]
	obj["trigger"] = trigger.duplicate(true)
	return {"ok": true, "errors": [], "document": candidate}


static func clear_trigger(document: Dictionary, index: int) -> Dictionary:
	var objects: Array = document.get("objects", [])
	if index < 0 or index >= objects.size():
		return _fail("请先选中一个物件")
	var candidate := document.duplicate(true)
	var obj: Dictionary = (candidate.get("objects", []) as Array)[index]
	if not obj.has("trigger"):
		return _fail("该物件没有触发器")
	obj.erase("trigger")
	return {"ok": true, "errors": [], "document": candidate}


static func set_spawn(document: Dictionary, cell: Vector2i) -> Dictionary:
	if not EditQueries.in_bounds(document, cell):
		return _fail("出生点超出地图范围")
	var candidate := document.duplicate(true)
	var center := EditQueries.cell_center(cell)
	candidate["spawn"] = {"x": center.x, "z": center.y}
	return {"ok": true, "errors": [], "document": candidate}


static func add_region(
	document: Dictionary, corner_a: Vector2i, corner_b: Vector2i, region_name: String
) -> Dictionary:
	var clean_name := region_name.strip_edges()
	if clean_name.is_empty():
		return _fail("区域名字不能为空")
	var rect := Rect2i(
		Vector2i(mini(corner_a.x, corner_b.x), mini(corner_a.y, corner_b.y)),
		Vector2i(absi(corner_a.x - corner_b.x) + 1, absi(corner_a.y - corner_b.y) + 1)
	)
	if not EditQueries.rect_in_bounds(document, rect):
		return _fail("区域必须完整落在地图内")
	var candidate := document.duplicate(true)
	var regions: Array = candidate.get("regions", [])
	regions.append({
		"name": clean_name,
		"x": rect.position.x,
		"z": rect.position.y,
		"width": rect.size.x,
		"depth": rect.size.y,
	})
	candidate["regions"] = regions
	return {"ok": true, "errors": [], "document": candidate, "index": regions.size() - 1}


# 同时更新 ID/名字/尺寸；缩小时若有数据会被裁掉，整体拒绝，不做半截修改。
static func apply_map_info(
	document: Dictionary, catalog: Dictionary,
	id: String, display_name: String, width: int, depth: int
) -> Dictionary:
	var clean_id := id.strip_edges()
	var clean_name := display_name.strip_edges()
	if not _valid_id(clean_id):
		return _fail("地图 ID 只能用小写字母、数字和下划线，且以字母开头")
	if clean_name.is_empty():
		return _fail("地图名字不能为空")
	if width < MIN_SPAN or width > MAX_SPAN or depth < MIN_SPAN or depth > MAX_SPAN:
		return _fail("地图格数必须在 %d..%d 之间" % [MIN_SPAN, MAX_SPAN])
	if width != int(document.get("width", 0)) or depth != int(document.get("depth", 0)):
		var cropped := EditQueries.cropped_summary(document, catalog, width, depth)
		if not cropped.is_empty():
			return _fail("缩小地图会裁掉 %s，请先清理这些数据" % cropped)
	var candidate := document.duplicate(true)
	candidate["id"] = clean_id
	candidate["name"] = clean_name
	candidate["width"] = width
	candidate["depth"] = depth
	return {"ok": true, "errors": [], "document": candidate}


static func _valid_id(id: String) -> bool:
	if id.is_empty():
		return false
	for i in range(id.length()):
		var code := id.unicode_at(i)
		if i == 0:
			if code < 97 or code > 122:
				return false
		elif not ((code >= 97 and code <= 122) \
				or (code >= 48 and code <= 57) or code == 95):
			return false
	return true


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "errors": [message], "document": {}}

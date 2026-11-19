@tool
extends RefCounted

# 地图文档的只读查询/几何辅助；编辑器画布与状态模型共用，避免两套坐标判断。

const LayoutCatalog = preload("res://core/layouts/layout_catalog.gd")
const LayoutDocument = preload("res://core/layouts/layout_document.gd")

const TILE_SIZE: float = 2.0


# 文档 spawn 是世界单位；界面统一用格坐标。
static func spawn_to_cell(spawn_value: Variant) -> Vector2i:
	if not (spawn_value is Dictionary):
		return Vector2i(-1, -1)
	var spawn: Dictionary = spawn_value
	return Vector2i(
		int(floor(float(spawn.get("x", 0.0)) / TILE_SIZE)),
		int(floor(float(spawn.get("z", 0.0)) / TILE_SIZE))
	)


static func empty_selection() -> Dictionary:
	return {"kind": "none", "index": -1, "cell": Vector2i(-1, -1)}


# 撤销/删除后索引可能失效，回到空选择。
static func fixed_selection(document: Dictionary, selection: Dictionary) -> Dictionary:
	var kind := str(selection.get("kind", "none"))
	var index := int(selection.get("index", -1))
	if kind == "object":
		if index < 0 or index >= (document.get("objects", []) as Array).size():
			return empty_selection()
	elif kind == "region":
		if index < 0 or index >= (document.get("regions", []) as Array).size():
			return empty_selection()
	return selection


static func cell_center(cell: Vector2i) -> Vector2:
	return Vector2(
		(float(cell.x) + 0.5) * TILE_SIZE,
		(float(cell.y) + 0.5) * TILE_SIZE
	)


# 两角（含两端格）对应的格矩形，供区域/台地/水面共用。
static func cell_rect(corner_a: Vector2i, corner_b: Vector2i) -> Rect2i:
	var origin := Vector2i(mini(corner_a.x, corner_b.x), mini(corner_a.y, corner_b.y))
	var size := Vector2i(
		absi(corner_a.x - corner_b.x) + 1,
		absi(corner_a.y - corner_b.y) + 1
	)
	return Rect2i(origin, size)


# 格矩形转世界单位矩形；地形 rect 使用世界坐标且两角对齐格边。
static func cell_rect_world(corner_a: Vector2i, corner_b: Vector2i) -> Rect2:
	var rect := cell_rect(corner_a, corner_b)
	return Rect2(
		Vector2(rect.position) * TILE_SIZE,
		Vector2(rect.size) * TILE_SIZE
	)


static func world_rect_to_cells(rect: Rect2) -> Rect2i:
	return Rect2i(
		int(round(rect.position.x / TILE_SIZE)),
		int(round(rect.position.y / TILE_SIZE)),
		int(round(rect.size.x / TILE_SIZE)),
		int(round(rect.size.y / TILE_SIZE))
	)


static func in_bounds(document: Dictionary, cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 \
		and cell.x < int(document.get("width", 0)) \
		and cell.y < int(document.get("depth", 0))


static func rect_in_bounds(document: Dictionary, rect: Rect2i) -> bool:
	return rect.position.x >= 0 and rect.position.y >= 0 \
		and rect.position.x + rect.size.x <= int(document.get("width", 0)) \
		and rect.position.y + rect.size.y <= int(document.get("depth", 0))


static func cell_from(entry: Dictionary) -> Vector2i:
	return Vector2i(int(entry.get("x", 0)), int(entry.get("z", 0)))


static func find_tile_index(document: Dictionary, cell: Vector2i) -> int:
	var tiles: Array = document.get("tiles", [])
	for i in range(tiles.size()):
		var tile: Dictionary = tiles[i]
		if int(tile.get("x", -1)) == cell.x and int(tile.get("z", -1)) == cell.y:
			return i
	return -1


# 连续刷地时先建一次 cell -> tiles 下标，避免每格线性扫描整张地面表。
static func tile_index_by_cell(tiles: Array) -> Dictionary:
	var index: Dictionary = {}
	for i in range(tiles.size()):
		var tile: Dictionary = tiles[i]
		index[Vector2i(int(tile.get("x", -1)), int(tile.get("z", -1)))] = i
	return index


static func object_index_at(document: Dictionary, catalog: Dictionary, cell: Vector2i) -> int:
	var objects: Array = document.get("objects", [])
	for i in range(objects.size()):
		var obj: Dictionary = objects[i]
		var item := LayoutCatalog.item(catalog, str(obj.get("asset", "")))
		var cells := LayoutDocument.footprint_cells(
			item, int(obj.get("x", 0)), int(obj.get("z", 0)), int(obj.get("turn", 0))
		)
		if cells.has_point(cell):
			return i
	return -1


static func region_index_at(document: Dictionary, cell: Vector2i) -> int:
	var regions: Array = document.get("regions", [])
	for i in range(regions.size()):
		var region: Dictionary = regions[i]
		var rect := Rect2i(
			int(region.get("x", 0)), int(region.get("z", 0)),
			int(region.get("width", 0)), int(region.get("depth", 0))
		)
		if rect.has_point(cell):
			return i
	return -1


# 缩小地图前检查哪些数据会落到边界外；返回空字符串表示可以安全缩到该尺寸。
static func cropped_summary(
	document: Dictionary, catalog: Dictionary, width: int, depth: int
) -> String:
	var parts: Array[String] = []
	var tiles := 0
	for raw in document.get("tiles", []):
		var tile: Dictionary = raw
		if int(tile.get("x", 0)) >= width or int(tile.get("z", 0)) >= depth:
			tiles += 1
	if tiles > 0:
		parts.append("地面 %d 格" % tiles)
	var objects := 0
	for raw in document.get("objects", []):
		var obj: Dictionary = raw
		var item := LayoutCatalog.item(catalog, str(obj.get("asset", "")))
		var cells := LayoutDocument.footprint_cells(
			item, int(obj.get("x", 0)), int(obj.get("z", 0)), int(obj.get("turn", 0))
		)
		if cells.position.x + cells.size.x > width \
				or cells.position.y + cells.size.y > depth:
			objects += 1
	if objects > 0:
		parts.append("物件 %d 个" % objects)
	var regions := 0
	for raw in document.get("regions", []):
		var region: Dictionary = raw
		if int(region.get("x", 0)) + int(region.get("width", 0)) > width \
				or int(region.get("z", 0)) + int(region.get("depth", 0)) > depth:
			regions += 1
	if regions > 0:
		parts.append("区域 %d 个" % regions)
	var spawn := LayoutDocument.spawn_point(document)
	if spawn.x > float(width) * TILE_SIZE or spawn.y > float(depth) * TILE_SIZE:
		parts.append("出生点")
	return "、".join(PackedStringArray(parts))

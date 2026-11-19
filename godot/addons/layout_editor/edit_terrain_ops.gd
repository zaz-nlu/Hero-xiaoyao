@tool
extends RefCounted

# 地形的纯文档操作：输入旧文档，返回携带新文档的结果或错误，不碰状态/历史。
# 是否合法统一交给 LayoutDocument.validate_document；EditState 负责提交或丢弃。
# 坐标约定与 core/layouts/layout_terrain_data.gd 一致：
#   terraces / water 的 rect 是世界坐标 [x0,z0,x1,z1]；
#   stairs 的 north/south 用 x0/x1，east/west 用 z0/z1，端点对齐 2 单位格边。

const EditQueries = preload("res://addons/layout_editor/edit_queries.gd")
const TerrainData = preload("res://core/layouts/layout_terrain_data.gd")

const TILE_SIZE: float = 2.0


# ---------------------------------------------------------------- 台地

static func add_terrace(
	document: Dictionary,
	display_name: String,
	corner_a: Vector2i,
	corner_b: Vector2i,
	y: float,
	from_y: float,
	top_asset: String
) -> Dictionary:
	var cells := EditQueries.cell_rect(corner_a, corner_b)
	if not EditQueries.rect_in_bounds(document, cells):
		return _fail("台地必须完整落在地图内")
	if y <= from_y:
		return _fail("顶部高度必须高于下层高度")
	var candidate := document.duplicate(true)
	var terraces: Array = candidate.get("terraces", [])
	var entry := {
		"name": display_name.strip_edges(),
		"rect": _world_rect_array(cells),
		"y": y,
		"from_y": from_y,
		"stairs": [],
	}
	var top := top_asset.strip_edges()
	if not top.is_empty():
		entry["top"] = top
	terraces.append(entry)
	candidate["terraces"] = terraces
	return {"ok": true, "errors": [], "document": candidate, "index": terraces.size() - 1}


# 只改名称/高度/顶面材料；rect 与已有 stairs 保持不变。
static func update_terrace(
	document: Dictionary,
	index: int,
	display_name: String,
	y: float,
	from_y: float,
	top_asset: String
) -> Dictionary:
	var terraces: Array = document.get("terraces", [])
	if index < 0 or index >= terraces.size():
		return _fail("请先选中一个台地")
	if y <= from_y:
		return _fail("顶部高度必须高于下层高度")
	var candidate := document.duplicate(true)
	var entries: Array = candidate.get("terraces", [])
	var entry: Dictionary = entries[index]
	entry["name"] = display_name.strip_edges()
	entry["y"] = y
	entry["from_y"] = from_y
	var top := top_asset.strip_edges()
	if top.is_empty():
		entry.erase("top")
	else:
		entry["top"] = top
	candidate["terraces"] = entries
	return {"ok": true, "errors": [], "document": candidate}


static func remove_terrace(document: Dictionary, index: int) -> Dictionary:
	var terraces: Array = document.get("terraces", [])
	if index < 0 or index >= terraces.size():
		return _fail("请先选中一个台地")
	var candidate := document.duplicate(true)
	var entries: Array = candidate.get("terraces", [])
	entries.remove_at(index)
	candidate["terraces"] = entries
	return {"ok": true, "errors": [], "document": candidate}


# ---------------------------------------------------------------- 水面

# level 为 null 时写自动水位（运行时取底面 + WATER_LIFT）。
static func add_water(
	document: Dictionary,
	display_name: String,
	corner_a: Vector2i,
	corner_b: Vector2i,
	level: Variant
) -> Dictionary:
	var cells := EditQueries.cell_rect(corner_a, corner_b)
	if not EditQueries.rect_in_bounds(document, cells):
		return _fail("水面必须完整落在地图内")
	var candidate := document.duplicate(true)
	var water: Array = candidate.get("water", [])
	var entry := {
		"name": display_name.strip_edges(),
		"rect": _world_rect_array(cells),
	}
	if level != null:
		entry["y"] = float(level)
	water.append(entry)
	candidate["water"] = water
	return {"ok": true, "errors": [], "document": candidate, "index": water.size() - 1}


static func remove_water(document: Dictionary, index: int) -> Dictionary:
	var water: Array = document.get("water", [])
	if index < 0 or index >= water.size():
		return _fail("请先选中一个水面")
	var candidate := document.duplicate(true)
	var entries: Array = candidate.get("water", [])
	entries.remove_at(index)
	candidate["water"] = entries
	return {"ok": true, "errors": [], "document": candidate}


# ---------------------------------------------------------------- 连接

# 在选中台地的同一条边缘上放楼梯/坡道。side 为空时按两格推断；
# 角落或单格谷地歧义时要求作者显式选方向。连接从台地边缘向低侧延伸，
# 低侧接合与阻挡由 LayoutTerrain 的完整校验负责。
static func add_connector(
	document: Dictionary,
	platform_index: int,
	kind: String,
	side: String,
	cell_a: Vector2i,
	cell_b: Vector2i
) -> Dictionary:
	var terraces: Array = document.get("terraces", [])
	if platform_index < 0 or platform_index >= terraces.size():
		return _fail("请先选中一个台地")
	if not TerrainData.CONNECTOR_KINDS.has(kind):
		return _fail("连接类型只能是楼梯或坡道")
	var entry: Dictionary = terraces[platform_index]
	var platform_rect := _entry_rect(entry)
	if platform_rect.size.x <= 0.0 or platform_rect.size.y <= 0.0:
		return _fail("台地矩形无效，无法放连接")
	var resolved := _resolve_side(platform_rect, side, cell_a, cell_b)
	if not bool(resolved.get("ok", false)):
		return _fail(str(resolved.get("reason", "无法确定连接方向")))
	var final_side := str(resolved.get("side", side))
	var open_a := Vector2i.ZERO
	var open_b := Vector2i.ZERO
	if final_side == "north" or final_side == "south":
		open_a = Vector2i(mini(cell_a.x, cell_b.x), 0)
		open_b = Vector2i(maxi(cell_a.x, cell_b.x) + 1, 0)
	else:
		open_a = Vector2i(0, mini(cell_a.y, cell_b.y))
		open_b = Vector2i(0, maxi(cell_a.y, cell_b.y) + 1)
	var depth := TerrainData.connector_depth(kind, float(entry.get("from_y", 0.0)), float(entry.get("y", 0.0)))
	if depth <= 0.0:
		return _fail("连接需要正的高差：顶部高度必须高于下层高度")
	var connector_rect := Rect2()
	if final_side == "north" or final_side == "south":
		connector_rect = TerrainData.connector_rect(
			platform_rect, final_side,
			float(open_a.x) * TILE_SIZE, float(open_b.x) * TILE_SIZE, depth
		)
	else:
		connector_rect = TerrainData.connector_rect(
			platform_rect, final_side,
			float(open_a.y) * TILE_SIZE, float(open_b.y) * TILE_SIZE, depth
		)
	if not _inside_map(document, connector_rect):
		return _fail("连接会伸出地图，请换一侧或降低高差")
	var candidate := document.duplicate(true)
	var entries: Array = candidate.get("terraces", [])
	var target: Dictionary = entries[platform_index]
	var stairs: Array = target.get("stairs", [])
	var stair := {"side": final_side, "kind": kind}
	if final_side == "north" or final_side == "south":
		stair["x0"] = float(open_a.x) * TILE_SIZE
		stair["x1"] = float(open_b.x) * TILE_SIZE
	else:
		stair["z0"] = float(open_a.y) * TILE_SIZE
		stair["z1"] = float(open_b.y) * TILE_SIZE
	stairs.append(stair)
	target["stairs"] = stairs
	entries[platform_index] = target
	candidate["terraces"] = entries
	return {
		"ok": true,
		"errors": [],
		"document": candidate,
		"stairs_index": stairs.size() - 1,
		"side": final_side,
	}


static func remove_connector(
	document: Dictionary, platform_index: int, stairs_index: int
) -> Dictionary:
	var terraces: Array = document.get("terraces", [])
	if platform_index < 0 or platform_index >= terraces.size():
		return _fail("请先选中一个台地")
	var entry: Dictionary = terraces[platform_index]
	var stairs: Array = entry.get("stairs", [])
	if stairs_index < 0 or stairs_index >= stairs.size():
		return _fail("请先选中一条连接")
	var candidate := document.duplicate(true)
	var entries: Array = candidate.get("terraces", [])
	var target: Dictionary = entries[platform_index]
	var remaining: Array = target.get("stairs", [])
	remaining.remove_at(stairs_index)
	target["stairs"] = remaining
	entries[platform_index] = target
	candidate["terraces"] = entries
	return {"ok": true, "errors": [], "document": candidate}


# ---------------------------------------------------------------- helpers

static func side_label(side: String) -> String:
	match side:
		"north":
			return "北"
		"south":
			return "南"
		"east":
			return "东"
		"west":
			return "西"
	return side


static func kind_label(kind: String) -> String:
	return "坡道" if kind == "ramp" else "楼梯"


# 给定台地两格，返回 {"ok", "side"} 或 {"ok": false, "reason"}。
static func _resolve_side(
	rect: Rect2, requested: String, cell_a: Vector2i, cell_b: Vector2i
) -> Dictionary:
	var x0 := int(round(rect.position.x / TILE_SIZE))
	var z0 := int(round(rect.position.y / TILE_SIZE))
	var x1 := int(round(rect.end.x / TILE_SIZE))
	var z1 := int(round(rect.end.y / TILE_SIZE))
	var span_x := mini(cell_a.x, cell_b.x) >= x0 and maxi(cell_a.x, cell_b.x) < x1
	var span_z := mini(cell_a.y, cell_b.y) >= z0 and maxi(cell_a.y, cell_b.y) < z1
	var candidates: Array[String] = []
	if cell_a.y == cell_b.y and cell_a.y == z1 - 1 and span_x:
		candidates.append("south")
	if cell_a.y == cell_b.y and cell_a.y == z0 and span_x:
		candidates.append("north")
	if cell_a.x == cell_b.x and cell_a.x == x1 - 1 and span_z:
		candidates.append("east")
	if cell_a.x == cell_b.x and cell_a.x == x0 and span_z:
		candidates.append("west")
	if not requested.is_empty():
		if candidates.has(requested):
			return {"ok": true, "side": requested}
		return {
			"ok": false,
			"reason": "两格不在台地的%s边缘上" % side_label(requested),
		}
	if candidates.size() == 1:
		return {"ok": true, "side": candidates[0]}
	if candidates.is_empty():
		return {"ok": false, "reason": "两格必须在台地同一条边缘上"}
	return {"ok": false, "reason": "该位置在台地角落，请先选择连接方向"}


static func _world_rect_array(cells: Rect2i) -> Array:
	return [
		float(cells.position.x) * TILE_SIZE,
		float(cells.position.y) * TILE_SIZE,
		float(cells.position.x + cells.size.x) * TILE_SIZE,
		float(cells.position.y + cells.size.y) * TILE_SIZE,
	]


static func _entry_rect(entry: Dictionary) -> Rect2:
	var value: Variant = entry.get("rect", null)
	if not (value is Array) or (value as Array).size() != 4:
		return Rect2()
	var coords: Array = value
	var x0 := float(coords[0])
	var z0 := float(coords[1])
	var x1 := float(coords[2])
	var z1 := float(coords[3])
	if x1 <= x0 or z1 <= z0:
		return Rect2()
	return Rect2(x0, z0, x1 - x0, z1 - z0)


static func _inside_map(document: Dictionary, rect: Rect2) -> bool:
	var width := int(document.get("width", 0))
	var depth := int(document.get("depth", 0))
	if width <= 0 or depth <= 0:
		return true
	return rect.position.x >= -TerrainData.EPSILON \
		and rect.position.y >= -TerrainData.EPSILON \
		and rect.end.x <= float(width) * TILE_SIZE + TerrainData.EPSILON \
		and rect.end.y <= float(depth) * TILE_SIZE + TerrainData.EPSILON


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "errors": [message], "document": {}}

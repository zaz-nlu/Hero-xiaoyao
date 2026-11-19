@tool
extends RefCounted

# 地图地形编译与查询。
#
# 公开 API：
#   LayoutTerrain.validate(document, catalog) -> Array[String]
#       由 LayoutDocument.validate_document 增量接入。
#   LayoutTerrain.compile(document) -> Dictionary
#       {platforms, connectors, water, walls, blockers: Array[Rect2], bounds}
#       platforms:   {index,name,rect,y,from_y,top}
#       connectors:  {index,platform,kind,side,rect,open0,open1,from_y,y,steps,depth,top}
#       water:       {index,name,rect,bottom,y}
#       walls:       {rect,top,bottom,kind,axis,side}
#   LayoutTerrain.height_at(compiled, point: Vector2) -> float
#       台地顶面、楼梯踏面、坡道斜面与平地高度；水面不参与站立高度。
#   LayoutTerrain.platform_height(compiled, point: Vector2) -> float
#       只看台地与平地的平坦支撑高度，用于涂装落位（不跟随楼梯/坡道）。
#
# 地形是同一 XZ 上的单一地表：台地不可面积重叠，连接从台地边缘向外伸。
# 阻挡墙在编译时沿台地/连接边段扫描并合并，运行和渲染共享同一批矩形；
# 运行时不需要逐格重建。

const Data = preload("res://core/layouts/layout_terrain_data.gd")
const Validation = preload("res://core/layouts/layout_terrain_validation.gd")

const SAMPLE_OFFSET := 0.1


static func validate(document: Variant, catalog: Dictionary) -> Array[String]:
	return Validation.validate(document, catalog)


static func compile(document: Dictionary) -> Dictionary:
	var platforms := Data.platforms(document)
	var connectors := Data.connectors(document, platforms)
	var water := Data.water_entries(document, platforms)
	var walls := _build_walls(document, platforms, connectors)
	var blockers: Array[Rect2] = []
	for wall_value in walls:
		var wall: Dictionary = wall_value as Dictionary
		var rect_value: Variant = wall["rect"]
		blockers.append(rect_value)
	for water_value in water:
		var entry: Dictionary = water_value as Dictionary
		var rect_value: Variant = entry["rect"]
		blockers.append(rect_value)
	return {
		"platforms": platforms,
		"connectors": connectors,
		"water": water,
		"walls": walls,
		"blockers": blockers,
		"bounds": Data.world_bounds(document),
	}


static func height_at(compiled: Dictionary, point: Vector2) -> float:
	var connectors_value: Variant = compiled.get("connectors", [])
	if connectors_value is Array:
		for connector_value in connectors_value:
			if not (connector_value is Dictionary):
				continue
			var height := Data.connector_height(connector_value as Dictionary, point)
			if is_finite(height):
				return height
	return platform_height(compiled, point)


static func platform_height(compiled: Dictionary, point: Vector2) -> float:
	var platforms_value: Variant = compiled.get("platforms", [])
	if platforms_value is Array:
		return Data.platform_height(platforms_value as Array, point)
	return 0.0


# ---------------------------------------------------------------- walls

static func _build_walls(
	document: Dictionary, platforms: Array, connectors: Array
) -> Array:
	var walls: Array = []
	var bounds := Data.world_bounds(document)
	for platform_value in platforms:
		if platform_value is Dictionary:
			_scan_platform(platform_value as Dictionary, platforms, connectors, bounds, walls)
	for connector_value in connectors:
		if connector_value is Dictionary:
			_add_connector_sides(connector_value as Dictionary, walls)
	return walls


static func _scan_platform(
	platform: Dictionary,
	platforms: Array,
	connectors: Array,
	bounds: Rect2,
	walls: Array
) -> void:
	var rect_value: Variant = platform["rect"]
	var rect: Rect2 = rect_value
	var has_bounds := bounds.size.x > 0.0 and bounds.size.y > 0.0
	if not has_bounds or rect.position.y > bounds.position.y + Data.EPSILON:
		_scan_edge(
			platform, "north", rect.position.x, rect.end.x, rect.position.y, -1.0,
			platforms, connectors, walls
		)
	if not has_bounds or rect.end.y < bounds.end.y - Data.EPSILON:
		_scan_edge(
			platform, "south", rect.position.x, rect.end.x, rect.end.y, 1.0,
			platforms, connectors, walls
		)
	if not has_bounds or rect.position.x > bounds.position.x + Data.EPSILON:
		_scan_edge(
			platform, "west", rect.position.y, rect.end.y, rect.position.x, -1.0,
			platforms, connectors, walls
		)
	if not has_bounds or rect.end.x < bounds.end.x - Data.EPSILON:
		_scan_edge(
			platform, "east", rect.position.y, rect.end.y, rect.end.x, 1.0,
			platforms, connectors, walls
		)


static func _scan_edge(
	platform: Dictionary,
	side: String,
	start: float,
	end: float,
	fixed: float,
	outward: float,
	platforms: Array,
	connectors: Array,
	walls: Array
) -> void:
	var top := float(platform["y"])
	var cursor := start
	var run_start := 0.0
	var run_end := 0.0
	var run_bottom := INF
	var has_run := false
	while cursor < end - Data.EPSILON:
		var segment_end := minf(cursor + Data.TILE_SIZE, end)
		var middle := (cursor + segment_end) * 0.5
		var sample := Vector2.ZERO
		if side == "north" or side == "south":
			sample = Vector2(middle, fixed + outward * SAMPLE_OFFSET)
		else:
			sample = Vector2(fixed + outward * SAMPLE_OFFSET, middle)
		var outside := _surface_height(platforms, connectors, sample)
		# 开口（本台地、本侧）直接视作连通：坡道在采样点略低于顶面，
		# 不能因此把坡顶封成墙。
		var open := _edge_is_open(platform, side, middle, connectors)
		if not open and outside + Data.EPSILON < top:
			if not has_run:
				run_start = cursor
				run_bottom = outside
				has_run = true
			run_end = segment_end
			run_bottom = minf(run_bottom, outside)
		elif has_run:
			_append_wall(walls, side, run_start, run_end, fixed, top, run_bottom)
			has_run = false
		cursor = segment_end
	if has_run:
		_append_wall(walls, side, run_start, run_end, fixed, top, run_bottom)


# 当前台地、当前侧是否有连接，且 middle 落在该连接的开口范围内。
static func _edge_is_open(
	platform: Dictionary, side: String, middle: float, connectors: Array
) -> bool:
	var index := int(platform.get("index", -1))
	for connector_value in connectors:
		if not (connector_value is Dictionary):
			continue
		var connector: Dictionary = connector_value
		if int(connector.get("platform", -1)) != index:
			continue
		if str(connector.get("side", "")) != side:
			continue
		var open0 := float(connector.get("open0", 0.0))
		var open1 := float(connector.get("open1", 0.0))
		if middle >= open0 - Data.EPSILON and middle <= open1 + Data.EPSILON:
			return true
	return false


static func _surface_height(
	platforms: Array, connectors: Array, point: Vector2
) -> float:
	var height := Data.platform_height(platforms, point)
	for connector_value in connectors:
		if not (connector_value is Dictionary):
			continue
		var connector_height := Data.connector_height(connector_value as Dictionary, point)
		if is_finite(connector_height):
			height = maxf(height, connector_height)
	return height


static func _append_wall(
	walls: Array,
	side: String,
	start: float,
	end: float,
	fixed: float,
	top: float,
	bottom: float
) -> void:
	if end - start <= Data.EPSILON:
		return
	var thickness := Data.WALL_THICKNESS
	var rect := Rect2()
	var axis := "x"
	if side == "north" or side == "south":
		rect = Rect2(start, fixed - thickness * 0.5, end - start, thickness)
	else:
		rect = Rect2(fixed - thickness * 0.5, start, thickness, end - start)
		axis = "z"
	walls.append({
		"rect": rect,
		"top": top,
		"bottom": bottom,
		"kind": "terrace",
		"axis": axis,
		"side": side,
	})


static func _add_connector_sides(connector: Dictionary, walls: Array) -> void:
	var rect_value: Variant = connector["rect"]
	var rect: Rect2 = rect_value
	var top := float(connector["y"])
	var bottom := float(connector["from_y"])
	var side := str(connector["side"])
	if side == "north" or side == "south":
		# 南北向连接：两侧墙 x 固定、沿 z 延伸。
		_add_connector_side(
			walls, rect.position.x, rect.position.y, rect.size.y, "z", top, bottom
		)
		_add_connector_side(
			walls, rect.end.x, rect.position.y, rect.size.y, "z", top, bottom
		)
	else:
		# 东西向连接：两侧墙 z 固定、沿 x 延伸。
		_add_connector_side(
			walls, rect.position.y, rect.position.x, rect.size.x, "x", top, bottom
		)
		_add_connector_side(
			walls, rect.end.y, rect.position.x, rect.size.x, "x", top, bottom
		)


# fixed 是墙所在的 x（axis=z）或 z（axis=x）；start/length 沿墙延伸方向。
static func _add_connector_side(
	walls: Array,
	fixed: float,
	start: float,
	length: float,
	axis: String,
	top: float,
	bottom: float
) -> void:
	if length <= Data.EPSILON:
		return
	var thickness := Data.CONNECTOR_WALL_THICKNESS
	var rect := Rect2()
	if axis == "z":
		rect = Rect2(fixed - thickness * 0.5, start, thickness, length)
	else:
		rect = Rect2(start, fixed - thickness * 0.5, length, thickness)
	walls.append({
		"rect": rect,
		"top": top,
		"bottom": bottom,
		"kind": "connector",
		"axis": axis,
		"side": "",
	})

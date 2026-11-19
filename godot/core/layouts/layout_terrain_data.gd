@tool
extends RefCounted

# 地图地形数据：台地、连接（楼梯/坡道）与水面的规范化读取。
# 纯静态、无副作用，供运行编译（layout_terrain.gd）、校验
# （layout_terrain_validation.gd）和场景搭建（layout_terrain_mesh.gd）共用。
#
# 数据约定（layout version=1，全部字段可选，旧地图按 0 高度平地读取）：
#   terraces: [{name?, rect:[x0,z0,x1,z1], y, from_y?, top?, stairs?}]
#     rect 为世界单位，两角对齐 2 单位格边；不可面积重叠，可共享边。
#     y > from_y >= 0，0.5 单位增量，y <= 24。
#     top 缺省为 document.ground。
#   stairs:   [{x0,x1 | z0,z1, side?, kind?, name?}]  side 缺省 south，
#     kind 缺省 stairs。南北开口用 x0/x1，东西开口用 z0/z1。
#     楼梯每阶升 0.5、进深 1；坡道进深 ceil(高差 * 3)。
#   water:    [{name?, rect:[x0,z0,x1,z1], y?}]  矩形对齐格边，
#     底面必须连续同高；缺省水位为底面 + 0.05。

const LayoutGrid := preload("res://core/layouts/layout_grid.gd")

const TILE_SIZE := 2.0
const STEP_HEIGHT := 0.5
const STEP_DEPTH := 1.0
const WALL_THICKNESS := 0.4
const CONNECTOR_WALL_THICKNESS := 0.2
const MAX_HEIGHT := 24.0
const RAMP_RUN_PER_HEIGHT := 3.0
const WATER_LIFT := 0.05
const EPSILON := 0.001

const SIDES: Array[String] = ["north", "south", "east", "west"]
const CONNECTOR_KINDS: Array[String] = ["stairs", "ramp"]


static func platforms(document: Dictionary) -> Array:
	var result: Array = []
	var raw_value: Variant = document.get("terraces", [])
	if not (raw_value is Array):
		return result
	var raw: Array = raw_value
	for i in range(raw.size()):
		var entry_value: Variant = raw[i]
		if not (entry_value is Dictionary):
			continue
		var entry: Dictionary = entry_value
		var rect_value: Variant = entry.get("rect", null)
		if not (rect_value is Array) or (rect_value as Array).size() != 4:
			continue
		var coords: Array = rect_value
		if not _all_numbers(coords):
			continue
		var x0 := float(coords[0])
		var z0 := float(coords[1])
		var x1 := float(coords[2])
		var z1 := float(coords[3])
		if x1 <= x0 or z1 <= z0:
			continue
		var y_value: Variant = entry.get("y", null)
		if not _is_number(y_value):
			continue
		var from_y := 0.0
		var from_value: Variant = entry.get("from_y", null)
		if _is_number(from_value):
			from_y = float(from_value)
		result.append({
			"index": i,
			"name": str(entry.get("name", "")),
			"rect": Rect2(x0, z0, x1 - x0, z1 - z0),
			"y": float(y_value),
			"from_y": from_y,
			"top": str(entry.get("top", document.get("ground", ""))),
			"stairs_raw": entry.get("stairs", []),
		})
	return result


# 把台地上的 stairs 项展开为绝对世界矩形。非法项跳过；校验在
# layout_terrain_validation.gd 里给出具体原因。
static func connectors(document: Dictionary, platform_list: Array) -> Array:
	var result: Array = []
	for platform_value in platform_list:
		if not (platform_value is Dictionary):
			continue
		var platform: Dictionary = platform_value
		var raw_value: Variant = platform.get("stairs_raw", [])
		if not (raw_value is Array):
			continue
		var raw: Array = raw_value
		for j in range(raw.size()):
			var entry_value: Variant = raw[j]
			if not (entry_value is Dictionary):
				continue
			var entry: Dictionary = entry_value
			var side := str(entry.get("side", "south"))
			if not SIDES.has(side):
				continue
			var kind := str(entry.get("kind", "stairs"))
			if not CONNECTOR_KINDS.has(kind):
				continue
			var bounds := opening_bounds(entry, side)
			if bounds.size() != 2:
				continue
			var open0 := float(bounds[0])
			var open1 := float(bounds[1])
			if open1 <= open0:
				continue
			var from_y := float(platform["from_y"])
			var y := float(platform["y"])
			var depth := connector_depth(kind, from_y, y)
			if depth <= 0.0:
				continue
			var rect_value: Variant = platform["rect"]
			var platform_rect: Rect2 = rect_value
			result.append({
				"index": result.size(),
				"platform": int(platform["index"]),
				"stairs_index": j,
				"name": str(entry.get("name", "")),
				"kind": kind,
				"side": side,
				"rect": connector_rect(platform_rect, side, open0, open1, depth),
				"open0": open0,
				"open1": open1,
				"from_y": from_y,
				"y": y,
				"steps": stairs_steps(from_y, y),
				"depth": depth,
				"top": str(platform.get("top", document.get("ground", ""))),
			})
	return result


static func water_entries(document: Dictionary, platform_list: Array) -> Array:
	var result: Array = []
	var raw_value: Variant = document.get("water", [])
	if not (raw_value is Array):
		return result
	var raw: Array = raw_value
	for i in range(raw.size()):
		var entry_value: Variant = raw[i]
		if not (entry_value is Dictionary):
			continue
		var entry: Dictionary = entry_value
		var rect_value: Variant = entry.get("rect", null)
		if not (rect_value is Array) or (rect_value as Array).size() != 4:
			continue
		var coords: Array = rect_value
		if not _all_numbers(coords):
			continue
		var x0 := float(coords[0])
		var z0 := float(coords[1])
		var x1 := float(coords[2])
		var z1 := float(coords[3])
		if x1 <= x0 or z1 <= z0:
			continue
		var rect := Rect2(x0, z0, x1 - x0, z1 - z0)
		var bottom := platform_height(platform_list, rect.get_center())
		var level := bottom + WATER_LIFT
		var y_value: Variant = entry.get("y", null)
		if _is_number(y_value):
			level = float(y_value)
		result.append({
			"index": i,
			"name": str(entry.get("name", "")),
			"rect": rect,
			"bottom": bottom,
			"y": level,
		})
	return result


# 南北开口返回 [x0, x1]，东西开口返回 [z0, z1]；非法时返回空数组。
static func opening_bounds(entry: Dictionary, side: String) -> Array:
	var keys := ["x0", "x1"] if side == "north" or side == "south" else ["z0", "z1"]
	var first: Variant = entry.get(keys[0], null)
	var second: Variant = entry.get(keys[1], null)
	if not _is_number(first) or not _is_number(second):
		return []
	return [float(first), float(second)]


static func stairs_steps(from_y: float, y: float) -> int:
	return int(round((y - from_y) / STEP_HEIGHT))


static func connector_depth(kind: String, from_y: float, y: float) -> float:
	var rise := y - from_y
	if rise <= 0.0:
		return 0.0
	if kind == "ramp":
		return maxf(1.0, ceilf(rise * RAMP_RUN_PER_HEIGHT))
	return float(maxi(1, stairs_steps(from_y, y))) * STEP_DEPTH


static func connector_rect(
	platform_rect: Rect2, side: String, open0: float, open1: float, depth: float
) -> Rect2:
	match side:
		"north":
			return Rect2(
				open0, platform_rect.position.y - depth, open1 - open0, depth
			)
		"west":
			return Rect2(
				platform_rect.position.x - depth, open0, depth, open1 - open0
			)
		"east":
			return Rect2(
				platform_rect.end.x, open0, depth, open1 - open0
			)
		_:
			return Rect2(
				open0, platform_rect.end.y, open1 - open0, depth
			)


static func connector_height(connector: Dictionary, point: Vector2) -> float:
	var rect_value: Variant = connector.get("rect", null)
	if not (rect_value is Rect2):
		return -INF
	var rect: Rect2 = rect_value
	if not rect_contains(rect, point):
		return -INF
	var side := str(connector.get("side", "south"))
	var depth := float(connector.get("depth", 0.0))
	if depth <= 0.0:
		return -INF
	var distance := 0.0
	match side:
		"north":
			distance = rect.end.y - point.y
		"east":
			distance = point.x - rect.position.x
		"west":
			distance = rect.end.x - point.x
		_:
			distance = point.y - rect.position.y
	distance = clampf(distance, 0.0, depth)
	var from_y := float(connector.get("from_y", 0.0))
	var y := float(connector.get("y", 0.0))
	if str(connector.get("kind", "stairs")) == "ramp":
		return y - (y - from_y) * (distance / depth)
	if distance >= depth - EPSILON:
		return from_y
	var steps := maxi(1, int(connector.get("steps", 1)))
	# 与小镇一致：踏面边界同时属于上下两级时取较高的一级。
	var band := int(floor(distance / STEP_DEPTH))
	if band > 0 and absf(distance - roundf(distance)) <= EPSILON:
		band -= 1
	var step_index := clampi(steps - band, 1, steps)
	return from_y + STEP_HEIGHT * float(step_index)


static func platform_height(platform_list: Array, point: Vector2) -> float:
	var height := 0.0
	var found := false
	for platform_value in platform_list:
		if not (platform_value is Dictionary):
			continue
		var platform: Dictionary = platform_value
		var rect_value: Variant = platform.get("rect", null)
		if not (rect_value is Rect2):
			continue
		if not rect_contains(rect_value, point):
			continue
		var value := float(platform.get("y", 0.0))
		if not found or value > height:
			height = value
			found = true
	return height


static func world_bounds(document: Dictionary) -> Rect2:
	return LayoutGrid.world_bounds(document)


static func item_footprint_world(
	items: Dictionary, asset: String, x: int, z: int, turn: int
) -> Rect2:
	return LayoutGrid.item_footprint_world(items, asset, x, z, turn)


static func footprint_cells(
	items: Dictionary, asset: String, x: int, z: int, turn: int
) -> Rect2i:
	return LayoutGrid.item_footprint_cells(items, asset, x, z, turn)


static func rect_contains(rect: Rect2, point: Vector2) -> bool:
	return point.x >= rect.position.x - EPSILON \
		and point.x <= rect.end.x + EPSILON \
		and point.y >= rect.position.y - EPSILON \
		and point.y <= rect.end.y + EPSILON


static func rect_overlap(a: Rect2, b: Rect2) -> bool:
	var overlap := a.intersection(b)
	return overlap.size.x > EPSILON and overlap.size.y > EPSILON


static func is_grid_aligned(value: float) -> bool:
	return absf(value / TILE_SIZE - roundf(value / TILE_SIZE)) <= 0.0001


static func is_half_step(value: float) -> bool:
	return absf(value * 2.0 - roundf(value * 2.0)) <= 0.0001


static func is_number(value: Variant) -> bool:
	return _is_number(value)


static func is_int(value: Variant) -> bool:
	return _is_int(value)


static func _all_numbers(values: Array) -> bool:
	for value in values:
		if not _is_number(value):
			return false
	return true


static func _is_number(value: Variant) -> bool:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return is_finite(float(value))
	return false


static func _is_int(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) == TYPE_FLOAT:
		var number: float = value
		return is_finite(number) and is_equal_approx(number, roundf(number))
	return false

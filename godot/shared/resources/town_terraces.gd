extends RefCounted

# 小镇多级梯田/台地数据：读取规整、高度查询与挡墙碰撞矩形。
# 纯静态，不依赖场景类型；数据读取（town_data）与场景搭建（town_ground）共用。

const WALL_THICKNESS := 0.4
const STEP_HEIGHT := 0.5
const STEP_DEPTH := 1.0


static func list(data: Dictionary) -> Array:
	var result: Array = []
	var raw_value: Variant = data.get("terraces", [])
	if typeof(raw_value) != TYPE_ARRAY:
		return result
	var raw: Array = raw_value
	for value in raw:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = value
		var rect_value: Variant = entry.get("rect", [])
		if typeof(rect_value) != TYPE_ARRAY:
			continue
		var rect: Array = rect_value
		if rect.size() < 4:
			continue
		if not _is_number(rect[0]) or not _is_number(rect[1]) \
				or not _is_number(rect[2]) or not _is_number(rect[3]):
			continue
		if not _is_number(entry.get("y", null)):
			continue
		var from_y := 0.0
		if _is_number(entry.get("from_y", null)):
			from_y = float(entry["from_y"])
		result.append({
			"rect": [float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3])],
			"y": float(entry["y"]),
			"top": str(entry.get("top", "flagstone")),
			"from_y": from_y,
			"stairs": _stairs(entry.get("stairs", [])),
		})
	return result


static func height_at(data: Dictionary, x: float, z: float) -> float:
	var best := -1.0
	for terrace_value in list(data):
		var terrace: Dictionary = terrace_value
		var rect: Array = terrace["rect"]
		var x0 := float(rect[0])
		var z0 := float(rect[1])
		var x1 := float(rect[2])
		var z1 := float(rect[3])
		var terrace_height := -1.0
		if x >= x0 and x <= x1 and z >= z0 and z <= z1:
			terrace_height = float(terrace["y"])
		var step_height := _stairs_height(terrace, x, z)
		if step_height >= 0.0:
			terrace_height = maxf(terrace_height, step_height)
		best = maxf(best, terrace_height)
	return best


static func blockers(data: Dictionary) -> Array:
	var result: Array = []
	var bounds: Rect2 = bounds_rect(data)
	for terrace_value in list(data):
		var terrace: Dictionary = terrace_value
		var rect: Array = terrace["rect"]
		var x0 := float(rect[0])
		var z0 := float(rect[1])
		var x1 := float(rect[2])
		var z1 := float(rect[3])
		# 南缘挡墙：在台阶缺口处断开。
		var cursor := x0
		for gap_value in _stair_gaps(terrace, x0, x1):
			var gap: Array = gap_value
			_append_wall(result, cursor, float(gap[0]), z1)
			cursor = maxf(cursor, float(gap[1]))
		_append_wall(result, cursor, x1, z1)
		# 西/东侧墙：贴着地图边界的省略。
		if bounds.size == Vector2.ZERO or x0 > bounds.position.x + 0.001:
			result.append(
				Rect2(x0 - WALL_THICKNESS * 0.5, z0, WALL_THICKNESS, z1 - z0)
			)
		if bounds.size == Vector2.ZERO or x1 < bounds.end.x - 0.001:
			result.append(
				Rect2(x1 - WALL_THICKNESS * 0.5, z0, WALL_THICKNESS, z1 - z0)
			)
	return result


static func bounds_rect(data: Dictionary) -> Rect2:
	var bounds_value: Variant = data.get("bounds", null)
	if typeof(bounds_value) != TYPE_DICTIONARY:
		return Rect2()
	var bounds: Dictionary = bounds_value
	if not _is_number(bounds.get("x0", null)) or not _is_number(bounds.get("x1", null)) \
			or not _is_number(bounds.get("z0", null)) or not _is_number(bounds.get("z1", null)):
		return Rect2()
	var x0 := float(bounds["x0"])
	var x1 := float(bounds["x1"])
	var z0 := float(bounds["z0"])
	var z1 := float(bounds["z1"])
	return Rect2(x0, z0, x1 - x0, z1 - z0)


static func _stairs(value: Variant) -> Array:
	var result: Array = []
	if typeof(value) != TYPE_ARRAY:
		return result
	var raw: Array = value
	for item in raw:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = item
		if not _is_number(entry.get("x0", null)) or not _is_number(entry.get("x1", null)):
			continue
		var x0 := float(entry["x0"])
		var x1 := float(entry["x1"])
		if x1 <= x0:
			continue
		result.append({"x0": x0, "x1": x1})
	return result


static func _stair_gaps(terrace: Dictionary, x0: float, x1: float) -> Array:
	var gaps: Array = []
	for stairs_value in terrace["stairs"]:
		var stairs: Dictionary = stairs_value
		var gap_x0 := maxf(float(stairs["x0"]), x0)
		var gap_x1 := minf(float(stairs["x1"]), x1)
		if gap_x1 > gap_x0:
			gaps.append([gap_x0, gap_x1])
	gaps.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	return gaps


static func _stairs_height(terrace: Dictionary, x: float, z: float) -> float:
	var rect: Array = terrace["rect"]
	var z1 := float(rect[3])
	var from_y := float(terrace["from_y"])
	var steps := int(round((float(terrace["y"]) - from_y) / STEP_HEIGHT))
	if steps <= 0:
		return -1.0
	var best := -1.0
	for stairs_value in terrace["stairs"]:
		var stairs: Dictionary = stairs_value
		var x0 := float(stairs["x0"])
		var x1 := float(stairs["x1"])
		if x < x0 or x > x1:
			continue
		for k in range(1, steps + 1):
			var z_low := z1 + float(steps - k)
			if z >= z_low and z <= z_low + STEP_DEPTH:
				best = maxf(best, from_y + STEP_HEIGHT * float(k))
	return best


static func _append_wall(result: Array, x_start: float, x_end: float, z1: float) -> void:
	if x_end - x_start <= 0.001:
		return
	result.append(
		Rect2(x_start, z1 - WALL_THICKNESS * 0.5, x_end - x_start, WALL_THICKNESS)
	)


static func _is_number(value: Variant) -> bool:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return true
	return false

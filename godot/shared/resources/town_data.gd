extends RefCounted

const AssetPaths = preload("res://shared/resources/asset_paths.gd")
const TownTerraces = preload("res://shared/resources/town_terraces.gd")

const DEFAULT_FOREST_SIGN := Vector2(5.4, 20.7)
const DEFAULT_FOREST_RETURN := Vector2(0.0, 19.2)

const BUILDING_KINDS: Array[String] = ["house", "smith", "shop", "tavern"]
const PROP_KINDS: Array[String] = [
	"barrel", "crate", "bench", "lamp_post", "banner", "cart", "stall", "tree",
	"jars", "baskets", "stone_lantern", "boat", "well", "notice_board",
	"shrub", "grass_tuft", "peony", "chrysanthemum", "bamboo", "rocks", "sprite"
]


static func load_town(path: String) -> Dictionary:
	var errors: Array[String] = []
	var result: Dictionary = {"data": {}, "errors": errors}
	if not FileAccess.file_exists(path):
		errors.append("town file not found: %s" % path)
		return result
	var text: String = FileAccess.get_file_as_string(path)
	var parser := JSON.new()
	var err: Error = parser.parse(text)
	if err != OK:
		errors.append("invalid JSON: %s" % parser.get_error_message())
		return result
	var value: Variant = parser.data
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("town JSON root is not an object")
		return result
	var data: Dictionary = value
	result["data"] = data
	result["errors"] = validate(data)
	return result


static func validate(data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var bounds: Rect2 = _bounds(data)
	if bounds.size == Vector2.ZERO:
		errors.append("bounds are missing or invalid")
		return errors

	var building_footprints: Array[Rect2] = []
	var buildings: Array = data.get("buildings", [])
	for i in range(buildings.size()):
		var building_value: Variant = buildings[i]
		if typeof(building_value) != TYPE_DICTIONARY:
			errors.append("building %d is not an object" % i)
			continue
		var building: Dictionary = building_value
		var id := str(building.get("id", "building_%d" % i))
		var kind := str(building.get("kind", ""))
		if not BUILDING_KINDS.has(kind):
			errors.append("building %s has unknown kind '%s'" % [id, kind])
		if not _has_numbers(building, ["x0", "x1", "z_front", "depth"]):
			errors.append("building %s is missing dimensions" % id)
			continue
		var facade_value: Variant = building.get("facade", null)
		if facade_value != null \
				and (typeof(facade_value) != TYPE_STRING or str(facade_value) == ""):
			errors.append("building %s has an invalid facade" % id)
		var plaque_value: Variant = building.get("plaque", null)
		if plaque_value != null:
			if typeof(plaque_value) != TYPE_ARRAY:
				errors.append("building %s has an invalid plaque" % id)
			else:
				var plaque: Array = plaque_value
				if plaque.size() < 2 or not _is_number(plaque[0]) \
						or not _is_number(plaque[1]):
					errors.append("building %s has an invalid plaque" % id)
		var plaque_w_value: Variant = building.get("plaque_w", null)
		if plaque_w_value != null \
				and (not _is_number(plaque_w_value) or float(plaque_w_value) <= 0.0):
			errors.append("building %s has an invalid plaque_w" % id)
		var footprint: Rect2 = _building_footprint(building)
		if not _bounds_contains(bounds, footprint):
			errors.append("building %s footprint is outside bounds" % id)
		for other_i in range(building_footprints.size()):
			if building_footprints[other_i].intersects(footprint):
				errors.append("building %s overlaps building %d" % [id, other_i])
		building_footprints.append(footprint)

	var props: Array = data.get("props", [])
	for i in range(props.size()):
		var prop_value: Variant = props[i]
		if typeof(prop_value) != TYPE_DICTIONARY:
			errors.append("prop %d is not an object" % i)
			continue
		var prop: Dictionary = prop_value
		var kind := str(prop.get("kind", ""))
		if not PROP_KINDS.has(kind):
			errors.append("prop %d has unknown kind '%s'" % [i, kind])

	var spawn_value: Variant = data.get("spawn", null)
	if typeof(spawn_value) == TYPE_DICTIONARY:
		var spawn: Dictionary = spawn_value
		if _has_numbers(spawn, ["x", "z"]):
			var spawn_pos := Vector2(float(spawn["x"]), float(spawn["z"]))
			if not _bounds_has_point(bounds, spawn_pos):
				errors.append("spawn is outside bounds")
			for rect in building_footprints:
				if rect.has_point(spawn_pos):
					errors.append("spawn is inside a building")
					break

	var npcs: Array = data.get("npcs", [])
	var blocker_rects: Array = footprints(data)
	for i in range(npcs.size()):
		var npc_value: Variant = npcs[i]
		if typeof(npc_value) != TYPE_DICTIONARY:
			errors.append("npc %d is not an object" % i)
			continue
		var npc: Dictionary = npc_value
		var id := str(npc.get("id", "npc_%d" % i))
		var sprite := str(npc.get("sprite", ""))
		var sprite_path := AssetPaths.sprite_path(sprite)
		if sprite == "" or not FileAccess.file_exists(sprite_path):
			errors.append("npc %s has missing sprite '%s'" % [id, sprite])
		if _has_numbers(npc, ["x", "z"]):
			var npc_pos := Vector2(float(npc["x"]), float(npc["z"]))
			if not _bounds_has_point(bounds, npc_pos):
				errors.append("npc %s is outside bounds" % id)
			if _point_in_rects(npc_pos, blocker_rects):
				errors.append("npc %s is inside a blocker" % id)
		var wander_value: Variant = npc.get("wander", null)
		if typeof(wander_value) == TYPE_DICTIONARY:
			var wander: Dictionary = wander_value
			var route_value: Variant = wander.get("route", [])
			if typeof(route_value) == TYPE_ARRAY:
				var route: Array = route_value
				for point_index in range(route.size()):
					var point_value: Variant = route[point_index]
					if typeof(point_value) != TYPE_ARRAY:
						errors.append(
							"npc %s wander point %d is not an array" % [id, point_index]
						)
						continue
					var point: Array = point_value
					if point.size() < 2 or not _is_number(point[0]) \
							or not _is_number(point[1]):
						errors.append("npc %s wander point %d is invalid" % [id, point_index])
						continue
					var route_pos := Vector2(float(point[0]), float(point[1]))
					if not _bounds_has_point(bounds, route_pos):
						errors.append(
							"npc %s wander point %d is outside bounds" % [id, point_index]
						)
					if _point_in_rects(route_pos, blocker_rects):
						errors.append(
							"npc %s wander point %d is inside a blocker" % [id, point_index]
						)

	return errors


static func footprints(data: Dictionary) -> Array:
	var result: Array = []
	var buildings: Array = data.get("buildings", [])
	for building_value in buildings:
		if typeof(building_value) != TYPE_DICTIONARY:
			continue
		var building: Dictionary = building_value
		if not _has_numbers(building, ["x0", "x1", "z_front", "depth"]):
			continue
		result.append(_building_footprint(building))

	var props: Array = data.get("props", [])
	for prop_value in props:
		if typeof(prop_value) != TYPE_DICTIONARY:
			continue
		var prop: Dictionary = prop_value
		if not _has_numbers(prop, ["x", "z"]):
			continue
		var kind := str(prop.get("kind", ""))
		var x := float(prop["x"])
		var z := float(prop["z"])
		var collide_value: Variant = prop.get("collide", null)
		if typeof(collide_value) == TYPE_ARRAY:
			var collide: Array = collide_value
			if collide.size() >= 2 and _is_number(collide[0]) and _is_number(collide[1]):
				var collide_w := float(collide[0])
				var collide_d := float(collide[1])
				result.append(
					Rect2(x - collide_w * 0.5, z - collide_d * 0.5, collide_w, collide_d)
				)
				continue
		match kind:
			"barrel", "crate":
				result.append(Rect2(x - 0.5, z - 0.5, 1.0, 1.0))
			"bench":
				result.append(Rect2(x - 1.0, z - 0.4, 2.0, 0.8))
			"cart":
				result.append(Rect2(x - 1.2, z - 0.7, 2.4, 1.4))
			"stall":
				var w := float(prop.get("w", 4.0))
				var d := float(prop.get("d", 2.0))
				result.append(Rect2(x - w * 0.5, z - d * 0.5, w, d))
			"well":
				result.append(Rect2(x - 0.7, z - 0.7, 1.4, 1.4))
			"notice_board":
				result.append(Rect2(x - 0.8, z - 0.2, 1.6, 0.4))

	var bridges: Array = data.get("bridges", [])
	var ground: Array = data.get("ground", [])
	for ground_value in ground:
		if typeof(ground_value) != TYPE_DICTIONARY:
			continue
		var ground_entry: Dictionary = ground_value
		if str(ground_entry.get("type", "")) != "water":
			continue
		var rect_value: Variant = ground_entry.get("rect", [])
		if typeof(rect_value) != TYPE_ARRAY:
			continue
		var rect: Array = rect_value
		if rect.size() < 4:
			continue
		var wx0 := float(rect[0])
		var wz0 := float(rect[1])
		var wx1 := float(rect[2])
		var wz1 := float(rect[3])
		# Cut the water into the stretches between the bridges (any number of bridges).
		var gaps: Array = []
		for bridge_value in bridges:
			if typeof(bridge_value) != TYPE_DICTIONARY:
				continue
			var bridge: Dictionary = bridge_value
			if not _has_numbers(bridge, ["x0", "x1"]):
				continue
			var bx0 := float(bridge["x0"])
			var bx1 := float(bridge["x1"])
			if bx1 <= wx0 or bx0 >= wx1:
				continue
			gaps.append([maxf(bx0, wx0), minf(bx1, wx1)])
		gaps.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		var cursor := wx0
		for gap in gaps:
			var gap_arr: Array = gap
			if float(gap_arr[0]) > cursor:
				result.append(Rect2(cursor, wz0, float(gap_arr[0]) - cursor, wz1 - wz0))
			cursor = maxf(cursor, float(gap_arr[1]))
		if cursor < wx1:
			result.append(Rect2(cursor, wz0, wx1 - cursor, wz1 - wz0))

	var platform_value: Variant = data.get("platform", null)
	if typeof(platform_value) == TYPE_DICTIONARY:
		var platform: Dictionary = platform_value
		var p_rect_value: Variant = platform.get("rect", [])
		if typeof(p_rect_value) == TYPE_ARRAY:
			var p_rect: Array = p_rect_value
			if p_rect.size() >= 4:
				result.append(
					Rect2(
						float(p_rect[0]),
						float(p_rect[1]),
						float(p_rect[2]) - float(p_rect[0]),
						float(p_rect[3]) - float(p_rect[1])
					)
				)

	return result


static func _building_footprint(building: Dictionary) -> Rect2:
	var x0 := float(building["x0"])
	var x1 := float(building["x1"])
	var z_front := float(building["z_front"])
	var depth := float(building["depth"])
	return Rect2(x0, z_front - depth, x1 - x0, depth)


static func _bounds(data: Dictionary) -> Rect2:
	var bounds_value: Variant = data.get("bounds", null)
	if typeof(bounds_value) != TYPE_DICTIONARY:
		return Rect2()
	var bounds: Dictionary = bounds_value
	if not _has_numbers(bounds, ["x0", "x1", "z0", "z1"]):
		return Rect2()
	var x0 := float(bounds["x0"])
	var x1 := float(bounds["x1"])
	var z0 := float(bounds["z0"])
	var z1 := float(bounds["z1"])
	return Rect2(x0, z0, x1 - x0, z1 - z0)


static func _bounds_contains(bounds: Rect2, rect: Rect2) -> bool:
	var eps := 0.001
	return rect.position.x >= bounds.position.x - eps \
		and rect.position.y >= bounds.position.y - eps \
		and rect.end.x <= bounds.end.x + eps \
		and rect.end.y <= bounds.end.y + eps


static func _bounds_has_point(bounds: Rect2, point: Vector2) -> bool:
	return point.x >= bounds.position.x and point.x <= bounds.end.x \
		and point.y >= bounds.position.y and point.y <= bounds.end.y


static func ground_height(data: Dictionary, x: float, z: float) -> float:
	var height := _base_ground_height(data, x, z)
	var terrace_height: float = TownTerraces.height_at(data, x, z)
	if terrace_height >= 0.0:
		height = maxf(height, terrace_height)
	return height


# 紫霞林入口路牌的位置：顶层 "forest": {"sign": [x, z]}，缺省保持旧常量。
static func forest_sign(data: Dictionary) -> Vector2:
	return _read_point(data, "forest", "sign", DEFAULT_FOREST_SIGN)


# 紫霞林出口判定区：顶层 "forest": {"exit_rect": [x, z, w, h]}，缺省保持旧常量。
static func forest_exit_rect(data: Dictionary) -> Rect2:
	var forest_value: Variant = data.get("forest", null)
	if typeof(forest_value) == TYPE_DICTIONARY:
		var r_value: Variant = forest_value.get("exit_rect", null)
		if typeof(r_value) == TYPE_ARRAY and r_value.size() >= 4:
			return Rect2(float(r_value[0]), float(r_value[1]), float(r_value[2]), float(r_value[3]))
	return Rect2(-4.0, 20.0, 8.0, 1.8)


# 相机跟随的夹取范围：顶层 "camera_clamp": [x0, z0, x1, z1]，缺省不夹取。
static func camera_clamp(data: Dictionary) -> Rect2:
	var value: Variant = data.get("camera_clamp", null)
	if typeof(value) != TYPE_ARRAY:
		return Rect2()
	var rect: Array = value
	if rect.size() < 4:
		return Rect2()
	for item in [rect[0], rect[1], rect[2], rect[3]]:
		if not _is_number(item):
			return Rect2()
	var x0 := float(rect[0])
	var z0 := float(rect[1])
	var x1 := float(rect[2])
	var z1 := float(rect[3])
	if x1 <= x0 or z1 <= z0:
		return Rect2()
	return Rect2(x0, z0, x1 - x0, z1 - z0)


# 从紫霞林回到小镇时的落点：顶层 "forest": {"return": [x, z]}，缺省保持旧常量。
static func forest_return(data: Dictionary) -> Vector2:
	return _read_point(data, "forest", "return", DEFAULT_FOREST_RETURN)


# 返回当前位置满足条件的地点 id。每项支持 x_lt / x_gt / z_lt / z_gt，
# 给出的条件必须全部满足；没有 "unlock_zones" 时沿用旧的写死规则。
static func unlocked_zones(data: Dictionary, pos: Vector2) -> Array:
	var zones_value: Variant = data.get("unlock_zones", null)
	if typeof(zones_value) != TYPE_ARRAY:
		var fallback: Array = []
		if pos.x < -36.0:
			fallback.append("west_street")
		if pos.x > 22.0:
			fallback.append("gate")
		return fallback
	var result: Array = []
	for zone_value in zones_value:
		if typeof(zone_value) != TYPE_DICTIONARY:
			continue
		var zone: Dictionary = zone_value
		var zone_id := str(zone.get("id", ""))
		if zone_id == "":
			continue
		if _zone_matches(zone, pos):
			result.append(zone_id)
	return result


static func _read_point(
	data: Dictionary, section: String, key: String, fallback: Vector2
) -> Vector2:
	var section_value: Variant = data.get(section, null)
	if typeof(section_value) != TYPE_DICTIONARY:
		return fallback
	var section_data: Dictionary = section_value
	var point_value: Variant = section_data.get(key, null)
	if typeof(point_value) != TYPE_ARRAY:
		return fallback
	var point: Array = point_value
	if point.size() < 2 or not _is_number(point[0]) or not _is_number(point[1]):
		return fallback
	return Vector2(float(point[0]), float(point[1]))


static func _zone_matches(zone: Dictionary, pos: Vector2) -> bool:
	if _is_number(zone.get("x_lt", null)) and not (pos.x < float(zone["x_lt"])):
		return false
	if _is_number(zone.get("x_gt", null)) and not (pos.x > float(zone["x_gt"])):
		return false
	if _is_number(zone.get("z_lt", null)) and not (pos.y < float(zone["z_lt"])):
		return false
	if _is_number(zone.get("z_gt", null)) and not (pos.y > float(zone["z_gt"])):
		return false
	return true


static func _base_ground_height(data: Dictionary, x: float, z: float) -> float:
	var platform_value: Variant = data.get("platform", null)
	if typeof(platform_value) == TYPE_DICTIONARY:
		var platform: Dictionary = platform_value
		var rect_value: Variant = platform.get("rect", [])
		if typeof(rect_value) == TYPE_ARRAY:
			var rect: Array = rect_value
			if rect.size() >= 4:
				if x >= float(rect[0]) and x <= float(rect[2]) \
						and z >= float(rect[1]) and z <= float(rect[3]):
					return float(platform.get("y", 0.0))

	var stairs_value: Variant = data.get("stairs", null)
	if typeof(stairs_value) == TYPE_DICTIONARY:
		var stairs: Dictionary = stairs_value
		if _has_numbers(stairs, ["x0", "x1", "z_start", "z_end"]):
			var sx0 := float(stairs["x0"])
			var sx1 := float(stairs["x1"])
			var z_start := float(stairs["z_start"])
			var z_end := float(stairs["z_end"])
			if x >= sx0 and x <= sx1 and z <= z_start and z >= z_end:
				var step_index := floori(z_start - z)
				var y_top := float(stairs.get("y_top", 0.0))
				return minf(0.5 * float(step_index + 1), y_top)

	var bridges: Array = data.get("bridges", [])
	for bridge_value in bridges:
		if typeof(bridge_value) != TYPE_DICTIONARY:
			continue
		var bridge: Dictionary = bridge_value
		if not _has_numbers(bridge, ["x0", "x1", "z0", "z1"]):
			continue
		if x >= float(bridge["x0"]) and x <= float(bridge["x1"]) \
				and z >= float(bridge["z0"]) and z <= float(bridge["z1"]):
			return 0.25

	return 0.0


static func extra_blockers(data: Dictionary) -> Array:
	var result: Array = []
	result.append_array(TownTerraces.blockers(data))
	var platform_value: Variant = data.get("platform", null)
	var stairs_value: Variant = data.get("stairs", null)
	if typeof(platform_value) != TYPE_DICTIONARY or typeof(stairs_value) != TYPE_DICTIONARY:
		return result
	var platform: Dictionary = platform_value
	var stairs: Dictionary = stairs_value
	var rect_value: Variant = platform.get("rect", [])
	if typeof(rect_value) != TYPE_ARRAY:
		return result
	var rect: Array = rect_value
	if rect.size() < 4:
		return result
	if not _has_numbers(stairs, ["x0"]):
		return result
	var px0 := float(rect[0])
	var pz0 := float(rect[1])
	var pz1 := float(rect[3])
	var cliff_width := float(stairs["x0"]) - px0
	if cliff_width <= 0.0:
		return result
	result.append(Rect2(px0, pz0, cliff_width, pz1 - pz0))
	return result


static func _has_numbers(entry: Dictionary, keys: Array) -> bool:
	for key in keys:
		var value: Variant = entry.get(key, null)
		if not _is_number(value):
			return false
	return true


static func _is_number(value: Variant) -> bool:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return true
	return false


static func _point_in_rects(point: Vector2, rects: Array) -> bool:
	for rect_value in rects:
		if rect_value is Rect2:
			var rect: Rect2 = rect_value
			if rect.has_point(point):
				return true
	return false

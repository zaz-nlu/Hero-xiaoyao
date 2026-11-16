extends RefCounted

const BUILDING_KINDS: Array[String] = ["house", "smith", "shop", "tavern"]
const PROP_KINDS: Array[String] = [
	"barrel", "crate", "bench", "lamp_post", "banner", "cart", "stall", "tree"
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
	for i in range(npcs.size()):
		var npc_value: Variant = npcs[i]
		if typeof(npc_value) != TYPE_DICTIONARY:
			errors.append("npc %d is not an object" % i)
			continue
		var npc: Dictionary = npc_value
		var id := str(npc.get("id", "npc_%d" % i))
		var sprite := str(npc.get("sprite", ""))
		var sprite_path := "res://assets/sprites/%s.png" % sprite
		if sprite == "" or not FileAccess.file_exists(sprite_path):
			errors.append("npc %s has missing sprite '%s'" % [id, sprite])
		if _has_numbers(npc, ["x", "z"]):
			var npc_pos := Vector2(float(npc["x"]), float(npc["z"]))
			if not _bounds_has_point(bounds, npc_pos):
				errors.append("npc %s is outside bounds" % id)
			for rect in building_footprints:
				if rect.has_point(npc_pos):
					errors.append("npc %s is inside a building" % id)
					break

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
			if bx0 > wx0:
				result.append(Rect2(wx0, wz0, bx0 - wx0, wz1 - wz0))
			if bx1 < wx1:
				result.append(Rect2(bx1, wz0, wx1 - bx1, wz1 - wz0))

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
		match typeof(value):
			TYPE_INT, TYPE_FLOAT:
				pass
			_:
				return false
	return true

@tool
extends RefCounted

# 地图地形的严格校验：terraces / stairs / ramp / water 与出生点、物件的落位。
# 由 LayoutDocument.validate_document 增量调用；只读 document，不修改任何数据。
# 旧地图没有这些字段时不会新增限制。

const Data = preload("res://core/layouts/layout_terrain_data.gd")


static func validate(document: Variant, catalog: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not (document is Dictionary):
		return errors
	var doc: Dictionary = document
	var items_value: Variant = catalog.get("items", {})
	var items: Dictionary = items_value if items_value is Dictionary else {}
	_validate_terraces(doc, items, errors)
	var platforms := Data.platforms(doc)
	_validate_water(doc, platforms, errors)
	_validate_connectors(doc, platforms, errors)
	_validate_placement(doc, items, platforms, errors)
	return errors


# ---------------------------------------------------------------- terraces

static func _validate_terraces(
	document: Dictionary, items: Dictionary, errors: Array[String]
) -> void:
	var raw_value: Variant = document.get("terraces", [])
	if raw_value == null:
		return
	if not (raw_value is Array):
		errors.append("terraces: must be an array")
		return
	var raw: Array = raw_value
	var bounds := Data.world_bounds(document)
	var has_bounds := bounds.size.x > 0.0 and bounds.size.y > 0.0
	var accepted: Array[Rect2] = []
	var accepted_labels: Array[String] = []
	for i in range(raw.size()):
		var entry_value: Variant = raw[i]
		if not (entry_value is Dictionary):
			errors.append("terraces[%d]: must be an object" % i)
			continue
		var entry: Dictionary = entry_value
		var where := _label("terraces[%d]" % i, entry.get("name", ""))
		if entry.has("name") and typeof(entry["name"]) != TYPE_STRING:
			errors.append("%s: name must be a string" % where)
		if entry.has("top"):
			_validate_top(entry, items, where, errors)
		var stairs_value: Variant = entry.get("stairs", null)
		if entry.has("stairs") and not (stairs_value is Array):
			errors.append("%s: stairs must be an array" % where)
		var rect := _read_rect(entry.get("rect"), where, bounds, has_bounds, errors)
		if rect.size.x > 0.0:
			for j in range(accepted.size()):
				if Data.rect_overlap(rect, accepted[j]):
					errors.append("%s overlaps %s" % [where, accepted_labels[j]])
					break
			accepted.append(rect)
			accepted_labels.append(where)
		var y_ok := false
		var from_ok := false
		var y := 0.0
		var from_y := 0.0
		var y_value: Variant = entry.get("y", null)
		if not Data.is_number(y_value):
			errors.append("%s: y must be a finite number" % where)
		else:
			y = float(y_value)
			if not Data.is_half_step(y):
				errors.append("%s: y must use 0.5 increments" % where)
			elif y > Data.MAX_HEIGHT + Data.EPSILON:
				errors.append("%s: y must not exceed %.0f" % [where, Data.MAX_HEIGHT])
			elif y <= Data.EPSILON:
				errors.append("%s: y must be greater than 0" % where)
			else:
				y_ok = true
		var from_value: Variant = entry.get("from_y", 0.0)
		if not Data.is_number(from_value):
			errors.append("%s: from_y must be a finite number" % where)
		else:
			from_y = float(from_value)
			if not Data.is_half_step(from_y):
				errors.append("%s: from_y must use 0.5 increments" % where)
			elif from_y < -Data.EPSILON:
				errors.append("%s: from_y must not be negative" % where)
			elif from_y > Data.MAX_HEIGHT + Data.EPSILON:
				errors.append(
					"%s: from_y must not exceed %.0f" % [where, Data.MAX_HEIGHT]
				)
			else:
				from_ok = true
		if y_ok and from_ok and y <= from_y + Data.EPSILON:
			errors.append("%s: y must be greater than from_y" % where)


static func _validate_top(
	entry: Dictionary, items: Dictionary, where: String, errors: Array[String]
) -> void:
	if typeof(entry["top"]) != TYPE_STRING or str(entry["top"]) == "":
		errors.append("%s: top must be a ground asset id" % where)
		return
	var asset := str(entry["top"])
	var item_value: Variant = items.get(asset, null)
	if not (item_value is Dictionary):
		errors.append("%s: top asset '%s' is not in the catalog" % [where, asset])
	elif str((item_value as Dictionary).get("kind", "")) != "ground":
		errors.append("%s: top asset '%s' is not a ground item" % [where, asset])


# ---------------------------------------------------------------- water

static func _validate_water(
	document: Dictionary, platforms: Array, errors: Array[String]
) -> void:
	var raw_value: Variant = document.get("water", [])
	if raw_value == null:
		return
	if not (raw_value is Array):
		errors.append("water: must be an array")
		return
	var raw: Array = raw_value
	var bounds := Data.world_bounds(document)
	var has_bounds := bounds.size.x > 0.0 and bounds.size.y > 0.0
	var accepted: Array[Rect2] = []
	var accepted_labels: Array[String] = []
	for i in range(raw.size()):
		var entry_value: Variant = raw[i]
		if not (entry_value is Dictionary):
			errors.append("water[%d]: must be an object" % i)
			continue
		var entry: Dictionary = entry_value
		var where := _label("water[%d]" % i, entry.get("name", ""))
		if entry.has("name") and typeof(entry["name"]) != TYPE_STRING:
			errors.append("%s: name must be a string" % where)
		var rect := _read_rect(entry.get("rect"), where, bounds, has_bounds, errors)
		if rect.size.x <= 0.0:
			continue
		var bottom := Data.platform_height(platforms, rect.get_center())
		if not _continuous_bottom(platforms, rect, bottom):
			errors.append("%s: bottom must sit on one continuous height" % where)
		if entry.has("y"):
			var level_value: Variant = entry["y"]
			if not Data.is_number(level_value):
				errors.append("%s: y must be a finite number" % where)
			elif float(level_value) <= bottom + Data.EPSILON:
				errors.append("%s: y must be above the water bottom" % where)
		for j in range(accepted.size()):
			if Data.rect_overlap(rect, accepted[j]):
				errors.append("%s overlaps %s" % [where, accepted_labels[j]])
				break
		accepted.append(rect)
		accepted_labels.append(where)


static func _continuous_bottom(
	platforms: Array, rect: Rect2, bottom: float
) -> bool:
	return _matches_height(platforms, rect, bottom)


# 两个同高矩形查询共用这一套相交判断：
# 平台保证互不相叠，任何与目标矩形面积相交且高度不同的平台都返回 false；
# 目标高为 0 时无需全覆盖（空地即 0），否则相交面积必须覆盖目标直角矩形。
static func _matches_height(platforms: Array, rect: Rect2, target: float) -> bool:
	var covered := 0.0
	for platform_value in platforms:
		if not (platform_value is Dictionary):
			continue
		var platform: Dictionary = platform_value
		var platform_rect_value: Variant = platform.get("rect", null)
		if not (platform_rect_value is Rect2):
			continue
		var overlap := (platform_rect_value as Rect2).intersection(rect)
		if overlap.size.x <= Data.EPSILON or overlap.size.y <= Data.EPSILON:
			continue
		if absf(float(platform.get("y", 0.0)) - target) > Data.EPSILON:
			return false
		covered += overlap.size.x * overlap.size.y
	if target > Data.EPSILON:
		return covered >= rect.size.x * rect.size.y - Data.EPSILON
	return true


# ---------------------------------------------------------------- connectors

static func _validate_connectors(
	document: Dictionary, platforms: Array, errors: Array[String]
) -> void:
	var bounds := Data.world_bounds(document)
	var has_bounds := bounds.size.x > 0.0 and bounds.size.y > 0.0
	var water_rects := _raw_water_rects(document)
	var accepted: Array[Rect2] = []
	var accepted_labels: Array[String] = []
	for platform_value in platforms:
		if not (platform_value is Dictionary):
			continue
		var platform: Dictionary = platform_value
		var raw_value: Variant = platform.get("stairs_raw", [])
		if not (raw_value is Array):
			continue
		var raw: Array = raw_value
		var platform_rect_value: Variant = platform["rect"]
		var platform_rect: Rect2 = platform_rect_value
		var from_y := float(platform["from_y"])
		var y := float(platform["y"])
		for j in range(raw.size()):
			var entry_value: Variant = raw[j]
			var where := "terraces[%d].stairs[%d]" % [int(platform["index"]), j]
			if not (entry_value is Dictionary):
				errors.append("%s: must be an object" % where)
				continue
			var entry: Dictionary = entry_value
			where = _label(where, entry.get("name", ""))
			var side := str(entry.get("side", "south"))
			if not Data.SIDES.has(side):
				errors.append("%s: side must be north, south, east or west" % where)
				continue
			var kind := str(entry.get("kind", "stairs"))
			if not Data.CONNECTOR_KINDS.has(kind):
				errors.append("%s: kind must be stairs or ramp" % where)
				continue
			if entry.has("name") and typeof(entry["name"]) != TYPE_STRING:
				errors.append("%s: name must be a string" % where)
			var opening := _read_opening(entry, side, where, errors)
			if opening.is_empty():
				continue
			var open0 := float(opening[0])
			var open1 := float(opening[1])
			if side == "north" or side == "south":
				if open0 < platform_rect.position.x - Data.EPSILON \
						or open1 > platform_rect.end.x + Data.EPSILON:
					errors.append("%s: opening must lie along the terrace edge" % where)
					continue
			else:
				if open0 < platform_rect.position.y - Data.EPSILON \
						or open1 > platform_rect.end.y + Data.EPSILON:
					errors.append("%s: opening must lie along the terrace edge" % where)
					continue
			var depth := Data.connector_depth(kind, from_y, y)
			if depth <= 0.0:
				errors.append("%s: needs a positive height difference" % where)
				continue
			var rect := Data.connector_rect(platform_rect, side, open0, open1, depth)
			if has_bounds and not _inside_bounds(rect, bounds):
				errors.append("%s: connection extends outside the map" % where)
				continue
			if not _ground_matches(platforms, rect, from_y):
				errors.append(
					"%s: low side ground must be %.1f" % [where, from_y]
				)
			var blocked := false
			for water_rect in water_rects:
				if Data.rect_overlap(rect, water_rect):
					errors.append("%s overlaps water" % where)
					blocked = true
					break
			if blocked:
				continue
			for k in range(accepted.size()):
				if Data.rect_overlap(rect, accepted[k]):
					errors.append("%s overlaps %s" % [where, accepted_labels[k]])
					break
			accepted.append(rect)
			accepted_labels.append(where)


static func _read_opening(
	entry: Dictionary, side: String, where: String, errors: Array[String]
) -> Array:
	var keys := ["x0", "x1"] if side == "north" or side == "south" else ["z0", "z1"]
	var first_value: Variant = entry.get(keys[0], null)
	var second_value: Variant = entry.get(keys[1], null)
	if not Data.is_number(first_value) or not Data.is_number(second_value):
		errors.append(
			"%s: opening needs finite %s and %s" % [where, keys[0], keys[1]]
		)
		return []
	var open0 := float(first_value)
	var open1 := float(second_value)
	if not Data.is_grid_aligned(open0) or not Data.is_grid_aligned(open1):
		errors.append("%s: opening must align to 2-unit cell edges" % where)
		return []
	if open1 <= open0 + Data.EPSILON:
		errors.append("%s: opening must have positive width" % where)
		return []
	return [open0, open1]


static func _ground_matches(
	platforms: Array, rect: Rect2, from_y: float
) -> bool:
	return _matches_height(platforms, rect, from_y)


# ---------------------------------------------------------------- placement

static func _validate_placement(
	document: Dictionary, items: Dictionary, platforms: Array, errors: Array[String]
) -> void:
	var connectors := Data.connectors(document, platforms)
	var water_rects: Array[Rect2] = []
	for water_value in Data.water_entries(document, platforms):
		if water_value is Dictionary:
			var water_rect_value: Variant = (water_value as Dictionary)["rect"]
			var water_rect: Rect2 = water_rect_value
			water_rects.append(water_rect)
	_validate_objects(document, items, platforms, connectors, water_rects, errors)
	_validate_spawn(document, water_rects, errors)


static func _validate_objects(
	document: Dictionary,
	items: Dictionary,
	platforms: Array,
	connectors: Array,
	water_rects: Array[Rect2],
	errors: Array[String]
) -> void:
	var raw_value: Variant = document.get("objects", [])
	if not (raw_value is Array):
		return
	var raw: Array = raw_value
	for i in range(raw.size()):
		var object_value: Variant = raw[i]
		if not (object_value is Dictionary):
			continue
		var object: Dictionary = object_value
		var asset := str(object.get("asset", ""))
		var item_value: Variant = items.get(asset, null)
		if not (item_value is Dictionary):
			continue
		var item: Dictionary = item_value
		var x_value: Variant = object.get("x", null)
		var z_value: Variant = object.get("z", null)
		if not Data.is_int(x_value) or not Data.is_int(z_value):
			continue
		var x := int(x_value)
		var z := int(z_value)
		var turn := int(object.get("turn", 0))
		var where := "objects[%d] '%s'" % [i, asset]
		var footprint := Data.item_footprint_world(items, asset, x, z, turn)
		if footprint.size.x <= 0.0:
			continue
		for water_rect in water_rects:
			if Data.rect_overlap(footprint, water_rect):
				errors.append("%s overlaps water" % where)
				break
		if str(item.get("kind", "")) == "ground":
			continue
		for connector_value in connectors:
			if not (connector_value is Dictionary):
				continue
			var connector: Dictionary = connector_value
			var connector_rect_value: Variant = connector["rect"]
			var connector_rect: Rect2 = connector_rect_value
			if Data.rect_overlap(footprint, connector_rect):
				errors.append("%s covers a stairs/ramp opening" % where)
				break
		if _spans_height_change(platforms, items, asset, x, z, turn):
			errors.append("%s spans a height change" % where)


static func _spans_height_change(
	platforms: Array, items: Dictionary, asset: String, x: int, z: int, turn: int
) -> bool:
	var cells := Data.footprint_cells(items, asset, x, z, turn)
	if cells.size.x <= 0 or cells.size.y <= 0:
		return false
	var base := Data.platform_height(
		platforms, _cell_center(cells.position.x, cells.position.y)
	)
	for cx in range(cells.position.x, cells.position.x + cells.size.x):
		for cz in range(cells.position.y, cells.position.y + cells.size.y):
			var height := Data.platform_height(platforms, _cell_center(cx, cz))
			if absf(height - base) > Data.EPSILON:
				return true
	return false


static func _validate_spawn(
	document: Dictionary, water_rects: Array[Rect2], errors: Array[String]
) -> void:
	var spawn_value: Variant = document.get("spawn", null)
	if not (spawn_value is Dictionary):
		return
	var spawn: Dictionary = spawn_value
	var x_value: Variant = spawn.get("x", null)
	var z_value: Variant = spawn.get("z", null)
	if not Data.is_number(x_value) or not Data.is_number(z_value):
		return
	var point := Vector2(float(x_value), float(z_value))
	for water_rect in water_rects:
		if Data.rect_contains(water_rect, point):
			errors.append("spawn (%.1f,%.1f) is in water" % [point.x, point.y])
			return


# ---------------------------------------------------------------- helpers

static func _read_rect(
	value: Variant,
	where: String,
	bounds: Rect2,
	has_bounds: bool,
	errors: Array[String]
) -> Rect2:
	if not (value is Array) or (value as Array).size() != 4:
		errors.append("%s: rect must be [x0,z0,x1,z1]" % where)
		return Rect2()
	var coords: Array = value
	for coord in coords:
		if not Data.is_number(coord):
			errors.append("%s: rect values must be finite numbers" % where)
			return Rect2()
	var x0 := float(coords[0])
	var z0 := float(coords[1])
	var x1 := float(coords[2])
	var z1 := float(coords[3])
	if not Data.is_grid_aligned(x0) or not Data.is_grid_aligned(z0) \
			or not Data.is_grid_aligned(x1) or not Data.is_grid_aligned(z1):
		errors.append("%s: rect must align to 2-unit cell edges" % where)
		return Rect2()
	if x1 <= x0 or z1 <= z0:
		errors.append("%s: rect must have positive area" % where)
		return Rect2()
	var rect := Rect2(x0, z0, x1 - x0, z1 - z0)
	if has_bounds and not _inside_bounds(rect, bounds):
		errors.append("%s: rect extends outside the map" % where)
		return Rect2()
	return rect


static func _inside_bounds(rect: Rect2, bounds: Rect2) -> bool:
	return rect.position.x >= bounds.position.x - Data.EPSILON \
		and rect.position.y >= bounds.position.y - Data.EPSILON \
		and rect.end.x <= bounds.end.x + Data.EPSILON \
		and rect.end.y <= bounds.end.y + Data.EPSILON


static func _raw_water_rects(document: Dictionary) -> Array[Rect2]:
	var result: Array[Rect2] = []
	var raw_value: Variant = document.get("water", [])
	if not (raw_value is Array):
		return result
	var raw: Array = raw_value
	for entry_value in raw:
		if not (entry_value is Dictionary):
			continue
		var value: Variant = (entry_value as Dictionary).get("rect", null)
		if not (value is Array) or (value as Array).size() != 4:
			continue
		var coords: Array = value
		var numbers_ok := true
		for coord in coords:
			if not Data.is_number(coord):
				numbers_ok = false
				break
		if not numbers_ok:
			continue
		var x0 := float(coords[0])
		var z0 := float(coords[1])
		var x1 := float(coords[2])
		var z1 := float(coords[3])
		if x1 > x0 and z1 > z0:
			result.append(Rect2(x0, z0, x1 - x0, z1 - z0))
	return result


static func _cell_center(x: int, z: int) -> Vector2:
	return Vector2(
		(float(x) + 0.5) * Data.TILE_SIZE,
		(float(z) + 0.5) * Data.TILE_SIZE
	)


static func _label(base: String, name_value: Variant) -> String:
	if typeof(name_value) == TYPE_STRING and str(name_value) != "":
		return "%s '%s'" % [base, str(name_value)]
	return base

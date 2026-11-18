extends RefCounted

const Grid = preload("res://core/tactics/grid.gd")

const MAPS_DIR := "res://data/maps"


static func load_map(id: String) -> Dictionary:
	var path := "%s/%s.json" % [MAPS_DIR, id]
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		return {"ok": false, "errors": ["cannot read %s" % path], "grid": null, "meta": {}}
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {"ok": false, "errors": ["%s: top-level JSON must be an object" % path], "grid": null, "meta": {}}
	var result := parse_map(parsed)
	var meta: Dictionary = result["meta"]
	if str(meta.get("id", "")) == "":
		meta["id"] = id
	return result


static func list_maps() -> Array:
	var ids: Array = []
	var dir := DirAccess.open(MAPS_DIR)
	if dir == null:
		return ids
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			ids.append(file_name.get_basename())
		file_name = dir.get_next()
	dir.list_dir_end()
	ids.sort()
	return ids


static func parse_map(d: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var width := int(d.get("width", 0))
	var height := int(d.get("height", 0))
	if width <= 0 or height <= 0:
		errors.append("map: width and height must be positive")

	var tiles_ok := true
	var raw_tiles = d.get("tiles", [])
	if not (raw_tiles is Array):
		errors.append("tiles: must be an array of strings")
		tiles_ok = false
		raw_tiles = []
	elif raw_tiles.size() != height:
		errors.append("tiles: expected %d rows, got %d" % [height, raw_tiles.size()])
		tiles_ok = false
	for y in range(raw_tiles.size()):
		var row = raw_tiles[y]
		if not (row is String):
			errors.append("tiles row %d: must be a string" % y)
			tiles_ok = false
			continue
		if row.length() != width:
			errors.append("tiles row %d: expected width %d, got %d" % [y, width, row.length()])
			tiles_ok = false
		for x in range(row.length()):
			var ch: String = row.substr(x, 1)
			if not Grid.CHAR_TERRAIN.has(ch):
				errors.append("tiles row %d col %d: invalid char '%s'" % [y, x, ch])
				tiles_ok = false

	var heights_ok := true
	var raw_heights = d.get("heights", [])
	if raw_heights is Array and raw_heights.size() > 0:
		if raw_heights.size() != height:
			errors.append("heights: expected %d rows, got %d" % [height, raw_heights.size()])
			heights_ok = false
		for y in range(raw_heights.size()):
			var row = raw_heights[y]
			if not (row is String):
				errors.append("heights row %d: must be a string" % y)
				heights_ok = false
				continue
			if row.length() != width:
				errors.append("heights row %d: expected width %d, got %d" % [y, width, row.length()])
				heights_ok = false
			for x in range(row.length()):
				var ch: String = row.substr(x, 1)
				if not ch.is_valid_int():
					errors.append("heights row %d col %d: invalid height '%s'" % [y, x, ch])
					heights_ok = false
	elif not (raw_heights is Array):
		errors.append("heights: must be an array of strings")
		heights_ok = false

	var grid: Variant = Grid.from_dict(d)

	var spawn_points: Array[Vector2i] = []
	var spawns_ok := true
	var spawns = d.get("spawns", {})
	if not (spawns is Dictionary):
		errors.append("spawns: must be an object")
		spawns_ok = false
	else:
		for group in ["player", "enemies"]:
			var raw_group = spawns.get(group, [])
			if not (raw_group is Array) or raw_group.is_empty():
				errors.append("spawns '%s': must be a non-empty array" % group)
				spawns_ok = false
				continue
			for i in range(raw_group.size()):
				var pair = raw_group[i]
				if not (pair is Array) or pair.size() != 2:
					errors.append("spawns '%s'[%d]: must be [x, y]" % [group, i])
					spawns_ok = false
					continue
				var point := Vector2i(int(pair[0]), int(pair[1]))
				if not grid.in_bounds(point):
					errors.append("spawns '%s'[%d]: %s out of bounds" % [group, i, str(point)])
					spawns_ok = false
				elif not grid.is_walkable(point):
					errors.append("spawns '%s'[%d]: %s is not walkable" % [group, i, str(point)])
					spawns_ok = false
				else:
					spawn_points.append(point)

	if d.has("exit"):
		var raw_exit = d["exit"]
		if raw_exit is Array and raw_exit.size() == 2:
			var exit_cell := Vector2i(int(raw_exit[0]), int(raw_exit[1]))
			if not grid.in_bounds(exit_cell):
				errors.append("exit: %s out of bounds" % str(exit_cell))
			elif not grid.is_walkable(exit_cell):
				errors.append("exit: %s is not walkable" % str(exit_cell))
		else:
			errors.append("exit: must be [x, y]")

	if tiles_ok and heights_ok and spawns_ok and spawn_points.size() >= 2:
		if not _connected(grid, spawn_points):
			errors.append("spawns: player and enemy spawn points are not connected")

	var meta := {
		"id": str(d.get("id", "")),
		"name": str(d.get("name", "")),
		"width": width,
		"height": height,
		"backdrop": str(d.get("backdrop", "")),
		"spawns": spawns,
		"objective": str(d.get("objective", "")),
		"leader": str(d.get("leader", "")),
	}
	if d.has("exit"):
		meta["exit"] = d["exit"]
	return {"ok": errors.is_empty(), "errors": errors, "grid": grid, "meta": meta}


static func _connected(grid, points: Array[Vector2i]) -> bool:
	if points.is_empty():
		return true
	var visited := {points[0]: true}
	var queue: Array[Vector2i] = [points[0]]
	var head := 0
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		for neighbor in grid.neighbors(current):
			if visited.has(neighbor):
				continue
			if not grid.is_walkable(neighbor):
				continue
			visited[neighbor] = true
			queue.append(neighbor)
	for point in points:
		if not visited.has(point):
			return false
	return true

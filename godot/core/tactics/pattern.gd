extends RefCounted

const Facing = preload("res://core/tactics/facing.gd")
const Grid = preload("res://core/tactics/grid.gd")

const SHAPES: Array[String] = ["melee", "line", "ranged", "cone", "burst"]

const DIRECTIONS: Array[Vector2i] = [
	Vector2i.UP,
	Vector2i.DOWN,
	Vector2i.LEFT,
	Vector2i.RIGHT,
]


static func normalize(def: Dictionary) -> Dictionary:
	var shape := str(def.get("shape", "melee")).to_lower()
	if not SHAPES.has(shape):
		shape = "melee"
	var min_value := maxi(1, int(def.get("min", 1)))
	var max_value := maxi(min_value, int(def.get("max", 1)))
	var width := maxi(1, int(def.get("width", 1)))
	var pierce := bool(def.get("pierce", false))
	return {
		"shape": shape,
		"min": min_value,
		"max": max_value,
		"width": width,
		"pierce": pierce,
	}


static func target_cells(def: Dictionary, origin: Vector2i, facing: Vector2i, grid) -> Array[Vector2i]:
	var pattern := normalize(def)
	var result: Array[Vector2i] = []
	var min_range := int(pattern["min"])
	var max_range := int(pattern["max"])
	match str(pattern["shape"]):
		"melee":
			if min_range == 1 and max_range == 1:
				for melee_direction in DIRECTIONS:
					var near: Vector2i = origin + melee_direction
					if _is_valid_cell(near, grid, origin):
						result.append(near)
			else:
				for y in range(grid.height):
					for x in range(grid.width):
						var melee_cell := Vector2i(x, y)
						var melee_distance := Grid.manhattan(origin, melee_cell)
						if melee_distance < min_range or melee_distance > max_range:
							continue
						if _is_valid_cell(melee_cell, grid, origin):
							result.append(melee_cell)
		"line":
			for line_direction in DIRECTIONS:
				for step in range(1, max_range + 1):
					var line_cell: Vector2i = origin + line_direction * step
					if not grid.in_bounds(line_cell):
						break
					if grid.terrain_at(line_cell) == "wall":
						break
					if step >= min_range:
						result.append(line_cell)
		"ranged":
			for y in range(grid.height):
				for x in range(grid.width):
					var ranged_cell := Vector2i(x, y)
					var ranged_distance := Grid.manhattan(origin, ranged_cell)
					if ranged_distance < min_range or ranged_distance > max_range:
						continue
					if not _is_valid_cell(ranged_cell, grid, origin):
						continue
					if not grid.has_line_of_sight(origin, ranged_cell):
						continue
					result.append(ranged_cell)
		"cone":
			var facing_dir := _safe_facing(facing)
			var perpendicular := Vector2i(-facing_dir.y, facing_dir.x)
			for cone_distance in range(1, max_range + 1):
				if cone_distance < min_range:
					continue
				for offset in range(-(cone_distance - 1), cone_distance):
					var cone_cell: Vector2i = origin + facing_dir * cone_distance + perpendicular * offset
					if _is_valid_cell(cone_cell, grid, origin):
						result.append(cone_cell)
		"burst":
			for y in range(origin.y - max_range, origin.y + max_range + 1):
				for x in range(origin.x - max_range, origin.x + max_range + 1):
					var area_cell := Vector2i(x, y)
					if Grid.manhattan(origin, area_cell) > max_range:
						continue
					if _is_valid_cell(area_cell, grid, origin):
						result.append(area_cell)
	return result


static func affected_cells(def: Dictionary, origin: Vector2i, facing: Vector2i, target: Vector2i, grid) -> Array[Vector2i]:
	var pattern := normalize(def)
	var result: Array[Vector2i] = []
	var max_range := int(pattern["max"])
	match str(pattern["shape"]):
		"melee", "ranged":
			if target != origin and grid.in_bounds(target):
				result.append(target)
		"line":
			if target == origin:
				return result
			var line_direction := Facing.from_delta(target - origin, Facing.UP)
			var line_distance := absi(target.x - origin.x)
			if line_direction.x == 0:
				line_distance = absi(target.y - origin.y)
			var line_limit := line_distance
			if bool(pattern["pierce"]):
				line_limit = maxi(line_distance, max_range)
			for step in range(1, line_limit + 1):
				var line_cell: Vector2i = origin + line_direction * step
				if not grid.in_bounds(line_cell):
					break
				if grid.terrain_at(line_cell) == "wall":
					break
				result.append(line_cell)
		"cone":
			var facing_dir := _safe_facing(facing)
			var perpendicular := Vector2i(-facing_dir.y, facing_dir.x)
			var delta := target - origin
			var cone_distance := delta.x * facing_dir.x + delta.y * facing_dir.y
			if cone_distance < 1:
				return result
			for offset in range(-(cone_distance - 1), cone_distance):
				var cone_cell: Vector2i = origin + facing_dir * cone_distance + perpendicular * offset
				if _is_valid_cell(cone_cell, grid, origin):
					result.append(cone_cell)
		"burst":
			for y in range(origin.y - max_range, origin.y + max_range + 1):
				for x in range(origin.x - max_range, origin.x + max_range + 1):
					var area_cell := Vector2i(x, y)
					if Grid.manhattan(origin, area_cell) > max_range:
						continue
					if _is_valid_cell(area_cell, grid, origin):
						result.append(area_cell)
	return result


static func _is_valid_cell(cell: Vector2i, grid, origin: Vector2i) -> bool:
	if cell == origin:
		return false
	if not grid.in_bounds(cell):
		return false
	return grid.terrain_at(cell) != "wall"


static func _safe_facing(facing: Vector2i) -> Vector2i:
	return Facing.from_delta(facing, Facing.UP)

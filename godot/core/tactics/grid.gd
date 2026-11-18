extends RefCounted

const CHAR_TERRAIN := {
	".": "floor",
	"#": "wall",
	"~": "water",
	"o": "obstacle",
	"f": "furniture",
	"b": "bush",
}

const WALKABLE_TERRAIN := {
	"floor": true,
	"bush": true,
}

# 横向优先、再纵向：保证 path() 在多条最短路时结果确定。
const NEIGHBOR_DIRS: Array[Vector2i] = [
	Vector2i.LEFT,
	Vector2i.RIGHT,
	Vector2i.UP,
	Vector2i.DOWN,
]

var width: int = 0
var height: int = 0
# terrain[y][x] / heights[y][x]
var terrain: Array[Array] = []
var heights: Array[Array] = []


func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < width and p.y < height


func terrain_at(p: Vector2i) -> String:
	if not in_bounds(p) or p.y >= terrain.size():
		return ""
	var row: Array = terrain[p.y]
	if p.x >= row.size():
		return ""
	return str(row[p.x])


func height_at(p: Vector2i) -> int:
	if not in_bounds(p) or p.y >= heights.size():
		return 0
	var row: Array = heights[p.y]
	if p.x >= row.size():
		return 0
	return int(row[p.x])


func is_walkable(p: Vector2i) -> bool:
	if not in_bounds(p):
		return false
	return WALKABLE_TERRAIN.has(terrain_at(p))


func is_cover(p: Vector2i) -> bool:
	return terrain_at(p) == "bush"


func neighbors(p: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for direction in NEIGHBOR_DIRS:
		var neighbor: Vector2i = p + direction
		if in_bounds(neighbor):
			out.append(neighbor)
	return out


static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func reachable(
	start: Vector2i,
	move_points: int,
	max_climb: int,
	blocked: Dictionary = {},
	passable_allies: Dictionary = {}
) -> Dictionary:
	var out := {}
	if not in_bounds(start):
		return out
	out[start] = 0
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		var next_cost := int(out[current]) + 1
		if next_cost > move_points:
			continue
		for neighbor in neighbors(current):
			if out.has(neighbor) or blocked.has(neighbor):
				continue
			if not is_walkable(neighbor):
				continue
			if absi(height_at(neighbor) - height_at(current)) > max_climb:
				continue
			out[neighbor] = next_cost
			queue.append(neighbor)
	# passable_allies 可以穿过，但不作为终点；调用方按
	# "返回字典里不属于 blocked / passable_allies 的格子" 取得终点集合。
	return out


func path(
	start: Vector2i,
	goal: Vector2i,
	move_points: int,
	max_climb: int,
	blocked: Dictionary = {},
	passable_allies: Dictionary = {}
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not in_bounds(start) or not in_bounds(goal):
		return result
	if blocked.has(goal) or passable_allies.has(goal):
		return result
	if start == goal:
		result.append(start)
		return result

	var previous := {start: start}
	var distance := {start: 0}
	var queue: Array[Vector2i] = [start]
	var head := 0
	var found := false
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		if current == goal:
			found = true
			break
		var next_cost := int(distance[current]) + 1
		if next_cost > move_points:
			continue
		for neighbor in neighbors(current):
			if distance.has(neighbor) or blocked.has(neighbor):
				continue
			if not is_walkable(neighbor):
				continue
			if absi(height_at(neighbor) - height_at(current)) > max_climb:
				continue
			distance[neighbor] = next_cost
			previous[neighbor] = current
			queue.append(neighbor)
	if not found:
		return result

	var cursor: Vector2i = goal
	while cursor != start:
		result.push_front(cursor)
		cursor = previous[cursor]
	result.push_front(start)
	return result


func line_cells(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if a == b:
		return cells
	var x0 := a.x
	var y0 := a.y
	var x1 := b.x
	var y1 := b.y
	var dx := absi(x1 - x0)
	var step_x := 1 if x0 < x1 else -1
	var dy := -absi(y1 - y0)
	var step_y := 1 if y0 < y1 else -1
	var error := dx + dy
	while x0 != x1 or y0 != y1:
		var doubled := 2 * error
		if doubled >= dy:
			error += dy
			x0 += step_x
		if doubled <= dx:
			error += dx
			y0 += step_y
		cells.append(Vector2i(x0, y0))
	return cells


func has_line_of_sight(a: Vector2i, b: Vector2i) -> bool:
	if a == b:
		return true
	var base_height := maxi(height_at(a), height_at(b))
	for cell in line_cells(a, b):
		if cell == b:
			continue
		if terrain_at(cell) == "wall":
			return false
		if height_at(cell) - base_height >= 2:
			return false
	return true


static func from_dict(d: Dictionary) -> RefCounted:
	var script: Variant = load("res://core/tactics/grid.gd")
	var grid: Variant = script.new()
	grid.width = int(d.get("width", 0))
	grid.height = int(d.get("height", 0))
	var raw_tiles = d.get("tiles", [])
	var raw_heights = d.get("heights", [])
	var tiles: Array[Array] = []
	var height_rows: Array[Array] = []
	for y in range(grid.height):
		var tile_text := ""
		var height_text := ""
		if raw_tiles is Array and y < raw_tiles.size():
			tile_text = str(raw_tiles[y])
		if raw_heights is Array and y < raw_heights.size():
			height_text = str(raw_heights[y])
		var tile_row: Array = []
		var height_row: Array = []
		for x in range(grid.width):
			var tile_char := tile_text.substr(x, 1)
			tile_row.append(str(CHAR_TERRAIN.get(tile_char, "floor")))
			var height_char := height_text.substr(x, 1)
			height_row.append(int(height_char) if height_char.is_valid_int() else 0)
		tiles.append(tile_row)
		height_rows.append(height_row)
	grid.terrain = tiles
	grid.heights = height_rows
	return grid

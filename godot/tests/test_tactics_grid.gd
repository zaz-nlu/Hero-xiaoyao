extends "res://tests/test_case.gd"

const Grid = preload("res://core/tactics/grid.gd")


func _grid(tiles: Array, heights: Array = []) -> Variant:
	var height := tiles.size()
	var width := 0
	if height > 0:
		width = str(tiles[0]).length()
	return Grid.from_dict({
		"width": width,
		"height": height,
		"tiles": tiles,
		"heights": heights,
	})


func _same_cells(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if a[i] != b[i]:
			return false
	return true


func test_from_dict_parses_terrain_and_heights() -> void:
	var grid = _grid(["..#", "...", "~.b"], ["012", "000", "001"])
	assert_eq(grid.width, 3)
	assert_eq(grid.height, 3)
	assert_eq(grid.terrain_at(Vector2i(0, 0)), "floor")
	assert_eq(grid.terrain_at(Vector2i(2, 0)), "wall")
	assert_eq(grid.terrain_at(Vector2i(0, 2)), "water")
	assert_eq(grid.terrain_at(Vector2i(2, 2)), "bush")
	assert_eq(grid.height_at(Vector2i(0, 0)), 0)
	assert_eq(grid.height_at(Vector2i(1, 0)), 1)
	assert_eq(grid.height_at(Vector2i(2, 0)), 2)
	assert_eq(grid.height_at(Vector2i(2, 2)), 1)


func test_walkable_and_cover() -> void:
	var grid = _grid(["..#", "~.o", "b.f"])
	assert_true(grid.is_walkable(Vector2i(0, 0)), "floor walkable")
	assert_true(grid.is_walkable(Vector2i(0, 2)), "bush walkable")
	assert_true(not grid.is_walkable(Vector2i(2, 0)), "wall blocked")
	assert_true(not grid.is_walkable(Vector2i(0, 1)), "water blocked for now")
	assert_true(not grid.is_walkable(Vector2i(2, 1)), "obstacle blocked")
	assert_true(not grid.is_walkable(Vector2i(2, 2)), "furniture blocked")
	assert_true(not grid.is_walkable(Vector2i(9, 9)), "out of bounds blocked")
	assert_true(grid.is_cover(Vector2i(0, 2)), "bush is cover")
	assert_true(not grid.is_cover(Vector2i(1, 0)), "floor is not cover")


func test_neighbors_filters_bounds_only() -> void:
	var grid = _grid([".#.", ".#.", "..."])
	var corner: Array = grid.neighbors(Vector2i(0, 0))
	assert_eq(corner.size(), 2)
	assert_true(corner.has(Vector2i(1, 0)))
	assert_true(corner.has(Vector2i(0, 1)))
	var middle: Array = grid.neighbors(Vector2i(1, 1))
	assert_eq(middle.size(), 4, "terrain is not filtered")


func test_manhattan() -> void:
	assert_eq(Grid.manhattan(Vector2i(0, 0), Vector2i(3, 4)), 7)
	assert_eq(Grid.manhattan(Vector2i(2, 2), Vector2i(2, 2)), 0)


func test_reachable_open_diamond() -> void:
	var grid = _grid([".....", ".....", ".....", ".....", "....."])
	var result: Dictionary = grid.reachable(Vector2i(2, 2), 2, 1)
	assert_eq(result.size(), 13, "all cells within manhattan 2")
	assert_eq(result.get(Vector2i(2, 2)), 0)
	assert_eq(result.get(Vector2i(2, 0)), 2)
	assert_eq(result.get(Vector2i(4, 2)), 2)
	assert_true(not result.has(Vector2i(0, 0)), "outside move range")


func test_reachable_routes_around_obstacle() -> void:
	var grid = _grid([".....", ".#...", "....."])
	var result: Dictionary = grid.reachable(Vector2i(0, 1), 4, 1)
	assert_eq(result.get(Vector2i(2, 1)), 4, "detour around the wall")
	assert_true(not grid.reachable(Vector2i(0, 1), 3, 1).has(Vector2i(2, 1)), "too far in 3 points")


func test_reachable_blocked_and_allies() -> void:
	var grid = _grid(["...", "...", "..."])
	var blocked: Dictionary = grid.reachable(Vector2i(0, 0), 2, 1, {Vector2i(1, 0): true})
	assert_true(not blocked.has(Vector2i(1, 0)), "enemy cell is impassable")
	assert_true(not blocked.has(Vector2i(2, 0)), "enemy blocks the path")
	var allies: Dictionary = grid.reachable(Vector2i(0, 0), 2, 1, {}, {Vector2i(1, 0): true})
	assert_eq(allies.get(Vector2i(1, 0)), 1, "ally cell is passable")
	assert_eq(allies.get(Vector2i(2, 0)), 2, "walking through an ally continues")
	var to_ally: Array = grid.path(Vector2i(0, 0), Vector2i(1, 0), 2, 1, {}, {Vector2i(1, 0): true})
	assert_eq(to_ally.size(), 0, "cannot stop on an ally")


func test_reachable_honors_climb_limit() -> void:
	var grid = _grid(["...", "..."], ["012", "000"])
	var flat: Dictionary = grid.reachable(Vector2i(0, 0), 2, 0)
	assert_true(not flat.has(Vector2i(1, 0)), "height step of 1 needs climb 1")
	var climbing: Dictionary = grid.reachable(Vector2i(0, 0), 2, 1)
	assert_eq(climbing.get(Vector2i(1, 0)), 1)
	assert_eq(climbing.get(Vector2i(2, 0)), 2)


func test_path_is_shortest_and_prefers_horizontal() -> void:
	var grid = _grid(["...", "...", "..."])
	var route: Array = grid.path(Vector2i(0, 0), Vector2i(2, 2), 4, 1)
	assert_eq(route.size(), 5)
	assert_eq(route[0], Vector2i(0, 0))
	assert_eq(route[1], Vector2i(1, 0), "horizontal first on ties")
	assert_eq(route[route.size() - 1], Vector2i(2, 2))
	var again: Array = grid.path(Vector2i(0, 0), Vector2i(2, 2), 4, 1)
	assert_true(_same_cells(again, route), "path is deterministic")


func test_path_detours_around_wall() -> void:
	var grid = _grid(["...", ".#.", "..."])
	var route: Array = grid.path(Vector2i(0, 1), Vector2i(2, 1), 4, 1)
	assert_eq(route.size(), 5, "wall forces a detour")
	assert_true(not route.has(Vector2i(1, 1)), "wall cell is not used")
	assert_true(route.has(Vector2i(0, 0)), "detour goes through a free neighbour")


func test_path_rejects_unreachable() -> void:
	var grid = _grid(["...", "..."])
	assert_eq(grid.path(Vector2i(0, 0), Vector2i(2, 1), 2, 1).size(), 0, "not enough move points")
	assert_eq(grid.path(Vector2i(0, 0), Vector2i(2, 0), 5, 1, {Vector2i(2, 0): true}).size(), 0, "blocked goal")


func test_line_cells_includes_end_not_start() -> void:
	var grid = _grid([".....", "....."])
	var line: Array = grid.line_cells(Vector2i(0, 0), Vector2i(3, 0))
	assert_eq(line.size(), 3)
	assert_eq(line[0], Vector2i(1, 0))
	assert_eq(line[1], Vector2i(2, 0))
	assert_eq(line[2], Vector2i(3, 0))
	assert_eq(grid.line_cells(Vector2i(2, 2), Vector2i(2, 2)).size(), 0)
	var diagonal: Array = grid.line_cells(Vector2i(0, 0), Vector2i(2, 2))
	assert_eq(diagonal.size(), 2)
	assert_eq(diagonal[0], Vector2i(1, 1))
	assert_eq(diagonal[1], Vector2i(2, 2))


func test_line_of_sight_wall_and_height() -> void:
	var wall_grid = _grid(["..#.."])
	assert_true(not wall_grid.has_line_of_sight(Vector2i(0, 0), Vector2i(4, 0)), "wall blocks sight")
	assert_true(wall_grid.has_line_of_sight(Vector2i(0, 0), Vector2i(1, 0)), "no cell in between")
	var flat_grid = _grid(["....."], ["01000"])
	assert_true(flat_grid.has_line_of_sight(Vector2i(0, 0), Vector2i(4, 0)), "one level higher does not block")
	var ridge_grid = _grid(["....."], ["02000"])
	assert_true(not ridge_grid.has_line_of_sight(Vector2i(0, 0), Vector2i(4, 0)), "two levels higher blocks")

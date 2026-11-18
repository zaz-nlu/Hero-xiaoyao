extends "res://tests/test_case.gd"

const Facing = preload("res://core/tactics/facing.gd")
const Pattern = preload("res://core/tactics/pattern.gd")
const Grid = preload("res://core/tactics/grid.gd")


func _open_grid(width: int, height: int) -> Variant:
	var tiles: Array = []
	for _y in range(height):
		tiles.append(".".repeat(width))
	return Grid.from_dict({"width": width, "height": height, "tiles": tiles})


func test_facing_relation_cardinal() -> void:
	var defender := Vector2i(2, 2)
	assert_eq(Facing.relation(defender, Facing.UP, Vector2i(2, 1)), "front")
	assert_eq(Facing.relation(defender, Facing.UP, Vector2i(2, 3)), "back")
	assert_eq(Facing.relation(defender, Facing.UP, Vector2i(1, 2)), "side")
	assert_eq(Facing.relation(defender, Facing.UP, Vector2i(3, 2)), "side")
	assert_eq(Facing.relation(defender, Facing.UP, defender), "front", "same cell counts as front")
	assert_eq(Facing.relation(defender, Facing.RIGHT, Vector2i(3, 2)), "front")
	assert_eq(Facing.relation(defender, Facing.RIGHT, Vector2i(1, 2)), "back")


func test_facing_relation_diagonal() -> void:
	var defender := Vector2i(2, 2)
	assert_eq(Facing.relation(defender, Facing.UP, Vector2i(3, 1)), "front", "45 degrees up-right is front")
	assert_eq(Facing.relation(defender, Facing.UP, Vector2i(1, 1)), "front", "45 degrees up-left is front")
	assert_eq(Facing.relation(defender, Facing.UP, Vector2i(3, 3)), "back", "135 degrees down-right is back")
	assert_eq(Facing.relation(defender, Facing.UP, Vector2i(1, 3)), "back", "135 degrees down-left is back")
	assert_eq(Facing.relation(defender, Facing.RIGHT, Vector2i(3, 3)), "front", "45 degrees ahead-right is front")
	assert_eq(Facing.relation(defender, Facing.RIGHT, Vector2i(1, 3)), "back")


func test_facing_helpers() -> void:
	assert_eq(Facing.from_delta(Vector2i(3, 1), Facing.DOWN), Facing.RIGHT, "horizontal wins ties")
	assert_eq(Facing.from_delta(Vector2i(1, 3), Facing.RIGHT), Facing.DOWN)
	assert_eq(Facing.from_delta(Vector2i(-2, 0), Facing.UP), Facing.LEFT)
	assert_eq(Facing.from_delta(Vector2i.ZERO, Facing.LEFT), Facing.LEFT)
	assert_eq(Facing.opposite(Facing.UP), Facing.DOWN)
	assert_eq(Facing.opposite(Facing.RIGHT), Facing.LEFT)


func test_pattern_normalize_defaults_and_fallback() -> void:
	var melee: Dictionary = Pattern.normalize({})
	assert_eq(melee["shape"], "melee")
	assert_eq(melee["min"], 1)
	assert_eq(melee["max"], 1)
	assert_eq(melee["width"], 1)
	assert_eq(melee["pierce"], false)
	var bad: Dictionary = Pattern.normalize({"shape": "ray"})
	assert_eq(bad["shape"], "melee", "unknown shape falls back to melee")
	var line: Dictionary = Pattern.normalize({"shape": "line", "min": 0, "max": 2, "pierce": true})
	assert_eq(line["min"], 1, "min is at least 1")
	assert_eq(line["max"], 2)
	assert_eq(line["pierce"], true)


func test_target_cells_melee() -> void:
	var grid = _open_grid(7, 7)
	var cells: Array = Pattern.target_cells({"shape": "melee"}, Vector2i(3, 3), Facing.UP, grid)
	assert_eq(cells.size(), 4)
	assert_true(cells.has(Vector2i(3, 2)))
	assert_true(cells.has(Vector2i(3, 4)))
	assert_true(cells.has(Vector2i(2, 3)))
	assert_true(cells.has(Vector2i(4, 3)))
	assert_true(not cells.has(Vector2i(3, 3)), "origin is excluded")
	var two: Array = Pattern.target_cells({"shape": "melee", "min": 2, "max": 2}, Vector2i(3, 3), Facing.UP, grid)
	assert_eq(two.size(), 8, "manhattan ring at distance 2")


func test_target_cells_line_stops_at_wall() -> void:
	var grid = Grid.from_dict({"width": 7, "height": 1, "tiles": ["...#..."]})
	var cells: Array = Pattern.target_cells({"shape": "line", "min": 1, "max": 5}, Vector2i(0, 0), Facing.RIGHT, grid)
	assert_eq(cells.size(), 2)
	assert_true(cells.has(Vector2i(1, 0)))
	assert_true(cells.has(Vector2i(2, 0)))
	assert_true(not cells.has(Vector2i(3, 0)), "the wall itself is not targetable")


func test_target_cells_ranged_needs_line_of_sight() -> void:
	var grid = _open_grid(7, 7)
	var cells: Array = Pattern.target_cells({"shape": "ranged", "min": 2, "max": 3}, Vector2i(0, 0), Facing.RIGHT, grid)
	assert_true(cells.has(Vector2i(2, 0)))
	assert_true(cells.has(Vector2i(3, 0)))
	assert_true(cells.has(Vector2i(1, 1)))
	assert_true(not cells.has(Vector2i(0, 1)), "min range excludes distance 1")
	assert_true(not cells.has(Vector2i(4, 0)), "max range excludes distance 4")
	var blocked = Grid.from_dict({"width": 5, "height": 1, "tiles": [".#..."]})
	var blocked_cells: Array = Pattern.target_cells({"shape": "ranged", "min": 2, "max": 3}, Vector2i(0, 0), Facing.RIGHT, blocked)
	assert_eq(blocked_cells.size(), 0, "wall blocks line of sight")


func test_target_cells_cone_widens() -> void:
	var grid = _open_grid(7, 7)
	var cells: Array = Pattern.target_cells({"shape": "cone", "min": 1, "max": 3}, Vector2i(0, 2), Facing.RIGHT, grid)
	assert_eq(cells.size(), 1 + 3 + 5)
	assert_true(cells.has(Vector2i(1, 2)), "distance 1 is one wide")
	assert_true(cells.has(Vector2i(2, 1)))
	assert_true(cells.has(Vector2i(2, 3)))
	assert_true(cells.has(Vector2i(3, 0)))
	assert_true(cells.has(Vector2i(3, 4)))
	assert_true(not cells.has(Vector2i(1, 1)), "width is 1 at distance 1")


func test_target_cells_burst_diamond() -> void:
	var grid = _open_grid(7, 7)
	var cells: Array = Pattern.target_cells({"shape": "burst", "max": 2}, Vector2i(3, 3), Facing.UP, grid)
	assert_eq(cells.size(), 12, "manhattan radius 2 minus the origin")
	assert_true(cells.has(Vector2i(3, 1)))
	assert_true(cells.has(Vector2i(5, 3)))
	assert_true(not cells.has(Vector2i(5, 5)), "outside the diamond")


func test_affected_melee_and_ranged_are_single_target() -> void:
	var grid = _open_grid(7, 7)
	var melee: Array = Pattern.affected_cells({"shape": "melee"}, Vector2i(3, 3), Facing.UP, Vector2i(3, 2), grid)
	assert_eq(melee.size(), 1)
	assert_eq(melee[0], Vector2i(3, 2))
	var ranged: Array = Pattern.affected_cells({"shape": "ranged", "min": 2, "max": 5}, Vector2i(0, 0), Facing.RIGHT, Vector2i(2, 0), grid)
	assert_eq(ranged.size(), 1)
	assert_eq(ranged[0], Vector2i(2, 0))


func test_affected_line_and_pierce() -> void:
	var grid = _open_grid(7, 7)
	var line: Array = Pattern.affected_cells({"shape": "line", "min": 1, "max": 3}, Vector2i(0, 2), Facing.RIGHT, Vector2i(3, 2), grid)
	assert_eq(line.size(), 3)
	assert_eq(line[0], Vector2i(1, 2))
	assert_eq(line[2], Vector2i(3, 2))
	var pierced: Array = Pattern.affected_cells({"shape": "line", "min": 1, "max": 5, "pierce": true}, Vector2i(0, 2), Facing.RIGHT, Vector2i(2, 2), grid)
	assert_eq(pierced.size(), 5)
	assert_eq(pierced[4], Vector2i(5, 2), "pierce continues past the target")


func test_affected_cone_is_cross_section() -> void:
	var grid = _open_grid(7, 7)
	var cells: Array = Pattern.affected_cells({"shape": "cone", "max": 3}, Vector2i(0, 2), Facing.RIGHT, Vector2i(2, 1), grid)
	assert_eq(cells.size(), 3)
	assert_true(cells.has(Vector2i(2, 1)))
	assert_true(cells.has(Vector2i(2, 2)))
	assert_true(cells.has(Vector2i(2, 3)))


func test_affected_burst_diamond() -> void:
	var grid = _open_grid(7, 7)
	var cells: Array = Pattern.affected_cells({"shape": "burst", "max": 2}, Vector2i(3, 3), Facing.UP, Vector2i(3, 3), grid)
	assert_eq(cells.size(), 12)
	assert_true(not cells.has(Vector2i(3, 3)), "origin is not affected")

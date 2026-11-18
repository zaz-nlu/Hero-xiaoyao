extends RefCounted

# 森林空间数据：加载后的 JSON、边界/道路/出口/采集点/藏身点，
# 以及生成阶段产出的树、岩石与碰撞矩形。这里只做数据与几何查询，
# 不感知玩家、任务、奖励或警报状态。

const Pickups = preload("res://shared/gameplay/pickups.gd")

const FOREST_PATH := "res://data/forest.json"
const TREE_SEED := 20261117
const TREE_GAP := 1.6
const ROAD_CLEARANCE := 2.5
const ARENA_CLEARANCE := 9.0
const SPAWN_CLEARANCE := 3.0
const CHEST_CLEARANCE := 2.5
const HERB_CLEARANCE := 1.5
const EXIT_CLEARANCE := 1.0
const BOUNDS_INSET := 0.8
const CAMP_CLEAR_RADIUS := 2.5

var data: Dictionary = {}
var bounds_rect: Rect2 = Rect2()
var arena_origin: Vector3 = Vector3.ZERO
var exits: Dictionary = {}
var hide_spots: Array = []
var pickups: Array = []
var tree_positions: Array[Vector2] = []
var rock_positions: Array[Vector2] = []
var blockers: Array = []
var road_points: Array[Vector2] = []
var spawn: Dictionary = {}
# 树生成阶段在 blockers 中的起点；第 i 棵树的碰撞矩形是
# blockers[tree_blocker_offset + i]，由 move_tree() 维护。
var tree_blocker_offset: int = 0


func build(path: String = FOREST_PATH) -> void:
	load_data(path)
	begin_generation()


func load_data(path: String = FOREST_PATH) -> void:
	data = {}
	exits.clear()
	pickups.clear()
	hide_spots.clear()
	road_points.clear()
	if not FileAccess.file_exists(path):
		push_warning("forest: %s not found" % path)
		return
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("forest: invalid JSON in %s" % path)
		return
	data = parsed
	bounds_rect = _read_bounds()
	spawn = _read_spawn()
	arena_origin = _read_arena_origin()
	road_points = _read_road()
	_read_exits()
	_read_pickups()
	_read_hide_spots()


func begin_generation() -> void:
	blockers.clear()
	tree_positions.clear()
	rock_positions.clear()
	tree_blocker_offset = blockers.size()


# ---------------------------------------------------------------- parsing

func _read_bounds() -> Rect2:
	var bounds_value: Variant = data.get("bounds", null)
	if not (bounds_value is Dictionary):
		return Rect2()
	var bounds: Dictionary = bounds_value
	var x0 := float(bounds.get("x0", 0.0))
	var x1 := float(bounds.get("x1", 0.0))
	var z0 := float(bounds.get("z0", 0.0))
	var z1 := float(bounds.get("z1", 0.0))
	return Rect2(x0, z0, x1 - x0, z1 - z0)


func _read_spawn() -> Dictionary:
	var spawn_value: Variant = data.get("spawn", null)
	if spawn_value is Dictionary:
		return spawn_value
	return {}


func _read_arena_origin() -> Vector3:
	var arena_value: Variant = data.get("arena", null)
	if not (arena_value is Dictionary):
		return Vector3.ZERO
	var arena: Dictionary = arena_value
	var origin_value: Variant = arena.get("origin", null)
	if origin_value is Array:
		var origin: Array = origin_value
		if origin.size() >= 3:
			return Vector3(float(origin[0]), float(origin[1]), float(origin[2]))
	return Vector3.ZERO


func _read_road() -> Array[Vector2]:
	var result: Array[Vector2] = []
	var road_value: Variant = data.get("road", [])
	if not (road_value is Array):
		return result
	var road: Array = road_value
	for point_value in road:
		if not (point_value is Array):
			continue
		var point: Array = point_value
		if point.size() < 2:
			continue
		result.append(Vector2(float(point[0]), float(point[1])))
	return result


func _read_exits() -> void:
	var exits_value: Variant = data.get("exits", {})
	if not (exits_value is Dictionary):
		return
	var exit_entries: Dictionary = exits_value
	for key in exit_entries.keys():
		var entry_value: Variant = exit_entries[key]
		if not (entry_value is Dictionary):
			continue
		var entry: Dictionary = entry_value
		var rect: Rect2 = rect_from_array(entry.get("rect", []))
		if rect.size == Vector2.ZERO:
			continue
		exits[str(key)] = {"rect": rect, "prompt": str(entry.get("prompt", ""))}


func _read_pickups() -> void:
	pickups = Pickups.parse_entries(data.get("pickups", []))


func _read_hide_spots() -> void:
	var hide_data: Array = data.get("hide_spots", [])
	for hide_value in hide_data:
		if not (hide_value is Dictionary):
			continue
		var hide: Dictionary = hide_value
		hide_spots.append({
			"pos": Vector2(float(hide.get("x", 0.0)), float(hide.get("z", 0.0))),
			"radius": float(hide.get("radius", 1.8)),
			"road": bool(hide.get("road", false)),
		})


func rect_from_array(value: Variant) -> Rect2:
	if not (value is Array):
		return Rect2()
	var rect: Array = value
	if rect.size() < 4:
		return Rect2()
	var x0 := float(rect[0])
	var z0 := float(rect[1])
	var x1 := float(rect[2])
	var z1 := float(rect[3])
	if x1 <= x0 or z1 <= z0:
		return Rect2()
	return Rect2(x0, z0, x1 - x0, z1 - z0)


# ---------------------------------------------------------------- geometry

func in_bounds(point: Vector2) -> bool:
	if bounds_rect.size == Vector2.ZERO:
		return true
	return point.x >= bounds_rect.position.x + BOUNDS_INSET \
		and point.x <= bounds_rect.end.x - BOUNDS_INSET \
		and point.y >= bounds_rect.position.y + BOUNDS_INSET \
		and point.y <= bounds_rect.end.y - BOUNDS_INSET


func spawn_point() -> Vector2:
	return Vector2(
		float(spawn.get("x", 0.0)),
		float(spawn.get("z", 21.5))
	)


func road_distance(point: Vector2) -> float:
	if road_points.size() < 2:
		return 9999.0
	var best := 9999.0
	for i in range(road_points.size() - 1):
		var a: Vector2 = road_points[i]
		var b: Vector2 = road_points[i + 1]
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(point, a, b)
		best = minf(best, point.distance_to(closest))
	return best


func point_blocked(point: Vector2, radius: float) -> bool:
	for value in blockers:
		var rect: Rect2 = value
		if rect.grow(radius).has_point(point):
			return true
	return false


func is_clear(
	point: Vector2, road_clearance: float, arena_clearance: float, tree_gap: float
) -> bool:
	if not in_bounds(point):
		return false
	if road_distance(point) < road_clearance:
		return false
	if point.distance_to(spawn_point()) < SPAWN_CLEARANCE:
		return false
	if point.distance_to(Vector2(arena_origin.x, arena_origin.z)) < arena_clearance:
		return false
	for pickup_value in pickups:
		var pickup: Dictionary = pickup_value
		var pos_value: Variant = pickup.get("pos", Vector2.ZERO)
		if not (pos_value is Vector2):
			continue
		var radius := HERB_CLEARANCE
		if str(pickup.get("kind", "herb")) == "chest":
			radius = CHEST_CLEARANCE
		var pickup_pos: Vector2 = pos_value
		if point.distance_to(pickup_pos) < radius:
			return false
	for key in exits.keys():
		var entry_value: Variant = exits[key]
		if not (entry_value is Dictionary):
			continue
		var entry: Dictionary = entry_value
		var rect_value: Variant = entry.get("rect", Rect2())
		if not (rect_value is Rect2):
			continue
		var exit_rect: Rect2 = rect_value
		if exit_rect.grow(EXIT_CLEARANCE).has_point(point):
			return false
	for other_value in tree_positions:
		var other: Vector2 = other_value
		if point.distance_to(other) < tree_gap:
			return false
	return true


func camp_position() -> Vector2:
	var camp_value: Variant = data.get("camp", null)
	if camp_value is Dictionary:
		var camp: Dictionary = camp_value
		var pos_value: Variant = camp.get("pos", null)
		if pos_value is Array:
			var pos: Array = pos_value
			if pos.size() >= 2:
				return Vector2(float(pos[0]), float(pos[1]))
	return Vector2(-12.0, 4.0)


# ---------------------------------------------------------------- generated data

func tree_blocker_index(index: int) -> int:
	return tree_blocker_offset + index


func add_tree(point: Vector2) -> void:
	tree_positions.append(point)
	blockers.append(Rect2(point.x - 0.5, point.y - 0.5, 1.0, 1.0))


func move_tree(index: int, point: Vector2) -> void:
	if index < 0 or index >= tree_positions.size():
		return
	tree_positions[index] = point
	var blocker_index := tree_blocker_index(index)
	if blocker_index >= 0 and blocker_index < blockers.size():
		blockers[blocker_index] = Rect2(point.x - 0.5, point.y - 0.5, 1.0, 1.0)


func add_rock(point: Vector2) -> void:
	rock_positions.append(point)
	blockers.append(Rect2(point.x - 0.5, point.y - 0.5, 1.0, 1.0))


func add_blocker(rect: Rect2) -> void:
	blockers.append(rect)

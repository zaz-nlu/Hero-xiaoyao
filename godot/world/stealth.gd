extends RefCounted

# Pure helpers for the forest stealth layer. Everything here works on the 2D xz
# plane (Vector2(x, z)) so it can be unit-tested without a scene tree.

const BASE_VIEW_DISTANCE := 6.5
const VIEW_HALF_ANGLE := PI * 40.0 / 180.0
const CROUCH_VIEW_MULT := 0.5
const HIDE_VIEW_DISTANCE := 1.5
const BEHIND_ANGLE := PI * 120.0 / 180.0
const SNEAK_RANGE := 1.8
const CLOSE_SNEAK_RANGE := 1.0


static func to_vec2(value: Variant) -> Vector2:
	if value is Vector2:
		var vec: Vector2 = value
		return vec
	if value is Array:
		var point: Array = value
		if point.size() >= 2:
			return Vector2(float(point[0]), float(point[1]))
	return Vector2.ZERO


static func angle_of(v: Vector2) -> float:
	return atan2(v.y, v.x)


static func direction(angle: float) -> Vector2:
	return Vector2(cos(angle), sin(angle))


static func angle_gap(a: float, b: float) -> float:
	return absf(wrapf(a - b, -PI, PI))


static func facing_angle(facing: String) -> float:
	match facing:
		"up":
			return -PI * 0.5
		"left":
			return PI
		"right":
			return 0.0
		_:
			return PI * 0.5


static func facing_from_vector(v: Vector2, current: String = "down") -> String:
	if v.length_squared() < 0.000001:
		return current
	if absf(v.x) >= absf(v.y):
		return "right" if v.x > 0.0 else "left"
	return "down" if v.y > 0.0 else "up"


# Crouching halves the reach; crouching inside a hide spot drops it to 1.5.
static func view_distance(base: float, crouched: bool, in_hide_spot: bool) -> float:
	if not crouched:
		return base
	if in_hide_spot:
		return HIDE_VIEW_DISTANCE
	return base * CROUCH_VIEW_MULT


static func in_cone(
	guard_pos: Vector2,
	facing: float,
	player_pos: Vector2,
	reach: float,
	half_angle: float
) -> bool:
	var to_player := player_pos - guard_pos
	var dist := to_player.length()
	if dist > reach:
		return false
	if dist <= 0.0001:
		return true
	return angle_gap(angle_of(to_player), facing) <= half_angle


static func segment_blocked(a: Vector2, b: Vector2, blockers: Array) -> bool:
	for blocker_value in blockers:
		if not (blocker_value is Rect2):
			continue
		var blocker: Rect2 = blocker_value
		if _segment_hits_rect(a, b, blocker):
			return true
	return false


static func _segment_hits_rect(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	var seg_box := Rect2(a, Vector2.ZERO).expand(b)
	if not seg_box.intersects(rect):
		return false
	if rect.has_point(a) or rect.has_point(b):
		return true
	var corners: Array[Vector2] = [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	]
	for i in range(4):
		var hit: Variant = Geometry2D.segment_intersects_segment(
			a, b, corners[i], corners[(i + 1) % 4]
		)
		if hit != null:
			return true
	return false


static func sees(
	guard_pos: Vector2,
	facing: float,
	player_pos: Vector2,
	reach: float,
	half_angle: float,
	blockers: Array
) -> bool:
	if not in_cone(guard_pos, facing, player_pos, reach, half_angle):
		return false
	return not segment_blocked(guard_pos, player_pos, blockers)


static func is_behind(
	guard_pos: Vector2,
	facing: float,
	player_pos: Vector2,
	threshold: float = -1.0
) -> bool:
	if threshold < 0.0:
		threshold = BEHIND_ANGLE
	var to_player := player_pos - guard_pos
	if to_player.length_squared() < 0.000001:
		return false
	return angle_gap(angle_of(to_player), facing) > threshold


# Behind within 1.8 units, or outside the vision cone within 1.0 units.
static func can_sneak(
	guard_pos: Vector2,
	facing: float,
	player_pos: Vector2,
	in_view: bool
) -> bool:
	var dist := guard_pos.distance_to(player_pos)
	if dist > SNEAK_RANGE:
		return false
	if is_behind(guard_pos, facing, player_pos):
		return true
	return dist <= CLOSE_SNEAK_RANGE and not in_view


static func is_walkable(point: Vector2, blockers: Array, bounds: Rect2) -> bool:
	if bounds.size != Vector2.ZERO:
		if point.x < bounds.position.x or point.x > bounds.end.x \
				or point.y < bounds.position.y or point.y > bounds.end.y:
			return false
	for blocker_value in blockers:
		if not (blocker_value is Rect2):
			continue
		var blocker: Rect2 = blocker_value
		if blocker.has_point(point):
			return false
	return true


static func nearest_road_point(point: Vector2, road: Array) -> Vector2:
	if road.is_empty():
		return point
	if road.size() == 1:
		return to_vec2(road[0])
	var best := point
	var best_dist := INF
	for i in range(road.size() - 1):
		var a: Vector2 = to_vec2(road[i])
		var b: Vector2 = to_vec2(road[i + 1])
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(point, a, b)
		var dist := point.distance_squared_to(closest)
		if dist < best_dist:
			best_dist = dist
			best = closest
	return best


# Snaps unwalkable route points onto the road, then inserts road detours for any
# straight leg that would cut through a tree or rock blocker.
static func sanitize_route(
	points: Array, blockers: Array, bounds: Rect2, road: Array
) -> Array:
	var snapped: Array = []
	for value in points:
		var point: Vector2 = to_vec2(value)
		if not is_walkable(point, blockers, bounds):
			point = nearest_road_point(point, road)
		snapped.append(point)
	var result: Array = []
	for i in range(snapped.size()):
		var point: Vector2 = snapped[i]
		if i > 0:
			var previous: Vector2 = snapped[i - 1]
			result.append_array(_detour(previous, point, blockers, road, 3))
		result.append(point)
	return result


static func _detour(
	a: Vector2, b: Vector2, blockers: Array, road: Array, depth: int
) -> Array:
	if not segment_blocked(a, b, blockers):
		return []
	if depth <= 0 or road.is_empty():
		return []
	var midpoint: Vector2 = (a + b) * 0.5
	var via: Vector2 = nearest_road_point(midpoint, road)
	if via.distance_to(a) < 0.01 or via.distance_to(b) < 0.01:
		return []
	var raw: Array = []
	raw.append_array(_detour(a, via, blockers, road, depth - 1))
	raw.append(via)
	raw.append_array(_detour(via, b, blockers, road, depth - 1))
	var clean: Array = []
	for value in raw:
		var point: Vector2 = value
		if clean.is_empty():
			clean.append(point)
			continue
		var last: Vector2 = clean[clean.size() - 1]
		if last.distance_to(point) > 0.01:
			clean.append(point)
	return clean

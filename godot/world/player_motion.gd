extends RefCounted

const RADIUS := 0.4
const SPEED := 5.0


static func facing_from_input(input: Vector2, current: String) -> String:
	if input == Vector2.ZERO:
		return current
	if absf(input.x) >= absf(input.y):
		if input.x > 0.0:
			return "right"
		return "left"
	if input.y > 0.0:
		return "down"
	return "up"


static func blocked(pos: Vector2, blockers: Array) -> bool:
	for blocker_value in blockers:
		if typeof(blocker_value) != TYPE_RECT2:
			continue
		var blocker: Rect2 = blocker_value
		if blocker.grow(RADIUS).has_point(pos):
			return true
	return false


static func step(
	pos: Vector2, input: Vector2, delta: float, blockers: Array, bounds: Rect2
) -> Vector2:
	var move := input
	if move.length() > 1.0:
		move = move.normalized()
	var displacement := move * SPEED * delta
	var result := pos
	var try_x := Vector2(result.x + displacement.x, result.y)
	if not blocked(try_x, blockers):
		result.x = try_x.x
	var try_z := Vector2(result.x, result.y + displacement.y)
	if not blocked(try_z, blockers):
		result.y = try_z.y
	if bounds.size == Vector2.ZERO:
		return result
	result.x = clampf(result.x, bounds.position.x + RADIUS, bounds.end.x - RADIUS)
	result.y = clampf(result.y, bounds.position.y + RADIUS, bounds.end.y - RADIUS)
	return result

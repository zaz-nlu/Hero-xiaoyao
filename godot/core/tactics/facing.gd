extends RefCounted

const UP := Vector2i.UP
const DOWN := Vector2i.DOWN
const LEFT := Vector2i.LEFT
const RIGHT := Vector2i.RIGHT


static func from_delta(delta: Vector2i, fallback: Vector2i) -> Vector2i:
	if delta == Vector2i.ZERO:
		return fallback
	if absi(delta.x) >= absi(delta.y):
		return RIGHT if delta.x > 0 else LEFT
	return DOWN if delta.y > 0 else UP


static func opposite(facing: Vector2i) -> Vector2i:
	return -facing


static func relation(defender_pos: Vector2i, defender_facing: Vector2i, attacker_pos: Vector2i) -> String:
	var delta := attacker_pos - defender_pos
	if delta == Vector2i.ZERO:
		return "front"
	var facing := defender_facing
	if facing == Vector2i.ZERO:
		facing = DOWN
	var dot_value := float(facing.x * delta.x + facing.y * delta.y)
	var cross_value := float(facing.x * delta.y - facing.y * delta.x)
	var angle := absf(atan2(cross_value, dot_value)) * 180.0 / PI
	if angle <= 45.0 + 0.0001:
		return "front"
	if angle >= 135.0 - 0.0001:
		return "back"
	return "side"

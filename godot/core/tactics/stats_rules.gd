extends RefCounted

const React_SLACK := 5
const BACK_BONUS := 0.50
const SIDE_BONUS := 0.20
const HEIGHT_BONUS_PER_LEVEL := 0.10
const HEIGHT_BONUS_MAX := 0.30


static func move_range(speed: int) -> int:
	return mini(8, 3 + int(speed / 10.0))


static func max_climb(skill: int) -> int:
	return 1 + int(skill / 30.0)


static func reaction_points(skill: int) -> int:
	return 1 + int(skill / 15.0)


static func height_bonus(attacker_h: int, defender_h: int) -> float:
	var bonus := float(attacker_h - defender_h) * HEIGHT_BONUS_PER_LEVEL
	return clampf(bonus, 0.0, HEIGHT_BONUS_MAX)


static func facing_bonus(relation: String) -> float:
	if relation == "back":
		return BACK_BONUS
	if relation == "side":
		return SIDE_BONUS
	return 0.0

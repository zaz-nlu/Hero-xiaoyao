extends RefCounted

const Stats = preload("res://core/stats.gd")

enum Verdict { IMPOSSIBLE = 0, BARELY = 1, ADVANTAGE = 2 }


static func evaluate(
	martial,
	user_stats: Dictionary,
	enemy_speed: int,
	move: Dictionary,
	first_strike: bool
) -> int:
	if not martial.counters.has(str(move.get("type", ""))):
		return Verdict.IMPOSSIBLE

	var speed_delta: float = (int(user_stats["speed"]) - enemy_speed) / 5.0
	var speed_mod: int = clampi(floori(speed_delta), -3, 3)
	var counter_power: int = int(user_stats["skill"]) + int(martial.counter_level) + speed_mod
	var gap: int = counter_power - int(move.get("threat", 0))
	if gap < -5:
		return Verdict.IMPOSSIBLE

	var fast: bool = first_strike \
			or (int(user_stats["speed"]) + int(martial.initiative) >= enemy_speed)
	if fast and gap >= 0:
		return Verdict.ADVANTAGE
	return Verdict.BARELY


static func is_perfect(
	verdict: int,
	martial,
	user_stats: Dictionary,
	weak_moves: Array,
	move_id: String
) -> bool:
	if verdict != Verdict.ADVANTAGE:
		return false
	if not weak_moves.has(move_id):
		return false
	return Stats.top_keys(user_stats).has(martial.advantage_stat)


static func toughness_cost(verdict: int, perfect: bool) -> float:
	if perfect:
		return 2.0
	match verdict:
		Verdict.ADVANTAGE:
			return 1.0
		Verdict.BARELY:
			return 0.5
		_:
			return 0.0

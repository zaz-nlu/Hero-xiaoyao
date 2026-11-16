extends RefCounted


static func choose(moves: Array, rng: RandomNumberGenerator) -> Dictionary:
	if moves.is_empty():
		return {}
	var index: int = rng.randi_range(0, moves.size() - 1)
	var picked: Dictionary = moves[index]
	return picked

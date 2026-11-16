extends RefCounted

const KEYS: Array[String] = ["power", "speed", "defense", "recovery", "skill", "mechanism"]


static func top_keys(stats: Dictionary) -> Array[String]:
	var top: Array[String] = []
	var best_value = null
	for key in KEYS:
		if not stats.has(key):
			continue
		var value = stats[key]
		if best_value == null or value > best_value:
			best_value = value
			top.clear()
			top.append(key)
		elif value == best_value:
			top.append(key)
	return top

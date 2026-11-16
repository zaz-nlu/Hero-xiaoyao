extends RefCounted

static var flags: Dictionary = {}
static var town_return_pos: Variant = null


static func set_flag(key: String, value: bool = true) -> void:
	flags[key] = value


static func has_flag(key: String) -> bool:
	return bool(flags.get(key, false))


static func reset() -> void:
	flags.clear()
	town_return_pos = null

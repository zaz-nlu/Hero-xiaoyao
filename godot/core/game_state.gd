extends RefCounted

static var flags: Dictionary = {}


static func set_flag(key: String, value: bool = true) -> void:
	flags[key] = value


static func has_flag(key: String) -> bool:
	return bool(flags.get(key, false))


static func reset() -> void:
	flags.clear()

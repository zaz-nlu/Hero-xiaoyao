extends RefCounted

static var flags: Dictionary = {}
static var town_return_pos: Variant = null
static var known_moves: Dictionary = {}
static var stat_bonus: Dictionary = {}
static var equipment: Dictionary = {}
static var inventory: Dictionary = {}
static var quests: Dictionary = {}
static var mastery_exp: Dictionary = {}
static var toasts: Array = []


static func set_flag(key: String, value: bool = true) -> void:
	flags[key] = value


static func has_flag(key: String) -> bool:
	return bool(flags.get(key, false))


static func reset() -> void:
	flags.clear()
	town_return_pos = null
	known_moves.clear()
	stat_bonus.clear()
	equipment.clear()
	inventory.clear()
	quests.clear()
	mastery_exp.clear()
	toasts.clear()

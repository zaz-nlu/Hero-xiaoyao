extends RefCounted

const INITIAL_POINTS := 3

static var flags: Dictionary = {}
static var town_return_pos: Variant = null
static var forest_return_pos: Variant = null
static var battle_backdrop: String = "town"
static var known_moves: Dictionary = {}
static var stat_bonus: Dictionary = {}
static var equipment: Dictionary = {}
static var inventory: Dictionary = {}
static var quests: Dictionary = {}
static var mastery_exp: Dictionary = {}
static var mastery_total: Dictionary = {}
static var unspent_points: int = INITIAL_POINTS
static var toasts: Array = []


static func set_flag(key: String, value: bool = true) -> void:
	flags[key] = value


static func has_flag(key: String) -> bool:
	return bool(flags.get(key, false))


static func reset() -> void:
	flags.clear()
	town_return_pos = null
	forest_return_pos = null
	battle_backdrop = "town"
	known_moves.clear()
	stat_bonus.clear()
	equipment.clear()
	inventory.clear()
	quests.clear()
	mastery_exp.clear()
	mastery_total.clear()
	unspent_points = INITIAL_POINTS
	toasts.clear()

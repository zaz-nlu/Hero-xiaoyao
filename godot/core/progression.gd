extends RefCounted

const DataLoader = preload("res://core/data_loader.gd")
const GameState = preload("res://core/game_state.gd")
const Stats = preload("res://core/stats.gd")

const ITEMS_PATH := "res://data/items.json"
const STAT_NAMES := {
	"power": "力量",
	"speed": "速度",
	"defense": "防御",
	"recovery": "恢复",
	"skill": "技巧",
	"mechanism": "机关",
}

static var _items: Dictionary = {}
static var _items_loaded := false


static func reload_items() -> void:
	_items = {}
	_items_loaded = false


static func all_items() -> Dictionary:
	if not _items_loaded:
		_items = DataLoader.load_items(ITEMS_PATH)
		_items_loaded = true
	return _items


static func item_def(id: String) -> Dictionary:
	var def: Variant = all_items().get(id, {})
	if def is Dictionary:
		return def
	return {}


# 基础属性 + 永久加点 + 装备加成。
static func final_stats(base: Dictionary) -> Dictionary:
	var result: Dictionary = base.duplicate()
	for key in Stats.KEYS:
		if not result.has(key):
			continue
		var total := int(result[key]) + int(GameState.stat_bonus.get(key, 0))
		result[key] = total
	for slot in GameState.equipment:
		var item: Dictionary = item_def(str(GameState.equipment[slot]))
		var bonus: Variant = item.get("bonus", {})
		if not (bonus is Dictionary):
			continue
		var bonus_dict: Dictionary = bonus
		for key in Stats.KEYS:
			if not result.has(key) or not bonus_dict.has(key):
				continue
			result[key] = int(result[key]) + int(bonus_dict[key])
	return result


static func add_stat(stat: String, amount: int) -> void:
	if not STAT_NAMES.has(stat):
		return
	GameState.stat_bonus[stat] = int(GameState.stat_bonus.get(stat, 0)) + amount
	push_toast("%s +%d" % [STAT_NAMES[stat], amount])


static func give_item(id: String, count: int = 1) -> void:
	if id == "":
		return
	GameState.inventory[id] = int(GameState.inventory.get(id, 0)) + count
	var item: Dictionary = item_def(id)
	var item_name := str(item.get("name", id))
	push_toast("获得 %s" % item_name)
	if str(item.get("kind", "")) == "weapon":
		var slot := str(item.get("slot", ""))
		if slot != "" and not GameState.equipment.has(slot):
			GameState.equipment[slot] = id
			push_toast("已装备 %s" % item_name)
	# 惰性加载，避免 Quests 与 Progression 互相 preload 形成循环依赖。
	load("res://core/quests.gd").notify("item", id, count)


static func item_count(id: String) -> int:
	return int(GameState.inventory.get(id, 0))


static func equipped(slot: String) -> String:
	return str(GameState.equipment.get(slot, ""))


static func push_toast(text: String) -> void:
	GameState.toasts.append(text)


static func take_toasts() -> Array:
	var out: Array = GameState.toasts.duplicate()
	GameState.toasts.clear()
	return out

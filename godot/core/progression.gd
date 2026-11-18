extends RefCounted

const DataLoader = preload("res://core/data_loader.gd")
const GameState = preload("res://core/game_state.gd")
const QuestProgress = preload("res://core/quest_progress.gd")
const Realms = preload("res://core/realms.gd")
const Stats = preload("res://core/stats.gd")

const ITEMS_PATH := DataLoader.ITEMS_PATH
const PLAYER_PATH := DataLoader.PLAYER_PATH
const PROGRESSION_PATH := DataLoader.PROGRESSION_PATH
const STAT_CAP := 50
const EQUIP_SLOTS: Array[String] = ["weapon", "armor", "accessory"]
const STAT_NAMES := {
	"power": "力量",
	"speed": "速度",
	"defense": "防御",
	"recovery": "恢复",
	"skill": "技巧",
	"constitution": "体质",
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


# 年龄轴：达到剧情年龄点时自动增加的体质（data/progression.json）。
static func age_bonus_constitution() -> int:
	var total := 0
	for raw in _age_milestones():
		var milestone: Dictionary = raw
		if GameState.age >= int(milestone.get("age", 0)):
			total += int(milestone.get("constitution", 0))
	return total


# 气血上限 = 基础气血 + 体质 × 每点气血（含加点、装备与年龄加成）。
static func max_hp(base_stats: Dictionary) -> int:
	var stats: Dictionary = final_stats(base_stats)
	var constitution := int(stats.get("constitution", 0)) + age_bonus_constitution()
	return Realms.max_hp_for(constitution, GameState.realm_id)


static func _age_milestones() -> Array:
	var text := FileAccess.get_file_as_string(PROGRESSION_PATH)
	if text == "":
		return []
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return []
	var data: Dictionary = parsed
	var raw: Variant = data.get("age_milestones", [])
	if raw is Array:
		var milestones: Array = raw
		return milestones
	return []


static func add_stat(stat: String, amount: int) -> void:
	if not STAT_NAMES.has(stat):
		return
	GameState.stat_bonus[stat] = int(GameState.stat_bonus.get(stat, 0)) + amount
	push_toast("%s +%d" % [STAT_NAMES[stat], amount])


static func add_points(n: int) -> void:
	if n <= 0:
		return
	GameState.unspent_points += n
	push_toast("获得 %d 点属性点" % n)


static func _base_stats() -> Dictionary:
	var player: Dictionary = DataLoader.load_player(PLAYER_PATH)
	var raw: Variant = player.get("stats", {})
	if raw is Dictionary:
		var stats: Dictionary = raw
		return stats
	return {}


static func can_spend(stat: String) -> bool:
	if GameState.unspent_points <= 0:
		return false
	if not STAT_NAMES.has(stat):
		return false
	var final_values: Dictionary = final_stats(_base_stats())
	return int(final_values.get(stat, 0)) < STAT_CAP


static func spend_point(stat: String) -> bool:
	if not can_spend(stat):
		return false
	GameState.stat_bonus[stat] = int(GameState.stat_bonus.get(stat, 0)) + 1
	GameState.unspent_points -= 1
	return true


static func equip(item_id: String) -> bool:
	if item_count(item_id) <= 0:
		return false
	var item: Dictionary = item_def(item_id)
	var kind := str(item.get("kind", ""))
	if not EQUIP_SLOTS.has(kind):
		return false
	var slot := str(item.get("slot", kind))
	if slot == "" or not EQUIP_SLOTS.has(slot):
		slot = kind
	GameState.equipment[slot] = item_id
	push_toast("已装备 %s" % str(item.get("name", item_id)))
	return true


static func unequip(slot: String) -> void:
	GameState.equipment.erase(slot)


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
	# 任务进度服务只依赖 GameState，避免 Quests 与 Progression 互相引用形成循环。
	QuestProgress.notify("item", id, count)


# 服用带永久加成的消耗品（如养元丹）：消耗一颗，永久加属性，并提示气血上限变化。
static func use_permanent_item(id: String) -> bool:
	var item: Dictionary = item_def(id)
	var raw_perm: Variant = item.get("perm", {})
	if not (raw_perm is Dictionary):
		return false
	var perm: Dictionary = raw_perm
	if perm.is_empty() or item_count(id) <= 0:
		return false
	GameState.inventory[id] = item_count(id) - 1
	for key in perm.keys():
		add_stat(str(key), int(perm[key]))
	push_toast("气血上限 +%d" % Realms.hp_per_con(GameState.realm_id))
	return true


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

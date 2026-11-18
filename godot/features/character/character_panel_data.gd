extends RefCounted

# 角色面板各页签共用的数据读取：玩家基础属性、最终属性与武学定义缓存。

const Progression = preload("res://core/progression.gd")
const DataLoader = preload("res://core/data_loader.gd")

const PLAYER_PATH := DataLoader.PLAYER_PATH
const MARTIALS_PATH := DataLoader.MARTIALS_PATH

const STAT_KEYS: Array[String] = ["power", "speed", "defense", "recovery", "skill", "constitution"]
const STAT_NAMES := {
	"power": "力量",
	"speed": "速度",
	"defense": "防御",
	"recovery": "恢复",
	"skill": "技巧",
	"constitution": "体质",
}

var _martial_def_cache: Dictionary = {}


func player() -> Dictionary:
	return DataLoader.load_player(PLAYER_PATH)


func base_stats() -> Dictionary:
	var raw: Variant = player().get("stats", {})
	if raw is Dictionary:
		var stats: Dictionary = raw
		return stats
	return {}


func final_stats() -> Dictionary:
	return Progression.final_stats(base_stats())


func martial_def_map() -> Dictionary:
	if _martial_def_cache.is_empty():
		var loaded: Dictionary = DataLoader.load_martials(MARTIALS_PATH)
		var defs_value: Variant = loaded.get("defs", {})
		if defs_value is Dictionary:
			_martial_def_cache = defs_value
	return _martial_def_cache


func martial_def(martial_id: String) -> Variant:
	return martial_def_map().get(martial_id, null)


func martial_name(martial_id: String) -> String:
	var def: Variant = martial_def(martial_id)
	if def != null:
		return str(def.name)
	return martial_id


func martial_grade(martial_id: String) -> String:
	var def: Variant = martial_def(martial_id)
	if def != null:
		return str(def.grade)
	return "common"


func martial_glyph(martial_id: String) -> String:
	var glyph_name := martial_name(martial_id)
	if glyph_name.is_empty():
		return "?"
	return glyph_name.substr(0, 1)


func stat_name(stat_id: String) -> String:
	return str(STAT_NAMES.get(stat_id, stat_id))


func signed(amount: int) -> String:
	if amount >= 0:
		return "+%d" % amount
	return str(amount)

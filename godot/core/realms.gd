extends RefCounted

# 境界表：data/realms.json 是唯一数值来源；文件缺失或条目损坏时回退到
# 内置的炼体默认值，保证公式永远有数可用。

const REALMS_PATH := "res://data/realms.json"
const DEFAULT_REALM := "lianti"
const DEFAULT_SCALE := 1.0
const DEFAULT_HP_PER_CON := 15
const DEFAULT_BASE_HP := 40
const DEFAULT_STAGE_NAMES: Array[String] = ["初期", "中期", "高期", "巅峰"]
const DEFAULT_REALMS: Array = [
	{"id": "lianti", "name": "炼体", "scale": 1.0, "hp_per_con": 15},
	{"id": "renjie", "name": "人杰", "scale": 2.0, "hp_per_con": 30},
	{"id": "diling", "name": "地灵", "scale": 3.5, "hp_per_con": 50},
	{"id": "tianwang", "name": "天王", "scale": 5.0, "hp_per_con": 70},
	{"id": "jiyi", "name": "极意", "scale": 6.5, "hp_per_con": 90},
	{"id": "banshen", "name": "半神", "scale": 8.0, "hp_per_con": 105},
]

static var _realms: Dictionary = {}
static var _stages: Array[String] = []
static var _base_hp: int = DEFAULT_BASE_HP
static var _loaded := false


static func reload() -> void:
	_realms = {}
	_stages = []
	_base_hp = DEFAULT_BASE_HP
	_loaded = false


static func get_realm(id: String) -> Dictionary:
	_ensure_loaded()
	if _realms.has(id):
		return _realms[id]
	return _realms[DEFAULT_REALM]


static func scale(id: String) -> float:
	return float(get_realm(id).get("scale", DEFAULT_SCALE))


static func hp_per_con(id: String) -> int:
	return int(get_realm(id).get("hp_per_con", DEFAULT_HP_PER_CON))


static func base_hp() -> int:
	_ensure_loaded()
	return _base_hp


static func name_of(id: String) -> String:
	return str(get_realm(id).get("name", id))


static func stage_name(index: int) -> String:
	_ensure_loaded()
	if index < 0 or index >= _stages.size():
		return ""
	return _stages[index]


static func max_hp_for(constitution: int, realm_id: String) -> int:
	_ensure_loaded()
	return _base_hp + constitution * hp_per_con(realm_id)


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_load_from_file()
	_apply_defaults()


static func _load_from_file() -> void:
	var text := FileAccess.get_file_as_string(REALMS_PATH)
	if text == "":
		return
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return
	var data: Dictionary = parsed
	var raw_realms: Variant = data.get("realms", [])
	if raw_realms is Array:
		for raw in raw_realms:
			if not (raw is Dictionary):
				continue
			var entry: Dictionary = raw
			var realm_id := str(entry.get("id", ""))
			if realm_id == "":
				continue
			var realm_scale := float(entry.get("scale", DEFAULT_SCALE))
			var realm_hp := int(entry.get("hp_per_con", DEFAULT_HP_PER_CON))
			if realm_scale <= 0.0:
				realm_scale = DEFAULT_SCALE
			if realm_hp <= 0:
				realm_hp = DEFAULT_HP_PER_CON
			_realms[realm_id] = {
				"id": realm_id,
				"name": str(entry.get("name", realm_id)),
				"scale": realm_scale,
				"hp_per_con": realm_hp,
			}
	var raw_stages: Variant = data.get("stages", [])
	if raw_stages is Array:
		for raw_stage in raw_stages:
			_stages.append(str(raw_stage))
	var file_base_hp := int(data.get("base_hp", DEFAULT_BASE_HP))
	if file_base_hp > 0:
		_base_hp = file_base_hp


static func _apply_defaults() -> void:
	for raw in DEFAULT_REALMS:
		var entry: Dictionary = raw
		var realm_id := str(entry.get("id", ""))
		if _realms.has(realm_id):
			continue
		_realms[realm_id] = {
			"id": realm_id,
			"name": str(entry.get("name", realm_id)),
			"scale": float(entry.get("scale", DEFAULT_SCALE)),
			"hp_per_con": int(entry.get("hp_per_con", DEFAULT_HP_PER_CON)),
		}
	if _stages.is_empty():
		var fallback: Array[String] = []
		for stage in DEFAULT_STAGE_NAMES:
			fallback.append(str(stage))
		_stages = fallback

extends RefCounted

const Balance = preload("res://core/balance.gd")
const GameState = preload("res://core/game_state.gd")
const Realms = preload("res://core/realms.gd")

const MASTERY_PATH := "res://data/mastery.json"
const DEFAULT_GRADE := "common"
const GRADE_ORDER: Array[String] = ["common", "fine", "rare", "epic", "legendary"]
const DEFAULT_GRADES := {
	"common": {"name": "普通", "color": "#e8e4d8", "exp_per_level": 100},
	"fine": {"name": "精良", "color": "#7ccf6b", "exp_per_level": 150},
	"rare": {"name": "稀有", "color": "#5da9ff", "exp_per_level": 200},
	"epic": {"name": "史诗", "color": "#b783ff", "exp_per_level": 250},
	"legendary": {"name": "传说", "color": "#ff9a3c", "exp_per_level": 300},
}
const DEFAULT_DAMAGE_BONUS_PER_LEVEL := 0.04
const DEFAULT_COUNTER_BONUS_EVERY := 3
const DEFAULT_COUNTER_BONUS_MAX := 3
const DEFAULT_COUNTER_EXP := {"advantage": 1, "perfect": 2, "barely": 0}

static var _config: Dictionary = {}
static var _config_loaded := false

# 一个 Mastery 实例属于一个角色，记录该角色每门武学的累计经验。
var _exp: Dictionary = {}
var _grades: Dictionary = {}
var realm_id: String = ""


func _init() -> void:
	realm_id = str(GameState.realm_id)


static func _ensure_config() -> void:
	if _config_loaded:
		return
	_config_loaded = true
	var grades: Dictionary = {}
	for raw_grade in DEFAULT_GRADES.keys():
		var entry: Dictionary = DEFAULT_GRADES[raw_grade]
		grades[str(raw_grade)] = entry.duplicate()
	var damage_bonus := DEFAULT_DAMAGE_BONUS_PER_LEVEL
	var counter_every := DEFAULT_COUNTER_BONUS_EVERY
	var counter_max := DEFAULT_COUNTER_BONUS_MAX
	var counter_exp: Dictionary = DEFAULT_COUNTER_EXP.duplicate()

	var text := FileAccess.get_file_as_string(MASTERY_PATH)
	if text != "":
		var parsed = JSON.parse_string(text)
		if parsed is Dictionary:
			var data: Dictionary = parsed
			var raw_grades: Variant = data.get("grades", {})
			if raw_grades is Dictionary:
				var grade_map: Dictionary = raw_grades
				for raw_key in grade_map.keys():
					var grade := str(raw_key)
					var raw_entry: Variant = grade_map[raw_key]
					if not (raw_entry is Dictionary):
						continue
					var file_entry: Dictionary = raw_entry
					var base: Dictionary = grades.get(
						grade, {"name": grade, "color": "#e8e4d8", "exp_per_level": 100}
					)
					base["name"] = str(file_entry.get("name", base.get("name", grade)))
					base["color"] = str(file_entry.get("color", base.get("color", "#e8e4d8")))
					base["exp_per_level"] = maxi(
						1, int(file_entry.get("exp_per_level", int(base.get("exp_per_level", 100))))
					)
					grades[grade] = base
			damage_bonus = float(data.get("damage_bonus_per_level", damage_bonus))
			counter_every = int(data.get("counter_bonus_every", counter_every))
			counter_max = int(data.get("counter_bonus_max", counter_max))
			var raw_exp: Variant = data.get("counter_exp", {})
			if raw_exp is Dictionary:
				var exp_map: Dictionary = raw_exp
				for key in exp_map.keys():
					counter_exp[str(key)] = int(exp_map[key])
	_config = {
		"grades": grades,
		"damage_bonus_per_level": damage_bonus,
		"counter_bonus_every": maxi(1, counter_every),
		"counter_bonus_max": maxi(0, counter_max),
		"counter_exp": counter_exp,
	}


static func grade_per_level(grade: String) -> int:
	_ensure_config()
	var grades: Dictionary = _config["grades"]
	var entry: Dictionary = grades.get(grade, grades[DEFAULT_GRADE])
	return maxi(1, int(entry.get("exp_per_level", 100)))


static func grade_name(grade: String) -> String:
	_ensure_config()
	var grades: Dictionary = _config["grades"]
	var entry: Dictionary = grades.get(grade, grades[DEFAULT_GRADE])
	return str(entry.get("name", grade))


static func grade_color(grade: String) -> Color:
	_ensure_config()
	var grades: Dictionary = _config["grades"]
	var entry: Dictionary = grades.get(grade, grades[DEFAULT_GRADE])
	return Color.html(str(entry.get("color", "#e8e4d8")))


static func damage_bonus_at_level(level: int) -> float:
	_ensure_config()
	return float(_config.get("damage_bonus_per_level", DEFAULT_DAMAGE_BONUS_PER_LEVEL)) * float(level)


static func counter_bonus_at_level(level: int) -> int:
	_ensure_config()
	var every: int = maxi(1, int(_config.get("counter_bonus_every", DEFAULT_COUNTER_BONUS_EVERY)))
	var cap: int = maxi(0, int(_config.get("counter_bonus_max", DEFAULT_COUNTER_BONUS_MAX)))
	return mini(floori(float(level) / float(every)), cap)


static func counter_exp(kind: String) -> int:
	_ensure_config()
	var exp_map: Dictionary = _config.get("counter_exp", DEFAULT_COUNTER_EXP)
	return maxi(0, int(exp_map.get(kind, 0)))


func set_grades(grades: Dictionary) -> void:
	for key in grades.keys():
		_grades[str(key)] = str(grades[key])


func grade_of(id: String) -> String:
	return str(_grades.get(id, DEFAULT_GRADE))


func _realm_cap() -> int:
	return mini(Realms.mastery_cap(realm_id), Balance.MAX_LEVEL)


func level(id: String) -> int:
	var per := grade_per_level(grade_of(id))
	var amount := exp_of(id)
	var result := floori(float(amount) / float(per))
	return clampi(result, 0, _realm_cap())


func add_exp(id: String, amount: int) -> void:
	_exp[id] = _exp.get(id, 0) + amount


func exp_of(id: String) -> int:
	return int(_exp.get(id, 0))


func export_exp() -> Dictionary:
	return _exp.duplicate()


func import_exp(d: Dictionary) -> void:
	for key in d.keys():
		_exp[str(key)] = int(d[key])


static func progress_in_level(exp: int, grade: String = "common", cap: int = 10) -> Dictionary:
	var per := grade_per_level(grade)
	var max_level := maxi(0, mini(cap, Balance.MAX_LEVEL))
	var amount := maxi(0, exp)
	var current := mini(floori(float(amount) / float(per)), max_level)
	var into := maxi(0, amount - current * per)
	if max_level > 0 and current >= max_level:
		return {
			"level": current,
			"into": into,
			"need": 0,
			"capped": true,
		}
	return {
		"level": current,
		"into": into,
		"need": per,
		"capped": false,
	}


func learn(id: String) -> void:
	var needed := grade_per_level(grade_of(id))
	if _exp.get(id, 0) < needed:
		_exp[id] = needed


func damage_multiplier(id: String) -> float:
	return 1.0 + damage_bonus_at_level(level(id))


func counter_bonus(id: String) -> int:
	return counter_bonus_at_level(level(id))

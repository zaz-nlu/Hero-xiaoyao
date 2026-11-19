extends RefCounted

# 最小日历：第几天 + 一天四个时段（早上/白天/晚上/深夜）。
# 时段名称与打坐消耗来自 data/calendar.json；当前日期存在 GameState.day / GameState.phase。
# 本轮不与小镇的昼夜光照联动。

const GameState = preload("res://core/game_state.gd")

const CALENDAR_PATH := "res://data/calendar.json"
const DEFAULT_PHASES: Array[String] = ["早上", "白天", "晚上", "深夜"]
const DEFAULT_MEDITATE_COST := 1
const DEFAULT_RESTORE_PCT := 100

static var _data: Dictionary = {}
static var _loaded := false


static func reload() -> void:
	_data = {}
	_loaded = false


static func _config() -> Dictionary:
	if not _loaded:
		_loaded = true
		var text := FileAccess.get_file_as_string(CALENDAR_PATH)
		var parsed = JSON.parse_string(text)
		if parsed is Dictionary:
			_data = parsed
	return _data


static func phase_names() -> Array:
	var raw: Variant = _config().get("phases", [])
	if raw is Array and not (raw as Array).is_empty():
		return raw
	return DEFAULT_PHASES.duplicate()


static func phase_count() -> int:
	return maxi(1, phase_names().size())


static func phase_name() -> String:
	var names: Array = phase_names()
	return str(names[posmod(GameState.phase, names.size())])


# 形如“第 3 天 · 晚上”。
static func label() -> String:
	return "第 %d 天 · %s" % [GameState.day, phase_name()]


# 推进若干时段；跨过深夜回到下一天早上，天数 +1。
static func advance(steps: int) -> Dictionary:
	var count := phase_count()
	var total := maxi(0, GameState.phase) + maxi(0, steps)
	var days := floori(float(total) / float(count))
	GameState.day = maxi(1, GameState.day) + days
	GameState.phase = total % count
	return {"day": GameState.day, "phase": GameState.phase, "text": label()}


static func _meditate_block() -> Dictionary:
	var raw: Variant = _config().get("meditate", {})
	if raw is Dictionary:
		return raw
	return {}


static func meditate_cost() -> int:
	return maxi(0, int(_meditate_block().get("cost_phases", DEFAULT_MEDITATE_COST)))


static func meditate_restore_pct() -> int:
	return clampi(int(_meditate_block().get("restore_pct", DEFAULT_RESTORE_PCT)), 0, 100)

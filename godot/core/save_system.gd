extends RefCounted

# 存档：JSON 落盘 + 原子替换。纯静态工具，不持有任何节点。
# 槽位固定为 auto / 1 / 2 / 3；一份存档同时记录场景位置（location）与
# GameState 的全部持久状态（state）。

const GameState = preload("res://core/game_state.gd")
const Progression = preload("res://core/progression.gd")
const Realms = preload("res://core/realms.gd")
const DataLoader = preload("res://core/data_loader.gd")

const SAVE_DIR := "user://saves"
const VERSION := 1
const SLOTS: Array[String] = ["auto", "1", "2", "3"]
const PLAYER_PATH := "res://data/player.json"
const CHAPTER_NAME := "第一章·紫霞镇"


static func save(
	slot: String,
	location: Dictionary,
	summary_extra: Dictionary = {},
	dir: String = SAVE_DIR
) -> bool:
	if not SLOTS.has(slot):
		return false
	if not _ensure_dir(dir):
		return false
	var path := slot_path(slot, dir)
	var tmp_path := path + ".tmp"
	var bak_path := path + ".bak"
	var payload := {
		"version": VERSION,
		"saved_at": int(Time.get_unix_time_from_system()),
		"playtime": GameState.playtime,
		"location": location.duplicate(true),
		"summary": _summary(summary_extra, str(location.get("kind", ""))),
		"state": GameState.to_dict(),
	}
	var text := JSON.stringify(payload, "\t")
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()

	# 原子替换：旧存档先改名为 .bak，tmp 再改名为正式文件；任何一步失败都恢复旧档。
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(bak_path):
			DirAccess.remove_absolute(_global(bak_path))
		if DirAccess.rename_absolute(_global(path), _global(bak_path)) != OK:
			DirAccess.remove_absolute(_global(tmp_path))
			return false
	if DirAccess.rename_absolute(_global(tmp_path), _global(path)) != OK:
		if FileAccess.file_exists(bak_path) and not FileAccess.file_exists(path):
			DirAccess.rename_absolute(_global(bak_path), _global(path))
		DirAccess.remove_absolute(_global(tmp_path))
		return false
	return true


static func load_slot(slot: String, dir: String = SAVE_DIR) -> Dictionary:
	if not SLOTS.has(slot):
		return {}
	var path := slot_path(slot, dir)
	var data := _read_valid(path)
	if not data.is_empty():
		return data
	return _read_valid(path + ".bak")


static func list_slots(dir: String = SAVE_DIR) -> Array:
	var result: Array = []
	for slot in SLOTS:
		var path := slot_path(slot, dir)
		var item := {
			"slot": slot,
			"exists": false,
			"saved_at": 0,
			"playtime": 0.0,
			"summary": {},
			"location": {},
			"corrupt": false,
		}
		if FileAccess.file_exists(path):
			item["exists"] = true
			var data := load_slot(slot, dir)
			if data.is_empty():
				item["corrupt"] = true
			else:
				item["saved_at"] = int(data.get("saved_at", 0))
				item["playtime"] = float(data.get("playtime", 0.0))
				var summary: Variant = data.get("summary", {})
				if summary is Dictionary:
					item["summary"] = summary
				var location: Variant = data.get("location", {})
				if location is Dictionary:
					item["location"] = location
		result.append(item)
	return result


static func delete_slot(slot: String, dir: String = SAVE_DIR) -> bool:
	if not SLOTS.has(slot):
		return false
	var path := slot_path(slot, dir)
	var removed := false
	for target in [path + ".tmp", path + ".bak", path]:
		if not FileAccess.file_exists(target):
			continue
		if DirAccess.remove_absolute(_global(target)) == OK:
			removed = true
	return removed


static func has_any(dir: String = SAVE_DIR) -> bool:
	for item in list_slots(dir):
		if bool(item.get("exists", false)) and not bool(item.get("corrupt", false)):
			return true
	return false


static func latest_slot(dir: String = SAVE_DIR) -> String:
	var best_slot := ""
	var best_time := -1
	for item in list_slots(dir):
		if not bool(item.get("exists", false)) or bool(item.get("corrupt", false)):
			continue
		var saved_at := int(item.get("saved_at", 0))
		if saved_at > best_time:
			best_time = saved_at
			best_slot = str(item.get("slot", ""))
	return best_slot


static func format_playtime(seconds: float) -> String:
	var total := int(maxf(0.0, seconds))
	if total < 60:
		return "不到1分"
	var minutes := total / 60
	if minutes < 60:
		return "%d分" % minutes
	var hours := minutes / 60
	var rest := minutes % 60
	if rest == 0:
		return "%d小时" % hours
	return "%d小时%d分" % [hours, rest]


static func format_time(unix: int) -> String:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var date := Time.get_datetime_dict_from_unix_time(unix + bias)
	return "%02d-%02d %02d:%02d" % [
		int(date.get("month", 1)),
		int(date.get("day", 1)),
		int(date.get("hour", 0)),
		int(date.get("minute", 0)),
	]


static func slot_path(slot: String, dir: String = SAVE_DIR) -> String:
	return dir.path_join("slot_%s.json" % slot)


# ---------------------------------------------------------------- internals

static func _summary(extra: Dictionary, location_kind: String) -> Dictionary:
	var quests_done := 0
	for raw_id in GameState.quests.keys():
		var entry: Variant = GameState.quests[raw_id]
		if entry is Dictionary and str((entry as Dictionary).get("state", "")) == "done":
			quests_done += 1
	var realm := Realms.name_of(GameState.realm_id)
	var stage := Realms.stage_name(GameState.realm_stage)
	if stage != "":
		realm += "·" + stage
	var summary := {
		"place": place_name(location_kind),
		"chapter": CHAPTER_NAME,
		"realm": realm,
		"age": GameState.age,
		"hp": Progression.max_hp(_base_stats()),
		"quests_done": quests_done,
	}
	for key in extra.keys():
		summary[key] = extra[key]
	return summary


static func place_name(kind: String) -> String:
	match kind:
		"tavern":
			return "紫霞镇·酒馆"
		"forest":
			return "紫霞林"
		_:
			return "紫霞镇"


static func _base_stats() -> Dictionary:
	var player := DataLoader.load_player(PLAYER_PATH)
	var stats: Variant = player.get("stats", {})
	if stats is Dictionary:
		return stats
	return {}


static func _read_valid(path: String) -> Dictionary:
	var parsed: Variant = _read_json(path)
	if not (parsed is Dictionary):
		return {}
	var data: Dictionary = parsed
	if int(data.get("version", 0)) != VERSION:
		return {}
	if not (data.get("state", null) is Dictionary):
		return {}
	if not (data.get("location", null) is Dictionary):
		return {}
	return data


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		return null
	return JSON.parse_string(text)


static func _ensure_dir(dir: String) -> bool:
	if dir.strip_edges() == "":
		return false
	if DirAccess.dir_exists_absolute(_global(dir)):
		return true
	return DirAccess.make_dir_recursive_absolute(_global(dir)) == OK


static func _global(path: String) -> String:
	return ProjectSettings.globalize_path(path)

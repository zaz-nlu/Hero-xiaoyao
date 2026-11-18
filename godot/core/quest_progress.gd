extends RefCounted

const GameState = preload("res://core/game_state.gd")

const QUESTS_PATH := "res://data/quests.json"

static var _quests: Dictionary = {}
static var _loaded := false


static func reload() -> void:
	_quests = {}
	_loaded = false


static func load_all() -> Dictionary:
	if _loaded:
		return _quests
	_quests = {}
	var text := FileAccess.get_file_as_string(QUESTS_PATH)
	if text != "":
		var parsed = JSON.parse_string(text)
		if parsed is Array:
			for entry in parsed:
				if entry is Dictionary and entry.has("id"):
					_quests[str(entry["id"])] = entry
		elif parsed is Dictionary:
			_quests = parsed
	_loaded = true
	return _quests


static func state(id: String) -> String:
	if not GameState.quests.has(id):
		return "none"
	var entry: Variant = GameState.quests[id]
	if not (entry is Dictionary):
		return "none"
	return str(entry.get("state", "none"))


static func notify(kind: String, key: String, amount: int = 1) -> void:
	for raw_id in GameState.quests.keys():
		var id := str(raw_id)
		if state(id) != "active":
			continue
		var defs: Dictionary = load_all()
		var def: Dictionary = defs.get(id, {})
		var entry: Variant = GameState.quests[id]
		if not (entry is Dictionary):
			continue
		var progress_map: Dictionary = entry.get("progress", {})
		var matched := false
		var objectives: Variant = def.get("objectives", [])
		if objectives is Array:
			for objective in objectives:
				if not (objective is Dictionary):
					continue
				if str(objective.get("kind", "")) != kind:
					continue
				if str(objective.get("key", "")) != key:
					continue
				var need := int(objective.get("count", 0))
				var have := int(progress_map.get(key, 0)) + amount
				progress_map[key] = mini(have, need)
				matched = true
		if matched:
			entry["progress"] = progress_map
			check_ready(id)


static func progress(id: String) -> Array:
	var result: Array = []
	var def: Dictionary = load_all().get(id, {})
	var entry: Variant = GameState.quests.get(id, {})
	var progress_map: Dictionary = {}
	if entry is Dictionary:
		var raw_progress: Variant = entry.get("progress", {})
		if raw_progress is Dictionary:
			progress_map = raw_progress
	var objectives: Variant = def.get("objectives", [])
	if objectives is Array:
		for objective in objectives:
			if not (objective is Dictionary):
				continue
			var key := str(objective.get("key", ""))
			result.append({
				"text": str(objective.get("text", "")),
				"have": int(progress_map.get(key, 0)),
				"need": int(objective.get("count", 0)),
			})
	return result


static func check_ready(id: String) -> void:
	if state(id) != "active":
		return
	var def: Dictionary = load_all().get(id, {})
	var entry: Variant = GameState.quests.get(id, {})
	if not (entry is Dictionary):
		return
	var progress_map: Dictionary = entry.get("progress", {})
	var objectives: Variant = def.get("objectives", [])
	if objectives is Array:
		for objective in objectives:
			if not (objective is Dictionary):
				continue
			var key := str(objective.get("key", ""))
			var need := int(objective.get("count", 0))
			if int(progress_map.get(key, 0)) < need:
				return
	entry["state"] = "ready"
	GameState.toasts.append("任务完成：%s" % str(def.get("name", id)))

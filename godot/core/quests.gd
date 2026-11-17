extends RefCounted

const GameState = preload("res://core/game_state.gd")
const Progression = preload("res://core/progression.gd")

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


static func start(id: String) -> bool:
	var defs: Dictionary = load_all()
	if not defs.has(id):
		return false
	if state(id) != "none":
		return false
	var def: Dictionary = defs[id]
	var progress_map: Dictionary = {}
	var objectives: Variant = def.get("objectives", [])
	if objectives is Array:
		for objective in objectives:
			if not (objective is Dictionary):
				continue
			if str(objective.get("kind", "")) != "item":
				continue
			var key := str(objective.get("key", ""))
			progress_map[key] = Progression.item_count(key)
	GameState.quests[id] = {"state": "active", "progress": progress_map}
	return true


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
			_check_ready(id)


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


static func turn_in(id: String) -> bool:
	if state(id) != "ready":
		return false
	var def: Dictionary = load_all().get(id, {})
	var entry: Dictionary = GameState.quests[id]
	# 先标记完成，避免发物品时又把本任务算进进度。
	entry["state"] = "done"

	var rewards: Variant = def.get("rewards", {})
	if not (rewards is Dictionary):
		return true
	var stats_reward: Variant = rewards.get("stats", {})
	if stats_reward is Dictionary:
		for stat in stats_reward:
			Progression.add_stat(str(stat), int(stats_reward[stat]))
	var items_reward: Variant = rewards.get("items", {})
	if items_reward is Dictionary:
		for item_id in items_reward:
			Progression.give_item(str(item_id), int(items_reward[item_id]))
	var exp_reward: Variant = rewards.get("mastery_exp", {})
	if exp_reward is Dictionary:
		for martial_id in exp_reward:
			var key := str(martial_id)
			GameState.mastery_exp[key] = int(GameState.mastery_exp.get(key, 0)) + int(exp_reward[martial_id])
	var points_reward: Variant = rewards.get("points", 0)
	if points_reward is int or points_reward is float:
		Progression.add_points(int(points_reward))
	return true


static func list_by_state(wanted: String) -> Array:
	var result: Array = []
	for raw_id in load_all().keys():
		var id := str(raw_id)
		if state(id) == wanted:
			result.append(id)
	return result


static func _check_ready(id: String) -> void:
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
	Progression.push_toast("任务完成：%s" % str(def.get("name", id)))

extends RefCounted

const GameState = preload("res://core/game_state.gd")
const Progression = preload("res://core/progression.gd")
const QuestProgress = preload("res://core/quest_progress.gd")


static func reload() -> void:
	QuestProgress.reload()


static func load_all() -> Dictionary:
	return QuestProgress.load_all()


static func state(id: String) -> String:
	return QuestProgress.state(id)


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
	QuestProgress.notify(kind, key, amount)


static func progress(id: String) -> Array:
	return QuestProgress.progress(id)


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
	QuestProgress.check_ready(id)

extends "res://tests/test_case.gd"

const DataLoader = preload("res://core/data_loader.gd")
const GameState = preload("res://core/game_state.gd")
const Progression = preload("res://core/progression.gd")
const Quests = preload("res://core/quests.gd")
const Stats = preload("res://core/stats.gd")

const PLAYER_PATH := "res://data/player.json"
# 第一章可选成长上限：初始 37 + 开局 3 点 = 40，满做 50，所以额外成长 ≤ 10。
const BUDGET_CAP := 10


func _reset() -> void:
	GameState.reset()
	Quests.reload()
	Progression.reload_items()


func _player_base() -> Dictionary:
	var raw: Variant = DataLoader.load_player(PLAYER_PATH).get("stats", {})
	if raw is Dictionary:
		var stats: Dictionary = raw
		return stats
	return {}


func _bonus_sum(item_id: String) -> int:
	var item: Dictionary = Progression.item_def(item_id)
	var raw: Variant = item.get("bonus", {})
	if not (raw is Dictionary):
		return 0
	var bonus: Dictionary = raw
	var total := 0
	for key in bonus.keys():
		total += int(bonus[key])
	return total


func test_chapter_growth_budget_is_capped() -> void:
	_reset()
	var total := 0
	for quest_value in Quests.load_all().values():
		if not (quest_value is Dictionary):
			continue
		var quest: Dictionary = quest_value
		var raw_rewards: Variant = quest.get("rewards", {})
		if not (raw_rewards is Dictionary):
			continue
		var rewards: Dictionary = raw_rewards
		var stats_reward: Dictionary = {}
		var raw_stats: Variant = rewards.get("stats", {})
		if raw_stats is Dictionary:
			stats_reward = raw_stats
		for key in stats_reward.keys():
			total += int(stats_reward[key])
		total += int(rewards.get("points", 0))
		var items_reward: Dictionary = {}
		var raw_items: Variant = rewards.get("items", {})
		if raw_items is Dictionary:
			items_reward = raw_items
		for raw_id in items_reward.keys():
			var item_id := str(raw_id)
			var count := int(items_reward[raw_id])
			if item_id == "yangyuan_pill":
				total += count
				continue
			var item: Dictionary = Progression.item_def(item_id)
			if Progression.EQUIP_SLOTS.has(str(item.get("kind", ""))):
				total += count * _bonus_sum(item_id)
	# 宝箱里的普通的剑是唯一的装备类章节奖励。
	total += _bonus_sum("plain_sword")
	assert_true(
		total <= BUDGET_CAP,
		"chapter growth budget is at most %d, got %d" % [BUDGET_CAP, total]
	)
	GameState.reset()


func test_initial_points_and_player_stats_total() -> void:
	_reset()
	assert_eq(GameState.INITIAL_POINTS, 3, "the chapter starts with three free points")
	var base: Dictionary = _player_base()
	var total := 0
	for key in Stats.KEYS:
		total += int(base.get(key, 0))
	assert_eq(total, 37, "the initial six stats total 37")
	GameState.reset()


func test_initial_hp_and_constitution_growth() -> void:
	_reset()
	var base: Dictionary = _player_base()
	assert_eq(int(base.get("constitution", 0)), 4, "the player starts with constitution 4")
	assert_eq(Progression.max_hp(base), 100, "40 + 4 × 15 = 100 hp")
	GameState.stat_bonus["constitution"] = 1
	assert_eq(Progression.max_hp(base), 115, "one constitution point adds 15 hp")
	GameState.reset()

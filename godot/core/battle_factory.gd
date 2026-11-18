extends RefCounted

# live 战斗与模拟器共用的装配逻辑：单位、敌人展开、熟练度。
# 参数化装配；角色加成沿用 Progression 的当前角色状态，不依赖界面。

const Mastery = preload("res://core/mastery.gd")
const Progression = preload("res://core/progression.gd")
const Realms = preload("res://core/realms.gd")
const Unit = preload("res://core/unit.gd")


static func make_player(
	player_data: Dictionary,
	realm_id: String,
	stats_override: Dictionary = {}
) -> Variant:
	var stats: Dictionary = {}
	var max_hp := 0
	if not stats_override.is_empty():
		stats = stats_override.duplicate()
		max_hp = Realms.max_hp_for(int(stats.get("constitution", 0)), realm_id)
	else:
		var base_stats: Dictionary = {}
		var raw_stats: Variant = player_data.get("stats", {})
		if raw_stats is Dictionary:
			base_stats = raw_stats
			stats = Progression.final_stats(base_stats)
		# player.json 不再带显式 max_hp，气血由体质与境界算；若仍有 max_hp 则沿用（向后兼容）。
		if player_data.has("max_hp"):
			max_hp = int(player_data.get("max_hp", 0))
		else:
			max_hp = Progression.max_hp(base_stats)
	return Unit.make_player(
		str(player_data.get("name", "")),
		stats,
		max_hp,
		int(player_data.get("jianyi_max", 0)),
		int(player_data.get("foresight_max", 0)),
		realm_id
	)


# 按列表顺序展开混编敌人组；limit > 0 时最多生成 limit 个。
static func expand_group(group: Array, enemy_defs: Dictionary, limit: int = 0) -> Array:
	var result: Array = []
	for raw_entry in group:
		if not (raw_entry is Dictionary):
			continue
		var entry: Dictionary = raw_entry
		var def: Variant = enemy_defs.get(str(entry.get("id", "")), null)
		if def == null:
			continue
		var count: int = maxi(0, int(entry.get("count", 1)))
		for i in range(count):
			if limit > 0 and result.size() >= limit:
				return result
			result.append(Unit.from_enemy(def))
	return result


static func repeat_enemy(enemy_def: Variant, count: int) -> Array:
	var result: Array = []
	for i in range(count):
		result.append(Unit.from_enemy(enemy_def))
	return result


static func make_mastery(
	martials: Dictionary,
	learned: Array,
	loadout: Array,
	imported_exp: Dictionary = {},
	pending_exp: Dictionary = {}
) -> Variant:
	var mastery: Variant = Mastery.new()
	mastery.set_grades(martial_grades(martials))
	if not imported_exp.is_empty():
		mastery.import_exp(imported_exp)
	for raw_learned_id in learned:
		mastery.learn(str(raw_learned_id))
	for raw_id in loadout:
		mastery.learn(str(raw_id))
	for raw_martial_id in pending_exp.keys():
		mastery.add_exp(str(raw_martial_id), int(pending_exp[raw_martial_id]))
	return mastery


static func martial_grades(martials: Dictionary) -> Dictionary:
	var grades := {}
	for raw_id in martials.keys():
		var id := str(raw_id)
		grades[id] = str(martials[raw_id].grade)
	return grades

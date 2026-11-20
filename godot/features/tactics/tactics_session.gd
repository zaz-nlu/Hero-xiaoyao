extends RefCounted

# 游戏侧参数 → 战棋战斗：消费一次性的 GameState 输入（混编敌人组、头子伤势），
# 复用 core 的装配函数构建玩家与敌人，并按旧战斗的同一规则结算熟练度。
# 不依赖 features/battle；规则、数值与装配仍留在 core。

const Battle = preload("res://core/battle.gd")
const BattleFactory = preload("res://core/battle_factory.gd")
const DataLoader = preload("res://core/data_loader.gd")
const GameState = preload("res://core/game_state.gd")
const Progression = preload("res://core/progression.gd")
const TacticsEnergy = preload("res://core/tactics/tactics_energy.gd")
const TacticsSetup = preload("res://core/tactics/tactics_setup.gd")
const TurnQueue = preload("res://core/tactics/turn_queue.gd")

const CONFIG_PATH := "res://data/tactics_encounters.json"
const PLAYER_ID := "player"
const EXP_MARKER := "exp_settled"


static func build(enemy_id: String, count: int, first_strike: bool, origin: String) -> Dictionary:
	var config := _config()
	if config.is_empty():
		return _failed(["cannot read %s" % CONFIG_PATH])
	var origin_maps: Variant = config.get("origin_to_map", {})
	var map_id := str(config.get("fallback_map", ""))
	if origin_maps is Dictionary and (origin_maps as Dictionary).has(origin):
		map_id = str((origin_maps as Dictionary)[origin])
	if map_id == "":
		return _failed(["tactics_encounters: no map for origin '%s'" % origin])
	var group := _enemy_group(enemy_id, count)
	var tutorial := is_tutorial(origin)
	var player_path := DataLoader.PLAYER_PATH
	var origin_players: Variant = config.get("origin_player", {})
	if origin_players is Dictionary and (origin_players as Dictionary).has(origin):
		player_path = str((origin_players as Dictionary)[origin])
	var player_data: Dictionary = DataLoader.load_player(player_path)
	var built: Dictionary = TacticsSetup.build(
		map_id, group, player_data if not player_data.is_empty() else null,
		int(config.get("seed", 1)))
	if not bool(built.get("ok", false)):
		return built
	var battle: Variant = built["battle"]
	var player: Variant = battle.get_unit(PLAYER_ID)
	TacticsEnergy.apply_defaults(player)
	if not tutorial:
		_restore_neili(player)
		_import_mastery(battle, player_data)
		_apply_boss_wound(battle, config)
	if first_strike:
		battle.queue.add_ct(PLAYER_ID, TurnQueue.THRESHOLD)
	built["map_id"] = map_id
	built["group"] = group
	built["encounter_id"] = _encounter_id(group, enemy_id)
	built["first_strike"] = first_strike
	return built


# 教学战斗（如序幕的东方阳 vs 东方云）：使用独立角色数据，不读取也不写回存档里的养成状态。
static func is_tutorial(origin: String) -> bool:
	var origins: Variant = _config().get("tutorial_origins", [])
	return origins is Array and (origins as Array).has(origin)


# 内力跨战斗携带：上限走 TacticsEnergy 的成长入口，剩余按 GameState.neili_left
# 恢复（-1 表示未记录 = 满）。紫气不读存档，每场由新单位按 JSON 初值重置为满。
static func _restore_neili(player) -> void:
	if player == null or not player.energy_max.has("neili"):
		return
	var cap := maxi(0, TacticsEnergy.max_neili_for(GameState.realm_id))
	player.energy_max["neili"] = cap
	if GameState.neili_left >= 0:
		player.energy_left["neili"] = clampi(int(GameState.neili_left), 0, cap)
	else:
		player.energy_left["neili"] = cap


# 遭遇表中的键：混编组的第一条是头子（如 ma_youwei），单个敌人时退回 enemy_id。
static func _encounter_id(group: Array, fallback: String) -> String:
	for raw in group:
		if not (raw is Dictionary):
			continue
		var id := str((raw as Dictionary).get("id", ""))
		if id != "":
			return id
	return fallback


# 胜利后按旧战斗 settle_exp 的规则分配击杀经验并同步持久熟练度。
# 直接复用 core/battle.gd 的分配实现，不在 features 里复制算法。
static func settle(battle) -> void:
	if battle == null:
		return
	_persist_neili(battle, false)
	if battle.mastery == null or battle.result() != "win":
		return
	if _has_exp_marker(battle):
		return
	battle.log.append({"type": EXP_MARKER})
	var levels_before := {}
	for raw_id in battle.martials.keys():
		var id := str(raw_id)
		levels_before[id] = int(battle.mastery.level(id))
	var shell: Variant = Battle.new(null, [], [], battle.mastery, battle.martials, 1, false)
	shell.pending_exp = _kill_exp(battle)
	shell.uses = _usage_counts(battle)
	var gained: Dictionary = shell.settle_exp()
	GameState.mastery_total = battle.mastery.export_exp()
	_report_gain(battle, gained, levels_before)


# 战败不分配击杀经验，只把本场战斗中已经获得的熟练度同步进持久存档。
static func settle_defeat(battle) -> void:
	if battle == null:
		return
	_persist_neili(battle, true)
	if battle.mastery == null:
		return
	GameState.mastery_total = battle.mastery.export_exp()


# 战后写回玩家内力剩余；战败时按 JSON 下限取 max(剩余, 上限 × 比例)。
# 紫气不写回。
static func _persist_neili(battle, defeated: bool) -> void:
	var player: Variant = battle.get_unit(PLAYER_ID)
	if player == null or not player.energy_max.has("neili"):
		return
	var cap := int(player.energy_max.get("neili", 0))
	GameState.neili_left = TacticsEnergy.neili_after_battle(
		int(player.energy_left.get("neili", 0)), cap, defeated)


static func _enemy_group(enemy_id: String, count: int) -> Array:
	var raw: Variant = GameState.encounter_group
	if raw is Array and not (raw as Array).is_empty():
		var group: Array = (raw as Array).duplicate(true)
		GameState.encounter_group = []
		return group
	return [{"id": enemy_id, "count": count}]


static func _import_mastery(battle, player_data: Dictionary) -> void:
	var loaded: Dictionary = DataLoader.load_martials(DataLoader.MARTIALS_PATH)
	var martials: Dictionary = loaded.get("defs", {})
	var loadout: Array = []
	var learned: Array = []
	var raw_loadout: Variant = player_data.get("loadout", [])
	if raw_loadout is Array:
		loadout = raw_loadout
	var raw_learned: Variant = player_data.get("learned", [])
	if raw_learned is Array:
		learned = raw_learned
	battle.mastery = BattleFactory.make_mastery(
		martials, learned, loadout, GameState.mastery_total, GameState.mastery_exp)
	GameState.mastery_exp.clear()


# 前戏里紫霞师姐打掉的伤势只作用于马匪头子：当前气血降低、上限不变。
static func _apply_boss_wound(battle, config: Dictionary) -> void:
	var loss := int(GameState.boss_hp_loss)
	if loss <= 0:
		return
	var wounded := str(config.get("wounded_enemy", ""))
	for entry in battle.units:
		if entry.unit != null and str(entry.unit.id) == wounded:
			entry.unit.hp = maxi(1, int(entry.unit.hp) - loss)
	GameState.boss_hp_loss = 0


static func _has_exp_marker(battle) -> bool:
	for raw in battle.log:
		if raw is Dictionary and str(raw.get("type", "")) == EXP_MARKER:
			return true
	return false


static func _kill_exp(battle) -> int:
	var total := 0
	for entry in battle.units:
		if entry.side != "enemy" or entry.is_alive():
			continue
		if entry.unit != null and entry.unit.def != null:
			total += maxi(0, int(entry.unit.def.exp))
	return total


static func _usage_counts(battle) -> Dictionary:
	var uses := {}
	for raw in battle.log:
		if not (raw is Dictionary):
			continue
		var event: Dictionary = raw
		if str(event.get("type", "")) != "attack":
			continue
		if str(event.get("unit", "")) != PLAYER_ID:
			continue
		var id := str(event.get("martial_id", ""))
		if id != "":
			uses[id] = int(uses.get(id, 0)) + 1
	return uses


static func _report_gain(battle, gained: Dictionary, levels_before: Dictionary) -> void:
	if gained.is_empty():
		return
	var parts := PackedStringArray()
	for raw_id in gained.keys():
		var id := str(raw_id)
		parts.append("%s +%d" % [_martial_name(battle, id), int(gained[raw_id])])
	Progression.push_toast("熟练度 " + "、".join(parts))
	var upgrades := PackedStringArray()
	for raw_id in gained.keys():
		var id := str(raw_id)
		var after := int(battle.mastery.level(id))
		var before := int(levels_before.get(id, after))
		if after > before:
			upgrades.append("%s 升至 Lv.%d" % [_martial_name(battle, id), after])
	if not upgrades.is_empty():
		Progression.push_toast("、".join(upgrades))


static func _martial_name(battle, id: String) -> String:
	if battle.martials.has(id):
		return str(battle.martials[id].name)
	return id


static func _config() -> Dictionary:
	var text := FileAccess.get_file_as_string(CONFIG_PATH)
	if text == "":
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {}
	var config: Dictionary = parsed
	return config


static func _failed(errors: Array) -> Dictionary:
	return {"ok": false, "errors": errors, "battle": null, "map_id": "", "group": [], "seed": 0}

extends RefCounted

# 一场战斗的会话逻辑：装配 live battle、消费一次性 GameState 输入、提交动作、
# 结算熟练度并同步持久数据。不依赖任何 Node / Control / 舞台 / 音频。

const Battle = preload("res://core/battle.gd")
const BattleFactory = preload("res://core/battle_factory.gd")
const DataLoader = preload("res://core/data_loader.gd")
const GameState = preload("res://core/game_state.gd")
const Progression = preload("res://core/progression.gd")

const LIVE_MAX_ENEMIES := 6
const LIVE_SEED := 1

var battle: Variant = null
var last_error: String = ""

var _exp_settled: bool = false


func start(enemy_id: String, enemy_count: int, first_strike: bool) -> bool:
	var player_data: Dictionary = DataLoader.load_player(DataLoader.PLAYER_PATH)
	var loaded_martials: Dictionary = DataLoader.load_martials(DataLoader.MARTIALS_PATH)
	var martials: Dictionary = loaded_martials.get("defs", {})
	var loaded_enemies: Dictionary = DataLoader.load_enemies(DataLoader.ENEMIES_PATH)
	var enemy_defs: Dictionary = loaded_enemies.get("defs", {})
	# 混编敌人组优先于 enemy_id / enemy_count；读取后立即清空。
	var raw_group: Variant = GameState.encounter_group
	var group: Array = []
	if raw_group is Array and not (raw_group as Array).is_empty():
		group = raw_group
		GameState.encounter_group = []

	var loadout: Array = []
	var raw_loadout: Variant = player_data.get("loadout", [])
	if raw_loadout is Array:
		loadout = raw_loadout
	var learned: Array = []
	var raw_learned: Variant = player_data.get("learned", [])
	if raw_learned is Array:
		learned = raw_learned

	var player: Variant = BattleFactory.make_player(player_data, str(GameState.realm_id))
	var enemies: Array = []
	if not group.is_empty():
		enemies = BattleFactory.expand_group(group, enemy_defs, LIVE_MAX_ENEMIES)
		if enemies.is_empty():
			last_error = "未知敌人组"
			return false
	else:
		var enemy_def: Variant = enemy_defs.get(enemy_id, null)
		if enemy_def == null:
			last_error = "未知敌人：%s" % enemy_id
			return false
		enemies = BattleFactory.repeat_enemy(enemy_def, enemy_count)
	# 前戏里紫霞师姐打掉的伤势只作用于马匪头子：当前气血降低、上限不变，
	# 血条显示成 "207/295" 这样的带伤状态。小兵保持满血。
	var boss_hp_loss: int = int(GameState.boss_hp_loss)
	if boss_hp_loss > 0:
		for enemy in enemies:
			if str(enemy.id) == "ma_youwei":
				enemy.hp = maxi(1, int(enemy.hp) - boss_hp_loss)
		GameState.boss_hp_loss = 0
	var mastery: Variant = BattleFactory.make_mastery(
		martials, learned, loadout, GameState.mastery_total, GameState.mastery_exp
	)
	GameState.mastery_exp.clear()
	battle = Battle.new(player, enemies, loadout, mastery, martials, LIVE_SEED, first_strike)
	# Share the persistent dictionary so recognized moves carry over between battles.
	battle.known_moves = GameState.known_moves
	# Share the persistent inventory so herbs eaten in a fight stay eaten.
	battle.inventory = GameState.inventory

	last_error = ""
	_exp_settled = false
	return true


func submit(action: Dictionary) -> Dictionary:
	if battle == null:
		return {"ok": false, "error": "no battle"}
	var result: Dictionary = battle.submit(action)
	if bool(result.get("ok", false)):
		last_error = ""
	else:
		last_error = str(result.get("error", "action failed"))
	return result


func settle_exp() -> void:
	if _exp_settled or battle == null:
		return
	if battle.state() != Battle.State.WON:
		return
	_exp_settled = true
	var levels_before := {}
	for id in battle.martials.keys():
		levels_before[str(id)] = int(battle.mastery.level(str(id)))
	var gained: Dictionary = battle.settle_exp()
	if gained.is_empty():
		return
	var parts := PackedStringArray()
	for raw_id in gained.keys():
		var id := str(raw_id)
		parts.append("%s +%d" % [_martial_name(id), int(gained[raw_id])])
	if not parts.is_empty():
		Progression.push_toast("熟练度 " + "、".join(parts))
	var upgrades := PackedStringArray()
	for raw_id in gained.keys():
		var id := str(raw_id)
		var after := int(battle.mastery.level(id))
		var before := int(levels_before.get(id, after))
		if after > before:
			upgrades.append("%s 升至 Lv.%d" % [_martial_name(id), after])
	if not upgrades.is_empty():
		Progression.push_toast("、".join(upgrades))


func sync_mastery_total() -> void:
	if battle == null or battle.mastery == null:
		return
	GameState.mastery_total = battle.mastery.export_exp()


func _martial_name(id: String) -> String:
	if battle != null and battle.martials.has(id):
		return str(battle.martials[id].name)
	return id

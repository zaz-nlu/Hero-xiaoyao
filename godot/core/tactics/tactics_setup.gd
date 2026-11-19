extends RefCounted

# 从地图数据和敌人组装配一场战棋战斗：玩家出生点、敌人占位、头子优先、
# 次数制初始资源都在这里统一处理。纯静态，不依赖场景。

const BattleFactory = preload("res://core/battle_factory.gd")
const DataLoader = preload("res://core/data_loader.gd")
const Facing = preload("res://core/tactics/facing.gd")
const GameState = preload("res://core/game_state.gd")
const MapLoader = preload("res://core/tactics/map_loader.gd")
const TacticsBattle = preload("res://core/tactics/tactics_battle.gd")
const TacticsEnergy = preload("res://core/tactics/tactics_energy.gd")
const TacticsUnit = preload("res://core/tactics/tactics_unit.gd")

const PLAYER_ID := "player"


# player 可以是 null（读取 data/player.json）、字典（玩家数据覆盖）或
# 已经构造好的 TacticsUnit（只会重新放置出生点）。
static func build(
	map_id: String,
	enemy_group: Array,
	player: Variant = null,
	seed_value: int = 1,
	enemy_defs: Dictionary = {}
) -> Dictionary:
	var errors: Array[String] = []
	var loaded_map: Dictionary = MapLoader.load_map(map_id)
	if not bool(loaded_map.get("ok", false)):
		for message in loaded_map.get("errors", []):
			errors.append(str(message))
		return _failed(errors)
	var grid = loaded_map["grid"]
	var meta: Dictionary = loaded_map["meta"]

	var martials: Dictionary = {}
	var loaded_martials: Dictionary = DataLoader.load_martials(DataLoader.MARTIALS_PATH)
	martials = loaded_martials.get("defs", {})
	for message in loaded_martials.get("errors", []):
		errors.append(str(message))

	var defs: Dictionary = enemy_defs
	if defs.is_empty():
		var loaded_enemies: Dictionary = DataLoader.load_enemies(DataLoader.ENEMIES_PATH)
		defs = loaded_enemies.get("defs", {})
		for message in loaded_enemies.get("errors", []):
			errors.append(str(message))

	if enemy_group.is_empty():
		errors.append("enemy_group: must contain at least one enemy")
	else:
		for raw_entry in enemy_group:
			if not (raw_entry is Dictionary):
				errors.append("enemy_group: entries must be objects like {id, count}")
				continue
			var entry: Dictionary = raw_entry
			var entry_id := str(entry.get("id", ""))
			if entry_id == "" or not defs.has(entry_id):
				errors.append("enemy_group: unknown enemy '%s'" % entry_id)
	var enemy_units: Array = BattleFactory.expand_group(enemy_group, defs)
	if enemy_units.is_empty() and not enemy_group.is_empty():
		errors.append("enemy_group: expanded to zero enemies")

	var player_spawns: Array = []
	var enemy_spawns: Array = []
	var raw_spawns: Variant = meta.get("spawns", {})
	if raw_spawns is Dictionary:
		var spawns: Dictionary = raw_spawns
		player_spawns = _points(spawns.get("player", []))
		enemy_spawns = _points(spawns.get("enemies", []))
	if player_spawns.is_empty():
		errors.append("spawns: map has no player spawn")
	if enemy_units.size() > enemy_spawns.size():
		errors.append(
			"spawns: map has %d enemy spawns but the group has %d units"
			% [enemy_spawns.size(), enemy_units.size()]
		)

	var built_player := _build_player(player, martials, errors)
	if not errors.is_empty():
		return _failed(errors)

	var leader_id := str(meta.get("leader", ""))
	if leader_id != "":
		var leader_index := -1
		for i in range(enemy_units.size()):
			if str(enemy_units[i].id) == leader_id:
				leader_index = i
				break
		if leader_index > 0:
			var leader_raw = enemy_units[leader_index]
			enemy_units.remove_at(leader_index)
			enemy_units.push_front(leader_raw)

	var player_unit = built_player["unit"]
	var player_spawn: Vector2i = player_spawns[0]
	var facing := Facing.from_delta(enemy_spawns[0] - player_spawn, Facing.DOWN)
	player_unit.pos = player_spawn
	player_unit.facing = facing
	TacticsEnergy.apply_defaults(player_unit)

	var units: Array = [player_unit]
	var used_ids := {PLAYER_ID: true}
	var leader_tactics_id := ""
	for i in range(enemy_units.size()):
		var raw_unit = enemy_units[i]
		var base_id := str(raw_unit.id)
		var tactics_id := base_id
		if base_id == "" or used_ids.has(tactics_id):
			tactics_id = "%s_%d" % [base_id if base_id != "" else "enemy", i + 1]
			while used_ids.has(tactics_id):
				tactics_id += "_"
		used_ids[tactics_id] = true
		var enemy_cell: Vector2i = enemy_spawns[i]
		var enemy_facing := Facing.from_delta(player_spawn - enemy_cell, Facing.UP)
		units.append(TacticsUnit.create(
			tactics_id, raw_unit, "enemy", enemy_cell, enemy_facing, [], {}))
		if base_id == leader_id and leader_tactics_id == "":
			leader_tactics_id = tactics_id

	var objective := str(meta.get("objective", ""))
	if objective == "":
		objective = "defeat_all"
	var battle: Variant = TacticsBattle.create(
		grid, units, martials, built_player["mastery"], objective, leader_tactics_id,
		seed_value)
	return {
		"ok": true,
		"errors": [],
		"battle": battle,
		"grid": grid,
		"meta": meta,
		"seed": seed_value,
	}


static func _build_player(player: Variant, martials: Dictionary, errors: Array[String]) -> Dictionary:
	var realm := str(GameState.realm_id)
	var mastery: Variant = null
	if _is_tactics_unit(player):
		var unit = player
		TacticsEnergy.apply_defaults(unit)
		mastery = BattleFactory.make_mastery(martials, unit.loadout, unit.loadout)
		return {"unit": unit, "mastery": mastery}

	var player_data: Dictionary = {}
	var stats_override: Dictionary = {}
	if player is Dictionary:
		player_data = player
	else:
		player_data = DataLoader.load_player(DataLoader.PLAYER_PATH)
	if player_data.is_empty():
		errors.append("player: cannot read %s" % DataLoader.PLAYER_PATH)
		return {"unit": null, "mastery": null}
	if str(player_data.get("realm", "")) != "":
		realm = str(player_data.get("realm", ""))
	if player_data.get("stats_override") is Dictionary:
		stats_override = player_data.get("stats_override", {})

	var core_unit: Variant = BattleFactory.make_player(player_data, realm, stats_override)
	var loadout: Array = player_data.get("loadout", [])
	var learned: Array = player_data.get("learned", [])
	mastery = BattleFactory.make_mastery(martials, learned, loadout)
	var energy: Dictionary = {}
	if player_data.get("energy") is Dictionary:
		energy = player_data.get("energy")
	var tactics_unit: Variant = TacticsUnit.create(
		PLAYER_ID, core_unit, "player", Vector2i.ZERO, Facing.DOWN, loadout, energy)
	return {"unit": tactics_unit, "mastery": mastery}


static func _is_tactics_unit(value: Variant) -> bool:
	if value == null or not (value is Object):
		return false
	return value.get("unit") != null and value.get("side") != null


static func _points(raw: Variant) -> Array:
	var out: Array = []
	if not (raw is Array):
		return out
	for pair in raw:
		if pair is Array and pair.size() == 2:
			out.append(Vector2i(int(pair[0]), int(pair[1])))
	return out


static func _failed(errors: Array[String]) -> Dictionary:
	return {"ok": false, "errors": errors, "battle": null, "grid": null, "meta": {}, "seed": 0}

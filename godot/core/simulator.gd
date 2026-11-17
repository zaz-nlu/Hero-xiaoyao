extends RefCounted

const Balance = preload("res://core/balance.gd")
const Battle = preload("res://core/battle.gd")
const Counter = preload("res://core/counter.gd")
const DataLoader = preload("res://core/data_loader.gd")
const GameState = preload("res://core/game_state.gd")
const Jianyi = preload("res://core/jianyi.gd")
const Mastery = preload("res://core/mastery.gd")
const Progression = preload("res://core/progression.gd")
const Realms = preload("res://core/realms.gd")
const Unit = preload("res://core/unit.gd")

const PLAYER_PATH := "res://data/player.json"
const MARTIALS_PATH := "res://data/martials.json"
const ENEMIES_PATH := "res://data/enemies.json"


static func run(config: Dictionary) -> Dictionary:
	var battle_count: int = int(config.get("battles", 0))
	var seed_value: int = int(config.get("seed", 0))
	var bot: String = str(config.get("bot", "smart"))
	var first_strike: bool = bool(config.get("first_strike", false))
	var enemy_count: int = int(config.get("enemy_count", 1))
	var enemy_id: String = str(config.get("enemy_id", ""))
	var stats_override: Dictionary = {}
	var raw_stats_override: Variant = config.get("stats_override", {})
	if raw_stats_override is Dictionary:
		stats_override = raw_stats_override

	var player_data: Dictionary = DataLoader.load_player(PLAYER_PATH)
	var loaded_martials: Dictionary = DataLoader.load_martials(MARTIALS_PATH)
	var martials: Dictionary = loaded_martials.get("defs", {})
	var enemy_defs: Dictionary = _enemy_defs(config)

	var loadout: Array = config.get("loadout", [])
	if loadout.is_empty():
		var default_loadout: Variant = player_data.get("loadout", [])
		if default_loadout is Array:
			loadout = default_loadout
	var learned: Array = []
	var raw_learned: Variant = player_data.get("learned", [])
	if raw_learned is Array:
		learned = raw_learned

	var totals: Dictionary = {
		"wins": 0,
		"losses": 0,
		"timeouts": 0,
		"avg_rounds": 0.0,
		"win_rate": 0.0,
		"avg_hp_pct": 0.0,
	}
	if battle_count <= 0:
		return totals
	var enemy_def: Variant = enemy_defs.get(enemy_id, null)
	if enemy_def == null:
		return totals

	var bot_rng := RandomNumberGenerator.new()
	bot_rng.seed = seed_value

	var wins := 0
	var losses := 0
	var timeouts := 0
	var total_rounds := 0
	var total_hp_pct := 0.0
	for n in range(battle_count):
		var battle: Variant = _make_battle(
			player_data,
			enemy_def,
			enemy_count,
			loadout,
			learned,
			martials,
			seed_value + n,
			first_strike,
			stats_override
		)
		_run_battle(battle, bot, bot_rng)
		total_rounds += int(battle.round)
		var max_hp := float(battle.player.max_hp)
		if max_hp > 0.0:
			total_hp_pct += float(maxi(0, int(battle.player.hp))) / max_hp
		var final_state: int = battle.state()
		if final_state == Battle.State.WON:
			wins += 1
		elif final_state == Battle.State.LOST:
			losses += 1
		else:
			timeouts += 1

	totals["wins"] = wins
	totals["losses"] = losses
	totals["timeouts"] = timeouts
	totals["avg_rounds"] = float(total_rounds) / float(battle_count)
	totals["win_rate"] = float(wins) / float(battle_count)
	totals["avg_hp_pct"] = total_hp_pct / float(battle_count)
	return totals


static func _enemy_defs(config: Dictionary) -> Dictionary:
	var injected: Variant = config.get("enemy_defs", null)
	if injected is Dictionary:
		var injected_defs: Dictionary = injected
		return injected_defs
	var loaded: Dictionary = DataLoader.load_enemies(ENEMIES_PATH)
	var defs: Dictionary = loaded.get("defs", {})
	return defs


static func _make_battle(
	player_data: Dictionary,
	enemy_def: Variant,
	enemy_count: int,
	loadout: Array,
	learned: Array,
	martials: Dictionary,
	seed_value: int,
	first_strike: bool,
	stats_override: Dictionary
) -> Variant:
	var stats: Dictionary = {}
	var player_realm := str(GameState.realm_id)
	var max_hp := 0
	if not stats_override.is_empty():
		stats = stats_override.duplicate()
		max_hp = Realms.max_hp_for(int(stats.get("constitution", 0)), player_realm)
	else:
		var base_stats: Dictionary = {}
		var raw_stats: Variant = player_data.get("stats", {})
		if raw_stats is Dictionary:
			base_stats = raw_stats
			stats = Progression.final_stats(base_stats)
		# 本轮 player.json 仍带显式 max_hp；没有时才用体质公式。
		if player_data.has("max_hp"):
			max_hp = int(player_data.get("max_hp", 0))
		else:
			max_hp = Progression.max_hp(base_stats)
	var player: Variant = Unit.make_player(
		str(player_data.get("name", "")),
		stats,
		max_hp,
		int(player_data.get("jianyi_max", 0)),
		int(player_data.get("foresight_max", 0)),
		player_realm
	)
	var enemies: Array = []
	for i in range(enemy_count):
		enemies.append(Unit.from_enemy(enemy_def))
	var mastery: Variant = Mastery.new()
	for raw_learned in learned:
		mastery.learn(str(raw_learned))
	for raw_id in loadout:
		mastery.learn(str(raw_id))
	return Battle.new(player, enemies, loadout, mastery, martials, seed_value, first_strike)


static func _run_battle(battle: Variant, bot: String, rng: RandomNumberGenerator) -> void:
	var guard: int = Balance.MAX_ROUNDS + 5
	for i in range(guard):
		if battle.state() != Battle.State.ONGOING:
			return
		var action: Dictionary = _choose_action(battle, bot, rng)
		if action.is_empty():
			return
		var result: Dictionary = battle.submit(action)
		if not bool(result.get("ok", false)):
			var fallback: Dictionary = _fallback_action(battle)
			if fallback.is_empty():
				return
			battle.submit(fallback)


static func _choose_action(battle: Variant, bot: String, rng: RandomNumberGenerator) -> Dictionary:
	if bot == "random":
		return _random_action(battle, rng)
	if bot == "human":
		return _human_action(battle, rng)
	return _smart_action(battle)


# A bot that only uses what the battle UI shows a player: an enemy's move is known only
# after it was executed or foreseen. Known moves are countered exactly; unknown ones are
# guessed (a random martial); foresight is spent whenever the target's move is unknown.
static func _human_action(battle: Variant, rng: RandomNumberGenerator) -> Dictionary:
	var target_index: int = _first_alive(battle.enemies)
	if target_index < 0:
		return {}
	var target: Variant = battle.enemies[target_index]
	if target.is_stunned() or battle.is_move_known(target_index):
		return _smart_action(battle)
	if Jianyi.can_strike(battle.player, target):
		return {"kind": "jianyi", "target": target_index}
	if battle.foresight_available() and battle.foreseen(target_index).is_empty():
		return {"kind": "foresight"}
	var loadout: Array = battle.loadout
	if loadout.is_empty():
		return {}
	var pick: int = rng.randi_range(0, loadout.size() - 1)
	return {"kind": "martial", "id": str(loadout[pick]), "target": target_index}


static func _random_action(battle: Variant, rng: RandomNumberGenerator) -> Dictionary:
	var legal: Array = _legal_actions(battle)
	if legal.is_empty():
		return {}
	var index: int = rng.randi_range(0, legal.size() - 1)
	var picked: Dictionary = legal[index]
	return picked


static func _legal_actions(battle: Variant) -> Array:
	var actions: Array = []
	var enemies: Array = battle.enemies
	var loadout: Array = battle.loadout
	for i in range(enemies.size()):
		var enemy: Variant = enemies[i]
		if enemy.is_dead():
			continue
		for raw_id in loadout:
			actions.append({"kind": "martial", "id": str(raw_id), "target": i})
		if Jianyi.can_strike(battle.player, enemy):
			actions.append({"kind": "jianyi", "target": i})
	return actions


static func _smart_action(battle: Variant) -> Dictionary:
	var enemies: Array = battle.enemies
	var target_index: int = _first_alive(enemies)
	if target_index < 0:
		return {}
	var target: Variant = enemies[target_index]
	if Jianyi.can_strike(battle.player, target) and not target.is_stunned():
		return {"kind": "jianyi", "target": target_index}

	var loadout: Array = battle.loadout
	var martials: Dictionary = battle.martials
	var best_id := ""
	var best_verdict: int = Counter.Verdict.IMPOSSIBLE
	var best_power := -1
	for raw_id in loadout:
		var id: String = str(raw_id)
		if not martials.has(id):
			continue
		var verdict: int = battle.preview(id, target_index)
		if verdict == Counter.Verdict.IMPOSSIBLE:
			continue
		var power: int = int(martials[id].power)
		if verdict > best_verdict or (verdict == best_verdict and power > best_power):
			best_id = id
			best_verdict = verdict
			best_power = power
	if best_id != "":
		return {"kind": "martial", "id": best_id, "target": target_index}

	# 没有能反制的武学（或目标当前没有意图）：选威力最高的武学
	best_id = ""
	best_power = -1
	for raw_id in loadout:
		var id: String = str(raw_id)
		if not martials.has(id):
			continue
		var power: int = int(martials[id].power)
		if power > best_power:
			best_id = id
			best_power = power
	if best_id == "":
		return {}
	return {"kind": "martial", "id": best_id, "target": target_index}


static func _fallback_action(battle: Variant) -> Dictionary:
	var target_index: int = _first_alive(battle.enemies)
	var loadout: Array = battle.loadout
	if target_index < 0 or loadout.is_empty():
		return {}
	return {"kind": "martial", "id": str(loadout[0]), "target": target_index}


static func _first_alive(enemies: Array) -> int:
	for i in range(enemies.size()):
		var enemy: Variant = enemies[i]
		if not enemy.is_dead():
			return i
	return -1

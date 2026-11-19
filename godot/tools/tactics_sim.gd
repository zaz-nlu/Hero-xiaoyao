extends SceneTree

# 战棋模拟器：在 headless 里用 bot 打完整场，输出胜负、行动数、剩余气血、
# 剑意与反制次数。用法：
#   godot --headless --path godot -s res://tools/tactics_sim.gd -- runs=20
#   godot --headless --path godot -s res://tools/tactics_sim.gd -- scenario=all runs=100
# 可用参数：map、group（如 ma_youwei:1,bandit:5）、runs、bot（best/never）、seed；
# 平衡场景另加 scenario（场景名或 all）、profile、bandits、boss_loss。

const DataLoader = preload("res://core/data_loader.gd")
const TacticsAi = preload("res://core/tactics/tactics_ai.gd")
const TacticsBot = preload("res://core/tactics/tactics_bot.gd")
const TacticsEnergy = preload("res://core/tactics/tactics_energy.gd")
const TacticsSetup = preload("res://core/tactics/tactics_setup.gd")

const BALANCE_PATH := "res://data/tactics_balance.json"
const BOSS_ID := "ma_youwei"
const BANDIT_ID := "bandit"
const PLAYER_ID := "player"
const BOTS: Array[String] = ["best", "never"]
const DEFAULT_GROUP := [{"id": "ma_youwei", "count": 1}, {"id": "bandit", "count": 5}]
const MAX_ACTIONS := 200


func _init() -> void:
	var config := _parse_args()
	if str(config["scenario"]) != "":
		var report := run_report(config)
		if not bool(report.get("ok", false)):
			print("tactics_sim setup failed: %s" % str(report.get("errors", [])))
			quit(1)
			return
		for line in report.get("lines", []):
			print(str(line))
		quit(0)
		return
	var runs_value: int = int(config["runs"])
	var runs: int = runs_value if runs_value > 0 else 50
	var group: Array = _parse_group(str(config["group"]))
	var bot_mode := str(config["bot"])
	if bot_mode != "best" and bot_mode != "never":
		bot_mode = "best"
	var base_seed: int = int(config["seed"])

	var wins := 0
	var losses := 0
	var timeouts := 0
	var total_actions := 0
	var max_actions := 0
	var total_hp_pct := 0.0
	var total_jianyi := 0
	var total_counters := 0
	var total_weak_hits := 0
	var total_breaks := 0
	var total_releases := 0
	var energy_uses := {"neili": 0, "ziqi": 0, "xianqi": 0}

	for n in range(runs):
		var run_seed := base_seed + n
		var built: Dictionary = TacticsSetup.build(str(config["map"]), group, null, run_seed)
		if not bool(built.get("ok", false)):
			print("tactics_sim setup failed: %s" % str(built.get("errors", [])))
			quit(1)
			return
		var battle: Variant = built["battle"]
		var rng := RandomNumberGenerator.new()
		rng.seed = run_seed
		var picker: Callable = func(preview: Array) -> Dictionary:
			return TacticsBot.pick_reactions(preview, bot_mode)
		var actions := 0
		while battle.result() == "" and actions < MAX_ACTIONS:
			var actor: String = battle.begin_turn()
			if actor == "":
				break
			var unit = battle.get_unit(actor)
			if unit != null and unit.side == "player":
				TacticsBot.take_turn(battle, actor, rng, bot_mode)
			else:
				TacticsAi.take_turn(battle, actor, rng, picker)
			battle.end_turn(actor)
			actions += 1

		var outcome: String = battle.result()
		if outcome == "":
			timeouts += 1
		elif outcome == "win":
			wins += 1
		else:
			losses += 1

		total_actions += actions
		max_actions = maxi(max_actions, actions)
		var player = battle.get_unit("player")
		if player != null and int(player.unit.max_hp) > 0:
			var hp_ratio := float(maxi(0, int(player.unit.hp))) / float(player.unit.max_hp)
			total_hp_pct += clampf(hp_ratio, 0.0, 1.0)
		for event in battle.log:
			var event_type := str(event.get("type", ""))
			if event_type == "jianyi" and str(event.get("unit", "")) == "player":
				total_jianyi += 1
			elif event_type == "hit" and str(event.get("reaction", "")) != "":
				total_counters += 1
			elif event_type == "hit" and bool(event.get("weak", false)):
				total_weak_hits += 1
			elif event_type == "stun":
				total_breaks += 1
			elif event_type == "heal" and str(event.get("source", "")) == "ziqi_release":
				total_releases += 1
			elif event_type == "attack" and str(event.get("unit", "")) == "player":
				var energy := str(event.get("energy", "neili"))
				energy_uses[energy] = int(energy_uses.get(energy, 0)) + 1

	var run_count := float(runs)
	print("tactics_sim map=%s group=%s bot=%s seed=%d runs=%d" % [
		str(config["map"]), _group_text(group), bot_mode, base_seed, runs,
	])
	print("win %d  loss %d  timeout %d  win_rate %.1f%%" % [
		wins, losses, timeouts, float(wins) / run_count * 100.0,
	])
	print("actions avg %.1f  max %d" % [float(total_actions) / run_count, max_actions])
	print("player hp avg %.1f%%" % [total_hp_pct / run_count * 100.0])
	print("jianyi avg %.2f  counters avg %.2f" % [
		float(total_jianyi) / run_count, float(total_counters) / run_count,
	])
	print("weak_hits avg %.2f  breaks avg %.2f" % [
		float(total_weak_hits) / run_count, float(total_breaks) / run_count,
	])
	print("ziqi_release avg %.2f" % [float(total_releases) / run_count])
	print("energy avg neili %.2f  ziqi %.2f  xianqi %.2f" % [
		float(energy_uses["neili"]) / run_count,
		float(energy_uses["ziqi"]) / run_count,
		float(energy_uses["xianqi"]) / run_count,
	])
	quit(0)


func _parse_args() -> Dictionary:
	var config := {
		"map": "tavern_brawl",
		"group": "",
		"runs": -1,
		"bot": "best",
		"seed": 1,
		"scenario": "",
		"profile": "",
		"bandits": -1,
		"boss_loss": -1,
	}
	for raw_arg in OS.get_cmdline_user_args():
		var arg := str(raw_arg).strip_edges()
		if arg.begins_with("--"):
			arg = arg.substr(2)
		var split := arg.find("=")
		if split <= 0:
			continue
		var key := arg.substr(0, split)
		var value := arg.substr(split + 1)
		match key:
			"map":
				config["map"] = value
			"group":
				config["group"] = value
			"runs":
				config["runs"] = int(value)
			"bot":
				config["bot"] = value
			"seed":
				config["seed"] = int(value)
			"scenario":
				config["scenario"] = value
			"profile":
				config["profile"] = value
			"bandits":
				config["bandits"] = int(value)
			"boss_loss":
				config["boss_loss"] = int(value)
	return config


# --- 平衡场景：场景与目标都在 data/tactics_balance.json，不写死在脚本里 ---

static func load_balance() -> Dictionary:
	var text := FileAccess.get_file_as_string(BALANCE_PATH)
	if text == "":
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {}
	var data: Dictionary = parsed
	return data


# 按场景装配一场战斗：属性预设写进 stats_override，bandit 数量覆盖组，
# 头子按 boss_loss 扣开战气血（最低保留 1，与 tactics_session 一致）。
static func build_scenario_battle(
	balance: Dictionary,
	scenario_name: String,
	config: Dictionary,
	run_seed: int
) -> Dictionary:
	var errors: Array[String] = []
	var scenarios: Dictionary = balance.get("scenarios", {})
	if not scenarios.has(scenario_name):
		errors.append("unknown scenario '%s'" % scenario_name)
		return {"ok": false, "errors": errors, "battle": null}
	var scenarios_profiles: Dictionary = balance.get("profiles", {})
	var entry: Dictionary = scenarios[scenario_name]
	var profile_name := str(config.get("profile", ""))
	if profile_name == "":
		profile_name = str(entry.get("profile", ""))
	if not scenarios_profiles.has(profile_name):
		errors.append(
			"scenario '%s': unknown profile '%s'" % [scenario_name, profile_name])
		return {"ok": false, "errors": errors, "battle": null}
	var profile: Dictionary = scenarios_profiles[profile_name]
	var bandits := int(entry.get("bandits", 0))
	if int(config.get("bandits", -1)) >= 0:
		bandits = int(config.get("bandits"))
	var boss_loss := int(entry.get("boss_loss", 0))
	if int(config.get("boss_loss", -1)) >= 0:
		boss_loss = int(config.get("boss_loss"))
	var map_id := str(balance.get("map", "tavern_brawl"))
	if map_id == "":
		map_id = "tavern_brawl"
	var group: Array = [
		{"id": BOSS_ID, "count": 1},
		{"id": BANDIT_ID, "count": maxi(0, bandits)},
	]
	var player_data: Dictionary = DataLoader.load_player(DataLoader.PLAYER_PATH).duplicate(true)
	if player_data.is_empty():
		errors.append("player: cannot read %s" % DataLoader.PLAYER_PATH)
		return {"ok": false, "errors": errors, "battle": null}
	player_data["stats_override"] = profile.duplicate(true)
	var built: Dictionary = TacticsSetup.build(map_id, group, player_data, run_seed)
	if not bool(built.get("ok", false)):
		return {"ok": false, "errors": built.get("errors", []), "battle": null}
	var battle: Variant = built["battle"]
	TacticsEnergy.apply_defaults(battle.get_unit(PLAYER_ID))
	var boss = _find_unit(battle, BOSS_ID)
	if boss == null:
		errors.append("scenario '%s': battle has no '%s'" % [scenario_name, BOSS_ID])
		return {"ok": false, "errors": errors, "battle": null}
	if boss_loss > 0:
		boss.unit.hp = maxi(1, int(boss.unit.hp) - boss_loss)
	return {
		"ok": true,
		"errors": [],
		"battle": battle,
		"profile": profile_name,
		"bandits": bandits,
		"boss_loss": boss_loss,
	}


# 跑一个场景 × 一种 bot，返回胜率、胜局剩余气血与各项平均统计。
static func run_scenario(
	balance: Dictionary,
	scenario_name: String,
	bot_mode: String,
	config: Dictionary,
	runs: int,
	base_seed: int
) -> Dictionary:
	var wins := 0
	var losses := 0
	var timeouts := 0
	var total_actions := 0
	var total_win_hp := 0.0
	var weak_hits := 0
	var breaks := 0
	var ziqi_release := 0
	var perfect_counters := 0
	var boss_reached := 0
	var run_count := float(maxi(1, runs))
	for n in range(runs):
		var run_seed := base_seed + n
		var built := build_scenario_battle(balance, scenario_name, config, run_seed)
		if not bool(built.get("ok", false)):
			return {"ok": false, "errors": built.get("errors", [])}
		var battle: Variant = built["battle"]
		var rng := RandomNumberGenerator.new()
		rng.seed = run_seed
		var picker: Callable = func(preview: Array) -> Dictionary:
			return TacticsBot.pick_reactions(preview, bot_mode)
		var actions := 0
		while battle.result() == "" and actions < MAX_ACTIONS:
			var actor: String = battle.begin_turn()
			if actor == "":
				break
			var unit = battle.get_unit(actor)
			if unit != null and unit.side == "player":
				TacticsBot.take_turn(battle, actor, rng, bot_mode)
			else:
				TacticsAi.take_turn(battle, actor, rng, picker)
			battle.end_turn(actor)
			actions += 1

		var outcome: String = battle.result()
		if outcome == "win":
			wins += 1
			var hero = battle.get_unit(PLAYER_ID)
			if hero != null and int(hero.unit.max_hp) > 0:
				total_win_hp += clampf(
					float(maxi(0, int(hero.unit.hp))) / float(hero.unit.max_hp), 0.0, 1.0)
		elif outcome == "":
			timeouts += 1
		else:
			losses += 1
		total_actions += actions

		var reached := false
		for event in battle.log:
			var event_type := str(event.get("type", ""))
			if event_type == "hit":
				if bool(event.get("weak", false)):
					weak_hits += 1
				if str(event.get("outcome", "")) == "perfect" \
						and str(event.get("defender", "")) == PLAYER_ID:
					perfect_counters += 1
				if _player_hit_boss(event):
					reached = true
			elif event_type == "counter_hit":
				if _player_hit_boss(event):
					reached = true
			elif event_type == "stun":
				breaks += 1
			elif event_type == "heal" and str(event.get("source", "")) == "ziqi_release":
				ziqi_release += 1
		if reached:
			boss_reached += 1

	return {
		"ok": true,
		"errors": [],
		"scenario": scenario_name,
		"bot": bot_mode,
		"runs": runs,
		"wins": wins,
		"losses": losses,
		"timeouts": timeouts,
		"win_rate": float(wins) / run_count * 100.0,
		"hp_rate": (total_win_hp / float(wins) * 100.0) if wins > 0 else 0.0,
		"actions": float(total_actions) / run_count,
		"weak_hits": float(weak_hits) / run_count,
		"breaks": float(breaks) / run_count,
		"ziqi_release": float(ziqi_release) / run_count,
		"perfect_counters": float(perfect_counters) / run_count,
		"boss_reached": float(boss_reached) / run_count * 100.0,
	}


# scenario=all：所有场景 × best/never 各一行，按 targets 判 PASS/FAIL。
# rows 是表格行，lines 追加最后的“N/M 通过”；退出码由调用方决定。
static func run_report(config: Dictionary) -> Dictionary:
	var balance := load_balance()
	if balance.is_empty():
		return {"ok": false, "errors": ["cannot read %s" % BALANCE_PATH], "rows": [], "lines": []}
	var scenarios: Dictionary = balance.get("scenarios", {})
	var names: Array[String] = []
	var wanted := str(config.get("scenario", "all"))
	if wanted == "all":
		for key in scenarios.keys():
			names.append(str(key))
	elif scenarios.has(wanted):
		names.append(wanted)
	else:
		return {"ok": false, "errors": ["unknown scenario '%s'" % wanted], "rows": [], "lines": []}
	var targets: Dictionary = balance.get("targets", {})
	var runs := int(config.get("runs", -1))
	if runs <= 0:
		runs = 100
	var seed_value := int(config.get("seed", 1))
	var rows: Array = []
	var lines: Array[String] = []
	var passed := 0
	for scenario_name in names:
		for bot_mode in BOTS:
			var summary := run_scenario(balance, scenario_name, bot_mode, config, runs, seed_value)
			if not bool(summary.get("ok", false)):
				return {
					"ok": false,
					"errors": summary.get("errors", []),
					"rows": rows,
					"lines": lines,
				}
			var scenario_targets: Dictionary = targets.get(scenario_name, {})
			var target: Dictionary = scenario_targets.get(bot_mode, {})
			var ok := _meets_target(summary, target)
			summary["target"] = target
			summary["pass"] = ok
			rows.append(summary)
			if ok:
				passed += 1
			lines.append(_row_line(summary))
	lines.append("%d/%d 通过" % [passed, rows.size()])
	return {"ok": true, "errors": [], "rows": rows, "lines": lines}


static func _meets_target(summary: Dictionary, target: Dictionary) -> bool:
	if target.is_empty():
		return true
	var win := float(summary.get("win_rate", 0.0))
	var hp := float(summary.get("hp_rate", 0.0))
	if target.has("win_min") and win + 0.05 < float(target.get("win_min", 0.0)):
		return false
	if target.has("win_max") and win - 0.05 > float(target.get("win_max", 0.0)):
		return false
	if target.has("hp_min") and hp + 0.05 < float(target.get("hp_min", 0.0)):
		return false
	if target.has("hp_max") and hp - 0.05 > float(target.get("hp_max", 0.0)):
		return false
	return true


static func _row_line(row: Dictionary) -> String:
	var status := "PASS" if bool(row.get("pass", false)) else "FAIL"
	return "%s  %s  win %.1f%%  hp %.1f%%  actions %.1f  weak_hits %.2f  breaks %.2f  ziqi_release %.2f  perfect_counters %.2f  boss_reached %.1f%%  %s" % [
		str(row.get("scenario", "")),
		str(row.get("bot", "")),
		float(row.get("win_rate", 0.0)),
		float(row.get("hp_rate", 0.0)),
		float(row.get("actions", 0.0)),
		float(row.get("weak_hits", 0.0)),
		float(row.get("breaks", 0.0)),
		float(row.get("ziqi_release", 0.0)),
		float(row.get("perfect_counters", 0.0)),
		float(row.get("boss_reached", 0.0)),
		status,
	]


static func _player_hit_boss(event: Dictionary) -> bool:
	return str(event.get("attacker", "")) == PLAYER_ID \
			and str(event.get("defender", "")) == BOSS_ID \
			and int(event.get("damage", 0)) > 0


static func _find_unit(battle, uid: String):
	for entry in battle.units:
		if str(entry.id) == uid:
			return entry
	return null


func _parse_group(text: String) -> Array:
	var trimmed := text.strip_edges()
	if trimmed == "":
		return DEFAULT_GROUP.duplicate(true)
	var out: Array = []
	for raw_part in trimmed.split(","):
		var part := str(raw_part).strip_edges()
		if part == "":
			continue
		var pieces := part.split(":")
		var enemy_id := str(pieces[0]).strip_edges()
		if enemy_id == "":
			continue
		var count := 1
		if pieces.size() > 1:
			count = int(pieces[1])
		out.append({"id": enemy_id, "count": maxi(1, count)})
	if out.is_empty():
		return DEFAULT_GROUP.duplicate(true)
	return out


func _group_text(group: Array) -> String:
	var text := ""
	for entry in group:
		var item: Dictionary = entry
		if text != "":
			text += ","
		text += "%s:%d" % [str(item.get("id", "")), int(item.get("count", 1))]
	return text

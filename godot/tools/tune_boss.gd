extends SceneTree

# Scratch tuning tool: sweeps the boss's threat/power/HP and prints human/smart win rates
# for the starting and fully-grown stat lines.
#   godot --headless --path godot -s res://tools/tune_boss.gd

const Simulator = preload("res://core/simulator.gd")
const DataLoader = preload("res://core/data_loader.gd")


func _init() -> void:
	var player_data: Dictionary = DataLoader.load_player("res://data/player.json")
	var base: Dictionary = player_data.get("stats", {})
	var grown := {
		"power": 8,
		"speed": 9,
		"defense": 5,
		"recovery": 5,
		"skill": 17,
		"constitution": 6,
	}
	var configs: Array = [
		[0, 0, 295], [1, 0, 295], [2, 0, 295], [1, 1, 295], [2, 1, 295], [0, 1, 330], [1, 1, 360],
	]
	for cfg in configs:
		var loaded: Dictionary = DataLoader.load_enemies("res://data/enemies.json")
		var defs: Dictionary = loaded.get("defs", {})
		var boss: Variant = defs["ma_youwei"]
		var new_moves: Array = []
		for raw in boss.moves:
			var m: Dictionary = raw.duplicate()
			m["threat"] = int(m["threat"]) + int(cfg[0])
			m["power"] = int(m["power"]) + int(cfg[1])
			new_moves.append(m)
		boss.moves = new_moves
		# enemies.json 不再写 max_hp（默认按体质算 295）；这里显式覆盖以扫描血量，
		# EnemyDef.max_hp 仍会被 Unit.from_enemy 优先采用。
		boss.max_hp = int(cfg[2])
		var line := "threat+%d power+%d hp %d :" % [cfg[0], cfg[1], cfg[2]]
		for label in ["init", "grown"]:
			for bot in ["human", "smart"]:
				var r: Dictionary = Simulator.run({
					"enemy_id": "ma_youwei", "enemy_count": 1, "battles": 300, "seed": 3,
					"bot": bot, "first_strike": false,
					"stats_override": base if label == "init" else grown,
					"enemy_defs": defs,
				})
				line += "  %s/%s %.0f%%(%.0fhp)" % [label, bot, float(r["win_rate"]) * 100.0, float(r["avg_hp_pct"]) * 100.0]
		print(line)
	quit(0)

extends SceneTree

# Scratch tuning tool: sweeps the boss's threat/power/HP and prints human/smart win rates
# for the starting and fully-grown stat lines.
#   godot --headless --path godot -s res://tools/tune_boss.gd

const Simulator = preload("res://core/simulator.gd")
const DataLoader = preload("res://core/data_loader.gd")


func _init() -> void:
	var player_data: Dictionary = DataLoader.load_player("res://data/player.json")
	var base: Dictionary = player_data.get("stats", {})
	var grown := base.duplicate()
	grown["skill"] = int(grown["skill"]) + 5
	grown["speed"] = int(grown["speed"]) + 1
	grown["power"] = int(grown["power"]) + 2
	grown["defense"] = int(grown["defense"]) + 1
	grown["recovery"] = int(grown["recovery"]) + 2
	var configs: Array = [
		[7, 1, 300], [7, 2, 300], [7, 3, 300], [7, 3, 330], [7, 4, 340], [7, 4, 360], [7, 2, 340],
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

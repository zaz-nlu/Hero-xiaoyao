extends SceneTree

# Scratch tuning tool for the final chapter-1 boss. Each config:
#   [kaishan_threat, kaishan_power, luandao_threat, luandao_power, cihou_threat, cihou_power,
#    boss_recovery, boss_defense, boss_hp, boss_toughness, weak_move]
# Prints human/smart win rates (and average hp left) for the starting and the grown stat lines.
#   godot --headless --path godot -s res://tools/tune_boss.gd

const Simulator = preload("res://core/simulator.gd")
const DataLoader = preload("res://core/data_loader.gd")

const GROWN := {"power": 8, "speed": 9, "defense": 5, "recovery": 5, "skill": 17, "constitution": 6}
const BATTLES := 200


func _init() -> void:
	var player_data: Dictionary = DataLoader.load_player("res://data/player.json")
	var base: Dictionary = player_data.get("stats", {})
	var configs: Array = [
		[21, 22, 17, 16, 19, 18, 1, 6, 195, 8, "cihou"],
		[21, 24, 17, 18, 19, 20, 1, 6, 195, 8, "cihou"],
		[20, 22, 16, 16, 18, 18, 1, 6, 195, 8, "cihou"],
		[21, 22, 17, 16, 19, 18, 1, 6, 195, 6, "cihou"],
		[22, 22, 18, 16, 19, 18, 1, 6, 195, 8, "cihou"],
		[21, 26, 17, 20, 19, 22, 1, 6, 195, 8, "cihou"],
		[21, 22, 17, 16, 19, 18, 2, 6, 195, 8, "cihou"],
		[20, 24, 16, 18, 18, 20, 1, 6, 195, 8, "cihou"],
	]
	for cfg in configs:
		var loaded: Dictionary = DataLoader.load_enemies("res://data/enemies.json")
		var defs: Dictionary = loaded.get("defs", {})
		var boss: Variant = defs["ma_youwei"]
		var by_id := {"kaishan": [cfg[0], cfg[1]], "luandao": [cfg[2], cfg[3]], "cihou": [cfg[4], cfg[5]]}
		var new_moves: Array = []
		for raw in boss.moves:
			var m: Dictionary = raw.duplicate()
			var pair: Array = by_id[str(m["id"])]
			m["threat"] = int(pair[0])
			m["power"] = int(pair[1])
			new_moves.append(m)
		boss.moves = new_moves
		boss.stats["recovery"] = int(cfg[6])
		boss.stats["defense"] = int(cfg[7])
		boss.max_hp = int(cfg[8])
		boss.toughness = int(cfg[9])
		boss.weak_moves = [str(cfg[10])]
		var line := "k%d/%d l%d/%d c%d/%d rec%d def%d hp%d tough%d weak=%s :" % cfg
		for label in ["init", "grown"]:
			for bot in ["human", "smart"]:
				var r: Dictionary = Simulator.run({
					"enemy_id": "ma_youwei", "enemy_count": 1, "battles": BATTLES, "seed": 3,
					"bot": bot, "first_strike": false,
					"stats_override": base if label == "init" else GROWN,
					"enemy_defs": defs,
				})
				line += "  %s/%s %.0f%%(%.0fhp,%.0frd)" % [label, bot, float(r["win_rate"]) * 100.0, float(r["avg_hp_pct"]) * 100.0, float(r["avg_rounds"])]
		print(line)
	quit(0)

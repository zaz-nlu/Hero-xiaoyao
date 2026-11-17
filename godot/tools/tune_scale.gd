extends SceneTree

# Scratch: retune the cast for a weaker (nine-year-old) protagonist.
#   godot --headless --path godot -s res://tools/tune_scale.gd

const Simulator = preload("res://core/simulator.gd")
const DataLoader = preload("res://core/data_loader.gd")

const INIT := {"power": 6, "speed": 8, "defense": 4, "recovery": 4, "skill": 12, "mechanism": 3}
# +3 free points into skill, spar +2 skill, sword +1 spd/+1 pow, herb +2 rec, scout +1 pow/+1 def
const GROWN := {"power": 8, "speed": 9, "defense": 5, "recovery": 6, "skill": 17, "mechanism": 3}


func _boss(defs: Dictionary, spd: int, dfn: int, pw: int, t: int, hp: int, tough: int) -> void:
	var boss: Variant = defs["ma_youwei"]
	boss.stats = {"power": pw, "speed": spd, "defense": dfn, "recovery": 3, "skill": 8, "mechanism": 3}
	boss.moves = [
		{"id": "kaishan", "name": "开山", "type": "heavy", "threat": t + 3, "power": pw + 6},
		{"id": "luandao", "name": "乱刀横扫", "type": "sweep", "threat": t - 1, "power": pw},
		{"id": "cihou", "name": "刺喉", "type": "thrust", "threat": t + 1, "power": pw + 2},
	]
	boss.max_hp = hp
	boss.toughness = tough


func _init() -> void:
	var configs: Array = [
		# spd dfn pw  t  hp tough
		[8, 5, 8, 16, 200, 6],
		[8, 5, 8, 18, 200, 6],
		[8, 5, 8, 19, 200, 6],
		[8, 5, 7, 18, 200, 6],
		[8, 5, 8, 18, 160, 6],
		[8, 4, 8, 18, 200, 6],
		[9, 5, 8, 18, 200, 6],
	]
	for cfg in configs:
		var loaded: Dictionary = DataLoader.load_enemies("res://data/enemies.json")
		var defs: Dictionary = loaded.get("defs", {})
		_boss(defs, cfg[0], cfg[1], cfg[2], cfg[3], cfg[4], cfg[5])
		var line := "spd%d def%d pw%d t%d hp%d tough%d :" % cfg
		for label in ["init", "grown"]:
			for bot in ["human", "smart"]:
				var r: Dictionary = Simulator.run({
					"enemy_id": "ma_youwei", "enemy_count": 1, "battles": 300, "seed": 5,
					"bot": bot, "first_strike": false,
					"stats_override": INIT if label == "init" else GROWN,
					"enemy_defs": defs,
				})
				line += "  %s/%s %.0f%%(%.0fhp)" % [label, bot, float(r["win_rate"]) * 100.0, float(r["avg_hp_pct"]) * 100.0]
		print(line)
	quit(0)

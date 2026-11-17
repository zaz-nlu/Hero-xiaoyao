extends SceneTree

# Scratch tuner for the chapter-1 tavern fight (boss + bandits, after the Zixia pre-fight).
# Each config: [bandit_power_delta, boss_power_delta, bandit_threat_delta, boss_threat_delta]
#   godot --headless --path godot -s res://tools/tune_tavern.gd

const Simulator = preload("res://core/simulator.gd")
const DataLoader = preload("res://core/data_loader.gd")
const Prefight = preload("res://core/prefight.gd")

const INITIAL := {"power": 6, "speed": 8, "defense": 4, "recovery": 3, "skill": 12, "constitution": 4}
const GROWN := {"power": 8, "speed": 9, "defense": 5, "recovery": 5, "skill": 17, "constitution": 6}
const BATTLES := 200


func _init() -> void:
	var configs: Array = [
		[-6, -5, 0, -1], [-6, -6, 0, -1], [-6, -7, 0, -1],
		[-7, -5, 0, -1], [-7, -6, 0, -1], [-5, -6, 0, -1],
	]
	for cfg in configs:
		var loaded: Dictionary = DataLoader.load_enemies("res://data/enemies.json")
		var defs: Dictionary = loaded.get("defs", {})
		for id in ["bandit", "ma_youwei"]:
			var def: Variant = defs[id]
			var pd: int = int(cfg[0]) if id == "bandit" else int(cfg[1])
			var td: int = int(cfg[2]) if id == "bandit" else int(cfg[3])
			var moves: Array = []
			for raw in def.moves:
				var m: Dictionary = raw.duplicate()
				m["power"] = int(m["power"]) + pd
				m["threat"] = int(m["threat"]) + td
				moves.append(m)
			def.moves = moves
		var line := "bP%+d mP%+d bT%+d mT%+d :" % cfg
		for sc in [["unprepared", INITIAL, 5, 0], ["prepared", GROWN, 2, 3]]:
			var loss: int = int(Prefight.simulate(int(sc[2])).get("boss_damage", 0))
			var r: Dictionary = Simulator.run({
				"enemies": [{"id": "ma_youwei", "count": 1}, {"id": "bandit", "count": int(sc[2])}],
				"herbs": int(sc[3]), "battles": BATTLES, "seed": 7, "bot": "human",
				"first_strike": false, "stats_override": sc[1], "boss_hp_loss": loss, "enemy_defs": defs,
			})
			line += "  %s %.0f%% (%.0fhp, %.0frd)" % [sc[0], float(r["win_rate"]) * 100.0, float(r["avg_hp_pct"]) * 100.0, float(r["avg_rounds"])]
		print(line)
	quit(0)

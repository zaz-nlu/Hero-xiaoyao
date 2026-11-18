extends SceneTree

const Simulator = preload("res://tools/simulator.gd")


func _init() -> void:
	var args: Dictionary = _parse_args(OS.get_cmdline_user_args())
	var config: Dictionary = {
		"enemy_id": str(args.get("enemy", "bandit")),
		"bot": str(args.get("bot", "smart")),
		"battles": int(args.get("battles", 100)),
		"seed": int(args.get("seed", 1)),
		"enemy_count": int(args.get("count", 1)),
		"first_strike": bool(args.get("first-strike", false)),
	}
	var result: Dictionary = Simulator.run(config)
	print("enemy=%s bot=%s battles=%d wins=%d losses=%d timeouts=%d win_rate=%.2f avg_rounds=%.1f" % [
		config["enemy_id"],
		config["bot"],
		int(config["battles"]),
		int(result["wins"]),
		int(result["losses"]),
		int(result["timeouts"]),
		float(result["win_rate"]),
		float(result["avg_rounds"]),
	])
	quit(0)


func _parse_args(raw: PackedStringArray) -> Dictionary:
	var parsed: Dictionary = {}
	for arg in raw:
		if not arg.begins_with("--"):
			continue
		var body: String = arg.substr(2)
		var eq: int = body.find("=")
		if eq < 0:
			parsed[body] = true
		else:
			parsed[body.substr(0, eq)] = body.substr(eq + 1)
	return parsed

extends SceneTree

# Difficulty report for the forest tutorial. Runs the two target encounters with
# both the starting and the fully-grown stat lines, using the random and smart
# bots, then prints a Markdown table and rewrites section 9 of the design doc.
#
# Run with:
#   godot --headless --path godot -s res://tools/difficulty_report.gd

const Simulator = preload("res://core/simulator.gd")
const DataLoader = preload("res://core/data_loader.gd")

const PLAYER_PATH := "res://data/player.json"
const DOC_RELATIVE := "../docs/superpowers/specs/2026-11-17-forest-growth-tutorial-design.md"
const BATTLES := 400
const SEED := 1
const TARGET_LOW := 15.0
const TARGET_HIGH := 35.0
const GROWN_LOW := 65.0
const GROWN_HIGH := 85.0


func _init() -> void:
	var player_data: Dictionary = DataLoader.load_player(PLAYER_PATH)
	var base_stats: Dictionary = player_data.get("stats", {})
	var initial := base_stats.duplicate()
	var grown := base_stats.duplicate()
	# 3 unspent points into skill, sparring +2 skill, sword +1 speed/+1 power,
	# herb +2 recovery, scout +1 power/+1 defense.
	_add_stat(grown, "skill", 5)
	_add_stat(grown, "speed", 1)
	_add_stat(grown, "power", 2)
	_add_stat(grown, "defense", 1)
	_add_stat(grown, "recovery", 2)

	var stat_sets: Array = [
		{"label": "初始属性", "stats": initial},
		{"label": "养成后属性", "stats": grown},
	]
	var scenarios: Array = [
		{"label": "酒馆遭遇（马匪头子 ×1）", "enemy_id": "ma_youwei", "count": 1},
		{"label": "两个马匪（马匪 ×2）", "enemy_id": "bandit", "count": 2},
	]
	var bots: Array[String] = ["random", "human", "smart"]

	var rows: Array = []
	for scenario_value in scenarios:
		var scenario: Dictionary = scenario_value
		for stat_set_value in stat_sets:
			var stat_set: Dictionary = stat_set_value
			for bot in bots:
				var result: Dictionary = Simulator.run({
					"enemy_id": str(scenario["enemy_id"]),
					"enemy_count": int(scenario["count"]),
					"battles": BATTLES,
					"seed": SEED,
					"bot": bot,
					"first_strike": false,
					"stats_override": stat_set["stats"],
				})
				var row := {
					"scenario": str(scenario["label"]),
					"stats": str(stat_set["label"]),
					"bot": bot,
					"win_rate": float(result["win_rate"]),
					"avg_rounds": float(result["avg_rounds"]),
					"avg_hp_pct": float(result["avg_hp_pct"]),
				}
				rows.append(row)
				print("%s | %s | %s | 胜率 %.1f%% | 平均回合 %.1f | 剩余 HP %.1f%%" % [
					row["scenario"],
					row["stats"],
					row["bot"],
					float(row["win_rate"]) * 100.0,
					float(row["avg_rounds"]),
					float(row["avg_hp_pct"]) * 100.0,
				])

	var section := _build_section(rows)
	_append_to_doc(section)
	quit(0)


func _add_stat(stats: Dictionary, key: String, amount: int) -> void:
	stats[key] = int(stats.get(key, 0)) + amount


func _find_row(rows: Array, scenario: String, stats_label: String, bot: String) -> Dictionary:
	for row_value in rows:
		var row: Dictionary = row_value
		if str(row["scenario"]) == scenario and str(row["stats"]) == stats_label \
				and str(row["bot"]) == bot:
			return row
	return {}


func _build_section(rows: Array) -> String:
	var lines: Array[String] = []
	lines.append("## 9. 难度模拟结果")
	lines.append("")
	lines.append("每格 400 局，`first_strike=false`，由 `tools/difficulty_report.gd` 生成。马匪头子数值已调整：三招威胁 +7、威力 +2（调参工具：`tools/tune_boss.gd`）。")
	lines.append("")
	lines.append("| 遭遇 | 属性 | bot | 胜率 | 平均回合 | 玩家平均剩余 HP |")
	lines.append("| --- | --- | --- | ---: | ---: | ---: |")
	for row_value in rows:
		var row: Dictionary = row_value
		lines.append("| %s | %s | %s | %.1f%% | %.1f | %.1f%% |" % [
			row["scenario"],
			row["stats"],
			row["bot"],
			float(row["win_rate"]) * 100.0,
			float(row["avg_rounds"]),
			float(row["avg_hp_pct"]) * 100.0,
		])
	lines.append("")
	lines.append("bot 说明：random 乱出招；human 只用界面上看得到的信息（未知招靠猜，有预判点数先预判，已识别的招精确反制）；smart 能直接看到所有出招（上限）。目标：human 在初始属性下打马匪头子胜率 15%~35%，养成后 65%~85%（真人比 human 更容易失误，所以养成后偏高是预期的）。")

	var boss_scenario := "酒馆遭遇（马匪头子 ×1）"
	var initial_row := _find_row(rows, boss_scenario, "初始属性", "human")
	var grown_row := _find_row(rows, boss_scenario, "养成后属性", "human")
	if not initial_row.is_empty() and not grown_row.is_empty():
		var initial_rate := float(initial_row["win_rate"]) * 100.0
		var grown_rate := float(grown_row["win_rate"]) * 100.0
		lines.append("")
		lines.append("实际与目标的差距：初始属性 %.1f%%（%s）；养成后 %.1f%%（%s）。" % [
			initial_rate,
			_range_gap(initial_rate, TARGET_LOW, TARGET_HIGH),
			grown_rate,
			_range_gap(grown_rate, GROWN_LOW, GROWN_HIGH),
		])
	return "\n".join(lines) + "\n"


func _range_gap(value: float, low: float, high: float) -> String:
	if value < low:
		return "比目标下限低 %.1f 个百分点" % (low - value)
	if value > high:
		return "比目标上限高 %.1f 个百分点" % (value - high)
	return "落在目标区间内"


func _doc_path() -> String:
	var base := ProjectSettings.globalize_path("res://").simplify_path()
	return base.path_join(DOC_RELATIVE).simplify_path()


func _append_to_doc(section: String) -> void:
	var path := _doc_path()
	var text := ""
	if FileAccess.file_exists(path):
		text = FileAccess.get_file_as_string(path)
	var marker := "## 9. 难度模拟结果"
	var at := text.find(marker)
	if at >= 0:
		text = text.substr(0, at).strip_edges()
		text += "\n\n"
	elif text != "" and not text.ends_with("\n"):
		text += "\n\n"
	text += section
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("difficulty_report: cannot write %s" % path)
		return
	file.store_string(text)
	file.close()
	print("wrote %s" % path)

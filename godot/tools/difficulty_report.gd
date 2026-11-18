extends SceneTree

# Difficulty report for chapter 1. Runs the two target encounters with both the
# starting and the fully-grown stat lines, using the random, human and smart bots,
# then prints a Markdown table and rewrites section 11 of the numbers design doc.
#
# Run with:
#   godot --headless --path godot -s res://tools/difficulty_report.gd

const Simulator = preload("res://tools/simulator.gd")
const DataLoader = preload("res://core/data_loader.gd")
const Prefight = preload("res://core/prefight.gd")

const PLAYER_PATH := DataLoader.PLAYER_PATH
const DOC_RELATIVE := "../docs/superpowers/specs/2026-11-17-numbers-system-design.md"
const BATTLES := 400
const SEED := 1
const TARGET_LOW := 10.0
const TARGET_HIGH := 30.0
const GROWN_LOW := 65.0
const GROWN_HIGH := 85.0


func _init() -> void:
	var player_data: Dictionary = DataLoader.load_player(PLAYER_PATH)
	var base_stats: Dictionary = player_data.get("stats", {})
	var initial := base_stats.duplicate()
	# 第一章当前可得 9 点（宝箱剑 +2、草药 +2、试招 +2、探子 +2、养元丹 +1）
	# 加 3 个自由点全加技巧；constitution 6 含之后由别的任务补的 1 点，
	# 即文档 §7 的 50 点参考线。
	var grown := {
		"power": 8,
		"speed": 9,
		"defense": 5,
		"recovery": 5,
		"skill": 17,
		"constitution": 6,
	}

	var scenarios: Array = [
		{
			"label": "酒馆战（未准备）",
			"stats": "初始属性",
			"stats_override": initial,
			"enemies": [
				{"id": "ma_youwei", "count": 1},
				{"id": "bandit", "count": 5},
			],
			"bandits": 5,
			"herbs": 0,
		},
		{
			"label": "酒馆战（准备好）",
			"stats": "养成后属性",
			"stats_override": grown,
			"enemies": [
				{"id": "ma_youwei", "count": 1},
				{"id": "bandit", "count": 2},
			],
			"bandits": 2,
			"herbs": 3,
		},
	]
	var bots: Array[String] = ["random", "human", "smart"]

	var rows: Array = []
	for scenario_value in scenarios:
		var scenario: Dictionary = scenario_value
		for bot in bots:
			var result: Dictionary = Simulator.run({
				"enemies": scenario["enemies"],
				"herbs": int(scenario["herbs"]),
				"battles": BATTLES,
				"seed": SEED,
				"bot": bot,
				"first_strike": false,
				"stats_override": scenario["stats_override"],
			})
			var row := {
				"scenario": str(scenario["label"]),
				"stats": str(scenario["stats"]),
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

	# 再跑一次两个酒馆场景，这次带上紫霞师姐前戏打出来的头子伤势。
	var prefight_rows: Array = []
	for scenario_value in scenarios:
		var scenario: Dictionary = scenario_value
		var bandit_count: int = int(scenario["bandits"])
		var loss: int = int(Prefight.simulate(bandit_count).get("boss_damage", 0))
		for bot in bots:
			var result: Dictionary = Simulator.run({
				"enemies": scenario["enemies"],
				"herbs": int(scenario["herbs"]),
				"battles": BATTLES,
				"seed": SEED,
				"bot": bot,
				"first_strike": false,
				"stats_override": scenario["stats_override"],
				"boss_hp_loss": loss,
			})
			var row := {
				"scenario": str(scenario["label"]),
				"stats": str(scenario["stats"]),
				"bot": bot,
				"boss_hp_loss": loss,
				"win_rate": float(result["win_rate"]),
				"avg_rounds": float(result["avg_rounds"]),
				"avg_hp_pct": float(result["avg_hp_pct"]),
			}
			prefight_rows.append(row)
			print("%s | %s | %s | 前戏减伤 %d | 胜率 %.1f%% | 平均回合 %.1f | 剩余 HP %.1f%%" % [
				row["scenario"],
				row["stats"],
				row["bot"],
				int(row["boss_hp_loss"]),
				float(row["win_rate"]) * 100.0,
				float(row["avg_rounds"]),
				float(row["avg_hp_pct"]) * 100.0,
			])
	_write_prefight_section(_build_prefight_section(prefight_rows))
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
	lines.append("## 11. 模拟结果")
	lines.append("")
	lines.append("每格 400 局，`first_strike=false`，由 `tools/difficulty_report.gd` 生成。数值为第一章炼体（s=1，h=15）的当前数值。未准备：初始属性、马匪头子 ×1 + 马匪 ×5、无草药；准备好：文档 §7 的 50 点参考线、马匪头子 ×1 + 马匪 ×2、草药 ×3。")
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
	lines.append("bot 说明：random 乱出招；human 只用界面上看得到的信息（未知招靠猜，有预判点数先预判，已识别的招精确反制）；smart 能直接看到所有出招（上限）。目标：human 在初始属性下打马匪头子胜率 10%~30%，养成后 65%~85%（真人比 human 更容易失误，所以养成后偏高是预期的）。")

	var boss_scenario := "酒馆战（未准备）"
	var initial_row := _find_row(rows, boss_scenario, "初始属性", "human")
	var grown_row := _find_row(rows, "酒馆战（准备好）", "养成后属性", "human")
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


# 前戏减伤后的重跑结果，写进设计文档 §9（标记之间），不覆盖 §11 的旧表。
func _build_prefight_section(rows: Array) -> String:
	var lines: Array[String] = []
	lines.append("### 9.1 前戏减伤后的模拟结果")
	lines.append("")
	lines.append("每格 400 局，`first_strike=false`，由 `tools/difficulty_report.gd` 生成。紫霞师姐前戏只让马匪头子带伤（`boss_hp_loss = prefight.simulate(小兵数).boss_damage`），小兵仍是满血。")
	lines.append("")
	lines.append("| 遭遇 | 属性 | bot | 头子减伤 | 胜率 | 平均回合 | 玩家平均剩余 HP |")
	lines.append("| --- | --- | --- | ---: | ---: | ---: | ---: |")
	for row_value in rows:
		var row: Dictionary = row_value
		lines.append("| %s | %s | %s | %d | %.1f%% | %.1f | %.1f%% |" % [
			row["scenario"],
			row["stats"],
			row["bot"],
			int(row["boss_hp_loss"]),
			float(row["win_rate"]) * 100.0,
			float(row["avg_rounds"]),
			float(row["avg_hp_pct"]) * 100.0,
		])
	lines.append("")
	lines.append("目标不变：未准备 human 10%~30%，准备好 human 65%~85%。")
	return "\n".join(lines) + "\n"


func _write_prefight_section(section: String) -> void:
	var path := _doc_path()
	var text := ""
	if FileAccess.file_exists(path):
		text = FileAccess.get_file_as_string(path)
	var start_marker := "<!-- prefight-report:start -->"
	var end_marker := "<!-- prefight-report:end -->"
	var block := start_marker + "\n" + section + end_marker
	var at := text.find(start_marker)
	if at >= 0:
		var end_at := text.find(end_marker, at)
		if end_at >= 0:
			text = text.substr(0, at) + block + text.substr(end_at + end_marker.length())
		else:
			text = text.substr(0, at) + block
	else:
		var next_section := text.find("## 10.")
		if next_section >= 0:
			text = text.substr(0, next_section) + block + "\n\n" + text.substr(next_section)
		else:
			text += "\n\n" + block
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("difficulty_report: cannot write %s" % path)
		return
	file.store_string(text)
	file.close()
	print("wrote prefight section to %s" % path)


func _doc_path() -> String:
	var base := ProjectSettings.globalize_path("res://").simplify_path()
	return base.path_join(DOC_RELATIVE).simplify_path()


func _append_to_doc(section: String) -> void:
	var path := _doc_path()
	var text := ""
	if FileAccess.file_exists(path):
		text = FileAccess.get_file_as_string(path)
	var marker := "## 11. 模拟结果"
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

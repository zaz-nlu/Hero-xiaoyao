extends RefCounted

# 酒馆闯入剧情的前戏推演：紫霞师姐与三名弟子先和马匪混战。
# 结果完全确定（不使用随机数）：同一 bandit_count 每次都得到同一份伤害与日志，
# 战败重来时直接复用缓存，前戏不必重播，数值也不会漂移。
#
# 数值意图见 docs/superpowers/specs/2026-11-17-numbers-system-design.md §7：
# 师姐（炼体中期，合计 44）强于马匪（31）但弱于头子（53）；
# 弟子（初期，26）弱于马匪但身法更快。前戏只对头子计伤，马匪始终满血。

const DATA_PATH := "res://data/prefight.json"
const MAX_ROUNDS := 40
const BOSS := {"power": 9, "defense": 6, "hp": 300}
const BANDIT := {"power": 9, "defense": 5, "hp": 40}

const DEFAULT_CONFIG := {
	"zixia_sister": {
		"name": "紫霞师姐", "power": 8, "speed": 10, "defense": 5, "skill": 9, "hp": 160
	},
	"zixia_disciple": {
		"name": "紫霞弟子",
		"power": 4,
		"speed": 8,
		"defense": 3,
		"skill": 8,
		"hp": 40,
		"count": 3,
	},
	"target_boss_damage": 100,
	"tolerance": 12,
}


# 推演结果：
#   boss_damage     头子掉的血（夹在 target ± tolerance 内）
#   sister_hp       师姐剩余气血
#   disciples_alive 最后还站着的弟子数
#   rounds          推演回合数
#   log             每次出手一条，格式 "攻击者>目标:-伤害"
static func simulate(bandit_count: int) -> Dictionary:
	var config: Dictionary = load_config()
	var sister: Dictionary = config.get("zixia_sister", {})
	var disciple: Dictionary = config.get("zixia_disciple", {})
	var target_damage: int = int(config.get("target_boss_damage", 100))
	var tolerance: int = int(config.get("tolerance", 12))

	var bandit_total: int = maxi(0, bandit_count)
	var disciple_total: int = maxi(0, int(disciple.get("count", 3)))
	var sister_max_hp: int = maxi(1, int(sister.get("hp", 160)))
	var sister_hp: int = sister_max_hp
	var disciple_max_hp: int = maxi(1, int(disciple.get("hp", 40)))
	var disciples: Array = []
	for i in range(disciple_total):
		disciples.append({"id": "disciple_%d" % (i + 1), "hp": disciple_max_hp})

	var sister_to_boss: int = maxi(
		1,
		int(floor(float(sister.get("power", 8)) * 1.3 + float(sister.get("skill", 9)) * 0.4))
			- int(BOSS["defense"])
	)
	var boss_to_sister: int = maxi(
		1, int(floor(float(BOSS["power"]) * 1.6)) - int(sister.get("defense", 5))
	)
	var disciple_to_bandit: int = maxi(1, int(disciple.get("power", 4)) - int(BANDIT["defense"]))
	var bandit_to_disciple: int = maxi(
		1, int(BANDIT["power"]) - int(disciple.get("defense", 3))
	)
	var bandit_to_sister: int = maxi(1, int(BANDIT["power"]) - int(sister.get("defense", 5)))

	var boss_damage: int = 0
	var rounds: int = 0
	var log: Array[String] = []
	# 每个马匪的每第 4 次出手算作打到师姐（用确定计数代替 25% 随机）。
	var bandit_attack_index: int = 0
	var disciple_target_index: int = 0
	var bandit_target_index: int = 0

	while rounds < MAX_ROUNDS:
		rounds += 1

		# 师姐一剑一剑磨头子。
		boss_damage += sister_to_boss
		log.append("zixia>ma_youwei:-%d" % sister_to_boss)

		# 弟子们轮流找马匪；马匪不会因此倒下，只写进日志作叙述。
		for i in range(disciples.size()):
			if int(disciples[i]["hp"]) <= 0:
				continue
			var bandit_number: int = 0
			if bandit_total > 0:
				bandit_number = bandit_target_index % bandit_total
				bandit_target_index += 1
			log.append(
				"disciple_%d>bandit_%d:-%d"
				% [i + 1, bandit_number + 1, disciple_to_bandit]
			)

		# 头子回手打师姐。
		sister_hp -= boss_to_sister
		log.append("ma_youwei>zixia:-%d" % boss_to_sister)

		# 马匪围攻：每第 4 次出手落到师姐身上，其余打弟子。
		for b in range(bandit_total):
			bandit_attack_index += 1
			if bandit_attack_index % 4 == 0:
				sister_hp -= bandit_to_sister
				log.append("bandit_%d>zixia:-%d" % [b + 1, bandit_to_sister])
				continue
			var target: int = _next_alive_disciple(disciples, disciple_target_index)
			if target < 0:
				continue
			disciple_target_index = target + 1
			disciples[target]["hp"] = int(disciples[target]["hp"]) - bandit_to_disciple
			log.append("bandit_%d>disciple_%d:-%d" % [b + 1, target + 1, bandit_to_disciple])

		# 师姐撑不住（气血降到 25% 以下）、弟子全部倒地，或头子已经挨够。
		if sister_hp * 4 <= sister_max_hp:
			break
		if _alive_disciples(disciples) <= 0:
			break
		if boss_damage >= target_damage:
			break

	var disciples_alive: int = _alive_disciples(disciples)
	var clamped_damage: int = clampi(
		boss_damage, maxi(0, target_damage - tolerance), target_damage + tolerance
	)
	return {
		"boss_damage": clamped_damage,
		"sister_hp": maxi(0, sister_hp),
		"disciples_alive": disciples_alive,
		"rounds": rounds,
		"log": log,
	}


static func load_config() -> Dictionary:
	var config: Dictionary = DEFAULT_CONFIG.duplicate(true)
	if not FileAccess.file_exists(DATA_PATH):
		return config
	var text: String = FileAccess.get_file_as_string(DATA_PATH)
	if text == "":
		return config
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return config
	var data: Dictionary = parsed
	for key in ["zixia_sister", "zixia_disciple"]:
		var value: Variant = data.get(key, null)
		if not (value is Dictionary):
			continue
		var source: Dictionary = value
		var target: Dictionary = config[key]
		for entry_key in source.keys():
			target[str(entry_key)] = source[entry_key]
	for key in ["target_boss_damage", "tolerance"]:
		var value: Variant = data.get(key, null)
		if value is int or value is float:
			config[key] = int(value)
	return config


static func _next_alive_disciple(disciples: Array, from_index: int) -> int:
	var size: int = disciples.size()
	if size <= 0:
		return -1
	for offset in range(size):
		var index: int = (from_index + offset) % size
		if int(disciples[index]["hp"]) > 0:
			return index
	return -1


static func _alive_disciples(disciples: Array) -> int:
	var count := 0
	for entry_value in disciples:
		var entry: Dictionary = entry_value
		if int(entry["hp"]) > 0:
			count += 1
	return count

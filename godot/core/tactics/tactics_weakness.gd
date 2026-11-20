extends RefCounted

# 进攻侧弱点：颜色槽、命中判定与刷新。数值来自 data/tactics_rules.json 的
# weakness 段；这里只读写 TacticsUnit 上的弱点状态，不依赖场景类型。

const TacticsEnergy = preload("res://core/tactics/tactics_energy.gd")
const TacticsRuleData = preload("res://core/tactics/tactics_rule_data.gd")

const DEFAULT_COLORS: Array[String] = ["neili", "ziqi", "xianqi"]
const NONE := "none"
const Facing = preload("res://core/tactics/facing.gd")
# 弱点方向用世界方向（上下左右），与单位朝向无关；Vector2i.ZERO 表示“任意方向”。
const DIRECTIONS: Array[Vector2i] = [Facing.UP, Facing.DOWN, Facing.LEFT, Facing.RIGHT]


# 敌人弱点槽数量：显式 weakness_slots 优先，否则按 tier。
static func slot_count(unit) -> int:
	if unit == null or unit.side != "enemy" or unit.unit == null:
		return 0
	var def = unit.unit.def
	if def == null:
		return 0
	if int(def.weakness_slots) >= 0:
		return int(def.weakness_slots)
	var by_tier: Dictionary = _rules().get("slots_by_tier", {})
	return maxi(0, int(by_tier.get(str(def.tier), 0)))


static func colors() -> Array:
	var out: Array = []
	var raw = _rules().get("colors", [])
	if raw is Array:
		for value in raw:
			out.append(str(value))
	return out if not out.is_empty() else DEFAULT_COLORS.duplicate()


static func damage_pct() -> int:
	return int(_rules().get("weak_damage_pct", 125))


# 开战时按战斗种子给所有敌人抽弱点：只从玩家方仍有剩余、且已开放的能量里取。
static func initialize(battle) -> void:
	var available := available_colors(battle)
	for raw_unit in battle.units:
		var unit = raw_unit
		if unit.side != "enemy":
			continue
		_fill(unit, available, battle.rng)


static func available_colors(battle) -> Array:
	var out: Array = []
	for raw_unit in battle.units:
		var unit = raw_unit
		if unit.side != "player" or not unit.is_alive():
			continue
		for color in TacticsEnergy.colors():
			var energy := str(color)
			if TacticsEnergy.is_locked(energy) or out.has(energy) or not colors().has(energy):
				continue
			if int(unit.energy_left.get(energy, 0)) > 0:
				out.append(energy)
	return out


# 攻击方出招所用能量是否命中该敌人的弱点；命中返回颜色，否则空字符串。
static func weak_color(battle, attacker, defender, energy: String) -> String:
	if attacker == null or defender == null:
		return ""
	if attacker.side != "player" or defender.side != "enemy":
		return ""
	if defender.unit == null or defender.unit.is_stunned():
		return ""
	if energy == "" or energy == NONE or not colors().has(energy):
		return ""
	return energy if hit_slot(attacker, defender, energy) >= 0 else ""


# 攻击方所在的方位（相对被攻击者的世界方向）。
static func attack_dir(attacker, defender) -> Vector2i:
	return Facing.from_delta(attacker.pos - defender.pos, Facing.DOWN)


# 命中的槽位：颜色相同，且槽有方向时攻击方必须站在该方向上；没有命中返回 -1。
static func hit_slot(attacker, defender, energy: String) -> int:
	var side := attack_dir(attacker, defender)
	for i in range(defender.weaknesses.size()):
		if str(defender.weaknesses[i]) != energy:
			continue
		var dir: Vector2i = Vector2i.ZERO
		if i < defender.weak_dirs.size():
			dir = defender.weak_dirs[i]
		if dir == Vector2i.ZERO or dir == side:
			return i
	return -1


# 弱点槽立即刷新：不等于刚命中的颜色，也不等于其他槽的颜色。
static func refresh(battle, unit, index: int) -> String:
	if index < 0 or index >= unit.weaknesses.size():
		return ""
	var used := str(unit.weaknesses[index])
	var available := available_colors(battle)
	var pool: Array = []
	for color in available:
		if color != used and not _other_slots_have(unit, index, color):
			pool.append(color)
	# 只有一种能量可用时，同色在新方向重新刷新。
	if pool.is_empty() and available.has(used):
		pool.append(used)
	var next := NONE
	if not pool.is_empty():
		next = str(pool[battle.rng.randi_range(0, pool.size() - 1)])
	unit.weaknesses[index] = next
	_set_dir(unit, index, _pick_dir(unit, index, battle.rng))
	return next


# 眩晕结束时重新抽取：按当前可用颜色重新填槽。
static func refill(battle, unit) -> void:
	_fill(unit, available_colors(battle), battle.rng)


# 击破时弱点全部清空为中性。
static func clear(unit) -> void:
	for i in range(unit.weaknesses.size()):
		unit.weaknesses[i] = NONE


static func _fill(unit, available: Array, rng: RandomNumberGenerator) -> void:
	var slots := slot_count(unit)
	var out: Array = []
	var pool: Array = available.duplicate()
	while out.size() < slots and not pool.is_empty():
		var index := rng.randi_range(0, pool.size() - 1)
		out.append(str(pool[index]))
		pool.remove_at(index)
	# 可用颜色比弱点数少时允许重复（不同方向），而不是留空槽。
	while out.size() < slots and not available.is_empty():
		out.append(str(available[rng.randi_range(0, available.size() - 1)]))
	while out.size() < slots:
		out.append(NONE)
	unit.weaknesses = out
	unit.weak_dirs = []
	for i in range(out.size()):
		unit.weak_dirs.append(Vector2i.ZERO)
	for i in range(out.size()):
		_set_dir(unit, i, _pick_dir(unit, i, rng))


static func _set_dir(unit, index: int, dir: Vector2i) -> void:
	while unit.weak_dirs.size() <= index:
		unit.weak_dirs.append(Vector2i.ZERO)
	unit.weak_dirs[index] = dir


# 随机一个方向：优先避开别的槽已占的方向与自己上一次的方向。
static func _pick_dir(unit, index: int, rng: RandomNumberGenerator) -> Vector2i:
	var old: Vector2i = Vector2i.ZERO
	if index < unit.weak_dirs.size():
		old = unit.weak_dirs[index]
	var pool: Array = []
	for dir in DIRECTIONS:
		var taken := false
		for i in range(unit.weak_dirs.size()):
			if i != index and unit.weak_dirs[i] == dir:
				taken = true
		if not taken and dir != old:
			pool.append(dir)
	if pool.is_empty():
		pool = DIRECTIONS.duplicate()
	return pool[rng.randi_range(0, pool.size() - 1)]


static func _other_slots_have(unit, index: int, color: String) -> bool:
	for i in range(unit.weaknesses.size()):
		if i != index and str(unit.weaknesses[i]) == color:
			return true
	return false


static func _rules() -> Dictionary:
	var block = TacticsRuleData.weakness()
	return block if block is Dictionary else {}

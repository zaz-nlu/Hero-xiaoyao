extends RefCounted

# 敌方单位的一回合决策：按 enemy def 的 ai 字段（rush / archer / guard / boss）行动。
# 所有状态变化都通过 TacticsBattle 的公开方法完成，非法时回退到 wait。

const EnemyAi = preload("res://core/enemy_ai.gd")
const Facing = preload("res://core/tactics/facing.gd")
const Pattern = preload("res://core/tactics/pattern.gd")

# 威胁分权重：气血占比低、防御低、距离近的目标更危险。
const THREAT_HP_WEIGHT := 40.0
const THREAT_DEFENSE_CAP := 30.0
const THREAT_DEFENSE_WEIGHT := 1.0
const THREAT_DISTANCE_WEIGHT := 3.0

const ARCHER_MIN_DISTANCE := 3
# 招式偏好只在同一站位评分档位内起作用；站位优先看背面/侧面/正面。
const CHOSEN_MOVE_BONUS := 1000.0
const CHOSEN_CELL_BONUS := 5.0


static func take_turn(
	battle,
	uid: String,
	rng: RandomNumberGenerator,
	reaction_picker: Callable = Callable()
) -> Array:
	var unit = battle.get_unit(uid)
	if unit == null or not unit.is_alive():
		return []
	if str(battle.current_actor) != uid:
		return []
	var turn_plan := plan(battle, uid, rng)
	return _execute_plan(battle, unit, turn_plan, reaction_picker)


# 这个敌人本回合的计划，不改变 battle 状态：
# {"move": Vector2i 或 null, "attack": {"martial_id": String, "target_cell": Vector2i} 或 null}。
# attack 按“已经移动到 move、朝向为到该格最后一步的方向”计算。
static func plan(battle, uid: String, rng: RandomNumberGenerator) -> Dictionary:
	var unit = battle.get_unit(uid)
	if unit == null or not unit.is_alive():
		return _empty_plan()
	if str(battle.current_actor) != uid:
		return _empty_plan()
	var ai_kind := "rush"
	if unit.unit != null and unit.unit.def != null:
		ai_kind = str(unit.unit.def.ai)
	match ai_kind:
		"archer":
			return _archer_plan(battle, unit, rng)
		"guard":
			return _guard_plan(battle, unit, rng)
		"boss":
			return _rush_plan(battle, unit, rng, true)
		_:
			return _rush_plan(battle, unit, rng, false)


static func _execute_plan(battle, unit, turn_plan: Dictionary, picker: Callable) -> Array:
	var events: Array = []
	if turn_plan.get("move", null) != null:
		var moved := _move_to(battle, unit, turn_plan["move"])
		if not bool(moved["ok"]):
			return _wait(battle, unit)
		events.append_array(moved["events"])
	var attack_plan: Variant = turn_plan.get("attack", null)
	if attack_plan is Dictionary:
		events.append_array(_execute_attack(battle, unit, attack_plan, picker))
	else:
		events.append_array(_wait(battle, unit))
	return events


static func _execute_attack(battle, unit, attack_plan: Dictionary, picker: Callable) -> Array:
	var martial_id := str(attack_plan.get("martial_id", ""))
	if martial_id == "":
		return _wait(battle, unit)
	var target_cell: Vector2i = attack_plan.get("target_cell", unit.pos)
	battle.face(unit.id, _facing_for(unit.pos, target_cell, unit.facing))
	var reactions := _pick_reactions(battle, unit, martial_id, target_cell, picker)
	var result: Dictionary = battle.attack(unit.id, martial_id, target_cell, reactions)
	if not bool(result.get("ok", false)):
		return _wait(battle, unit)
	return result.get("events", [])


static func _empty_plan() -> Dictionary:
	return {"move": null, "attack": null}


static func _plan_from_attack(now: Dictionary) -> Dictionary:
	var attack: Dictionary = {
		"martial_id": str(now.get("move", {}).get("id", "")),
		"target_cell": now["target"].pos,
	}
	return {"move": null, "attack": attack}


static func _plan_with_move(cell_plan: Dictionary) -> Dictionary:
	var attack: Dictionary = {
		"martial_id": str(cell_plan.get("move", {}).get("id", "")),
		"target_cell": cell_plan["target"].pos,
	}
	return {"move": cell_plan["cell"], "attack": attack}


static func _rush_plan(battle, unit, rng: RandomNumberGenerator, lowest_hp: bool) -> Dictionary:
	var targets: Array = battle.alive("player")
	if targets.is_empty():
		return _empty_plan()
	var moves := _moves(unit)
	if moves.is_empty():
		return _empty_plan()
	var ordered := _ordered_targets(unit, targets, lowest_hp)
	var chosen := EnemyAi.choose(moves, rng)
	var chosen_id := str(chosen.get("id", ""))

	var now := _best_attack_now(battle, unit, ordered, moves, chosen_id)
	if not now.is_empty():
		return _plan_from_attack(now)

	var cell_plan := _best_cell_plan(battle, unit, ordered, moves, chosen_id)
	if not cell_plan.is_empty():
		return _plan_with_move(cell_plan)

	var approach: Variant = _advance_cell(battle, unit, targets)
	return {"move": approach, "attack": null}


static func _guard_plan(battle, unit, rng: RandomNumberGenerator) -> Dictionary:
	var targets: Array = battle.alive("player")
	if targets.is_empty():
		return _empty_plan()
	var nearest = _nearest(unit.pos, targets)
	if nearest == null:
		return _empty_plan()
	var reach: int = unit.move_range() + _max_range(_moves(unit))
	if _distance(unit.pos, nearest.pos) > reach:
		return _empty_plan()
	return _rush_plan(battle, unit, rng, false)


static func _archer_plan(battle, unit, rng: RandomNumberGenerator) -> Dictionary:
	var targets: Array = battle.alive("player")
	if targets.is_empty():
		return _empty_plan()
	var moves := _moves(unit)
	if moves.is_empty():
		return _empty_plan()
	var nearest = _nearest(unit.pos, targets)
	if nearest == null:
		return _empty_plan()
	var ordered := _ordered_targets(unit, targets, false)
	var chosen := EnemyAi.choose(moves, rng)
	var chosen_id := str(chosen.get("id", ""))

	if _distance(unit.pos, nearest.pos) >= ARCHER_MIN_DISTANCE:
		var now := _best_attack_now(battle, unit, ordered, moves, chosen_id)
		if not now.is_empty():
			return _plan_from_attack(now)

	var cell_plan := _best_cell_plan(
		battle, unit, ordered, moves, chosen_id,
		ARCHER_MIN_DISTANCE, nearest, 5.0)
	if not cell_plan.is_empty():
		return _plan_with_move(cell_plan)

	# 找不到能射击的格子：退到离最近敌人最远的可达格，再尝试射击。
	var retreat: Variant = _farthest_cell(battle, unit, nearest)
	var after: Dictionary
	if retreat != null:
		after = _best_attack_from(battle, unit, retreat, ordered, moves, chosen_id)
	else:
		after = _best_attack_now(battle, unit, ordered, moves, chosen_id)
	var attack: Variant = null
	if not after.is_empty():
		attack = {
			"martial_id": str(after.get("move", {}).get("id", "")),
			"target_cell": after["target"].pos,
		}
	return {"move": retreat, "attack": attack}


static func _pick_reactions(battle, unit, move_id: String, target_cell: Vector2i,
		picker: Callable) -> Dictionary:
	if not picker.is_valid():
		return {}
	var preview: Array = battle.preview_reactions(unit.id, move_id, target_cell)
	if preview.is_empty():
		return {}
	var picked: Variant = picker.call(preview)
	if picked is Dictionary:
		return picked
	return {}


# 只读扫描：会临时改写 unit.facing，由调用方负责恢复。
static func _attack_scan(battle, unit, targets: Array, moves: Array,
		chosen_id: String) -> Dictionary:
	for target in targets:
		if target == null or not target.is_alive():
			continue
		battle.face(unit.id, _facing_for(unit.pos, target.pos, unit.facing))
		var best_move: Dictionary = {}
		var best_score := -1.0e9
		for move in moves:
			var move_id := str(move.get("id", ""))
			if not battle.attack_cells(unit.id, move_id).has(target.pos):
				continue
			if battle.affected_units(unit.id, move_id, target.pos).is_empty():
				continue
			var score := _move_score(move, chosen_id)
			if score > best_score:
				best_score = score
				best_move = move
		if not best_move.is_empty():
			return {"target": target, "move": best_move}
	return {}


static func _best_attack_now(battle, unit, targets: Array, moves: Array,
		chosen_id: String) -> Dictionary:
	var saved_pos: Vector2i = unit.pos
	var saved_facing: Vector2i = unit.facing
	var out := _attack_scan(battle, unit, targets, moves, chosen_id)
	unit.pos = saved_pos
	unit.facing = saved_facing
	return out


static func _best_attack_from(battle, unit, from_cell: Vector2i, targets: Array,
		moves: Array, chosen_id: String) -> Dictionary:
	var saved_pos: Vector2i = unit.pos
	var saved_facing: Vector2i = unit.facing
	unit.pos = from_cell
	var out := _attack_scan(battle, unit, targets, moves, chosen_id)
	unit.pos = saved_pos
	unit.facing = saved_facing
	return out


static func _best_cell_plan(
	battle,
	unit,
	targets: Array,
	moves: Array,
	chosen_id: String,
	min_distance: int = -1,
	anchor: Variant = null,
	distance_weight: float = 0.0
) -> Dictionary:
	var reachable: Dictionary = battle.reachable_cells(unit.id)
	var best: Dictionary = {}
	var best_score := -1.0e9
	for raw_cell in reachable.keys():
		var cell: Vector2i = raw_cell
		if cell == unit.pos:
			continue
		var anchor_distance := 0
		if anchor != null:
			anchor_distance = _distance(cell, anchor.pos)
			if min_distance >= 0 and anchor_distance < min_distance:
				continue
		for target in targets:
			if target == null or not target.is_alive():
				continue
			var relation := Facing.relation(target.pos, target.facing, cell)
			var relation_score := _relation_score(relation)
			for move in moves:
				if not _move_reaches(move, cell, target.pos, battle.grid):
					continue
				var score := relation_score * 1000.0 \
						+ float(battle.grid.height_at(cell)) * 20.0 \
						+ float(int(move.get("threat", 0))) * 0.1 \
						+ float(anchor_distance) * distance_weight
				if str(move.get("id", "")) == chosen_id:
					score += CHOSEN_CELL_BONUS
				if score > best_score:
					best_score = score
					best = {"cell": cell, "target": target, "move": move}
	return best


static func _advance_cell(battle, unit, targets: Array) -> Variant:
	var nearest = _nearest(unit.pos, targets)
	if nearest == null:
		return null
	var reachable: Dictionary = battle.reachable_cells(unit.id)
	var best_cell: Variant = null
	var best_distance := 1.0e9
	for raw_cell in reachable.keys():
		var cell: Vector2i = raw_cell
		if cell == unit.pos:
			continue
		var distance := _distance(cell, nearest.pos)
		if distance < best_distance:
			best_distance = distance
			best_cell = cell
	return best_cell


static func _farthest_cell(battle, unit, anchor) -> Variant:
	var reachable: Dictionary = battle.reachable_cells(unit.id)
	var best_cell: Variant = null
	var best_distance := -1
	var best_height := -1
	for raw_cell in reachable.keys():
		var cell: Vector2i = raw_cell
		if cell == unit.pos:
			continue
		var distance := _distance(cell, anchor.pos)
		var height := int(battle.grid.height_at(cell))
		if distance > best_distance or (distance == best_distance and height > best_height):
			best_distance = distance
			best_height = height
			best_cell = cell
	return best_cell


static func _move_to(battle, unit, cell: Vector2i) -> Dictionary:
	var result: Dictionary = battle.move(unit.id, cell)
	return {
		"ok": bool(result.get("ok", false)),
		"events": result.get("events", []),
	}


static func _wait(battle, unit) -> Array:
	var result: Dictionary = battle.wait(unit.id)
	return result.get("events", [])


static func _moves(unit) -> Array:
	if unit.unit == null or unit.unit.def == null:
		return []
	return unit.unit.def.moves


static func _max_range(moves: Array) -> int:
	var out := 1
	for move in moves:
		var range_def: Variant = move.get("range", {})
		if range_def is Dictionary:
			out = maxi(out, int(range_def.get("max", 1)))
	return out


static func _move_score(move: Dictionary, chosen_id: String) -> float:
	var score := float(int(move.get("power", 0))) \
			+ float(int(move.get("threat", 0))) * 0.1
	if str(move.get("id", "")) == chosen_id:
		score += CHOSEN_MOVE_BONUS
	return score


static func _relation_score(relation: String) -> int:
	match relation:
		"back":
			return 3
		"side":
			return 2
		_:
			return 1


static func _move_reaches(move: Dictionary, from_cell: Vector2i,
		target_pos: Vector2i, grid) -> bool:
	var range_def: Variant = move.get("range", {})
	if not (range_def is Dictionary):
		return false
	var facing := _facing_for(from_cell, target_pos, Facing.UP)
	return Pattern.target_cells(range_def, from_cell, facing, grid).has(target_pos)


static func _facing_for(from_cell: Vector2i, target_cell: Vector2i,
		fallback: Vector2i) -> Vector2i:
	return Facing.from_delta(target_cell - from_cell, fallback)


static func _nearest(from_cell: Vector2i, targets: Array) -> Variant:
	var best: Variant = null
	var best_distance := 1.0e9
	for target in targets:
		if target == null or not target.is_alive():
			continue
		var distance := _distance(from_cell, target.pos)
		if distance < best_distance:
			best_distance = distance
			best = target
	return best


static func _ordered_targets(unit, targets: Array, lowest_hp: bool) -> Array:
	var out: Array = targets.duplicate()
	# 选择排序：同分时保持原顺序，结果可复现。
	for i in range(out.size()):
		var best_index := i
		for j in range(i + 1, out.size()):
			if _target_before(unit, out[j], out[best_index], lowest_hp):
				best_index = j
		if best_index != i:
			var swap = out[i]
			out[i] = out[best_index]
			out[best_index] = swap
	return out


static func _target_before(unit, a, b, lowest_hp: bool) -> bool:
	if lowest_hp:
		var ratio_a := _hp_ratio(a)
		var ratio_b := _hp_ratio(b)
		if ratio_a != ratio_b:
			return ratio_a < ratio_b
	else:
		var score_a := _threat_score(unit, a)
		var score_b := _threat_score(unit, b)
		if score_a != score_b:
			return score_a > score_b
	return _distance(unit.pos, a.pos) < _distance(unit.pos, b.pos)


static func _threat_score(unit, target) -> float:
	var ratio := _hp_ratio(target)
	var defense := float(int(target.unit.stats.get("defense", 0)))
	var distance := float(_distance(unit.pos, target.pos))
	return (1.0 - ratio) * THREAT_HP_WEIGHT \
			+ maxf(0.0, THREAT_DEFENSE_CAP - defense) * THREAT_DEFENSE_WEIGHT \
			- distance * THREAT_DISTANCE_WEIGHT


static func _hp_ratio(target) -> float:
	var max_hp := float(target.unit.max_hp)
	if max_hp <= 0.0:
		return 0.0
	return clampf(float(target.unit.hp) / max_hp, 0.0, 1.0)


static func _distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

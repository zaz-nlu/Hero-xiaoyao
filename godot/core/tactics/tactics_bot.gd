extends RefCounted

# 玩家方的自动操作，用于模拟器和测试：优先剑意，其次能打到的武学，
# 打不到就朝最近的敌人靠近。反制选择支持 best / never 两种模式。

const Counter = preload("res://core/counter.gd")
const Facing = preload("res://core/tactics/facing.gd")
const StatsRules = preload("res://core/tactics/stats_rules.gd")
const TacticsDamage = preload("res://core/tactics/tactics_damage.gd")
const TacticsEnergy = preload("res://core/tactics/tactics_energy.gd")
const TacticsWeakness = preload("res://core/tactics/tactics_weakness.gd")


# preview 来自 battle.preview_reactions；返回 {defender_id: martial_id}。
# best：verdict 最高优先、完美破招优先；never：一律不反制。
static func pick_reactions(preview: Array, mode := "best") -> Dictionary:
	var out: Dictionary = {}
	if mode == "never":
		return out
	for raw_entry in preview:
		if not (raw_entry is Dictionary):
			continue
		var entry: Dictionary = raw_entry
		var defender_id := str(entry.get("defender_id", ""))
		if defender_id == "":
			continue
		var raw_options: Variant = entry.get("options", [])
		if not (raw_options is Array):
			continue
		var best: Dictionary = {}
		var best_rank := 0
		for raw_option in raw_options:
			if not (raw_option is Dictionary):
				continue
			var option: Dictionary = raw_option
			var rank := _outcome_rank(option)
			if rank > best_rank:
				best = option
				best_rank = rank
		if not best.is_empty():
			out[defender_id] = str(best.get("id", ""))
	return out


# perfect > counter > scrape（含基础格挡）> 不反应；旧数据没有 outcome 时按 verdict 回退。
static func _outcome_rank(option: Dictionary) -> int:
	var outcome := str(option.get("outcome", ""))
	match outcome:
		"perfect":
			return 3
		"counter":
			return 2
		"scrape":
			return 1
		"none":
			return 0
	var verdict := int(option.get("verdict", 0))
	if verdict == Counter.Verdict.ADVANTAGE:
		return 3 if bool(option.get("perfect", false)) else 2
	if verdict == Counter.Verdict.BARELY:
		return 1
	return 0


static func take_turn(
	battle,
	uid: String,
	rng: RandomNumberGenerator,
	mode := "best"
) -> Array:
	var unit = battle.get_unit(uid)
	if unit == null or not unit.is_alive():
		return []
	if str(battle.current_actor) != uid:
		return []
	var targets: Array = battle.alive("enemy")
	if targets.is_empty():
		return _wait(battle, unit)

	var release_events := _try_release(battle, unit, mode)
	if not release_events.is_empty():
		return release_events

	var jianyi_events := _try_jianyi(battle, unit, targets)
	if not jianyi_events.is_empty():
		return jianyi_events

	var attack_events := _try_attack(battle, unit, targets, mode)
	if not attack_events.is_empty():
		return attack_events

	var events := _approach(battle, unit, targets, rng)
	events.append_array(_wait(battle, unit))
	return events


static func _try_jianyi(battle, unit, targets: Array) -> Array:
	if int(unit.unit.jianyi_points) <= 0:
		return []
	var ordered := _jianyi_targets(battle, unit, targets)
	for raw_id in unit.loadout:
		var martial_id := str(raw_id)
		if not battle.martials.has(martial_id):
			continue
		for target in ordered:
			if target == null or not target.is_alive():
				continue
			battle.face(unit.id, _facing_for(unit.pos, target.pos, unit.facing))
			if not battle.attack_cells(unit.id, martial_id).has(target.pos):
				continue
			if battle.affected_units(unit.id, martial_id, target.pos).is_empty():
				continue
			var result: Dictionary = battle.jianyi(unit.id, martial_id, target.pos)
			if bool(result.get("ok", false)):
				return result.get("events", [])
	return []


static func _try_release(battle, unit, mode: String) -> Array:
	# best 模式气血低于 40% 时先运功回血；行动后 has_acted 置位，本回合不会再次释放。
	if mode != "best" or unit.has_acted:
		return []
	if _hp_ratio(unit) >= 0.4:
		return []
	var result: Dictionary = battle.release_ziqi(unit.id)
	if bool(result.get("ok", false)):
		return result.get("events", [])
	return []


static func _try_attack(battle, unit, targets: Array, mode: String) -> Array:
	var ordered := _attack_targets(unit, targets)
	for target in ordered:
		if target == null or not target.is_alive():
			continue
		battle.face(unit.id, _facing_for(unit.pos, target.pos, unit.facing))
		for raw_energy in _energy_candidates(unit, target):
			var energy := str(raw_energy)
			var best_id := _best_attack(battle, unit, target, energy)
			if best_id == "":
				continue
			var result: Dictionary = battle.attack(
				unit.id, best_id, target.pos, {}, energy)
			if bool(result.get("ok", false)):
				return result.get("events", [])
	return []


static func _best_attack(battle, unit, target, energy: String) -> String:
	var best_id := ""
	var best_tier := -1
	var best_weak := false
	var best_damage := -1
	for raw_id in unit.loadout:
		var martial_id := str(raw_id)
		var martial = battle.martials.get(martial_id)
		if martial == null:
			continue
		var cost := TacticsEnergy.cost_for(martial)
		if not unit.can_pay(energy, cost):
			continue
		if not battle.attack_cells(unit.id, martial_id).has(target.pos):
			continue
		if battle.affected_units(unit.id, martial_id, target.pos).is_empty():
			continue
		var tier := 1 if cost <= 0 else 2
		var weak := TacticsWeakness.weak_color(battle, unit, target, energy) != ""
		var damage := _expected_damage(battle, unit, target, martial_id, energy)
		var better := tier > best_tier \
				or (tier == best_tier and weak and not best_weak) \
				or (tier == best_tier and weak == best_weak and damage > best_damage)
		if better:
			best_id = martial_id
			best_tier = tier
			best_weak = weak
			best_damage = damage
	return best_id


# 目标有弱点且池子够时优先匹配颜色；气血低于一半时优先紫气回复；否则内力。
static func _energy_candidates(unit, target) -> Array:
	var out: Array = []
	for raw_color in target.weaknesses:
		var color := str(raw_color)
		if TacticsEnergy.is_color(color) and not out.has(color) and unit.has_energy(color):
			out.append(color)
	if _hp_ratio(unit) < 0.5 and not out.has("ziqi") and unit.has_energy("ziqi"):
		out.append("ziqi")
	if not out.has("neili") and unit.has_energy("neili"):
		out.append("neili")
	return out


static func _approach(battle, unit, targets: Array, rng: RandomNumberGenerator) -> Array:
	var nearest = _nearest(unit.pos, targets)
	if nearest == null:
		return []
	var reachable: Dictionary = battle.reachable_cells(unit.id)
	var best_distance := 1.0e9
	var cells: Array = []
	for raw_cell in reachable.keys():
		var cell: Vector2i = raw_cell
		if cell == unit.pos:
			continue
		var distance := _distance(cell, nearest.pos)
		if distance < best_distance:
			best_distance = distance
			cells = [cell]
		elif distance == best_distance:
			cells.append(cell)
	if cells.is_empty():
		return []
	var pick := 0
	if cells.size() > 1:
		pick = rng.randi_range(0, cells.size() - 1)
	var dest: Vector2i = cells[pick]
	var result: Dictionary = battle.move(unit.id, dest)
	if not bool(result.get("ok", false)):
		return []
	battle.face(unit.id, _facing_for(unit.pos, nearest.pos, unit.facing))
	return result.get("events", [])


static func _wait(battle, unit) -> Array:
	var result: Dictionary = battle.wait(unit.id)
	return result.get("events", [])


static func _jianyi_targets(battle, unit, targets: Array) -> Array:
	var out: Array = targets.duplicate()
	for i in range(out.size()):
		var best_index := i
		for j in range(i + 1, out.size()):
			if _jianyi_before(battle, unit, out[j], out[best_index]):
				best_index = j
		if best_index != i:
			var swap = out[i]
			out[i] = out[best_index]
			out[best_index] = swap
	return out


static func _jianyi_before(battle, unit, a, b) -> bool:
	var a_leader: bool = battle.leader_id != "" and a.id == battle.leader_id
	var b_leader: bool = battle.leader_id != "" and b.id == battle.leader_id
	if a_leader != b_leader:
		return a_leader
	var ratio_a := _hp_ratio(a)
	var ratio_b := _hp_ratio(b)
	if ratio_a != ratio_b:
		return ratio_a < ratio_b
	return _distance(unit.pos, a.pos) < _distance(unit.pos, b.pos)


static func _attack_targets(unit, targets: Array) -> Array:
	var out: Array = targets.duplicate()
	for i in range(out.size()):
		var best_index := i
		for j in range(i + 1, out.size()):
			if _attack_before(unit, out[j], out[best_index]):
				best_index = j
		if best_index != i:
			var swap = out[i]
			out[i] = out[best_index]
			out[best_index] = swap
	return out


static func _attack_before(unit, a, b) -> bool:
	var ratio_a := _hp_ratio(a)
	var ratio_b := _hp_ratio(b)
	if ratio_a != ratio_b:
		return ratio_a < ratio_b
	var distance_a := _distance(unit.pos, a.pos)
	var distance_b := _distance(unit.pos, b.pos)
	if distance_a != distance_b:
		return distance_a < distance_b
	return a.id < b.id


static func _expected_damage(battle, unit, target, martial_id: String,
		energy: String = "neili") -> int:
	var martial = battle.martials.get(martial_id)
	if martial == null:
		return 0
	var relation := Facing.relation(target.pos, target.facing, unit.pos)
	var height := StatsRules.height_bonus(
		battle.grid.height_at(unit.pos), battle.grid.height_at(target.pos))
	var multiplier := 1.0
	if battle.mastery != null:
		multiplier = float(battle.mastery.damage_multiplier(martial_id))
	var damage := TacticsDamage.martial_damage(
		unit.unit.stats, unit.unit.realm, int(martial.power), multiplier,
		target.unit, relation, height)
	damage = maxi(1, floori(
		float(damage) * float(TacticsEnergy.damage_pct(energy)) / 100.0))
	if TacticsWeakness.weak_color(battle, unit, target, energy) != "":
		damage = maxi(1, floori(
			float(damage) * float(TacticsWeakness.damage_pct()) / 100.0))
	return damage


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


static func _hp_ratio(target) -> float:
	var max_hp := float(target.unit.max_hp)
	if max_hp <= 0.0:
		return 0.0
	return clampf(float(target.unit.hp) / max_hp, 0.0, 1.0)


static func _facing_for(from_cell: Vector2i, target_cell: Vector2i,
		fallback: Vector2i) -> Vector2i:
	return Facing.from_delta(target_cell - from_cell, fallback)


static func _distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

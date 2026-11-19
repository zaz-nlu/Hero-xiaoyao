extends RefCounted

const Counter = preload("res://core/counter.gd")
const Facing = preload("res://core/tactics/facing.gd")
const Mastery = preload("res://core/mastery.gd")
const Pattern = preload("res://core/tactics/pattern.gd")
const StatsRules = preload("res://core/tactics/stats_rules.gd")
const TacticsDamage = preload("res://core/tactics/tactics_damage.gd")
const TacticsEnergy = preload("res://core/tactics/tactics_energy.gd")
const TacticsReaction = preload("res://core/tactics/tactics_reaction.gd")
const TacticsRelease = preload("res://core/tactics/tactics_release.gd")
const TacticsToughness = preload("res://core/tactics/tactics_toughness.gd")
const TacticsWeakness = preload("res://core/tactics/tactics_weakness.gd")
const TurnQueue = preload("res://core/tactics/turn_queue.gd")

var grid: Variant = null
var units: Array = []
var queue: Variant = null
var martials: Dictionary = {}
var mastery: Variant = null
var objective: String = "defeat_all"
var leader_id: String = ""
var log: Array = []
# 每次 end_turn 加 1。
var round: int = 0
var current_actor: String = ""
# 战斗种子驱动的随机源（弱点抽取与刷新）；同一 seed 可复现。
var rng: RandomNumberGenerator = null

static func create(p_grid, p_units: Array, p_martials: Dictionary, p_mastery,
		p_objective: String = "defeat_all", p_leader_id: String = "",
		p_seed: int = 1) -> RefCounted:
	var script: Variant = load("res://core/tactics/tactics_battle.gd")
	var out: Variant = script.new()
	out.grid = p_grid
	var unit_list: Array = []
	for raw_unit in p_units:
		unit_list.append(raw_unit)
	out.units = unit_list
	out.martials = p_martials
	out.mastery = p_mastery
	out.objective = p_objective
	out.leader_id = p_leader_id
	var turn_queue: Variant = TurnQueue.new()
	for entry in unit_list:
		turn_queue.add(str(entry.id), int(entry.speed()))
	out.queue = turn_queue
	out.rng = RandomNumberGenerator.new()
	out.rng.seed = p_seed
	TacticsWeakness.initialize(out)
	return out

func unit_at(cell: Vector2i) -> Variant:
	for entry in units:
		if entry.is_alive() and entry.pos == cell:
			return entry
	return null

func get_unit(unit_id: String) -> Variant:
	for entry in units:
		if entry.id == unit_id:
			return entry
	return null

func alive(side: String) -> Array:
	var out: Array = []
	for entry in units:
		if entry.is_alive() and entry.side == side:
			out.append(entry)
	return out

func reachable_cells(uid: String) -> Dictionary:
	var unit = get_unit(uid)
	if unit == null or not unit.is_alive():
		return {}
	if unit.unit.is_stunned():
		return {unit.pos: 0}
	var sets := _move_sets(unit)
	var reached: Dictionary = grid.reachable(
		unit.pos, unit.move_range(), unit.max_climb(), sets["blocked"], sets["allies"])
	for cell in sets["blocked"].keys():
		reached.erase(cell)
	for cell in sets["allies"].keys():
		reached.erase(cell)
	return reached

func attack_cells(uid: String, martial_id: String) -> Array[Vector2i]:
	var unit = get_unit(uid)
	if unit == null or not unit.is_alive():
		return []
	var pattern := _pattern_of(unit, martial_id)
	if pattern.is_empty():
		return []
	return Pattern.target_cells(pattern, unit.pos, unit.facing, grid)

func affected_units(uid: String, move_id: String, target_cell: Vector2i) -> Array:
	var unit = get_unit(uid)
	if unit == null or not unit.is_alive():
		return []
	var pattern := _pattern_of(unit, move_id)
	if pattern.is_empty():
		return []
	var cells: Array[Vector2i] = Pattern.affected_cells(
		pattern, unit.pos, unit.facing, target_cell, grid)
	var first_only := str(pattern.get("shape", "")) == "line" \
			and not bool(pattern.get("pierce", false))
	var out: Array = []
	for cell in cells:
		var target = unit_at(cell)
		if target == null:
			continue
		if target.side == unit.side:
			if first_only:
				break
			continue
		out.append(target)
		if first_only:
			break
	return out

func begin_turn() -> String:
	if result() != "":
		return ""
	var guard := 0
	while guard < 10000:
		guard += 1
		var actor_id: String = queue.next_actor()
		if actor_id == "":
			current_actor = ""
			return ""
		var actor = get_unit(actor_id)
		if actor == null or not actor.is_alive():
			queue.remove(actor_id)
			continue
		actor.start_turn()
		if actor.unit.stun_left > 0:
			_record([{"type": "stunned_skip", "unit": actor_id}])
			_record(TacticsToughness.tick_stun(self, actor))
			queue.end_turn(actor_id, TurnQueue.THRESHOLD)
			continue
		current_actor = actor_id
		return actor_id
	current_actor = ""
	return ""

func end_turn(uid: String) -> void:
	if get_unit(uid) == null:
		return
	_record(TacticsToughness.end_turn(self, uid))
	queue.end_turn(uid)
	if uid == current_actor:
		current_actor = ""
	round += 1

func move(uid: String, dest: Vector2i) -> Dictionary:
	if result() != "":
		return _fail("battle_over")
	var unit = get_unit(uid)
	if unit == null or not unit.is_alive():
		return _fail("no_unit")
	if uid != current_actor:
		return _fail("not_active")
	if unit.has_moved:
		return _fail("already_moved")
	if not reachable_cells(uid).has(dest):
		return _fail("unreachable")
	var from: Vector2i = unit.pos
	var sets := _move_sets(unit)
	var route: Array[Vector2i] = grid.path(
		from, dest, unit.move_range(), unit.max_climb(), sets["blocked"], sets["allies"])
	if dest != from and route.is_empty():
		return _fail("unreachable")
	if route.size() >= 2:
		var delta: Vector2i = route[route.size() - 1] - route[route.size() - 2]
		unit.facing = Facing.from_delta(delta, unit.facing)
	unit.pos = dest
	unit.has_moved = true
	var events: Array = [{
		"type": "move", "unit": uid, "from": from, "to": dest, "facing": unit.facing}]
	_record(events)
	return {"ok": true, "reason": "", "events": events}

func face(uid: String, dir: Vector2i) -> Dictionary:
	if result() != "":
		return _fail("battle_over")
	var unit = get_unit(uid)
	if unit == null or not unit.is_alive():
		return _fail("no_unit")
	var directions: Array[Vector2i] = [Facing.UP, Facing.DOWN, Facing.LEFT, Facing.RIGHT]
	if not directions.has(dir):
		return _fail("bad_direction")
	unit.facing = dir
	return {"ok": true, "reason": "", "events": []}

func attack(uid: String, martial_id: String, target_cell: Vector2i,
		reactions: Dictionary = {}, energy := "neili") -> Dictionary:
	if result() != "":
		return _fail("battle_over")
	var attacker = get_unit(uid)
	if attacker == null or not attacker.is_alive():
		return _fail("no_unit")
	if uid != current_actor:
		return _fail("not_active")
	if attacker.has_acted:
		return _fail("already_acted")
	var cost := 0
	if attacker.side == "enemy":
		if _enemy_move(attacker, martial_id).is_empty():
			return _fail("unknown_move")
	else:
		if not attacker.loadout.has(martial_id) or not martials.has(martial_id):
			return _fail("not_in_loadout")
		cost = TacticsEnergy.cost_for(martials[martial_id])
		if not attacker.can_pay(energy, cost):
			return _fail("no_energy")
	if not attack_cells(uid, martial_id).has(target_cell):
		return _fail("out_of_range")
	attacker.has_acted = true
	if attacker.side == "player":
		attacker.spend_energy(energy, cost)
	var empower_mult := TacticsToughness.consume_empower(attacker)
	var events: Array = [{
		"type": "attack", "unit": uid, "martial_id": martial_id,
		"target": target_cell, "energy": energy}]
	var defenders := affected_units(uid, martial_id, target_cell)
	for defender in defenders:
		events.append_array(
			_resolve_hit(attacker, martial_id, defender, reactions, empower_mult, energy))
	if attacker.side == "player" and not defenders.is_empty() and mastery != null:
		mastery.add_exp(martial_id, 1)
	_record(events)
	return {"ok": true, "reason": "", "events": events}

func preview_reactions(uid: String, martial_id: String, target_cell: Vector2i) -> Array:
	var attacker = get_unit(uid)
	if attacker == null or not attacker.is_alive():
		return []
	var move_def := _move_def(attacker, martial_id)
	if move_def.is_empty():
		return []
	var out: Array = []
	for defender in affected_units(uid, martial_id, target_cell):
		if defender.side != "player":
			continue
		var relation := Facing.relation(defender.pos, defender.facing, attacker.pos)
		out.append({
			"defender_id": defender.id,
			"options": TacticsReaction.options(
				defender, attacker, move_def, martials, mastery, relation, {"grid": grid}),
		})
	return out

func jianyi(uid: String, martial_id: String, target_cell: Vector2i) -> Dictionary:
	if result() != "":
		return _fail("battle_over")
	var attacker = get_unit(uid)
	if attacker == null or not attacker.is_alive():
		return _fail("no_unit")
	if uid != current_actor:
		return _fail("not_active")
	if attacker.has_acted:
		return _fail("already_acted")
	if attacker.side != "player":
		return _fail("player_only")
	if int(attacker.unit.jianyi_points) <= 0:
		return _fail("no_jianyi")
	if not attacker.loadout.has(martial_id) or not martials.has(martial_id):
		return _fail("not_in_loadout")
	if not attack_cells(uid, martial_id).has(target_cell):
		return _fail("out_of_range")
	var martial = martials[martial_id]
	var damage := TacticsDamage.jianyi_damage(
		attacker.unit.stats, attacker.unit.realm, int(martial.power), _mastery_mult(martial_id))
	attacker.unit.jianyi_points -= 1
	attacker.has_acted = true
	var events: Array = []
	for defender in affected_units(uid, martial_id, target_cell):
		defender.unit.take_wound(damage)
		events.append({
			"type": "jianyi", "unit": uid, "defender": defender.id, "damage": damage})
		var weak_color := TacticsWeakness.weak_color(self, attacker, defender, "")
		events.append_array(
			TacticsToughness.resolve_hit(self, attacker, defender, weak_color)["events"])
		if defender.unit.is_dead():
			events.append({"type": "dead", "unit": defender.id})
			queue.remove(defender.id)
	_record(events)
	return {"ok": true, "reason": "", "events": events}

func wait(uid: String) -> Dictionary:
	if result() != "":
		return _fail("battle_over")
	var unit = get_unit(uid)
	if unit == null or not unit.is_alive():
		return _fail("no_unit")
	if uid != current_actor:
		return _fail("not_active")
	unit.has_acted = true
	return {"ok": true, "reason": "", "events": []}

func release_ziqi(uid: String) -> Dictionary:
	return TacticsRelease.release(self, uid)

func result() -> String:
	var enemies := alive("enemy")
	if objective == "defeat_leader" and leader_id != "":
		var leader = get_unit(leader_id)
		if leader != null and not leader.is_alive():
			return "win"
	elif enemies.is_empty():
		return "win"
	if alive("player").is_empty():
		return "lose"
	var hero = get_unit("player")
	if hero != null and not hero.is_alive():
		return "lose"
	return ""

func _resolve_hit(attacker, martial_id: String, defender, reactions: Dictionary,
		empower_mult: float = 1.0, energy := "neili") -> Array:
	var events: Array = []
	var relation := Facing.relation(defender.pos, defender.facing, attacker.pos)
	var height_bonus := StatsRules.height_bonus(
		grid.height_at(attacker.pos), grid.height_at(defender.pos))
	var move_def := _move_def(attacker, martial_id)
	var base_damage := _base_damage(attacker, martial_id, defender, relation, height_bonus)
	if empower_mult != 1.0:
		base_damage = maxi(1, floori(float(base_damage) * empower_mult))
	base_damage = maxi(1, floori(
		float(base_damage) * float(TacticsEnergy.damage_pct(energy)) / 100.0))
	var damage := base_damage
	var weak_color := TacticsWeakness.weak_color(self, attacker, defender, energy)
	var weak := weak_color != ""
	var verdict: int = Counter.Verdict.IMPOSSIBLE
	var perfect := false
	var outcome := "none"
	var counter_pct := 0
	var jianyi_gain := 0
	var reaction_id := ""
	if reactions.has(defender.id):
		var chosen := str(reactions[defender.id])
		if chosen != "":
			var battle_ctx := {"grid": grid}
			var available: Array = TacticsReaction.options(
				defender, attacker, move_def, martials, mastery, relation, battle_ctx)
			if _has_option(available, chosen):
				reaction_id = chosen
				defender.reactions_left = maxi(0, defender.reactions_left - 1)
				defender.spend_energy(
					"neili", TacticsReaction.cost_of(chosen, martials))
				var resolved: Dictionary = TacticsReaction.resolve(
					defender, attacker, move_def, chosen, martials, mastery, relation,
					base_damage, battle_ctx)
				damage = int(resolved["damage"])
				verdict = int(resolved["verdict"])
				perfect = bool(resolved["perfect"])
				outcome = str(resolved.get("outcome", "none"))
				counter_pct = int(resolved.get("counter_pct", 0))
				jianyi_gain = int(resolved.get("jianyi", 0))
				if not bool(resolved.get("block", false)):
					_add_counter_exp(chosen, verdict, perfect)
	if weak:
		damage = maxi(1, floori(
			float(damage) * float(TacticsWeakness.damage_pct()) / 100.0))
	defender.unit.take_damage(damage)
	var toughness := TacticsToughness.resolve_hit(self, attacker, defender, weak_color)
	events.append({
		"type": "hit", "attacker": attacker.id, "defender": defender.id,
		"damage": damage, "relation": relation, "reaction": reaction_id,
		"verdict": verdict, "perfect": perfect, "outcome": outcome,
		"weak": weak, "weak_color": weak_color, "energy": energy,
		"toughness_left": toughness["toughness_left"],
	})
	events.append_array(toughness["events"])
	if energy == "ziqi" and attacker.side == "player":
		var healed: int = attacker.unit.heal(
			TacticsEnergy.heal_for(damage, attacker.unit.stats))
		if healed > 0:
			events.append({"type": "heal", "unit": attacker.id, "amount": healed})
	if counter_pct > 0:
		events.append_array(_counter_hit(defender, attacker, reaction_id, counter_pct))
	if jianyi_gain > 0:
		defender.unit.jianyi_points = mini(
			int(defender.unit.jianyi_max), int(defender.unit.jianyi_points) + jianyi_gain)
	if defender.unit.is_dead():
		events.append({"type": "dead", "unit": defender.id})
		queue.remove(defender.id)
	if attacker.unit.is_dead():
		events.append({"type": "dead", "unit": attacker.id})
		queue.remove(attacker.id)
	return events

func _counter_hit(defender, attacker, martial_id: String, counter_pct: int) -> Array:
	var martial = martials.get(martial_id)
	if martial == null or counter_pct <= 0:
		return []
	var relation := Facing.relation(attacker.pos, attacker.facing, defender.pos)
	var height_bonus := StatsRules.height_bonus(
		grid.height_at(defender.pos), grid.height_at(attacker.pos))
	var full_damage := TacticsDamage.martial_damage(
		defender.unit.stats, defender.unit.realm, int(martial.power), _mastery_mult(martial_id),
		attacker.unit, relation, height_bonus)
	var damage := maxi(1, floori(float(full_damage) * float(counter_pct) / 100.0))
	attacker.unit.take_damage(damage)
	return [{
		"type": "counter_hit", "attacker": defender.id,
		"defender": attacker.id, "damage": damage,
	}]

func _base_damage(attacker, martial_id: String, defender, relation: String,
		height_bonus: float) -> int:
	if attacker.side == "enemy":
		var move_def := _enemy_move(attacker, martial_id)
		return TacticsDamage.move_damage(
			int(move_def.get("power", 0)), attacker.unit.realm,
			defender.unit, relation, height_bonus)
	var martial = martials.get(martial_id)
	if martial == null:
		return 0
	return TacticsDamage.martial_damage(
		attacker.unit.stats, attacker.unit.realm, int(martial.power),
		_mastery_mult(martial_id), defender.unit, relation, height_bonus)

func _add_counter_exp(martial_id: String, verdict: int, perfect: bool) -> void:
	if mastery == null or verdict == Counter.Verdict.IMPOSSIBLE:
		return
	var kind := "barely"
	if verdict == Counter.Verdict.ADVANTAGE:
		kind = "perfect" if perfect else "advantage"
	var gain := Mastery.counter_exp(kind)
	if gain > 0:
		mastery.add_exp(martial_id, gain)

func _move_sets(unit) -> Dictionary:
	var blocked := {}
	var allies := {}
	for other in units:
		if other == unit or not other.is_alive():
			continue
		if other.side == unit.side:
			allies[other.pos] = true
		else:
			blocked[other.pos] = true
	return {"blocked": blocked, "allies": allies}

func _pattern_of(unit, martial_id: String) -> Dictionary:
	if unit.side == "enemy":
		var move_def := _enemy_move(unit, martial_id)
		if move_def.is_empty():
			return {}
		var move_range = move_def.get("range", {})
		return move_range if move_range is Dictionary else {}
	var martial = martials.get(martial_id)
	if martial == null or not (martial.range is Dictionary):
		return {}
	return martial.range

func _enemy_move(unit, move_id: String) -> Dictionary:
	var def = unit.unit.def
	if def == null:
		return {}
	for move_def in def.moves:
		if str(move_def.get("id", "")) == move_id:
			return move_def
	return {}

func _move_def(attacker, martial_id: String) -> Dictionary:
	if attacker.side == "enemy":
		return _enemy_move(attacker, martial_id)
	var martial = martials.get(martial_id)
	if martial == null:
		return {}
	return {
		"id": martial_id, "name": martial.name, "type": "", "threat": 0,
		"power": int(martial.power), "range": martial.range,
	}

func _mastery_mult(martial_id: String) -> float:
	if mastery == null:
		return 1.0
	return float(mastery.damage_multiplier(martial_id))

func _has_option(options: Array, martial_id: String) -> bool:
	for option in options:
		if str(option.get("id", "")) == martial_id:
			return true
	return false

func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "events": []}

func _record(events: Array) -> void:
	for event in events:
		log.append(event)

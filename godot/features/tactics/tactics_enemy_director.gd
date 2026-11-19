extends RefCounted

# 敌方回合演出：调用 AI 规划，逐步移动、计算可用反制、等待玩家反制（或 bot 自动选择），
# 然后执行攻击并结束行动。由视图在进入 enemy 状态后驱动；本类只调用规则与界面。

const Facing = preload("res://core/tactics/facing.gd")
const TacticsAi = preload("res://core/tactics/tactics_ai.gd")
const TacticsBot = preload("res://core/tactics/tactics_bot.gd")

const MOVE_PAUSE := 0.3
const EVENT_PAUSE := 0.4

var view = null
var actor_id: String = ""

var plan: Dictionary = {}
var pending_attack: Dictionary = {}
var reaction_queue: Array = []
var reaction_index: int = 0
var reactions: Dictionary = {}
var waiting_reaction: bool = false


func setup(p_view) -> void:
	view = p_view


func reset() -> void:
	actor_id = ""
	plan = {}
	pending_attack = {}
	reaction_queue = []
	reaction_index = 0
	reactions = {}
	waiting_reaction = false
	if view.reaction_menu != null:
		view.reaction_menu.close()


func begin(p_actor_id: String) -> void:
	actor_id = p_actor_id
	plan = TacticsAi.plan(view.battle, actor_id, view.rng)
	pending_attack = {}
	reaction_queue = []
	reaction_index = 0
	reactions = {}
	waiting_reaction = false
	view.reaction_menu.close()

	if plan.get("move", null) != null:
		var moved: Dictionary = view.battle.move(actor_id, plan["move"])
		if bool(moved.get("ok", false)):
			view._append_events(moved.get("events", []))
		else:
			plan = {"move": null, "attack": null}
		view._refresh_all()
		view._delay(MOVE_PAUSE, _after_move)
	else:
		_after_move()


func reaction_options() -> Array:
	if not waiting_reaction or reaction_index >= reaction_queue.size():
		return []
	var entry: Dictionary = reaction_queue[reaction_index]
	var options = entry.get("options", [])
	return options if options is Array else []


func choose_reaction(defender_id: String, martial_id: String) -> void:
	if not waiting_reaction or reaction_index >= reaction_queue.size():
		return
	var entry: Dictionary = reaction_queue[reaction_index]
	if str(entry.get("defender_id", "")) != defender_id:
		return
	if martial_id != "":
		reactions[defender_id] = martial_id
	reaction_index += 1
	_show_next_reaction()


func cancel() -> void:
	waiting_reaction = false
	if view.reaction_menu != null:
		view.reaction_menu.close()


func _after_move() -> void:
	if not is_instance_valid(view) or view.battle == null or view.state() != "enemy":
		return
	var attack: Variant = plan.get("attack", null)
	if not (attack is Dictionary):
		_finish()
		return
	pending_attack = attack
	var attacker = view.battle.get_unit(actor_id)
	if attacker == null or not attacker.is_alive():
		_finish()
		return
	var preview: Array = view.battle.preview_reactions(
		actor_id, str(attack["martial_id"]), attack["target_cell"])
	var available: Array = []
	for raw_entry in preview:
		if not (raw_entry is Dictionary):
			continue
		var entry: Dictionary = raw_entry
		var options = entry.get("options", [])
		if options is Array and not options.is_empty():
			available.append(entry)
	reactions = {}
	if available.is_empty():
		_execute_attack()
		return
	if view.auto_reactions:
		reactions = TacticsBot.pick_reactions(available, "best")
		_execute_attack()
		return
	reaction_queue = available
	reaction_index = 0
	waiting_reaction = true
	_show_next_reaction()


func _show_next_reaction() -> void:
	if view.battle == null:
		return
	if reaction_index >= reaction_queue.size():
		waiting_reaction = false
		view.reaction_menu.close()
		_execute_attack()
		return
	var entry: Dictionary = reaction_queue[reaction_index]
	var defender_id := str(entry.get("defender_id", ""))
	var defender = view.battle.get_unit(defender_id)
	var attacker = view.battle.get_unit(actor_id)
	if defender == null or attacker == null:
		reaction_index += 1
		_show_next_reaction()
		return
	var relation := Facing.relation(defender.pos, defender.facing, attacker.pos)
	var move_name := _move_name(attacker, str(pending_attack.get("martial_id", "")))
	var options = entry.get("options", [])
	view.reaction_menu.open_for(
		str(attacker.unit.name), move_name, view._relation_text(relation), defender_id,
		options if options is Array else [], view.battle.martials, defender.energy_left)


func _execute_attack() -> void:
	var attack: Dictionary = pending_attack
	if view.battle == null or attack.is_empty():
		_finish()
		return
	var attacker = view.battle.get_unit(actor_id)
	if attacker != null and attacker.is_alive():
		var target_cell: Vector2i = attack["target_cell"]
		view.battle.face(actor_id, Facing.from_delta(target_cell - attacker.pos, attacker.facing))
		var result: Dictionary = view.battle.attack(
			actor_id, str(attack["martial_id"]), target_cell, reactions)
		if bool(result.get("ok", false)):
			view._append_events(result.get("events", []))
		else:
			view._append_log("攻击失败：%s" % str(result.get("reason", "")))
			view.battle.wait(actor_id)
	view._refresh_all()
	view._delay(EVENT_PAUSE, _finish)


func _finish() -> void:
	if not is_instance_valid(view) or view.battle == null or view.state() != "enemy":
		return
	var finished := actor_id
	waiting_reaction = false
	pending_attack = {}
	view.reaction_menu.close()
	if str(view.battle.current_actor) == finished:
		view.battle.end_turn(finished)
	actor_id = ""
	view._actor_id = ""
	view._next_phase()


func _move_name(attacker, move_id: String) -> String:
	if attacker.unit != null and attacker.unit.def != null:
		for move in attacker.unit.def.moves:
			if str(move.get("id", "")) == move_id:
				return str(move.get("name", move_id))
	return move_id

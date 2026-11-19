extends "res://tests/test_case.gd"

const Counter = preload("res://core/counter.gd")
const Facing = preload("res://core/tactics/facing.gd")
const GameState = preload("res://core/game_state.gd")


func _make_view(use_stage_3d: bool = false) -> Dictionary:
	GameState.reset()
	var tree: Variant = Engine.get_meta("test_tree", null)
	var holder := Control.new()
	holder.size = Vector2(1152.0, 720.0)
	if tree != null:
		tree.root.add_child(holder)
	var view: Variant = load("res://features/tactics/tactics_view.gd").new()
	view.use_3d = use_stage_3d
	holder.add_child(view)
	view.size = Vector2(1152.0, 720.0)
	return {"holder": holder, "view": view}


func _finish(holder: Control) -> void:
	holder.free()
	GameState.reset()


func test_start_builds_battle_and_enters_a_turn() -> void:
	var built := _make_view()
	var view: Variant = built["view"]
	view.start()
	assert_true(view.battle != null, "the tavern battle is assembled")
	assert_eq(view.battle.units.size(), 7, "one player plus six enemies")
	assert_eq(view.board.battle, view.battle, "the board draws the assembled battle")
	assert_true(view.state() == "player" or view.state() == "enemy",
		"the state machine enters a turn, got %s" % view.state())
	_finish(built["holder"])


func test_player_move_attack_and_illegal_cell() -> void:
	var built := _make_view()
	var view: Variant = built["view"]
	view.start()
	assert_eq(view.state(), "player", "the player acts first at base stats")
	var battle: Variant = view.battle
	var player = battle.get_unit("player")
	var origin: Vector2i = player.pos

	view.choose_mode("move", "")
	view.click_cell(Vector2i(9, 0))
	assert_eq(player.pos, origin, "an unreachable cell does not move the player")
	assert_true(str(view.panel.message_label.text) != "", "an illegal move reports a message")
	assert_eq(view.state(), "player", "the illegal click keeps the player turn")

	var dest := Vector2i(origin.x, origin.y - 2)
	assert_true(battle.reachable_cells("player").has(dest), "the test destination is reachable")
	view.click_cell(dest)
	assert_eq(player.pos, dest, "clicking a reachable cell moves the player")

	var enemy = battle.units[1]
	enemy.pos = dest + Vector2i(1, 0)
	var hp_before := int(enemy.unit.hp)
	view.choose_mode("attack", "basic_sword")
	view.click_cell(enemy.pos)
	assert_true(int(enemy.unit.hp) < hp_before, "attacking the enemy cell deals damage")
	_finish(built["holder"])


# 把一个 rush 敌人放到玩家身旁，并让它在下一次行动时出手；玩家反制资格成立。
func _reaction_scenario() -> Dictionary:
	var built := _make_view()
	var view: Variant = built["view"]
	view.start()
	var battle: Variant = view.battle
	var player = battle.get_unit("player")
	player.facing = Facing.RIGHT
	var bandit = null
	for unit in battle.units:
		if unit.side == "enemy" and str(unit.unit.def.ai) == "rush":
			bandit = unit
			break
	if bandit == null:
		return {"holder": built["holder"], "view": view, "bandit": null}
	bandit.pos = player.pos + Vector2i(1, 0)
	bandit.facing = Facing.LEFT
	battle.queue.add_ct(str(bandit.id), 500)
	view.choose_mode("end", "")
	return {"holder": built["holder"], "view": view, "bandit": bandit}


func test_reaction_menu_can_decline() -> void:
	var scenario := _reaction_scenario()
	var view: Variant = scenario["view"]
	assert_true(scenario["bandit"] != null, "the scenario found a rush enemy")
	if scenario["bandit"] == null:
		_finish(scenario["holder"])
		return
	assert_true(view.is_waiting_reaction(), "a qualified defender opens the reaction menu")
	assert_true(view.reaction_options().size() > 0, "the menu lists counter options")
	var player = view.battle.get_unit("player")
	var hp_before := int(player.unit.hp)
	var guard := 0
	while view.is_waiting_reaction() and guard < 20:
		view.choose_reaction("player", "")
		guard += 1
	assert_true(int(player.unit.hp) < hp_before, "declining a reaction lets the hit land")
	_finish(scenario["holder"])


func test_reaction_menu_can_counter() -> void:
	var scenario := _reaction_scenario()
	var view: Variant = scenario["view"]
	assert_true(scenario["bandit"] != null, "the scenario found a rush enemy")
	if scenario["bandit"] == null:
		_finish(scenario["holder"])
		return
	assert_true(view.is_waiting_reaction(), "the reaction menu waits for a choice")
	var options: Array = view.reaction_options()
	assert_true(options.size() > 0, "the menu lists counter options")
	var option: Dictionary = options[0]
	var martial_id := str(option.get("id", ""))
	var expected_zero := bool(option.get("perfect", false)) \
			or int(option.get("verdict", 0)) == Counter.Verdict.ADVANTAGE
	view.choose_reaction("player", martial_id)
	assert_true(not view.is_waiting_reaction(), "a choice resumes the battle")

	var reacted := false
	for event in view.battle.log:
		if str(event.get("type", "")) != "hit":
			continue
		if str(event.get("defender", "")) != "player":
			continue
		if str(event.get("reaction", "")) != martial_id:
			continue
		reacted = true
		if expected_zero:
			assert_eq(int(event.get("damage", -1)), 0, "an advantage counter negates the hit")
	assert_true(reacted, "the chosen counter is recorded in the battle log")
	_finish(scenario["holder"])


func test_bot_plays_to_a_finish() -> void:
	var built := _make_view()
	var view: Variant = built["view"]
	view.start()
	var guard := 0
	while view.battle.result() == "" and guard < 100:
		if view.state() == "player":
			view.bot_play_player_turn()
		elif view.is_waiting_reaction():
			view.choose_reaction("player", "")
		else:
			break
		guard += 1
	var outcome := str(view.battle.result())
	assert_true(outcome == "win" or outcome == "lose",
		"the battle reaches a result, got '%s' (%d iterations)" % [outcome, guard])
	assert_true(guard < 100, "the loop is bounded")
	_finish(built["holder"])


func test_use_3d_stage_builds_by_default() -> void:
	var probe: Variant = load("res://features/tactics/tactics_view.gd").new()
	assert_true(probe.use_3d, "the view defaults to the 3d stage")
	probe.free()

	var built := _make_view(true)
	var view: Variant = built["view"]
	view.start()
	assert_true(view.stage != null, "the 3d stage is created")
	if view.stage != null:
		assert_true(view.board == view.stage, "the stage stands in for the board")
		assert_eq(str(view.stage.backdrop), "tavern", "the map backdrop reaches the stage")
		assert_true(view.stage.camera != null, "the stage owns a camera")
		assert_eq(
			view.stage.tiles.cell_count(),
			int(view.battle.grid.width) * int(view.battle.grid.height),
			"the stage builds one tile per cell")
		assert_eq(view.stage.units.actor_count(), view.battle.units.size(),
			"the stage builds an actor per unit")
	_finish(built["holder"])


func test_restart_after_result() -> void:
	var built := _make_view()
	var view: Variant = built["view"]
	view.start()
	var first_battle: Variant = view.battle
	var leader = first_battle.get_unit(first_battle.leader_id)
	assert_true(leader != null, "the tavern has a leader")
	leader.unit.hp = 0
	view.choose_mode("end", "")
	assert_eq(view.state(), "result", "a finished battle shows the result overlay")
	assert_true(view.result_overlay.visible, "the result overlay is visible")
	view.restart()
	assert_true(view.battle != first_battle, "restart builds a fresh battle")
	assert_eq(str(view.battle.result()), "", "the fresh battle is not over")
	assert_eq(int(view.battle.round), 0, "the fresh battle starts at action zero")
	assert_true(view.state() == "player" or view.state() == "enemy", "a new turn begins")
	_finish(built["holder"])

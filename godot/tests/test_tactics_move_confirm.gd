extends "res://tests/test_case.gd"

# 没选“移动”直接点蓝色可移动格：第一下选中，第二下移动。

const GameState = preload("res://core/game_state.gd")


func _make_view() -> Dictionary:
	GameState.reset()
	var tree: Variant = Engine.get_meta("test_tree", null)
	var holder := Control.new()
	holder.size = Vector2(1152.0, 720.0)
	if tree != null:
		tree.root.add_child(holder)
	var view: Variant = load("res://features/tactics/tactics_view.gd").new()
	view.use_3d = false
	holder.add_child(view)
	view.size = Vector2(1152.0, 720.0)
	return {"holder": holder, "view": view}


func _finish(holder: Control) -> void:
	holder.free()
	GameState.reset()


func _player_turn(view: Variant) -> bool:
	return view.state() == "player"


func _reachable_target(view: Variant) -> Vector2i:
	var unit = view.battle.get_unit(view._actor_id)
	for raw in view.battle.reachable_cells(unit.id).keys():
		var cell: Vector2i = raw
		if cell != unit.pos:
			return cell
	return Vector2i(-1, -1)


func test_two_clicks_on_a_blue_cell_move_the_player() -> void:
	var built := _make_view()
	var view: Variant = built["view"]
	view.start()
	if not _player_turn(view):
		_finish(built["holder"])
		return
	var unit = view.battle.get_unit(view._actor_id)
	var start: Vector2i = unit.pos
	var target := _reachable_target(view)
	assert_true(target.x >= 0, "the player has a reachable cell")
	view.click_cell(target)
	assert_eq(unit.pos, start, "the first click only selects the target")
	assert_eq(view._player_input.pending_move, target, "the target is remembered")
	assert_eq(view._player_input.overlays["selected"], target, "the target is highlighted")
	view.click_cell(target)
	assert_eq(unit.pos, target, "the second click on the same cell moves the player")
	assert_true(view._player_input.pending_move == null, "the pending target is cleared")
	_finish(built["holder"])


func test_clicking_another_blue_cell_changes_the_target() -> void:
	var built := _make_view()
	var view: Variant = built["view"]
	view.start()
	if not _player_turn(view):
		_finish(built["holder"])
		return
	var unit = view.battle.get_unit(view._actor_id)
	var start: Vector2i = unit.pos
	var cells: Array = []
	for raw in view.battle.reachable_cells(unit.id).keys():
		if raw != start:
			cells.append(raw)
	assert_true(cells.size() >= 2, "there are at least two reachable cells")
	view.click_cell(cells[0])
	view.click_cell(cells[1])
	assert_eq(unit.pos, start, "clicking a different cell only changes the target")
	assert_eq(view._player_input.pending_move, cells[1], "the new target replaces the old one")
	_finish(built["holder"])


func test_clicking_an_unreachable_cell_cancels_the_selection() -> void:
	var built := _make_view()
	var view: Variant = built["view"]
	view.start()
	if not _player_turn(view):
		_finish(built["holder"])
		return
	var unit = view.battle.get_unit(view._actor_id)
	var target := _reachable_target(view)
	view.click_cell(target)
	assert_true(view._player_input.pending_move != null, "a target is selected")
	view.click_cell(unit.pos)
	assert_true(view._player_input.pending_move == null, "clicking the own cell cancels it")
	assert_eq(unit.pos, unit.pos, "the player has not moved")
	_finish(built["holder"])


func test_explicit_move_mode_still_moves_with_one_click() -> void:
	var built := _make_view()
	var view: Variant = built["view"]
	view.start()
	if not _player_turn(view):
		_finish(built["holder"])
		return
	var unit = view.battle.get_unit(view._actor_id)
	var target := _reachable_target(view)
	view.choose_mode("move", "")
	view.click_cell(target)
	assert_eq(unit.pos, target, "after choosing the move action one click is enough")
	_finish(built["holder"])

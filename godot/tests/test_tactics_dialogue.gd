extends "res://tests/test_case.gd"

# 战棋胜利对话：遭遇表里有 win 对话时，胜利先播对话、播完再显示结算层；
# 无对话/战败/沙盒直接结算，对话只播一次，battle_finished 仍只发一次。

const GameState = preload("res://core/game_state.gd")
const TacticsSession = preload("res://features/tactics/tactics_session.gd")
const TacticsDialogueFlow = preload("res://features/tactics/tactics_dialogue_flow.gd")

var results: Array = []
var dialogue_done: int = 0


func _on_battle_finished(result: String) -> void:
	results.append(result)


func _on_dialogue_done() -> void:
	dialogue_done += 1


func _make_view() -> Dictionary:
	GameState.reset()
	results.clear()
	var tree: Variant = Engine.get_meta("test_tree", null)
	var holder := Control.new()
	holder.size = Vector2(1152.0, 648.0)
	if tree != null:
		tree.root.add_child(holder)
	var view: Variant = load("res://features/tactics/tactics_view.gd").new()
	view.use_3d = false
	holder.add_child(view)
	view.size = Vector2(1152.0, 648.0)
	return {"holder": holder, "view": view}


func _finish(holder: Control) -> void:
	holder.free()
	GameState.reset()


func _win_battle(view) -> void:
	for unit in view.battle.units:
		if unit.side == "enemy":
			unit.unit.hp = 0
	view._check_result()


func _lose_battle(view) -> void:
	view.battle.get_unit("player").unit.hp = 0
	view._check_result()


func _dialogue_node(view) -> Variant:
	return view.get_node_or_null("TacticsDialogueView")


func _play_out(flow) -> void:
	var guard := 0
	while flow.is_active() and guard < 60:
		flow.advance()
		guard += 1


func test_session_records_the_leader_as_the_encounter_id() -> void:
	GameState.reset()
	GameState.encounter_group = [
		{"id": "ma_youwei", "count": 1},
		{"id": "bandit", "count": 2},
	]
	var built: Dictionary = TacticsSession.build("ma_youwei", 1, false, "tavern")
	assert_eq(str(built.get("encounter_id", "")), "ma_youwei",
		"the ambush group's leader is the encounter id")
	var single: Dictionary = TacticsSession.build("bandit", 1, false, "tavern")
	assert_eq(str(single.get("encounter_id", "")), "bandit",
		"a single enemy falls back to its own id")
	GameState.reset()


func test_win_dialogue_plays_before_the_result_overlay() -> void:
	var built := _make_view()
	var view: Variant = built["view"]
	view.start_from_game("ma_youwei", 1, true, "tavern")
	assert_true(view.battle != null, "the ambush battle is assembled")
	if view.battle == null:
		_finish(built["holder"])
		return
	_win_battle(view)
	var dialogue: Variant = _dialogue_node(view)
	assert_true(dialogue != null, "the win dialogue view is built")
	if dialogue == null:
		_finish(built["holder"])
		return
	assert_true(bool(dialogue.is_active()), "the win dialogue starts on victory")
	assert_true(dialogue.visible, "the dialogue view is on screen")
	assert_true(not view.result_overlay.visible, "the result waits for the dialogue")
	var guard := 0
	while bool(dialogue.is_active()) and guard < 60:
		dialogue.advance()
		guard += 1
	assert_true(guard < 60, "the win dialogue finishes")
	assert_true(view.result_overlay.visible, "the result overlay shows after the dialogue")
	assert_eq(str(view.restart_button.text), "继续", "the game battle offers continue")
	_finish(built["holder"])


func test_encounter_without_win_dialogue_shows_the_result_directly() -> void:
	var built := _make_view()
	var view: Variant = built["view"]
	view.start_from_game("bandit", 1, true, "tavern")
	_win_battle(view)
	assert_true(view.result_overlay.visible, "no win dialogue means an immediate result")
	var dialogue: Variant = _dialogue_node(view)
	assert_true(dialogue == null or not bool(dialogue.is_active()),
		"the dialogue view stays hidden for a plain encounter")
	assert_eq(str(view.restart_button.text), "继续", "the game battle offers continue")
	_finish(built["holder"])


func test_defeat_does_not_play_the_win_dialogue() -> void:
	var built := _make_view()
	var view: Variant = built["view"]
	view.start_from_game("ma_youwei", 1, true, "tavern")
	view.battle_finished.connect(Callable(self, "_on_battle_finished"))
	_lose_battle(view)
	var dialogue: Variant = _dialogue_node(view)
	assert_true(dialogue == null or not bool(dialogue.is_active()),
		"a defeat never plays the win dialogue")
	assert_true(view.result_overlay.visible, "a defeat shows the result directly")
	view.restart_button.pressed.emit()
	assert_eq(results, ["lost"], "the defeat reports lost")
	_finish(built["holder"])


func test_win_dialogue_and_battle_finished_fire_once() -> void:
	var built := _make_view()
	var view: Variant = built["view"]
	view.start_from_game("ma_youwei", 1, true, "tavern")
	view.battle_finished.connect(Callable(self, "_on_battle_finished"))
	_win_battle(view)
	var dialogue: Variant = _dialogue_node(view)
	if dialogue == null:
		assert_true(false, "the win dialogue view is built")
		_finish(built["holder"])
		return
	var guard := 0
	while bool(dialogue.is_active()) and guard < 60:
		dialogue.advance()
		guard += 1
	assert_true(guard < 60, "the win dialogue finishes before the result check")
	view._check_result()
	assert_true(not bool(dialogue.is_active()), "the win dialogue is not replayed")
	view.restart_button.pressed.emit()
	view.restart_button.pressed.emit()
	assert_eq(results, ["won"], "battle_finished fires once for the fight")
	_finish(built["holder"])


func test_sandbox_battles_skip_the_win_dialogue() -> void:
	var built := _make_view()
	var view: Variant = built["view"]
	view.start()
	assert_true(view.battle != null, "the sandbox battle is assembled")
	if view.battle == null:
		_finish(built["holder"])
		return
	_win_battle(view)
	assert_true(_dialogue_node(view) == null, "the sandbox has no dialogue view")
	assert_true(view.result_overlay.visible, "the sandbox shows the result directly")
	assert_eq(str(view.restart_button.text), "重来", "the sandbox offers restart")
	_finish(built["holder"])


func test_missing_dialogue_file_continues_immediately() -> void:
	var path := "user://tactics_dialogue_test_encounters.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_true(file != null, "the temporary encounter table can be written")
	if file == null:
		return
	file.store_string(JSON.stringify({"ghost": {"win": "user://no_such_dialogue.json"}}))
	file.close()

	var holder := Control.new()
	var flow: Variant = TacticsDialogueFlow.new()
	flow.build(holder)
	flow.encounters_path = path
	flow.reset("ghost")
	dialogue_done = 0
	flow.maybe_play_win(true, Callable(self, "_on_dialogue_done"))
	assert_eq(dialogue_done, 1, "a missing dialogue file continues immediately")
	assert_true(not flow.is_active(), "no half-open dialogue is left behind")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	holder.free()


func test_flow_skips_the_dialogue_for_misses_and_defeats() -> void:
	var holder := Control.new()
	var flow: Variant = TacticsDialogueFlow.new()
	flow.build(holder)

	dialogue_done = 0
	flow.reset("not_in_encounters")
	flow.maybe_play_win(true, Callable(self, "_on_dialogue_done"))
	assert_eq(dialogue_done, 1, "an encounter without a win path continues immediately")
	assert_true(not flow.is_active(), "nothing plays without a win path")

	flow.reset("ma_youwei")
	flow.maybe_play_win(false, Callable(self, "_on_dialogue_done"))
	assert_eq(dialogue_done, 2, "a defeat continues immediately")
	assert_true(not flow.is_active(), "a defeat plays no dialogue")

	dialogue_done = 0
	flow.reset("ma_youwei")
	flow.maybe_play_win(true, Callable(self, "_on_dialogue_done"))
	assert_true(flow.is_active(), "the win path starts the dialogue")
	assert_eq(dialogue_done, 0, "the callback waits for the dialogue to end")
	_play_out(flow)
	assert_eq(dialogue_done, 1, "the callback fires when the dialogue ends")
	flow.maybe_play_win(true, Callable(self, "_on_dialogue_done"))
	assert_eq(dialogue_done, 2, "a second win finishes without replaying")
	assert_true(not flow.is_active(), "the dialogue is not played twice")
	holder.free()

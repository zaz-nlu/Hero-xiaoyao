extends "res://tests/test_case.gd"

# Q/E 旋转视角：四档 yaw 与过渡、取景宽深互换、旋转后拾取仍命中格子、
# 2D 灰盒与模态弹层不响应、日志里有键位提示。

const GameState = preload("res://core/game_state.gd")
const TacticsSetup = preload("res://core/tactics/tactics_setup.gd")
const TacticsStage = preload("res://features/tactics/tactics_stage.gd")
const StageCamera = preload("res://features/tactics/tactics_stage_camera.gd")
const TacticsPicker = preload("res://features/tactics/tactics_picker.gd")
const TacticsView = preload("res://features/tactics/tactics_view.gd")
const DialogueView = preload("res://shared/ui/dialogue_view.gd")

const TAVERN_GROUP := [{"id": "ma_youwei", "count": 1}, {"id": "bandit", "count": 5}]
const VIEWPORT := Vector2(1152.0, 720.0)
const YAWS := [0.0, 90.0, 180.0, 270.0]


func _make_battle() -> Variant:
	GameState.reset()
	var built: Dictionary = TacticsSetup.build("tavern_brawl", TAVERN_GROUP, null, 1)
	if not bool(built.get("ok", false)):
		return null
	return built["battle"]


func _make_stage(battle: Variant) -> Variant:
	var stage: Variant = TacticsStage.new()
	stage.build(battle, "tavern")
	return stage


func _make_view(use_3d: bool) -> Dictionary:
	GameState.reset()
	var tree: Variant = Engine.get_meta("test_tree", null)
	var holder := Control.new()
	holder.size = VIEWPORT
	if tree != null:
		tree.root.add_child(holder)
	var view: Variant = TacticsView.new()
	view.use_3d = use_3d
	holder.add_child(view)
	view.size = VIEWPORT
	return {"holder": holder, "view": view}


func _finish(holder: Control) -> void:
	holder.free()
	GameState.reset()


func test_four_turns_return_to_the_start_yaw() -> void:
	var battle: Variant = _make_battle()
	assert_true(battle != null, "the tavern battle is assembled")
	if battle == null:
		return
	var stage: Variant = _make_stage(battle)
	for i in range(4):
		stage.rotate_view(1)
	assert_near(stage.view_yaw(), 0.0, 0.001, "four 90° turns wrap back to 0°")
	stage.free()


func test_q_and_e_turn_opposite_ways() -> void:
	var battle: Variant = _make_battle()
	assert_true(battle != null, "the tavern battle is assembled")
	if battle == null:
		return
	var stage: Variant = _make_stage(battle)
	stage.rotate_view(1)
	assert_near(stage.view_yaw(), 90.0, 0.001, "E turns clockwise to 90°")
	stage.rotate_view(-1)
	assert_near(stage.view_yaw(), 0.0, 0.001, "Q turns back to 0°")
	stage.rotate_view(-1)
	assert_near(stage.view_yaw(), 270.0, 0.001, "Q from 0° lands on 270°")
	stage.free()


func test_camera_direction_turns_ninety_degrees() -> void:
	var battle: Variant = _make_battle()
	assert_true(battle != null, "the tavern battle is assembled")
	if battle == null:
		return
	var stage: Variant = _make_stage(battle)
	var base: Vector3 = stage.view_direction()
	stage.rotate_view(1)
	var turned: Vector3 = stage.view_direction()
	var flat_base := Vector2(base.x, base.z).normalized()
	var flat_turned := Vector2(turned.x, turned.z).normalized()
	assert_near(flat_base.dot(flat_turned), 0.0, 0.001,
		"the horizontal view axes are perpendicular after 90°")
	assert_near(turned.y, base.y, 0.001, "turning keeps the camera pitch")
	stage.free()


func test_framing_holds_for_four_yaws() -> void:
	var battle: Variant = _make_battle()
	assert_true(battle != null, "the tavern battle is assembled")
	if battle == null:
		return
	var stage: Variant = _make_stage(battle)
	var board_w := float(battle.grid.width) * float(stage.tiles.cell_size)
	var board_d := float(battle.grid.height) * float(stage.tiles.cell_size)
	for yaw in YAWS:
		var direction: Vector3 = StageCamera.direction_for_yaw(yaw)
		var framed: Dictionary = StageCamera.framing(
			VIEWPORT, board_w, board_d, 6.4, direction, yaw)
		assert_true(bool(framed.get("ok", false)),
			"framing succeeds at yaw %d" % int(yaw))
		var distance := float(framed.get("distance", 0.0))
		assert_true(is_finite(distance) and distance > 0.0,
			"framing distance is finite at yaw %d" % int(yaw))
	stage.free()


func test_picker_resolves_a_cell_from_every_yaw() -> void:
	var battle: Variant = _make_battle()
	assert_true(battle != null, "the tavern battle is assembled")
	if battle == null:
		return
	var stage: Variant = _make_stage(battle)
	var tree: Variant = Engine.get_meta("test_tree", null)
	if tree == null:
		stage.free()
		return
	var camera := Camera3D.new()
	tree.root.add_child(camera)
	# 测试运行器在首帧之前加入的节点还不在场景树里，此时拾取无法求交，跳过。
	if not camera.is_inside_tree():
		camera.free()
		stage.free()
		return
	camera.fov = StageCamera.CAM_FOV
	camera.near = 0.1
	camera.far = 500.0
	camera.current = true
	var target := Vector2i(4, 4)
	var center: Vector3 = stage.cell_center(target)
	var focus := Vector3(0.0, StageCamera.FOCUS_HEIGHT, 0.0)
	var board_w := float(battle.grid.width) * float(stage.tiles.cell_size)
	var board_d := float(battle.grid.height) * float(stage.tiles.cell_size)
	for yaw in YAWS:
		var direction: Vector3 = StageCamera.direction_for_yaw(yaw)
		var framed: Dictionary = StageCamera.framing(
			VIEWPORT, board_w, board_d, 6.4, direction, yaw)
		var distance := float(framed.get("distance", 0.0))
		var compose: Vector3 = framed.get("compose", Vector3.ZERO)
		camera.global_position = StageCamera.camera_position(
			focus, direction, distance, compose)
		camera.look_at(StageCamera.camera_target(focus, compose), Vector3.UP)
		var screen: Vector2 = camera.unproject_position(center)
		var picked: Vector2i = TacticsPicker.cell_at_screen(
			camera, screen, battle.grid, stage.tiles)
		assert_eq(picked, target,
			"the picker hits the projected cell at yaw %d" % int(yaw))
	camera.current = false
	camera.free()
	stage.free()


func test_2d_board_ignores_rotate_keys() -> void:
	var built := _make_view(false)
	var view: Variant = built["view"]
	view.start()
	assert_true(view.battle != null, "the 2d view builds a battle")
	assert_true(not view.board.has_method("rotate_view"),
		"the 2d board has no camera to rotate")
	view._player_input.handle_key(KEY_Q)
	view._player_input.handle_key(KEY_E)
	assert_true(view.battle != null, "pressing Q/E on the 2d board is ignored")
	_finish(built["holder"])


func test_modal_layers_block_rotate_keys() -> void:
	var built := _make_view(true)
	var view: Variant = built["view"]
	view.start()
	assert_true(view.stage != null, "the 3d stage exists")
	if view.stage == null:
		_finish(built["holder"])
		return
	var player = view.battle.get_unit("player")
	view.inspect_cell(player.pos)
	assert_true(view.is_bio_open(), "the bio card opens")
	view._player_input.handle_key(KEY_E)
	assert_near(view.stage.view_yaw_target(), 0.0, 0.001,
		"the bio card swallows Q/E")
	view.bio_card.close()

	var dialogue := DialogueView.new()
	dialogue.name = "TacticsDialogueView"
	view.add_child(dialogue)
	dialogue.start([{
		"speaker": "narrator", "name": "", "text": "……",
		"portrait": "", "side": "center"}])
	assert_true(dialogue.is_active(), "the dialogue is playing")
	view._player_input.handle_key(KEY_E)
	assert_near(view.stage.view_yaw_target(), 0.0, 0.001,
		"the dialogue swallows Q/E")

	dialogue.advance()
	dialogue.advance()
	assert_true(not dialogue.is_active(), "the dialogue is finished")
	view._player_input.handle_key(KEY_E)
	assert_near(view.stage.view_yaw_target(), 90.0, 0.001,
		"Q/E works again after the dialogue closes")
	_finish(built["holder"])


func test_rotation_hint_is_logged() -> void:
	var built := _make_view(false)
	var view: Variant = built["view"]
	view.start()
	var before := int(view.log_feed.line_count())
	view._player_input.announce_view_controls()
	assert_eq(view.log_feed.line_count(), before + 1,
		"the hint adds one log line")
	var box = view.log_feed._box
	var label = box.get_child(box.get_child_count() - 1)
	assert_true(str(label.text).contains("Q/E 旋转视角"),
		"the hint names the Q/E keys")
	_finish(built["holder"])

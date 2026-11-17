extends "res://tests/test_case.gd"

const GameState = preload("res://core/game_state.gd")

const GROUP: Array = [
	{"id": "ma_youwei", "count": 1},
	{"id": "bandit", "count": 5},
]


func _make_view() -> Variant:
	var view: Variant = load("res://ui/battle_view.gd").new()
	view.build_ui()
	return view


func _make_view_in_tree() -> Dictionary:
	var tree: Variant = Engine.get_meta("test_tree", null)
	var holder := SubViewport.new()
	holder.size = Vector2i(1152, 648)
	holder.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if tree != null:
		tree.root.add_child(holder)
	var view: Variant = load("res://ui/battle_view.gd").new()
	holder.add_child(view)
	view.build_ui()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.size = Vector2(1152.0, 648.0)
	return {"holder": holder, "view": view}


func test_six_enemies_are_created_from_the_group() -> void:
	GameState.reset()
	var view: Variant = _make_view()
	GameState.encounter_group = GROUP.duplicate(true)
	view.start("ma_youwei", 1, false, false)
	assert_eq(int(view.battle.enemies.size()), 6, "the group creates six enemies")
	assert_eq(GameState.encounter_group.size(), 0, "the group is cleared after start")
	assert_eq(str(view.battle.enemies[0].id), "ma_youwei", "the boss comes first")
	assert_eq(str(view.battle.enemies[1].def.sprite), "bandit", "bandits follow the boss")
	assert_eq(view.stage.enemy_actors.size(), 6, "the stage creates one actor per enemy")
	for i in range(view.stage.enemy_actors.size()):
		var actor: Variant = view.stage.enemy_actors[i]
		assert_true(
			actor.get_node_or_null("Sprite") != null,
			"enemy actor %d has its own sprite" % i
		)
		for j in range(i + 1, view.stage.enemy_actors.size()):
			var other: Variant = view.stage.enemy_actors[j]
			assert_true(
				actor.position.distance_to(other.position) >= 1.0,
				"actors %d and %d stand at least 1 unit apart" % [i, j]
			)
	view.free()
	GameState.reset()


func test_group_truncates_to_six_enemies() -> void:
	GameState.reset()
	var view: Variant = _make_view()
	GameState.encounter_group = [
		{"id": "bandit", "count": 8},
	]
	view.start("bandit", 1, false, false)
	assert_eq(int(view.battle.enemies.size()), 6, "at most six enemies are built")
	assert_eq(GameState.encounter_group.size(), 0, "the group is still cleared")
	view.free()
	GameState.reset()


func test_single_enemy_path_is_unchanged() -> void:
	GameState.reset()
	var view: Variant = _make_view()
	view.start("bandit", 1, false, false)
	assert_eq(int(view.battle.enemies.size()), 1, "a single encounter still builds one enemy")
	assert_eq(str(view.battle.enemies[0].id), "bandit", "the plain path keeps the enemy id")
	assert_eq(view.stage.enemy_actors.size(), 1, "one actor for one enemy")
	view.free()
	GameState.reset()


func test_six_head_labels_do_not_overlap_on_screen() -> void:
	GameState.reset()
	var built: Dictionary = _make_view_in_tree()
	var holder: SubViewport = built["holder"]
	var view: Variant = built["view"]
	GameState.encounter_group = GROUP.duplicate(true)
	view.start("ma_youwei", 1, false, false)
	view.size = Vector2(1152.0, 648.0)
	view._update_enemy_head_positions()
	if not view.is_inside_tree() or not view.stage.is_inside_tree():
		# Screen-space layout needs a live scene tree (nodes added while the test runner is still in
		# _init() are not inside it); the real-window check is done with the screenshot script.
		holder.free()
		GameState.reset()
		return
	var rects: Array = []
	for i in range(view.enemy_head_labels.size()):
		var head: Control = view.enemy_head_labels[i]
		if not head.visible:
			continue
		var head_size: Vector2 = head.size
		if head_size.x <= 0.0 or head_size.y <= 0.0:
			head_size = head.custom_minimum_size
		rects.append(Rect2(head.position, head_size))
	assert_eq(rects.size(), 6, "all six head labels are on screen")
	for i in range(rects.size()):
		for j in range(i + 1, rects.size()):
			var a: Rect2 = rects[i]
			var b: Rect2 = rects[j]
			assert_true(
				not a.intersects(b),
				"head labels %d and %d do not overlap (%s vs %s)" % [i, j, a, b]
			)
	holder.free()
	GameState.reset()

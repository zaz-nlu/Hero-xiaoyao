extends "res://tests/test_case.gd"

# 外壳淡出：转到相机一侧的外壳墙/树环隐藏，初始视角保持不变，
# 棋盘内部的 wall 格子在任何视角下都保持可见。

const GameState = preload("res://core/game_state.gd")
const TacticsSetup = preload("res://core/tactics/tactics_setup.gd")
const TacticsStage = preload("res://features/tactics/tactics_stage.gd")

const TAVERN_GROUP := [{"id": "ma_youwei", "count": 1}, {"id": "bandit", "count": 5}]
const FOREST_GROUP := [{"id": "bandit", "count": 2}]
const NORMAL_META := "shell_normal"


func _make_battle(map_id: String, group: Array) -> Variant:
	GameState.reset()
	var built: Dictionary = TacticsSetup.build(map_id, group, null, 1)
	if not bool(built.get("ok", false)):
		return null
	return built["battle"]


func _make_stage(battle: Variant, backdrop: String) -> Variant:
	var stage: Variant = TacticsStage.new()
	stage.build(battle, backdrop)
	return stage


func _turn(stage: Variant, steps: int) -> void:
	for i in range(steps):
		stage.rotate_view(1)


func _shell_nodes(stage: Variant, root_name: String) -> Array:
	var out: Array = []
	var root = stage.get_node_or_null(root_name)
	if root != null:
		for child in root.get_children():
			if child.has_meta(NORMAL_META):
				out.append(child)
	return out


func _alpha(node) -> float:
	if node is Sprite3D:
		return float(node.modulate.a)
	if node is MeshInstance3D:
		var mat = node.material_override
		if mat is StandardMaterial3D:
			return float((mat as StandardMaterial3D).albedo_color.a)
	return 1.0


func _hidden(node) -> bool:
	return not node.visible or _alpha(node) <= 0.001


func _visible(node) -> bool:
	return node.visible and _alpha(node) >= 0.999


func test_tavern_shell_is_visible_at_initial_yaw() -> void:
	var battle: Variant = _make_battle("tavern_brawl", TAVERN_GROUP)
	assert_true(battle != null, "the tavern battle is assembled")
	if battle == null:
		return
	var stage: Variant = _make_stage(battle, "tavern")
	var nodes: Array = _shell_nodes(stage, "TavernShell")
	assert_true(nodes.size() >= 6, "the tavern shell has wall nodes")
	for node in nodes:
		assert_true(node.has_meta(NORMAL_META)
			and node.get_meta(NORMAL_META) is Vector3,
			"%s records its outward normal" % node.name)
		assert_true(_visible(node), "%s stays visible at yaw 0" % node.name)
	var shell = stage.get_node_or_null("TavernShell")
	assert_true(shell != null, "the tavern shell root exists")
	if shell != null:
		for interior in ["CeilingBeam", "Lantern0", "LanternCord0"]:
			var node = shell.get_node_or_null(interior)
			assert_true(node != null and not node.has_meta(NORMAL_META),
				"%s is interior decoration, not a shell wall" % interior)
	stage.free()


func test_tavern_back_wall_hides_when_it_faces_the_camera() -> void:
	var battle: Variant = _make_battle("tavern_brawl", TAVERN_GROUP)
	assert_true(battle != null, "the tavern battle is assembled")
	if battle == null:
		return
	var stage: Variant = _make_stage(battle, "tavern")
	var shell = stage.get_node_or_null("TavernShell")
	assert_true(shell != null, "the tavern shell root exists")
	if shell == null:
		stage.free()
		return
	var back = shell.get_node_or_null("ShellBack")
	var left = shell.get_node_or_null("ShellLeft")
	var right = shell.get_node_or_null("ShellRight")
	assert_true(back != null and left != null and right != null,
		"the three walls exist")
	_turn(stage, 2)
	assert_true(_hidden(back), "the back wall fades out at 180°")
	assert_true(_visible(left) and _visible(right),
		"the side walls stay visible at 180°")
	var lights := 0
	for child in shell.get_children():
		if child is OmniLight3D:
			lights += 1
			assert_true(child.light_energy > 0.0,
				"wall lights keep their energy while the wall fades")
	assert_true(lights > 0, "the shell has lights")
	_turn(stage, 2)
	assert_true(_visible(back), "the back wall returns at 360°")
	stage.free()


func test_tavern_side_wall_hides_at_ninety_degrees() -> void:
	var battle: Variant = _make_battle("tavern_brawl", TAVERN_GROUP)
	assert_true(battle != null, "the tavern battle is assembled")
	if battle == null:
		return
	var stage: Variant = _make_stage(battle, "tavern")
	var shell = stage.get_node_or_null("TavernShell")
	assert_true(shell != null, "the tavern shell root exists")
	if shell == null:
		stage.free()
		return
	var back = shell.get_node_or_null("ShellBack")
	var left = shell.get_node_or_null("ShellLeft")
	var right = shell.get_node_or_null("ShellRight")
	_turn(stage, 1)
	assert_true(_hidden(right), "the +X wall fades out at 90°")
	assert_true(_visible(left), "the -X wall stays visible at 90°")
	assert_true(_visible(back), "the back wall stays visible at 90°")
	stage.free()


func test_interior_wall_cells_never_fade() -> void:
	var battle: Variant = _make_battle("tavern_brawl", TAVERN_GROUP)
	assert_true(battle != null, "the tavern battle is assembled")
	if battle == null:
		return
	var stage: Variant = _make_stage(battle, "tavern")
	var walls: Array = []
	for y in range(int(battle.grid.height)):
		for x in range(int(battle.grid.width)):
			var cell := Vector2i(x, y)
			if str(battle.grid.terrain_at(cell)) == "wall":
				walls.append(cell)
	assert_true(walls.size() > 0, "the map has wall cells")
	for step in range(4):
		for cell in walls:
			var node = stage.tiles.tile_node(cell)
			assert_true(node != null and node.visible,
				"wall cell %s stays visible at step %d" % [str(cell), step])
			assert_true(node != null and not node.has_meta(NORMAL_META),
				"wall cell %s is not treated as a shell wall" % str(cell))
		stage.rotate_view(1)
	stage.free()


func test_forest_ring_keeps_initial_view_and_fades_near_trees() -> void:
	var battle: Variant = _make_battle("forest_clearing", FOREST_GROUP)
	assert_true(battle != null, "the forest battle is assembled")
	if battle == null:
		return
	var stage: Variant = _make_stage(battle, "forest")
	var trees: Array = _shell_nodes(stage, "ForestRing")
	assert_true(trees.size() > 0, "the forest ring has trees")
	for tree in trees:
		assert_true(tree is Sprite3D, "ring trees are sprites")
		assert_true(tree.has_meta(NORMAL_META)
			and tree.get_meta(NORMAL_META) is Vector3,
			"%s records its outward normal" % tree.name)
		assert_true(_visible(tree), "%s stays visible at yaw 0" % tree.name)
	_turn(stage, 2)
	var hidden := 0
	var shown := 0
	for tree in trees:
		if _hidden(tree):
			hidden += 1
		elif _visible(tree):
			shown += 1
	assert_true(hidden > 0, "near-side trees fade at 180°")
	assert_true(shown > 0, "far-side trees stay at 180°")
	_turn(stage, 2)
	for tree in trees:
		assert_true(_visible(tree), "%s returns at 360°" % tree.name)
	stage.free()

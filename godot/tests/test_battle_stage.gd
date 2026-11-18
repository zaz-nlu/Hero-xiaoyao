extends "res://tests/test_case.gd"

const GameState = preload("res://core/game_state.gd")

const PLAYER_POS := Vector3(4.2, 0.0, 1.6)
const CAM_POS := Vector3(6.4, 14.0, 36.0)
const ENEMY_POSITIONS_2: Array = [
	Vector3(7.0, 0.0, 0.2),
	Vector3(10.8, 0.0, 2.4),
]


func _make_stage() -> Variant:
	var stage: Variant = load("res://features/battle/battle_stage.gd").new()
	stage.build(["bandit", "bandit"])
	return stage


func test_stage_builds_actors() -> void:
	var stage: Variant = _make_stage()
	assert_true(stage.player_actor != null, "the player actor exists")
	assert_eq(stage.enemy_actors.size(), 2, "two enemy actors")
	assert_eq(str(stage.player_actor.facing), "right", "the player faces right")
	assert_true(stage.player_actor.position.is_equal_approx(PLAYER_POS), "the player stands at the player position")
	for i in range(stage.enemy_actors.size()):
		var actor: Variant = stage.enemy_actors[i]
		assert_eq(str(actor.facing), "left", "enemy %d faces left" % i)
		assert_true(
			actor.position.is_equal_approx(ENEMY_POSITIONS_2[i]),
			"enemy %d stands at its slot" % i
		)
	stage.free()


func test_stage_has_no_town_actors() -> void:
	var stage: Variant = _make_stage()
	assert_eq(stage.town.npc_nodes.size(), 0, "the battle town has no npcs")
	assert_true(stage.town.player == null, "the battle town has no roaming player")
	stage.free()


func test_stage_camera_params() -> void:
	var stage: Variant = _make_stage()
	assert_true(stage.camera != null, "the stage owns a camera")
	if stage.camera != null:
		assert_near(stage.camera.fov, 26.0, 0.01, "the battle camera has its own fov")
		assert_true(stage.camera.position.distance_to(CAM_POS) < 0.01, "the camera sits at the stage position")
	stage.free()


func test_build_is_idempotent() -> void:
	var stage: Variant = _make_stage()
	var old_actor: Variant = stage.enemy_actors[0]
	stage.build(["bandit", "bandit"])
	assert_eq(stage.enemy_actors.size(), 2, "a rebuild keeps two enemy actors")
	assert_true(
		not is_instance_valid(old_actor) or not old_actor.is_inside_tree(),
		"the old actor has been removed"
	)
	stage.free()


func test_flash_and_recover() -> void:
	var stage: Variant = _make_stage()
	var actor: Variant = stage.enemy_actors[0]
	var sprite: Sprite3D = actor.get_node("Sprite") as Sprite3D
	stage.flash(actor, 0.25)
	assert_true(sprite.modulate.g < 0.8, "a flash tints the actor red")
	stage.advance(0.3)
	assert_true(sprite.modulate.g > 0.95, "the flash recovers to the base colour")
	stage.free()


func test_base_tint_applied() -> void:
	var stage: Variant = _make_stage()
	var actor: Variant = stage.enemy_actors[0]
	var sprite: Sprite3D = actor.get_node("Sprite") as Sprite3D
	stage.set_actor_base(actor, Color(0.6, 0.7, 1.0, 1.0))
	assert_true(sprite.modulate.b > sprite.modulate.r, "the base tint is applied when not flashing")
	stage.free()


func test_popup_rises_and_expires() -> void:
	var stage: Variant = _make_stage()
	stage.popup("-12", Vector3(8.0, 1.0, 1.0), Color.RED)
	assert_eq(stage.popups.size(), 1, "the popup is tracked")
	if stage.popups.size() == 1:
		var entry: Dictionary = stage.popups[0]
		var label: Label3D = entry["node"]
		var start_y: float = label.position.y
		stage.advance(0.45)
		assert_true(label.position.y - start_y > 0.3, "the popup rises")
		assert_true(label.modulate.a < 1.0, "the popup fades")
		stage.advance(0.6)
		assert_eq(stage.popups.size(), 0, "the popup expires")
	stage.free()


func test_lunge_returns_to_origin() -> void:
	var stage: Variant = _make_stage()
	var actor: Variant = stage.player_actor
	var origin: Vector3 = actor.position
	stage.lunge(actor, 0.9)
	stage.advance(0.09)
	assert_true(actor.position.x > origin.x + 0.1, "the actor lunges forward")
	stage.advance(0.2)
	assert_true(actor.position.distance_to(origin) < 0.01, "the actor returns to its origin")
	stage.free()


func test_forest_backdrop_offsets_the_stage() -> void:
	GameState.reset()
	GameState.battle_backdrop = "forest"
	var stage: Variant = load("res://features/battle/battle_stage.gd").new()
	stage.build(["bandit", "bandit"])
	var forest_origin: Vector3 = stage.town.arena_origin
	assert_true(
		stage.origin.is_equal_approx(forest_origin),
		"the stage adopts the forest arena origin"
	)
	assert_true(
		stage.player_actor.position.is_equal_approx(forest_origin + PLAYER_POS),
		"the player stands at origin + PLAYER_POS"
	)
	for i in range(stage.enemy_actors.size()):
		var actor: Variant = stage.enemy_actors[i]
		assert_true(
			actor.position.is_equal_approx(forest_origin + ENEMY_POSITIONS_2[i]),
			"enemy %d is offset by the forest origin" % i
		)
	assert_true(
		stage.camera.position.distance_to(forest_origin + CAM_POS) < 0.01,
		"the camera is offset by the forest origin"
	)
	stage.free()
	GameState.reset()

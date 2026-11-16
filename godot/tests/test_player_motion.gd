extends "res://tests/test_case.gd"

const PlayerMotion = preload("res://world/player_motion.gd")
const TownData = preload("res://world/town_data.gd")
const Town = preload("res://world/town.gd")

const TOWN_PATH := "res://data/town.json"
const BOUNDS := Rect2(-10.0, -10.0, 20.0, 20.0)


func _new_town():
	return Town.new()


func _tick(town, seconds: float, step_seconds: float = 0.05) -> void:
	var ticks := int(round(seconds / step_seconds))
	for i in range(ticks):
		town.tick_player(step_seconds)


func test_facing_from_input() -> void:
	assert_eq(
		PlayerMotion.facing_from_input(Vector2(1.0, 0.0), "down"), "right", "east is right"
	)
	assert_eq(
		PlayerMotion.facing_from_input(Vector2(-1.0, 0.0), "down"), "left", "west is left"
	)
	assert_eq(
		PlayerMotion.facing_from_input(Vector2(0.0, 1.0), "up"), "down", "south is down"
	)
	assert_eq(
		PlayerMotion.facing_from_input(Vector2(0.0, -1.0), "down"), "up", "north is up"
	)
	assert_eq(
		PlayerMotion.facing_from_input(Vector2(0.6, 0.8), "up"), "down", "dominant z wins"
	)
	assert_eq(
		PlayerMotion.facing_from_input(Vector2.ZERO, "left"), "left", "no input keeps facing"
	)


func test_free_move_speed() -> void:
	var end_pos: Vector2 = PlayerMotion.step(Vector2.ZERO, Vector2(1.0, 0.0), 0.5, [], BOUNDS)
	assert_near(end_pos.x, 2.5, 0.001, "half a second at speed five")
	assert_near(end_pos.y, 0.0, 0.001, "no sideways drift")


func test_diagonal_normalized() -> void:
	var end_pos: Vector2 = PlayerMotion.step(
		Vector2.ZERO, Vector2(1.0, 1.0), 1.0, [], BOUNDS
	)
	assert_near(end_pos.length(), PlayerMotion.SPEED, 0.01, "diagonal is normalised")


func test_blocked_by_rect() -> void:
	var blockers: Array = [Rect2(3.0, -1.0, 2.0, 2.0)]
	var pos := Vector2.ZERO
	for i in range(20):
		pos = PlayerMotion.step(pos, Vector2(1.0, 0.0), 0.1, blockers, BOUNDS)
	assert_true(pos.x > 1.0, "player walks toward the wall")
	assert_true(
		pos.x <= 3.0 - PlayerMotion.RADIUS + 0.001,
		"player stops at the wall face, x is %.3f" % pos.x
	)


func test_slides_along_wall() -> void:
	var blockers: Array = [Rect2(3.0, -1.0, 2.0, 2.0)]
	var start := Vector2(2.0, -1.0)
	var end_pos: Vector2 = PlayerMotion.step(start, Vector2(1.0, 1.0), 0.3, blockers, BOUNDS)
	assert_true(
		end_pos.x <= 3.0 - PlayerMotion.RADIUS + 0.001,
		"x is blocked by the wall, x is %.3f" % end_pos.x
	)
	assert_true(end_pos.y > start.y, "z keeps advancing along the wall")


func test_bounds_clamp() -> void:
	var end_pos: Vector2 = PlayerMotion.step(
		Vector2(9.5, 0.0), Vector2(1.0, 0.0), 3.0, [], BOUNDS
	)
	assert_true(
		end_pos.x <= BOUNDS.end.x - PlayerMotion.RADIUS + 0.001,
		"player is clamped inside the bounds, x is %.3f" % end_pos.x
	)


func test_blocked_helper() -> void:
	var blockers: Array = [Rect2(0.0, 0.0, 2.0, 2.0)]
	assert_true(PlayerMotion.blocked(Vector2(1.0, 1.0), blockers), "point inside is blocked")
	assert_true(
		PlayerMotion.blocked(Vector2(-0.2, 1.0), blockers), "point within radius is blocked"
	)
	assert_true(
		not PlayerMotion.blocked(Vector2(-1.0, 1.0), blockers), "point far away is free"
	)


func test_ground_height_values() -> void:
	var loaded: Dictionary = TownData.load_town(TOWN_PATH)
	var town_data: Dictionary = loaded["data"]
	assert_near(
		TownData.ground_height(town_data, -12.0, 10.5), 0.25, 0.0001, "bridge deck is raised"
	)
	assert_near(TownData.ground_height(town_data, 0.0, 1.0), 0.0, 0.0001, "street is flat")
	assert_near(
		TownData.ground_height(town_data, 30.0, -5.5), 1.5, 0.0001, "third stair step"
	)
	assert_near(
		TownData.ground_height(town_data, 30.0, -16.5), 7.0, 0.0001, "top of the stairs"
	)
	assert_near(
		TownData.ground_height(town_data, 28.0, -20.0), 7.0, 0.0001, "platform is high"
	)


func test_extra_blockers_cover_cliff() -> void:
	var loaded: Dictionary = TownData.load_town(TOWN_PATH)
	var town_data: Dictionary = loaded["data"]
	var extra: Array = TownData.extra_blockers(town_data)
	assert_true(extra.size() > 0, "cliff blocker exists")
	var covers_cliff := false
	var covers_stairs := false
	for value in extra:
		var rect: Rect2 = value
		if rect.has_point(Vector2(27.0, -20.0)):
			covers_cliff = true
		if rect.has_point(Vector2(30.5, -10.0)):
			covers_stairs = true
	assert_true(covers_cliff, "cliff blocks the platform edge")
	assert_true(not covers_stairs, "stairs stay open")


func test_player_spawns_at_spawn_point() -> void:
	var town = _new_town()
	town.build()
	var spawn: Dictionary = town.data.get("spawn", {})
	assert_true(town.player != null, "player exists")
	if town.player != null:
		assert_eq(str(town.player.name), "Player", "player node is named Player")
		assert_near(town.player.position.x, float(spawn["x"]), 0.001, "player spawns at x")
		assert_near(town.player.position.z, float(spawn["z"]), 0.001, "player spawns at z")
	assert_true(town.follow_target == town.player, "camera follows the player")
	town.free()


func test_player_moves_with_override() -> void:
	var town = _new_town()
	town.build()
	var start_x: float = town.player_pos.x
	town.set_input_override(Vector2(1.0, 0.0))
	_tick(town, 0.5)
	assert_true(town.player_pos.x > start_x, "player moves east")
	assert_eq(town.player.facing, "right", "player faces right")
	assert_true(town.player.moving, "player walk animation is running")
	town.set_input_override(Vector2.ZERO)
	town.tick_player(0.05)
	assert_true(not town.player.moving, "player stops when input is released")
	town.free()


func test_player_cannot_enter_tavern_wall() -> void:
	var town = _new_town()
	town.build()
	town.player_pos = Vector2(6.0, -1.5)
	town.set_input_override(Vector2(0.0, -1.0))
	_tick(town, 3.0)
	assert_true(town.player_pos.y < -1.5, "player walks north toward the tavern")
	assert_true(
		town.player_pos.y >= -3.0 + PlayerMotion.RADIUS - 0.001,
		"tavern front wall stops the player, z is %.3f" % town.player_pos.y
	)
	town.free()


func test_player_cannot_walk_into_river() -> void:
	var town = _new_town()
	town.build()
	town.player_pos = Vector2(-20.0, 5.0)
	town.set_input_override(Vector2(0.0, 1.0))
	_tick(town, 5.0)
	assert_true(
		town.player_pos.y <= 9.0 - PlayerMotion.RADIUS + 0.01,
		"river bank stops the player, z is %.3f" % town.player_pos.y
	)
	town.free()


func test_player_can_cross_bridge() -> void:
	var town = _new_town()
	town.build()
	town.player_pos = Vector2(-12.0, 5.0)
	town.set_input_override(Vector2(0.0, 1.0))
	_tick(town, 4.0)
	assert_true(
		town.player_pos.y > 12.0, "player crosses the bridge, z is %.3f" % town.player_pos.y
	)
	town.free()


func test_player_climbs_stairs() -> void:
	var town = _new_town()
	town.build()
	town.player_pos = Vector2(30.5, -2.0)
	town.set_input_override(Vector2(0.0, -1.0))
	_tick(town, 4.0)
	assert_true(
		town.player_pos.y < -10.0, "player walks up the stairs, z is %.3f" % town.player_pos.y
	)
	assert_true(
		town.player.position.y > 3.0,
		"player rises with the stairs, y is %.3f" % town.player.position.y
	)
	town.free()


func test_cliff_blocks_player() -> void:
	var town = _new_town()
	town.build()
	town.player_pos = Vector2(27.5, -10.0)
	town.set_input_override(Vector2(0.0, -1.0))
	_tick(town, 3.0)
	assert_true(
		town.player_pos.y >= -17.0 + PlayerMotion.RADIUS - 0.01,
		"cliff keeps the player off the platform, z is %.3f" % town.player_pos.y
	)
	town.player_pos = Vector2(27.5, -15.0)
	_tick(town, 2.0)
	assert_true(town.player_pos.y < -15.0, "player walks toward the cliff edge")
	assert_true(
		town.player_pos.y >= -17.0 + PlayerMotion.RADIUS - 0.01,
		"cliff line blocks the player, z is %.3f" % town.player_pos.y
	)
	town.free()

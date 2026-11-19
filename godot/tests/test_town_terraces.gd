extends "res://tests/test_case.gd"

const PlayerMotion = preload("res://shared/gameplay/player_motion.gd")
const TownData = preload("res://shared/resources/town_data.gd")
const TownTerraces = preload("res://shared/resources/town_terraces.gd")
const TownTerracesBuild = preload("res://shared/scenery/town/town_terraces_build.gd")

const BOUNDS := Rect2(-20.0, -20.0, 40.0, 40.0)


func _town_data() -> Dictionary:
	return {
		"bounds": {"x0": -20, "z0": -20, "x1": 20, "z1": 20},
		"terraces": [
			{
				"rect": [-10, -10, 10, -4],
				"y": 1.5,
				"top": "flagstone",
				"from_y": 0.0,
				"stairs": [{"x0": -1, "x1": 1}],
			}
		],
	}


func _covers(rects: Array, point: Vector2) -> bool:
	for value in rects:
		var rect: Rect2 = value
		if rect.has_point(point):
			return true
	return false


func _walk(start: Vector2, input: Vector2, seconds: float, blockers: Array) -> Vector2:
	var pos := start
	var ticks := int(round(seconds / 0.05))
	for i in range(ticks):
		pos = PlayerMotion.step(pos, input, 0.05, blockers, BOUNDS)
	return pos


func test_height_at_terrace_and_stairs() -> void:
	var data := _town_data()
	assert_near(TownTerraces.height_at(data, 0.0, -7.0), 1.5, 0.0001, "terrace top")
	assert_near(TownTerraces.height_at(data, 0.0, -1.5), 0.5, 0.0001, "first step")
	assert_near(TownTerraces.height_at(data, 0.0, -3.5), 1.5, 0.0001, "third step")
	assert_near(TownTerraces.height_at(data, 15.0, 10.0), -1.0, 0.0001, "no terrace")


func test_blockers_break_at_stairs() -> void:
	var walls: Array = TownTerraces.blockers(_town_data())
	assert_true(_covers(walls, Vector2(5.0, -4.0)), "south wall east of the stairs")
	assert_true(not _covers(walls, Vector2(0.0, -4.0)), "stairs gap stays open")
	assert_true(not _covers(walls, Vector2(0.0, -10.0)), "north edge has no wall")
	assert_true(_covers(walls, Vector2(-10.0, -7.0)), "west side wall exists")
	assert_true(_covers(walls, Vector2(10.0, -7.0)), "east side wall exists")


func test_ground_height_uses_terraces() -> void:
	var data := _town_data()
	assert_near(TownData.ground_height(data, 0.0, -7.0), 1.5, 0.0001, "on the terrace")
	assert_near(TownData.ground_height(data, 0.0, -1.5), 0.5, 0.0001, "on the stairs")
	assert_near(TownData.ground_height(data, 15.0, 10.0), 0.0, 0.0001, "flat ground")
	var legacy := {
		"bounds": {"x0": -20, "z0": -20, "x1": 20, "z1": 20},
		"platform": {"rect": [2, 2, 4, 4], "y": 7.0},
	}
	assert_near(TownData.ground_height(legacy, 3.0, 3.0), 7.0, 0.0001, "legacy platform")


func test_extra_blockers_include_terrace_walls() -> void:
	var extra: Array = TownData.extra_blockers(_town_data())
	assert_true(_covers(extra, Vector2(5.0, -4.0)), "terrace wall is a movement blocker")


func test_player_climbs_terrace_stairs() -> void:
	var data := _town_data()
	var blockers: Array = TownTerraces.blockers(data)
	var pos := _walk(Vector2(0.0, 0.0), Vector2(0.0, -1.0), 1.5, blockers)
	assert_true(pos.y < -4.0, "player walks through the stair gap, z is %.3f" % pos.y)
	assert_near(
		TownData.ground_height(data, pos.x, pos.y), 1.5, 0.0001, "player is on top"
	)


func test_player_blocked_by_terrace_wall() -> void:
	var blockers: Array = TownTerraces.blockers(_town_data())
	var pos := _walk(Vector2(5.0, 0.0), Vector2(0.0, -1.0), 1.5, blockers)
	assert_true(pos.y > -4.0, "south wall stops the player, z is %.3f" % pos.y)
	assert_true(
		pos.y >= -3.4 - 0.01,
		"player stays south of the wall face, z is %.3f" % pos.y
	)


func test_build_creates_terrace_geometry() -> void:
	var root := Node3D.new()
	var builder := TownTerracesBuild.new()
	builder.build(root, _town_data())
	var terrace := root.get_node_or_null("Terrace0")
	assert_true(terrace != null, "Terrace0 is built")
	if terrace == null:
		root.free()
		return
	assert_true(terrace.get_node_or_null("Terrace0_top") != null, "top slab is built")
	assert_true(
		terrace.get_node_or_null("TerraceWall0_south") != null, "south wall is built"
	)
	assert_true(
		terrace.get_node_or_null("TerraceWall0_west") != null, "west wall is built"
	)
	assert_true(terrace.get_node_or_null("TerraceStep0_3") != null, "top step is built")
	assert_true(terrace.get_child_count() >= 8, "top, walls and steps are all built")
	root.free()

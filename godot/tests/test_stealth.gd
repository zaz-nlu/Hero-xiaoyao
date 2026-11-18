extends "res://tests/test_case.gd"

const Stealth = preload("res://shared/gameplay/stealth.gd")


func test_cone_inside_outside_and_range() -> void:
	var guard := Vector2.ZERO
	assert_true(
		Stealth.in_cone(guard, 0.0, Vector2(3.0, 0.0), 6.5, Stealth.VIEW_HALF_ANGLE),
		"a target straight ahead is inside the cone"
	)
	assert_true(
		not Stealth.in_cone(guard, 0.0, Vector2(0.0, 3.0), 6.5, Stealth.VIEW_HALF_ANGLE),
		"a target at ninety degrees is outside the cone"
	)
	assert_true(
		not Stealth.in_cone(guard, 0.0, Vector2(9.0, 0.0), 6.5, Stealth.VIEW_HALF_ANGLE),
		"a target beyond the reach is not seen"
	)
	var edge := Stealth.direction(deg_to_rad(39.0))
	assert_true(
		Stealth.in_cone(guard, 0.0, edge * 4.0, 6.5, Stealth.VIEW_HALF_ANGLE),
		"inside the forty degree edge is still visible"
	)


func test_crouch_halves_view_distance() -> void:
	assert_near(Stealth.view_distance(6.5, false, false), 6.5, 0.0001, "standing uses full reach")
	assert_near(Stealth.view_distance(6.5, true, false), 3.25, 0.0001, "crouching halves reach")
	assert_near(
		Stealth.view_distance(6.5, true, true), 1.5, 0.0001,
		"crouching in a hide spot drops reach to 1.5"
	)
	assert_near(
		Stealth.view_distance(6.5, false, true), 6.5, 0.0001,
		"a hide spot alone does not hide a standing player"
	)


func test_blockers_stop_line_of_sight() -> void:
	var guard := Vector2.ZERO
	var player := Vector2(5.0, 0.0)
	var blockers: Array = [Rect2(2.0, -1.0, 1.0, 2.0)]
	assert_true(
		Stealth.sees(guard, 0.0, player, 6.5, Stealth.VIEW_HALF_ANGLE, []),
		"an open lane is visible"
	)
	assert_true(
		not Stealth.sees(guard, 0.0, player, 6.5, Stealth.VIEW_HALF_ANGLE, blockers),
		"a tree between guard and player blocks the view"
	)
	assert_true(
		Stealth.segment_blocked(Vector2(0.0, 0.0), Vector2(5.0, 0.0), blockers),
		"the segment helper agrees"
	)


func test_behind_requires_more_than_120_degrees() -> void:
	var guard := Vector2.ZERO
	var facing := Stealth.facing_angle("up")
	assert_true(
		Stealth.is_behind(guard, facing, Vector2(0.0, 1.5)),
		"standing due south of a north-facing guard is behind"
	)
	assert_true(
		not Stealth.is_behind(guard, facing, Vector2(0.0, -1.5)),
		"standing in front is not behind"
	)
	assert_true(
		not Stealth.is_behind(guard, facing, Vector2(1.5, 0.0)),
		"a ninety degree side is not behind"
	)
	var almost := Stealth.direction(facing + deg_to_rad(121.0)) * 1.5
	assert_true(Stealth.is_behind(guard, facing, almost), "121 degrees counts as behind")


func test_sneak_ranges() -> void:
	var guard := Vector2.ZERO
	var facing := 0.0
	assert_true(
		Stealth.can_sneak(guard, facing, Vector2(-1.5, 0.0), false),
		"behind within 1.8 allows a sneak attack"
	)
	assert_true(
		Stealth.can_sneak(guard, facing, Vector2(0.0, 0.9), false),
		"a side within 1.0 outside the cone also allows it"
	)
	assert_true(
		not Stealth.can_sneak(guard, facing, Vector2(0.0, 2.0), false),
		"a side at 2.0 is too far"
	)
	assert_true(
		not Stealth.can_sneak(guard, facing, Vector2(-2.5, 0.0), false),
		"behind beyond 1.8 is too far"
	)


func test_route_snaps_blocked_points_to_the_road() -> void:
	var bounds := Rect2(0.0, 0.0, 10.0, 10.0)
	var road: Array = [[0.0, 6.5], [10.0, 6.5]]
	var blockers: Array = [Rect2(4.0, 4.0, 1.0, 1.0)]
	var route: Array = Stealth.sanitize_route([[4.5, 4.5]], blockers, bounds, road)
	assert_eq(route.size(), 1, "a single blocked point stays a single point")
	if route.size() == 1:
		var snapped: Vector2 = route[0]
		assert_true(Stealth.is_walkable(snapped, blockers, bounds), "the snapped point is walkable")
		assert_near(snapped.y, 6.5, 0.01, "the blocked point is pulled onto the dirt road")


func test_route_detours_around_a_tree() -> void:
	var bounds := Rect2(0.0, 0.0, 10.0, 10.0)
	var road: Array = [[0.0, 6.5], [10.0, 6.5]]
	var blockers: Array = [Rect2(4.0, 4.0, 1.0, 1.0)]
	var raw: Array = [[2.0, 4.5], [8.0, 4.5]]
	var raw_a := Vector2(2.0, 4.5)
	var raw_b := Vector2(8.0, 4.5)
	assert_true(
		Stealth.segment_blocked(raw_a, raw_b, blockers),
		"the raw route cuts through the tree"
	)
	var route: Array = Stealth.sanitize_route(raw, blockers, bounds, road)
	assert_true(route.size() > 2, "the route gains road waypoints")
	for i in range(route.size() - 1):
		var a: Vector2 = route[i]
		var b: Vector2 = route[i + 1]
		assert_true(
			not Stealth.segment_blocked(a, b, blockers),
			"leg %d no longer crosses a blocker" % i
		)

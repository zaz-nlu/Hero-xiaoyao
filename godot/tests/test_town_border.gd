extends "res://tests/test_case.gd"

const TownBorder = preload("res://shared/scenery/town/town_border.gd")

const BOUNDS := Rect2(-20.0, -15.0, 40.0, 30.0)
const DEPTH := 10.0
const BORDER_FILES := ["prop_willow.png"]


func _data() -> Dictionary:
	return {
		"bounds": {
			"x0": BOUNDS.position.x,
			"z0": BOUNDS.position.y,
			"x1": BOUNDS.end.x,
			"z1": BOUNDS.end.y,
		},
		"border": {
			"depth": DEPTH,
			"spacing": 4.0,
			"seed": 1,
			"files": BORDER_FILES,
		},
	}


func _build_border(data: Dictionary) -> Node3D:
	var parent := Node3D.new()
	TownBorder.new().build(parent, data)
	return parent


func _border_root(parent: Node3D) -> Node3D:
	return parent.get_node_or_null("Border") as Node3D


func _assert_outside(border: Node3D) -> void:
	var grown := BOUNDS.grow(DEPTH)
	for child in border.get_children():
		var node := child as Node3D
		assert_true(node != null, "border children are Node3D")
		if node == null:
			continue
		var point := Vector2(node.position.x, node.position.z)
		assert_true(
			not BOUNDS.has_point(point), "border tree %s is outside bounds" % node.name
		)
		assert_true(
			grown.has_point(point), "border tree %s stays inside the depth band" % node.name
		)


func test_border_builds_ring_outside_bounds() -> void:
	var parent: Node3D = _build_border(_data())
	var border: Node3D = _border_root(parent)
	assert_true(border != null, "the Border root is created")
	if border == null:
		parent.free()
		return
	assert_true(border.get_child_count() > 0, "the border has trees")
	_assert_outside(border)
	parent.free()


func test_border_is_deterministic() -> void:
	var first_parent: Node3D = _build_border(_data())
	var second_parent: Node3D = _build_border(_data())
	var first: Node3D = _border_root(first_parent)
	var second: Node3D = _border_root(second_parent)
	assert_true(first != null and second != null, "both builds create the Border root")
	if first == null or second == null:
		first_parent.free()
		second_parent.free()
		return
	assert_eq(first.get_child_count(), second.get_child_count(), "same number of trees")
	var count: int = mini(first.get_child_count(), second.get_child_count())
	for i in range(count):
		var a := first.get_child(i) as Node3D
		var b := second.get_child(i) as Node3D
		assert_true(a.position.is_equal_approx(b.position), "tree %d position matches" % i)
	first_parent.free()
	second_parent.free()


func test_border_absent_builds_nothing() -> void:
	var data := _data()
	data.erase("border")
	var parent: Node3D = _build_border(data)
	assert_true(_border_root(parent) == null, "no Border root without the border key")
	parent.free()


func test_border_skips_the_northern_band() -> void:
	var parent: Node3D = _build_border(_data())
	var border: Node3D = _border_root(parent)
	if border == null:
		parent.free()
		return
	for child in border.get_children():
		var node := child as Node3D
		if node == null:
			continue
		var north := node.position.z < BOUNDS.position.y
		var inside_x := node.position.x >= BOUNDS.position.x \
			and node.position.x <= BOUNDS.end.x
		assert_true(not (north and inside_x), "no trees fill the northern band")
	parent.free()


func test_border_missing_assets_do_not_crash() -> void:
	var data := _data()
	var config: Dictionary = data["border"]
	config["files"] = ["border_does_not_exist.png"]
	var parent: Node3D = _build_border(data)
	var border: Node3D = _border_root(parent)
	assert_true(border != null, "the Border root still exists")
	if border != null:
		assert_eq(border.get_child_count(), 0, "missing assets are skipped")
	parent.free()

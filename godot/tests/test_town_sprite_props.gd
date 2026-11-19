extends "res://tests/test_case.gd"

const TownProps = preload("res://shared/scenery/town/town_props.gd")
const TownData = preload("res://shared/resources/town_data.gd")

const FRUIT_FILE := "town_stall_fruit.png"
const MISSING_FILE := "town_does_not_exist.png"


func _build_sprite_props(prop: Dictionary) -> Node3D:
	var parent := Node3D.new()
	var props: Variant = TownProps.new()
	props.build_props(parent, {"props": [prop]}, null, false)
	return parent


func _props_root(parent: Node3D) -> Node3D:
	return parent.get_child(0) as Node3D


func test_sprite_prop_builds_from_json_fields() -> void:
	var parent: Node3D = _build_sprite_props({
		"kind": "sprite",
		"sprite": FRUIT_FILE,
		"x": 3.5,
		"z": -2.0,
		"height": 2.4,
		"phase": "night",
	})
	var props_root: Node3D = _props_root(parent)
	assert_eq(props_root.get_child_count(), 1, "one sprite node is built")
	var sprite := props_root.get_child(0) as Node3D
	assert_true(sprite != null, "the sprite node is a Node3D")
	if sprite == null:
		parent.free()
		return
	assert_true(str(sprite.name).begins_with("Sprite_"), "the node name starts with Sprite_")
	assert_near(sprite.position.x, 3.5, 0.0001, "x comes from the entry")
	assert_near(sprite.position.z, -2.0, 0.0001, "z comes from the entry")
	assert_eq(str(sprite.get_meta("phase")), "night", "phase is written to meta")
	parent.free()


func test_sprite_prop_defaults_phase_and_ground() -> void:
	var parent: Node3D = _build_sprite_props({
		"kind": "sprite",
		"sprite": FRUIT_FILE,
		"x": 1.0,
		"z": 1.0,
		"height": 1.0,
	})
	var props_root: Node3D = _props_root(parent)
	assert_eq(props_root.get_child_count(), 1, "the sprite still builds")
	var sprite := props_root.get_child(0) as Node3D
	if sprite == null:
		parent.free()
		return
	assert_eq(str(sprite.get_meta("phase")), "both", "phase defaults to both")
	assert_near(sprite.position.y, 0.0, 0.0001, "no platform means ground y is zero")
	parent.free()


func test_sprite_prop_respects_y_and_lift() -> void:
	var parent: Node3D = _build_sprite_props({
		"kind": "sprite",
		"sprite": FRUIT_FILE,
		"x": 0.0,
		"z": 0.0,
		"height": 0.5,
		"y": 0.5,
		"lift": 1.0,
	})
	var sprite := _props_root(parent).get_child(0) as Node3D
	if sprite == null:
		parent.free()
		return
	assert_near(sprite.position.y, 1.5, 0.0001, "y plus lift sets the node height")
	parent.free()


func test_missing_sprite_file_is_skipped() -> void:
	var parent: Node3D = _build_sprite_props({
		"kind": "sprite",
		"sprite": MISSING_FILE,
		"x": 2.0,
		"z": 2.0,
		"height": 1.0,
	})
	assert_eq(_props_root(parent).get_child_count(), 0, "a missing file builds nothing")
	parent.free()


func test_sprite_collide_builds_one_footprint() -> void:
	var rects: Array = TownData.footprints({
		"props": [{
			"kind": "sprite",
			"sprite": FRUIT_FILE,
			"x": 2.0,
			"z": -3.0,
			"collide": [1.5, 0.8],
		}],
	})
	assert_eq(rects.size(), 1, "collide adds exactly one footprint")
	var rect: Rect2 = rects[0]
	assert_near(rect.position.x, 1.25, 0.0001, "footprint left edge")
	assert_near(rect.position.y, -3.4, 0.0001, "footprint near edge")
	assert_near(rect.size.x, 1.5, 0.0001, "footprint width")
	assert_near(rect.size.y, 0.8, 0.0001, "footprint depth")


func test_prop_without_collide_adds_no_footprint() -> void:
	var rects: Array = TownData.footprints({
		"props": [{
			"kind": "sprite",
			"sprite": FRUIT_FILE,
			"x": 2.0,
			"z": 2.0,
		}],
	})
	assert_eq(rects.size(), 0, "a sprite without collide is walkable")


func test_collide_overrides_existing_kind() -> void:
	var rects: Array = TownData.footprints({
		"props": [{
			"kind": "barrel",
			"x": 0.0,
			"z": 0.0,
			"collide": [2.0, 2.0],
		}],
	})
	assert_eq(rects.size(), 1, "collide replaces the kind footprint")
	var rect: Rect2 = rects[0]
	assert_near(rect.size.x, 2.0, 0.0001, "the collide width wins")
	assert_near(rect.size.y, 2.0, 0.0001, "the collide depth wins")


func test_sprite_prop_light_adds_night_light() -> void:
	var parent: Node3D = _build_sprite_props({
		"kind": "sprite",
		"sprite": FRUIT_FILE,
		"x": 0.0,
		"z": 0.0,
		"height": 2.0,
		"light": true,
	})
	var sprite := _props_root(parent).get_child(0) as Node3D
	assert_true(sprite != null, "the sprite node is built")
	if sprite == null:
		parent.free()
		return
	assert_true(sprite.has_meta("night_light"), "night_light meta is set")
	var lights := 0
	for child in sprite.get_children():
		if child is OmniLight3D:
			lights += 1
			var light := child as OmniLight3D
			assert_near(light.position.y, 1.2, 0.0001, "light sits at 60% of the sprite height")
			assert_near(light.light_energy, 0.0, 0.0001, "the light starts switched off")
	assert_eq(lights, 1, "one omni light is added")
	parent.free()


func test_sprite_prop_without_light_has_no_night_light() -> void:
	var parent: Node3D = _build_sprite_props({
		"kind": "sprite",
		"sprite": FRUIT_FILE,
		"x": 0.0,
		"z": 0.0,
		"height": 2.0,
	})
	var sprite := _props_root(parent).get_child(0) as Node3D
	assert_true(sprite != null, "the sprite node is built")
	if sprite == null:
		parent.free()
		return
	assert_true(not sprite.has_meta("night_light"), "no night_light meta without the flag")
	for child in sprite.get_children():
		assert_true(not (child is OmniLight3D), "no omni light without the flag")
	parent.free()

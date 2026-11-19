extends "res://tests/test_case.gd"

const WorldCamera = preload("res://shared/scene/world_camera.gd")
const TownData = preload("res://shared/resources/town_data.gd")

const OFFSET := Vector3(0.0, 16.7, 37.5)
const LOOK_AHEAD := Vector3(0.0, 1.0, -4.0)


func _fixture(target_position: Vector3) -> Dictionary:
	var parent := Node3D.new()
	var camera := Camera3D.new()
	var target := Node3D.new()
	target.position = target_position
	parent.add_child(camera)
	parent.add_child(target)
	return {"parent": parent, "camera": camera, "target": target}


func _run(fixture: Dictionary, clamp_rect: Rect2) -> Vector3:
	var focus := Vector3.ZERO
	var camera: Camera3D = fixture["camera"]
	var target: Node3D = fixture["target"]
	camera.position = Vector3.ZERO
	for i in range(30):
		focus = WorldCamera.update(
			camera, target, focus, OFFSET, LOOK_AHEAD, 0.1, Vector3.ZERO, clamp_rect
		)
	return focus


func test_update_clamps_focus_and_camera_position() -> void:
	var fixture := _fixture(Vector3(80.0, 0.0, 80.0))
	var rect := Rect2(-10.0, -8.0, 20.0, 16.0)
	var focus: Vector3 = _run(fixture, rect)
	var camera: Camera3D = fixture["camera"]
	var allowed := rect.grow(0.01)
	assert_true(allowed.has_point(Vector2(focus.x, focus.z)), "focus stays inside the clamp")
	assert_near(focus.x, 10.0, 0.01, "focus x is clamped")
	assert_near(focus.z, 8.0, 0.01, "focus z is clamped")
	assert_near(camera.position.x, 10.0, 0.01, "camera x follows the clamped target")
	assert_near(camera.position.z, 8.0 + OFFSET.z, 0.01, "camera z follows the clamped target")
	var parent: Node3D = fixture["parent"]
	parent.free()


func test_update_without_clamp_follows_target() -> void:
	var fixture := _fixture(Vector3(80.0, 0.0, 80.0))
	var focus: Vector3 = _run(fixture, Rect2())
	var camera: Camera3D = fixture["camera"]
	assert_near(focus.x, 80.0, 0.01, "focus x follows the target")
	assert_near(focus.z, 80.0, 0.01, "focus z follows the target")
	assert_near(camera.position.x, 80.0, 0.01, "camera x follows the target")
	assert_near(camera.position.z, 80.0 + OFFSET.z, 0.01, "camera z follows the target")
	var parent: Node3D = fixture["parent"]
	parent.free()


func test_town_data_camera_clamp_defaults_to_empty() -> void:
	var rect: Rect2 = TownData.camera_clamp({})
	assert_eq(rect.size, Vector2.ZERO, "no camera_clamp means no clamping")
	var short_rect: Rect2 = TownData.camera_clamp({"camera_clamp": [1.0, 2.0]})
	assert_eq(short_rect.size, Vector2.ZERO, "an incomplete entry falls back")


func test_town_data_reads_camera_clamp() -> void:
	var rect: Rect2 = TownData.camera_clamp({"camera_clamp": [-12.0, -15.0, 12.0, 6.0]})
	assert_near(rect.position.x, -12.0, 0.0001, "clamp left edge")
	assert_near(rect.position.y, -15.0, 0.0001, "clamp near edge")
	assert_near(rect.size.x, 24.0, 0.0001, "clamp width")
	assert_near(rect.size.y, 21.0, 0.0001, "clamp depth")

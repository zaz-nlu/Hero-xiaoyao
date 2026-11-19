extends RefCounted

# 可复用的世界相机工具：创建/DOF 属性/跟随位置/插值更新与吸附。
# 显式接收 offset、look_ahead、fov 与无目标时的 fallback_position；
# 调用方保留 Camera3D 节点本身与焦点状态。


static func build(parent: Node3D, offset: Vector3, fov: float) -> Camera3D:
	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.fov = fov
	camera.attributes = _attributes(offset)
	parent.add_child(camera)
	if camera.is_inside_tree():
		camera.current = true
	return camera


static func follow_position(
	target: Node3D, fallback_position: Vector3 = Vector3.ZERO
) -> Vector3:
	if target == null:
		return fallback_position
	if not target.is_inside_tree():
		return target.position
	return target.global_position


static func update(
	camera: Camera3D,
	target: Node3D,
	focus: Vector3,
	offset: Vector3,
	look_ahead: Vector3,
	delta: float,
	fallback_position: Vector3 = Vector3.ZERO,
	clamp_rect: Rect2 = Rect2()
) -> Vector3:
	if camera == null:
		return focus
	var target_pos := follow_position(target, fallback_position)
	if clamp_rect.size != Vector2.ZERO:
		target_pos.x = clampf(target_pos.x, clamp_rect.position.x, clamp_rect.end.x)
		target_pos.z = clampf(target_pos.z, clamp_rect.position.y, clamp_rect.end.y)
	var weight: float = 1.0 - exp(-8.0 * delta)
	focus = focus.lerp(target_pos, weight)
	camera.position = camera.position.lerp(target_pos + offset, weight)
	camera.look_at_from_position(camera.position, focus + look_ahead, Vector3.UP)
	return focus


static func snap(
	camera: Camera3D,
	target: Node3D,
	offset: Vector3,
	look_ahead: Vector3,
	fallback_position: Vector3 = Vector3.ZERO,
	clamp_rect: Rect2 = Rect2()
) -> Vector3:
	if camera == null:
		return Vector3.ZERO
	var target_pos := follow_position(target, fallback_position)
	if clamp_rect.size != Vector2.ZERO:
		target_pos.x = clampf(target_pos.x, clamp_rect.position.x, clamp_rect.end.x)
		target_pos.z = clampf(target_pos.z, clamp_rect.position.y, clamp_rect.end.y)
	camera.position = target_pos + offset
	camera.look_at_from_position(camera.position, target_pos + look_ahead, Vector3.UP)
	return target_pos


static func _attributes(offset: Vector3) -> CameraAttributesPractical:
	var attributes := CameraAttributesPractical.new()
	attributes.dof_blur_far_enabled = true
	var dist: float = offset.length()
	attributes.dof_blur_far_distance = dist + 14.0
	attributes.dof_blur_far_transition = 22.0
	attributes.dof_blur_near_enabled = true
	attributes.dof_blur_near_distance = dist - 9.0
	attributes.dof_blur_near_transition = 8.0
	attributes.dof_blur_amount = 0.08
	return attributes

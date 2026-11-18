extends RefCounted

# 森林巡逻队：路线、成员移动/朝向、视锥与警告标记。
# 只使用显式传入的空间数据；是否已击败由 feature 层决定后传入。

const CharacterSprite = preload("res://shared/scene/character_sprite.gd")
const Stealth = preload("res://shared/gameplay/stealth.gd")
const ForestLayout = preload("res://shared/resources/forest_layout.gd")

const PATROL_SPEED := 1.6
const PATROL_WAIT := 1.2
const PATROL_GAP := 1.2
const PATROL_TURN_TIME := 0.6
const PATROL_TURN_ANGLE := PI * 35.0 / 180.0
const SCOUT_VIEW_DISTANCE := 5.0
const SCOUT_HALF_ANGLE := PI * 30.0 / 180.0
const ALERT_MARK_HEIGHT := 2.6
const VIEW_CONE_SHOW_DISTANCE := 12.0
const VIEW_CONE_COLOR := Color(1.0, 0.3, 0.2, 0.18)

var groups: Array = []
var scout: Dictionary = {}
var root: Node3D = null


func build(
	parent: Node3D, layout: ForestLayout, defeated_routes: Array, build_scout: bool
) -> void:
	root = Node3D.new()
	root.name = "Patrols"
	parent.add_child(root)
	var slots: Dictionary = {}
	var slots_value: Variant = layout.data.get("patrol_slots", null)
	if slots_value is Dictionary:
		slots = slots_value
	_build_patrol_routes(slots, layout, defeated_routes)
	if build_scout:
		_build_scout(slots, layout)


func _build_patrol_routes(
	slots: Dictionary, layout: ForestLayout, defeated_routes: Array
) -> void:
	var routes_value: Variant = slots.get("routes", [])
	if not (routes_value is Array):
		return
	var routes: Array = routes_value
	for route_index in range(routes.size()):
		if defeated_routes.has(route_index):
			continue
		var raw_value: Variant = routes[route_index]
		if not (raw_value is Array):
			continue
		var raw_points: Array = raw_value
		var route: Array = Stealth.sanitize_route(
			raw_points, layout.blockers, layout.bounds_rect, layout.road_points
		)
		if route.size() < 2:
			continue
		var start: Vector2 = route[0]
		var second: Vector2 = route[1]
		var angle := Stealth.facing_angle("down")
		if start.distance_to(second) > 0.001:
			angle = Stealth.angle_of(second - start)
		var facing := Stealth.facing_from_vector(Stealth.direction(angle))
		var member_count := 2 if route_index == 0 else 1
		var group := {
			"index": route_index,
			"route": route,
			"target": 1,
			"dir": 1,
			"facing_angle": angle,
			"base_angle": angle,
			"turn_sign": 1.0,
			"wait": 0.0,
			"members": [],
			"alerted": false,
		}
		groups.append(group)
		for n in range(member_count):
			var pos: Vector2 = start
			if n > 0:
				pos = _follower_start(start, angle, layout.blockers, layout.bounds_rect)
			var member := _make_patrol_member(
				"Patrol_%d_%d" % [route_index, n],
				pos,
				facing,
				Stealth.BASE_VIEW_DISTANCE,
				Stealth.VIEW_HALF_ANGLE,
				group
			)
			var members: Array = group["members"]
			members.append(member)


func _build_scout(slots: Dictionary, layout: ForestLayout) -> void:
	var scout_value: Variant = slots.get("scout", null)
	if not (scout_value is Array):
		return
	var raw: Array = scout_value
	if raw.size() < 2:
		return
	var raw_pos := Vector2(float(raw[0]), float(raw[1]))
	var snapped: Array = Stealth.sanitize_route(
		[raw_pos], layout.blockers, layout.bounds_rect, layout.road_points
	)
	if snapped.is_empty():
		return
	var pos: Vector2 = snapped[0]
	var facing := "down"
	var member := _make_patrol_member(
		"Scout", pos, facing, SCOUT_VIEW_DISTANCE, SCOUT_HALF_ANGLE, {}
	)
	member["enemy_id"] = "bandit_scout"
	var node: Node3D = member["node"]
	var label := Label3D.new()
	label.name = "NameLabel"
	label.text = "探子"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.012
	label.font_size = 48
	label.outline_size = 10
	label.modulate = Color("#f2e2b0")
	label.outline_modulate = Color(0.0, 0.0, 0.0)
	label.position = Vector3(0.0, 2.3, 0.0)
	node.add_child(label)
	scout = member


func _make_patrol_member(
	node_name: String,
	pos: Vector2,
	facing: String,
	view: float,
	half_angle: float,
	group: Dictionary
) -> Dictionary:
	var character := CharacterSprite.new()
	character.name = node_name
	character.setup("bandit")
	character.position = Vector3(pos.x, 0.0, pos.y)
	character.set_facing(facing)
	root.add_child(character)
	var cone := _make_view_cone(character, half_angle)
	var mark := _make_alert_mark(character)
	return {
		"node": character,
		"pos": pos,
		"facing_angle": Stealth.facing_angle(facing),
		"vision": view,
		"half_angle": half_angle,
		"cone": cone,
		"mark": mark,
		"group": group,
		"alerted": false,
	}


func _follower_start(
	leader_pos: Vector2, angle: float, blockers: Array, bounds: Rect2
) -> Vector2:
	for gap in [PATROL_GAP, PATROL_GAP * 0.6, PATROL_GAP * 0.3]:
		var point: Vector2 = leader_pos - Stealth.direction(angle) * float(gap)
		if Stealth.is_walkable(point, blockers, bounds):
			return point
	return leader_pos


func advance_motion(delta: float, blockers: Array, bounds: Rect2) -> void:
	for group_value in groups:
		var group: Dictionary = group_value
		if bool(group.get("alerted", false)):
			continue
		var members: Array = group["members"]
		if members.is_empty():
			continue
		var route: Array = group["route"]
		if route.size() < 2:
			continue
		var leader: Dictionary = members[0]
		var wait := float(group.get("wait", 0.0))
		var moving := false
		if wait > 0.0:
			var remaining := maxf(0.0, wait - delta)
			group["wait"] = remaining
			var elapsed := PATROL_WAIT - remaining
			if elapsed <= PATROL_TURN_TIME:
				var t := clampf(elapsed / PATROL_TURN_TIME, 0.0, 1.0)
				var offset: float = sin(t * PI) * PATROL_TURN_ANGLE \
						* float(group.get("turn_sign", 1.0))
				group["facing_angle"] = float(group.get("base_angle", 0.0)) + offset
				_apply_group_facing(group, float(group["facing_angle"]))
			if remaining <= 0.0:
				_advance_route_target(group)
		else:
			var target: Vector2 = route[int(group["target"])]
			var leader_pos: Vector2 = leader["pos"]
			var to_target := target - leader_pos
			var dist := to_target.length()
			var step := PATROL_SPEED * delta
			if dist <= step:
				leader["pos"] = target
				group["wait"] = PATROL_WAIT
				group["base_angle"] = float(group["facing_angle"])
				group["turn_sign"] = -float(group.get("turn_sign", 1.0))
			else:
				leader["pos"] = leader_pos + to_target / dist * step
				var angle := Stealth.angle_of(to_target)
				group["facing_angle"] = angle
				_apply_group_facing(group, angle)
				moving = true
		_apply_group_facing(group, float(group["facing_angle"]))
		for i in range(1, members.size()):
			var follower: Dictionary = members[i]
			var desired := _follower_target(group, leader["pos"], blockers, bounds)
			var follower_pos: Vector2 = follower["pos"]
			var to_desired := desired - follower_pos
			var follower_step := PATROL_SPEED * delta
			var candidate := follower_pos
			if to_desired.length() <= follower_step:
				candidate = desired
			elif to_desired.length() > 0.0001:
				candidate = follower_pos + to_desired.normalized() * follower_step
			if Stealth.is_walkable(candidate, blockers, bounds):
				follower["pos"] = candidate
		for member_value in members:
			var member: Dictionary = member_value
			_sync_member_node(member)
		_set_group_moving(group, moving)


func _advance_route_target(group: Dictionary) -> void:
	var route: Array = group["route"]
	if route.size() < 2:
		return
	var target_index := int(group["target"])
	var direction := int(group.get("dir", 1))
	var next_index := target_index + direction
	if next_index < 0 or next_index >= route.size():
		direction = -direction
		next_index = target_index + direction
	group["dir"] = direction
	group["target"] = clampi(next_index, 0, route.size() - 1)
	var members: Array = group["members"]
	if members.is_empty():
		return
	var leader: Dictionary = members[0]
	var leader_pos: Vector2 = leader["pos"]
	var next_point: Vector2 = route[int(group["target"])]
	if leader_pos.distance_to(next_point) > 0.001:
		var angle := Stealth.angle_of(next_point - leader_pos)
		group["facing_angle"] = angle
		group["base_angle"] = angle
		_apply_group_facing(group, angle)


func _follower_target(
	group: Dictionary, leader_pos: Vector2, blockers: Array, bounds: Rect2
) -> Vector2:
	var angle := float(group["facing_angle"])
	for gap in [PATROL_GAP, PATROL_GAP * 0.6, PATROL_GAP * 0.3]:
		var point: Vector2 = leader_pos - Stealth.direction(angle) * float(gap)
		if Stealth.is_walkable(point, blockers, bounds):
			return point
	return leader_pos


func _apply_group_facing(group: Dictionary, angle: float) -> void:
	group["facing_angle"] = angle
	var members: Array = group["members"]
	for member_value in members:
		var member: Dictionary = member_value
		member["facing_angle"] = angle
		_apply_member_facing(member, angle)


func _apply_member_facing(member: Dictionary, angle: float) -> void:
	var node_value: Variant = member.get("node", null)
	if not (node_value is Node3D):
		return
	var node: Node3D = node_value
	var facing := Stealth.facing_from_vector(
		Stealth.direction(angle), str(node.get("facing"))
	)
	node.call("set_facing", facing)


func _set_group_moving(group: Dictionary, moving: bool) -> void:
	var members: Array = group["members"]
	for member_value in members:
		var member: Dictionary = member_value
		_set_member_moving(member, moving)


func _set_member_moving(member: Dictionary, moving: bool) -> void:
	var node_value: Variant = member.get("node", null)
	if not (node_value is Node3D):
		return
	var node: Node3D = node_value
	node.call("set_moving", moving)


func _sync_member_node(member: Dictionary) -> void:
	var node_value: Variant = member.get("node", null)
	if not (node_value is Node3D):
		return
	var node: Node3D = node_value
	var pos: Vector2 = member["pos"]
	node.position = Vector3(pos.x, 0.0, pos.y)


func update_view_cones(
	player_pos: Vector2, crouched: bool, in_hide: bool, alerted: bool
) -> void:
	for group_value in groups:
		var group: Dictionary = group_value
		var members: Array = group["members"]
		for member_value in members:
			var member: Dictionary = member_value
			_update_view_cone(member, player_pos, crouched, in_hide, alerted)
	if not scout.is_empty():
		_update_view_cone(scout, player_pos, crouched, in_hide, alerted)


func _update_view_cone(
	member: Dictionary, player_pos: Vector2, crouched: bool, in_hide: bool, alerted: bool
) -> void:
	var cone_value: Variant = member.get("cone", null)
	if not (cone_value is MeshInstance3D):
		return
	var cone: MeshInstance3D = cone_value
	var pos: Vector2 = member["pos"]
	var show := player_pos.distance_to(pos) <= VIEW_CONE_SHOW_DISTANCE and not alerted
	cone.visible = show
	if not show:
		return
	var reach := Stealth.view_distance(float(member["vision"]), crouched, in_hide)
	cone.scale = Vector3(reach, 1.0, reach)
	cone.rotation.y = -float(member["facing_angle"])


func stop_member(member: Dictionary) -> void:
	_set_member_moving(member, false)


func show_alert_mark(member: Dictionary) -> void:
	var mark_value: Variant = member.get("mark", null)
	if mark_value is Label3D:
		var mark: Label3D = mark_value
		mark.visible = true


func face_member_toward(member: Dictionary, point: Vector2) -> void:
	var pos: Vector2 = member["pos"]
	var delta := point - pos
	if delta.length_squared() < 0.000001:
		return
	var angle := Stealth.angle_of(delta)
	member["facing_angle"] = angle
	_apply_member_facing(member, angle)


func _make_view_cone(parent: Node3D, half_angle: float) -> MeshInstance3D:
	var cone := MeshInstance3D.new()
	cone.name = "ViewCone"
	cone.mesh = _cone_mesh(half_angle)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = VIEW_CONE_COLOR
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	cone.material_override = mat
	cone.position = Vector3(0.0, 0.03, 0.0)
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cone.visible = false
	parent.add_child(cone)
	return cone


func _cone_mesh(half_angle: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 18
	for i in range(segments):
		var a0: float = -half_angle + (2.0 * half_angle) * float(i) / float(segments)
		var a1: float = -half_angle + (2.0 * half_angle) * float(i + 1) / float(segments)
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(cos(a0), 0.0, sin(a0)))
		st.add_vertex(Vector3(cos(a1), 0.0, sin(a1)))
	st.generate_normals()
	return st.commit()


func _make_alert_mark(parent: Node3D) -> Label3D:
	var mark := Label3D.new()
	mark.name = "AlertMark"
	mark.text = "！"
	mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mark.no_depth_test = true
	mark.pixel_size = 0.02
	mark.font_size = 96
	mark.outline_size = 20
	mark.modulate = Color(1.0, 0.12, 0.1)
	mark.outline_modulate = Color(0.0, 0.0, 0.0)
	mark.position = Vector3(0.0, ALERT_MARK_HEIGHT, 0.0)
	mark.visible = false
	parent.add_child(mark)
	return mark

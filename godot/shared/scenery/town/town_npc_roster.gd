extends RefCounted

# 小镇 NPC 演员：节点、游走路线、朝向与任务标记。
# 不读取 GameState/Quest_flow；需要跳过哪些 NPC、标记是否受支持都由调用方传入。

const CharacterSprite = preload("res://shared/scene/character_sprite.gd")
const Interaction = preload("res://shared/gameplay/interaction.gd")
const TownData = preload("res://shared/resources/town_data.gd")
const TownMarkerIcons = preload("res://shared/scenery/town/town_marker_icons.gd")

const QUEST_MARKER_HEIGHT := 3.0
const QUEST_MARKER_INTERVAL := 0.5
const QUEST_MARKER_WIDTH := 1.15

var nodes: Dictionary = {}
var wander: Dictionary = {}

var _markers: Dictionary = {}
var _marker_phases: Dictionary = {}
var _marker_timer: float = 0.0
var _marker_info: Callable = Callable()


func build(
	parent: Node3D,
	npcs: Array,
	_bounds: Rect2,
	_blockers: Array,
	skip_ids: Array,
	marker_info: Callable,
	data: Dictionary = {}
) -> void:
	_marker_info = marker_info
	var root := Node3D.new()
	root.name = "NPCs"
	parent.add_child(root)
	for i in range(npcs.size()):
		var npc_value: Variant = npcs[i]
		if typeof(npc_value) != TYPE_DICTIONARY:
			continue
		var npc: Dictionary = npc_value
		var id := str(npc.get("id", "npc_%d" % i))
		if skip_ids.has(id):
			continue
		var character: Variant = CharacterSprite.new()
		character.name = id
		character.setup(str(npc.get("sprite", "")))
		var x := float(npc.get("x", 0.0))
		var z := float(npc.get("z", 0.0))
		character.position = Vector3(x, TownData.ground_height(data, x, z), z)
		character.set_facing(str(npc.get("facing", "down")))
		root.add_child(character)
		nodes[id] = character
		_register_wander(id, character, npc)
		_add_quest_marker(id, character, i)


func _register_wander(npc_id: String, node: Node3D, npc: Dictionary) -> void:
	var wander_value: Variant = npc.get("wander", null)
	if not (wander_value is Dictionary):
		return
	var wander_data: Dictionary = wander_value
	var route: Array[Vector2] = []
	var route_value: Variant = wander_data.get("route", [])
	if route_value is Array:
		for point_value in route_value:
			if not (point_value is Array):
				continue
			var point: Array = point_value
			if point.size() < 2:
				continue
			route.append(Vector2(float(point[0]), float(point[1])))
	if route.size() < 2:
		return
	wander[npc_id] = {
		"node": node,
		"route": route,
		"speed": float(wander_data.get("speed", 0.9)),
		"pause": float(wander_data.get("pause", 2.5)),
		"target": 1,
		"dir": 1,
		"wait": 0.0,
	}


# Moves every wandering NPC along its route, pinging back and forth between the
# end points and waiting `pause` seconds at each stop. An NPC stops and turns
# toward the player while the player is close or talking to it.
func advance(
	delta: float, player_pos: Vector2, current_npc_id: String, dialogue_active: bool
) -> void:
	for raw_id in wander.keys():
		var npc_id := str(raw_id)
		var state_value: Variant = wander[raw_id]
		if not (state_value is Dictionary):
			continue
		var state: Dictionary = state_value
		var node_value: Variant = state.get("node", null)
		if not (node_value is Node3D) or not is_instance_valid(node_value):
			continue
		var node: Node3D = node_value
		var pos := Vector2(node.position.x, node.position.z)
		var talking: bool = current_npc_id == npc_id and dialogue_active
		var player_close := player_pos.distance_to(pos) <= Interaction.RANGE
		if player_close or talking:
			state["wait"] = float(state.get("pause", 2.5))
			_face_node_toward(node, player_pos)
			node.call("set_moving", false)
			continue
		var wait := float(state.get("wait", 0.0))
		if wait > 0.0:
			state["wait"] = maxf(0.0, wait - delta)
			node.call("set_moving", false)
			continue
		var route: Array = state.get("route", [])
		if route.size() < 2:
			continue
		var target_index := clampi(int(state.get("target", 1)), 0, route.size() - 1)
		var target: Vector2 = route[target_index]
		var to_target := target - pos
		var dist := to_target.length()
		var speed := float(state.get("speed", 0.9))
		var step := speed * delta
		var moving := false
		if dist <= step:
			pos = target
			var dir := int(state.get("dir", 1))
			var next_index := target_index + dir
			if next_index < 0 or next_index >= route.size():
				dir = -dir
				next_index = target_index + dir
			state["dir"] = dir
			state["target"] = clampi(next_index, 0, route.size() - 1)
			state["wait"] = float(state.get("pause", 2.5))
		elif dist > 0.0001:
			pos += to_target / dist * step
			moving = true
		node.position = Vector3(pos.x, node.position.y, pos.y)
		if moving:
			_face_node_toward(node, pos + to_target)
		node.call("set_moving", moving)


func _face_node_toward(node: Node3D, point: Vector2) -> void:
	var dx: float = point.x - node.position.x
	var dz: float = point.y - node.position.z
	if absf(dx) < 0.0001 and absf(dz) < 0.0001:
		return
	var facing := "down"
	if absf(dx) >= absf(dz):
		facing = "right" if dx > 0.0 else "left"
	else:
		facing = "down" if dz > 0.0 else "up"
	node.call("set_facing", facing)


func _add_quest_marker(npc_id: String, parent: Node3D, index: int) -> void:
	if not _marker_info.is_valid():
		return
	var info_value: Variant = _marker_info.call(npc_id)
	var supported := false
	if info_value is Dictionary:
		var info: Dictionary = info_value
		supported = bool(info.get("supported", false))
	if not supported:
		return
	var sprite := Sprite3D.new()
	sprite.name = "QuestMarker_%s" % npc_id
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.no_depth_test = true
	sprite.render_priority = 10
	sprite.shaded = false
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	sprite.pixel_size = QUEST_MARKER_WIDTH / 128.0
	sprite.visible = false
	sprite.set_meta("marker_text", "")
	sprite.position = Vector3(0.0, QUEST_MARKER_HEIGHT, 0.0)
	parent.add_child(sprite)
	_markers[npc_id] = sprite
	_marker_phases[npc_id] = float(index) * 1.3


func refresh_markers() -> void:
	if not _marker_info.is_valid():
		return
	for raw_id in _markers.keys():
		var npc_id := str(raw_id)
		var sprite_value: Variant = _markers[raw_id]
		if not is_instance_valid(sprite_value) or not (sprite_value is Sprite3D):
			continue
		var sprite: Sprite3D = sprite_value
		var info_value: Variant = _marker_info.call(npc_id)
		var text := ""
		if info_value is Dictionary:
			var info: Dictionary = info_value
			text = str(info.get("text", ""))
		var texture := TownMarkerIcons.texture_for(text)
		sprite.texture = texture
		if texture != null:
			var size: Vector2 = texture.get_size()
			if size.x > 0.0:
				sprite.pixel_size = QUEST_MARKER_WIDTH / size.x
		sprite.visible = texture != null
		sprite.set_meta("marker_text", text)
		if text == "…":
			sprite.modulate = Color(1.0, 1.0, 1.0, 0.7)
		else:
			sprite.modulate = Color.WHITE


func update_markers(delta: float, elapsed: float) -> void:
	_marker_timer += delta
	if _marker_timer >= QUEST_MARKER_INTERVAL:
		_marker_timer = 0.0
		refresh_markers()
	for raw_id in _markers.keys():
		var sprite_value: Variant = _markers[raw_id]
		if not is_instance_valid(sprite_value) or not (sprite_value is Sprite3D):
			continue
		var sprite: Sprite3D = sprite_value
		if not sprite.visible:
			continue
		var phase := float(_marker_phases.get(raw_id, 0.0))
		sprite.position.y = QUEST_MARKER_HEIGHT + sin(elapsed * 2.0 + phase) * 0.08
		var breath := 1.0 + sin(elapsed * 2.0 + phase) * 0.05
		sprite.scale = Vector3(breath, breath, 1.0)

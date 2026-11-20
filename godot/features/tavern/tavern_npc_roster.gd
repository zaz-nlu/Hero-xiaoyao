extends RefCounted

# 酒馆 NPC 所有权：entries/nodes、入场/同步/移除、目标站位与闹事姿态。
# 显式接收 parent/data/状态；不读取其他系统私有字段。

const CharacterSprite = preload("res://shared/scene/character_sprite.gd")
const Interaction = preload("res://shared/gameplay/interaction.gd")
const TavernStateAnimation = preload("res://features/tavern/tavern_state_animation.gd")

const STATES: Array[String] = ["normal", "brawl", "aftermath"]
const ZIXIA_IDS: Array[String] = ["zixia", "disciple_1", "disciple_2", "disciple_3"]
const DISCIPLE_IDS: Array[String] = ["disciple_1", "disciple_2", "disciple_3"]
const GameState = preload("res://core/game_state.gd")
const ENTRANCE_STAGGER := 0.25
const PREFIGHT_START := Vector3(17.0, 0.0, -7.0)
const FALLEN_COLOR := Color(0.45, 0.45, 0.5, 0.75)

var entries: Dictionary = {}
var nodes: Dictionary = {}

var _parent: Node3D = null
var _root: Node3D = null
var _entrance := Vector3(11.0, 0.0, 5.5)


func setup(parent: Node3D, data: Dictionary) -> void:
	_parent = parent
	entries.clear()
	nodes.clear()
	var entrance_value: Variant = data.get("entrance", null)
	if entrance_value is Dictionary:
		var entrance: Dictionary = entrance_value
		_entrance = Vector3(
			float(entrance.get("x", 11.0)), 0.0, float(entrance.get("z", 5.5))
		)
	var npcs: Array = data.get("npcs", [])
	for i in range(npcs.size()):
		var npc_value: Variant = npcs[i]
		if typeof(npc_value) != TYPE_DICTIONARY:
			continue
		var npc: Dictionary = npc_value
		entries[str(npc.get("id", "npc_%d" % i))] = npc


func apply_state(
	new_state: String,
	animate: bool,
	stagger: bool,
	skip_actors: bool,
	bandit_count: int,
	prefight_done: bool,
	animation: TavernStateAnimation
) -> void:
	if skip_actors:
		return
	_sync(new_state, animate, stagger, bandit_count, animation)
	if new_state == "brawl":
		_apply_brawl_poses(prefight_done)
	elif new_state == "aftermath":
		_apply_aftermath_poses()


func target_position(id: String, new_state: String) -> Vector3:
	var entry_value: Variant = entries.get(id, null)
	if not (entry_value is Dictionary):
		return Vector3.ZERO
	return _position(entry_value, new_state)


func nearby_npc(player_pos: Vector2) -> String:
	var positions: Dictionary = {}
	for id in nodes.keys():
		var node_value: Variant = nodes[id]
		if not (node_value is Node3D):
			continue
		var node: Node3D = node_value
		if not node.visible:
			continue
		positions[str(id)] = Vector2(node.position.x, node.position.z)
	return Interaction.nearest_npc(player_pos, positions)


func entry(npc_id: String) -> Dictionary:
	var value: Variant = entries.get(npc_id, null)
	if value is Dictionary:
		return value
	return {}


func dialogue_path(npc_id: String, new_state: String) -> String:
	var npc_entry: Dictionary = entry(npc_id)
	var dialogues_value: Variant = npc_entry.get("dialogues", null)
	if dialogues_value is Dictionary:
		var dialogues: Dictionary = dialogues_value
		if dialogues.has(new_state):
			return str(dialogues[new_state])
		if dialogues.has("normal"):
			return str(dialogues["normal"])
		if dialogues.size() > 0:
			return str(dialogues[dialogues.keys()[0]])
	return str(npc_entry.get("dialogue", ""))


func display_name(npc_id: String) -> String:
	return str(entry(npc_id).get("name", npc_id))


func face_towards(npc_id: String, target: Vector2) -> void:
	var node_value: Variant = nodes.get(npc_id, null)
	if not (node_value is Node3D):
		return
	var node: Node3D = node_value
	var dx: float = target.x - node.position.x
	var dz: float = target.y - node.position.z
	var facing := "down"
	if absf(dx) >= absf(dz):
		facing = "right" if dx > 0.0 else "left"
	else:
		facing = "down" if dz > 0.0 else "up"
	node.call("set_facing", facing)


func _sync(
	new_state: String,
	animate: bool,
	stagger: bool,
	bandit_count: int,
	animation: TavernStateAnimation
) -> void:
	if _root == null:
		_root = Node3D.new()
		_root.name = "NPCs"
		_parent.add_child(_root)
	for id in nodes.keys():
		var entry_value: Variant = entries.get(id, null)
		var present := false
		if entry_value is Dictionary:
			present = _present(str(id), entry_value, new_state, bandit_count)
		if not present:
			_remove(str(id))
	var entrance_index := 0
	for id in entries.keys():
		var npc_entry: Dictionary = entries[id]
		if not _present(str(id), npc_entry, new_state, bandit_count):
			continue
		var target: Vector3 = _position(npc_entry, new_state)
		if nodes.has(id):
			var node: Node3D = nodes[id]
			node.visible = true
			if animate:
				animation.add_npc_move(node, node.position, target)
			else:
				node.position = target
		else:
			var character: Variant = CharacterSprite.new()
			character.name = str(id)
			character.setup(str(npc_entry.get("sprite", "")))
			character.set_facing(str(npc_entry.get("facing", "down")))
			if animate:
				character.position = _entrance_position(str(id))
				character.call("set_moving", true)
				var delay := 0.0
				if stagger and not ZIXIA_IDS.has(str(id)):
					delay = ENTRANCE_STAGGER * float(entrance_index)
					entrance_index += 1
				animation.add_npc_move(character, character.position, target, delay)
			else:
				character.position = target
			_root.add_child(character)
			nodes[str(id)] = character


func _remove(id: String) -> void:
	var node_value: Variant = nodes.get(id, null)
	nodes.erase(id)
	if not (node_value is Node):
		return
	var node: Node = node_value
	var parent: Node = node.get_parent()
	if parent != null:
		parent.remove_child(node)
	if node.is_inside_tree():
		node.queue_free()
	else:
		node.free()


func _present(id: String, npc_entry: Dictionary, new_state: String, bandit_count: int) -> bool:
	var states_value: Variant = npc_entry.get("states", STATES)
	if states_value is Array:
		var states: Array = states_value
		if not states.has(new_state):
			return false
	# 紫霞派晚于马匪入场：马匪砸完桌子、对话之后才进门（zixia_entered 由酒馆导演设置）。
	if new_state == "brawl" and ZIXIA_IDS.has(id) and not _zixia_arrived():
		return false
	if new_state == "brawl" and id.begins_with("bandit_"):
		var index := int(id.trim_prefix("bandit_"))
		return index >= 1 and index <= bandit_count
	return true


func _zixia_arrived() -> bool:
	return GameState.has_flag("zixia_entered") or GameState.has_flag("prefight_done")


func _position(npc_entry: Dictionary, new_state: String) -> Vector3:
	var positions_value: Variant = npc_entry.get("positions", null)
	if not (positions_value is Dictionary):
		return Vector3.ZERO
	var positions: Dictionary = positions_value
	var key := "normal"
	if positions.has(new_state):
		key = new_state
	elif positions.size() > 0:
		key = str(positions.keys()[0])
	var pos_value: Variant = positions.get(key, null)
	if pos_value is Array:
		var pos: Array = pos_value
		if pos.size() >= 2:
			return Vector3(float(pos[0]), 0.0, float(pos[1]))
	return Vector3.ZERO


func _entrance_position(id: String) -> Vector3:
	if ZIXIA_IDS.has(id):
		return PREFIGHT_START
	return _entrance


func _apply_brawl_poses(prefight_done: bool) -> void:
	for id in ZIXIA_IDS:
		var node_value: Variant = nodes.get(str(id), null)
		if not (node_value is Node3D):
			continue
		var node: Node3D = node_value
		node.rotation = Vector3.ZERO
		node.scale = Vector3.ONE
		if not prefight_done:
			node.call("set_facing", "right")
	if prefight_done:
		for i in range(DISCIPLE_IDS.size()):
			_lay_down_disciple(i)
		_crouch_sister()
		_face_brawl_enemies()
	else:
		_face_prefight_sides()


func _apply_aftermath_poses() -> void:
	for id in ZIXIA_IDS:
		var node_value: Variant = nodes.get(str(id), null)
		if not (node_value is Node3D):
			continue
		var node: Node3D = node_value
		node.rotation = Vector3.ZERO
		node.scale = Vector3.ONE
		_set_npc_tint(node, Color.WHITE)
		node.call("set_facing", "down")


func _face_prefight_sides() -> void:
	for id in ZIXIA_IDS:
		_face_npc(str(id), "right")
	for id in nodes.keys():
		if str(id) == "ma_youwei" or str(id).begins_with("bandit_"):
			_face_npc(str(id), "left")


func _face_brawl_enemies() -> void:
	for id in nodes.keys():
		if str(id) == "ma_youwei" or str(id).begins_with("bandit_"):
			_face_npc(str(id), "down")


func _face_npc(id: String, facing: String) -> void:
	var node_value: Variant = nodes.get(id, null)
	if node_value is Node:
		(node_value as Node).call("set_facing", facing)


func _lay_down_disciple(index: int) -> void:
	if index < 0 or index >= DISCIPLE_IDS.size():
		return
	var node_value: Variant = nodes.get(DISCIPLE_IDS[index], null)
	if not (node_value is Node3D):
		return
	var node: Node3D = node_value
	node.rotation.z = PI / 2.0
	_set_npc_tint(node, FALLEN_COLOR)


func _crouch_sister() -> void:
	var node_value: Variant = nodes.get("zixia", null)
	if not (node_value is Node3D):
		return
	(node_value as Node3D).scale = Vector3(1.0, 0.85, 1.0)


func _set_npc_tint(node: Node3D, color: Color) -> void:
	var sprite_value: Variant = node.get_node_or_null("Sprite")
	if sprite_value is Sprite3D:
		(sprite_value as Sprite3D).modulate = color

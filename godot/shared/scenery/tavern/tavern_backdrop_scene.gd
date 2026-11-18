extends RefCounted

# 酒馆背景场景：房间/家具/氛围/光照/相机，强制静态状态（如 brawl）。
# 没有 NPC、玩家、对话、前戏或故事时钟；家具视觉复用共享静态工具。

const TAVERN_PATH := "res://data/tavern.json"
const CAMERA_OFFSET := Vector3(0.0, 13.0, 30.0)
const LOOK_AHEAD := Vector3(0.0, 1.5, -7.5)
const CAMERA_FOV := 28.0

const TavernArt = preload("res://shared/scenery/tavern/tavern_art.gd")
const TavernLayout = preload("res://shared/scenery/tavern/tavern_layout.gd")
const TavernRoomBuilder = preload("res://shared/scenery/tavern/tavern_room_builder.gd")
const TavernAtmosphereBuilder = preload("res://shared/scenery/tavern/tavern_atmosphere_builder.gd")
const TavernFurnitureBuilder = preload("res://shared/scenery/tavern/tavern_furniture_builder.gd")
const TavernFurnitureVisuals = preload("res://shared/scenery/tavern/tavern_furniture_visuals.gd")
const WorldCamera = preload("res://shared/scene/world_camera.gd")

var data: Dictionary = {}
var room: Dictionary = {}
var camera: Camera3D = null
var arena_origin: Vector3 = Vector3.ZERO
var entries: Dictionary = {}
var furniture_nodes: Dictionary = {}
var debris_root: Node3D = null

var _art: TavernArt = null
var _focus: Vector3 = Vector3.ZERO
var _spawn := Vector3(11.0, 0.0, 3.5)


func build(parent: Node3D, _options: Dictionary) -> void:
	_art = TavernArt.new()
	data = _load_data()
	var room_value: Variant = data.get("room", {})
	if room_value is Dictionary:
		room = room_value
	_read_arena_origin()
	TavernRoomBuilder.build_room(parent, room, _art)
	TavernRoomBuilder.build_beams(parent, room, _art)
	TavernRoomBuilder.build_wall_decor(parent, room, _art)
	entries = _collect_entries(data)
	var furniture: Dictionary = TavernFurnitureBuilder.build_furniture(parent, entries, _art)
	var nodes_value: Variant = furniture.get("nodes", {})
	if nodes_value is Dictionary:
		furniture_nodes = nodes_value
	var debris_value: Variant = furniture.get("debris_root", null)
	if debris_value is Node3D:
		debris_root = debris_value
	TavernRoomBuilder.build_stairs(parent, data, _art)
	TavernRoomBuilder.build_windows(parent, room, _art)
	TavernAtmosphereBuilder.build_light_shafts(parent, room)
	TavernAtmosphereBuilder.build_dust(parent)
	TavernAtmosphereBuilder.build_lanterns(parent)
	TavernAtmosphereBuilder.build_lighting(parent, data)
	camera = WorldCamera.build(parent, CAMERA_OFFSET, CAMERA_FOV)


func advance(delta: float) -> void:
	_focus = WorldCamera.update(
		camera, null, _focus, CAMERA_OFFSET, LOOK_AHEAD, delta, _spawn
	)


# Applies furniture transforms and wrecked sprites without an animation clock.
func apply_state(new_state: String, _animate: bool = false) -> void:
	for id in entries.keys():
		var entry: Dictionary = entries[id]
		var node_value: Variant = furniture_nodes.get(id, null)
		if not (node_value is Node3D):
			continue
		var node: Node3D = node_value
		node.visible = TavernLayout.visible_for(entry, new_state)
		node.transform = TavernLayout.transform_for(entry, new_state)
		TavernFurnitureVisuals.apply_swap(node, entry, new_state)
	if debris_root != null:
		debris_root.visible = new_state != "normal"


# ---------------------------------------------------------------- data

func _load_data() -> Dictionary:
	if not FileAccess.file_exists(TAVERN_PATH):
		push_warning("tavern backdrop: %s not found" % TAVERN_PATH)
		return {}
	var text: String = FileAccess.get_file_as_string(TAVERN_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("tavern backdrop: invalid JSON in %s" % TAVERN_PATH)
		return {}
	var tavern_data: Dictionary = parsed
	return tavern_data


func _read_arena_origin() -> void:
	var arena_value: Variant = data.get("arena", null)
	if not (arena_value is Dictionary):
		return
	var origin_value: Variant = (arena_value as Dictionary).get("origin", null)
	if not (origin_value is Array):
		return
	var origin: Array = origin_value
	if origin.size() >= 3:
		arena_origin = Vector3(float(origin[0]), float(origin[1]), float(origin[2]))


func _collect_entries(town_data: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var furniture: Array = town_data.get("furniture", [])
	for i in range(furniture.size()):
		var entry_value: Variant = furniture[i]
		if typeof(entry_value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_value
		result[str(entry.get("id", "furniture_%d" % i))] = entry
	return result

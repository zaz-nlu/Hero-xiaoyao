extends RefCounted

# 小镇背景场景：地面/建筑/道具/光照/相机，可选的纯环境 NPC 与 pickup 外观。
# 不读取输入、任务、对话或存档；pickup 是否已采集由调用方 provider 输入。

const TOWN_PATH := "res://data/town.json"
const CAMERA_OFFSET := Vector3(0.0, 16.7, 37.5)
# Look slightly north of the player so the characters sit in the lower half of the frame.
const LOOK_AHEAD := Vector3(0.0, 1.0, -4.0)
const CAMERA_FOV := 28.0

const TownData = preload("res://shared/resources/town_data.gd")
const CharacterSprite = preload("res://shared/scene/character_sprite.gd")
const WorldCamera = preload("res://shared/scene/world_camera.gd")
const PlayerMotion = preload("res://shared/gameplay/player_motion.gd")
const Pickups = preload("res://shared/gameplay/pickups.gd")
const TownArt = preload("res://shared/scenery/town/town_art.gd")
const TownGround = preload("res://shared/scenery/town/town_ground.gd")
const TownBuildings = preload("res://shared/scenery/town/town_buildings.gd")
const TownProps = preload("res://shared/scenery/town/town_props.gd")
const TownNpcRoster = preload("res://shared/scenery/town/town_npc_roster.gd")

var data: Dictionary = {}
var bounds_rect: Rect2 = Rect2()
var blockers: Array = []
var pickups: Array = []
var camera: Camera3D = null
var player: Node3D = null
var player_pos: Vector2 = Vector2.ZERO
var arena_origin: Vector3 = Vector3.ZERO
var npc_nodes: Dictionary:
	get:
		return _roster.nodes

var _art: TownArt = TownArt.new()
var _ground: TownGround = TownGround.new()
var _props: TownProps = TownProps.new()
var _roster: TownNpcRoster = TownNpcRoster.new()
var _focus: Vector3 = Vector3.ZERO


func build(parent: Node3D, options: Dictionary) -> void:
	data = _load_town()
	bounds_rect = _read_bounds()
	blockers = TownData.footprints(data)
	pickups = Pickups.parse_entries(data.get("pickups", []))
	_ground.build_ground(parent, data, _art)
	var buildings := TownBuildings.new()
	var tavern_facade: bool = buildings.build_buildings(parent, data, _art)
	_props.build_props(parent, data, _art, tavern_facade)
	_props.build_forest_sign(parent, _art)
	_ground.build_stairs(parent, data, _art)
	_ground.build_backdrop(parent)
	_ground.build_lighting(parent)
	camera = WorldCamera.build(parent, CAMERA_OFFSET, CAMERA_FOV)
	player_pos = Vector2(_spawn_point().x, _spawn_point().z)
	if not bool(options.get("skip_actors", true)):
		_build_npcs(parent, options)
		_build_pickups(parent, options)
		_build_player(
			parent,
			bool(options.get("hide_player", true)),
			options.get("player_anchor", null)
		)
		snap_camera()


func advance(delta: float) -> void:
	_ground.advance(delta)
	_props.advance(delta)
	_roster.advance(delta, player_pos, "", false)
	_focus = WorldCamera.update(
		camera, player, _focus, CAMERA_OFFSET, LOOK_AHEAD, delta, _spawn_point()
	)


func snap_camera() -> void:
	_focus = WorldCamera.snap(camera, player, CAMERA_OFFSET, LOOK_AHEAD, _spawn_point())


# ---------------------------------------------------------------- data

func _load_town() -> Dictionary:
	var loaded: Dictionary = TownData.load_town(TOWN_PATH)
	var errors: Array = loaded.get("errors", [])
	for error_text in errors:
		push_warning("town backdrop: %s" % str(error_text))
	var value: Variant = loaded.get("data", {})
	if value is Dictionary:
		var town_data: Dictionary = value
		return town_data
	return {}


func _read_bounds() -> Rect2:
	var bounds_value: Variant = data.get("bounds", null)
	if typeof(bounds_value) != TYPE_DICTIONARY:
		return Rect2()
	var bounds: Dictionary = bounds_value
	var x0 := float(bounds.get("x0", 0.0))
	var x1 := float(bounds.get("x1", 0.0))
	var z0 := float(bounds.get("z0", 0.0))
	var z1 := float(bounds.get("z1", 0.0))
	return Rect2(x0, z0, x1 - x0, z1 - z0)


func _spawn_point() -> Vector3:
	var spawn_value: Variant = data.get("spawn", null)
	if spawn_value is Dictionary:
		var spawn: Dictionary = spawn_value
		return Vector3(float(spawn.get("x", 0.0)), 0.0, float(spawn.get("z", 0.0)))
	return Vector3.ZERO


# ---------------------------------------------------------------- actors

func _build_npcs(parent: Node3D, options: Dictionary) -> void:
	var skip_ids: Variant = options.get("skip_npc_ids", [])
	var skip_list: Array = skip_ids if skip_ids is Array else []
	var npc_entries: Array = data.get("npcs", [])
	# The shared backdrop never owns quest state: no marker provider is passed.
	_roster.build(
		parent,
		npc_entries,
		bounds_rect,
		blockers,
		skip_list,
		Callable()
	)


func _build_pickups(parent: Node3D, options: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "Pickups"
	parent.add_child(root)
	var provider_value: Variant = options.get("picked_flag_provider", Callable())
	var provider: Callable = Callable()
	if provider_value is Callable:
		provider = provider_value
	for pickup_value in pickups:
		if not (pickup_value is Dictionary):
			continue
		var pickup: Dictionary = pickup_value
		var collected := false
		var flag := str(pickup.get("flag", ""))
		if flag != "" and provider.is_valid():
			collected = bool(provider.call(flag))
		Pickups.spawn_visual(root, pickup, collected)


func _build_player(parent: Node3D, hide_player: bool, anchor: Variant) -> void:
	var spawn_value: Variant = data.get("spawn", null)
	var spawn: Dictionary = {}
	if typeof(spawn_value) == TYPE_DICTIONARY:
		spawn = spawn_value
	var px := float(spawn.get("x", 0.0))
	var pz := float(spawn.get("z", 0.0))
	if anchor is Vector2:
		var anchor_pos: Vector2 = anchor
		if _spawn_walkable(anchor_pos):
			px = anchor_pos.x
			pz = anchor_pos.y
	var start_y: float = TownData.ground_height(data, px, pz)
	var character := CharacterSprite.new()
	character.name = "Player"
	character.setup("ren_xiaoyao")
	character.position = Vector3(px, start_y, pz)
	character.set_facing(str(spawn.get("facing", "down")))
	parent.add_child(character)
	player = character
	player_pos = Vector2(px, pz)
	character.visible = not hide_player
	blockers.append_array(TownData.extra_blockers(data))


func _spawn_walkable(point: Vector2) -> bool:
	if bounds_rect.size != Vector2.ZERO \
			and not bounds_rect.grow(-PlayerMotion.RADIUS).has_point(point):
		return false
	var all_blockers: Array = blockers.duplicate()
	all_blockers.append_array(TownData.extra_blockers(data))
	return not PlayerMotion.blocked(point, all_blockers)

extends Node3D

signal encounter_requested(enemy_id: String, count: int, first_strike: bool)
signal enter_requested(place: String)

const DataLoader = preload("res://core/data_loader.gd")

const TOWN_PATH := DataLoader.TOWN_PATH
const NPC_DIALOGUES_PATH := DataLoader.NPC_DIALOGUES_PATH
const SPEAKERS_PATH := DataLoader.SPEAKERS_PATH
const CAMERA_OFFSET := Vector3(0.0, 16.7, 37.5)
# Look slightly north of the player so the characters sit in the lower half of the frame.
const LOOK_AHEAD := Vector3(0.0, 1.0, -4.0)
const DEFEATED_NPC_IDS: Array[String] = ["ma_youwei", "bandit_1", "bandit_2"]

const TownData = preload("res://shared/resources/town_data.gd")
const CharacterSprite = preload("res://shared/scene/character_sprite.gd")
const PlayerMotion = preload("res://shared/gameplay/player_motion.gd")
const Dialogue = preload("res://core/dialogue.gd")
const GameState = preload("res://core/game_state.gd")
const Quests = preload("res://core/quests.gd")
const Quest_flow = preload("res://core/quest_flow.gd")
const Interaction = preload("res://shared/gameplay/interaction.gd")
const Pickups = preload("res://shared/gameplay/pickups.gd")
const WorldCamera = preload("res://shared/scene/world_camera.gd")
const TownArt = preload("res://shared/scenery/town/town_art.gd")
const TownGround = preload("res://shared/scenery/town/town_ground.gd")
const TownBuildings = preload("res://shared/scenery/town/town_buildings.gd")
const TownProps = preload("res://shared/scenery/town/town_props.gd")
const TownNpcRoster = preload("res://shared/scenery/town/town_npc_roster.gd")

var data: Dictionary = {}
var blockers: Array = []
var pickups: Array = []
var npc_dialogues: Dictionary = {}
var camera: Camera3D = null
var follow_target: Node3D = null
var sun: DirectionalLight3D = null
var world_env: WorldEnvironment = null
var player: Node3D = null
var player_pos: Vector2 = Vector2.ZERO
var bounds_rect: Rect2 = Rect2()
var dialogue_view: Control = null
var prompt_label: Label = null
var pending_encounter: Dictionary = {}
var pending_after: Dictionary = {}
var current_npc_id: String = ""
var skip_actors: bool = false
var input_blocked: bool = false

var _input_override: Variant = null
var _built: bool = false
var _time: float = 0.0
var _focus: Vector3 = Vector3.ZERO
var _hud_layer: CanvasLayer = null
var _tavern_door_point: Vector2 = Vector2.INF
var _tavern_return_point: Vector2 = Vector2.INF
var _art: TownArt = TownArt.new()
var _ground: TownGround = TownGround.new()
var _props: TownProps = TownProps.new()
var _roster: TownNpcRoster = TownNpcRoster.new()

var npc_nodes: Dictionary:
	get:
		return _roster.nodes

var npc_wander: Dictionary:
	get:
		return _roster.wander


func _ready() -> void:
	_register_input_actions()
	build()
	build_hud()


func _register_input_actions() -> void:
	_add_action("move_left", KEY_A, KEY_LEFT)
	_add_action("move_right", KEY_D, KEY_RIGHT)
	_add_action("move_up", KEY_W, KEY_UP)
	_add_action("move_down", KEY_S, KEY_DOWN)
	_add_action("interact", KEY_E, KEY_NONE)


func _add_action(action: StringName, primary: int, secondary: int) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	_add_key_event(action, primary)
	if secondary != KEY_NONE:
		_add_key_event(action, secondary)


func _add_key_event(action: StringName, key: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(action, event)


func build() -> void:
	if _built:
		return
	_built = true
	var loaded: Dictionary = TownData.load_town(TOWN_PATH)
	data = loaded["data"]
	var errors: Array = loaded["errors"]
	for error_text in errors:
		push_warning("town: %s" % str(error_text))
	blockers = TownData.footprints(data)
	bounds_rect = _read_bounds()
	_read_pickups()
	_tavern_door_point = _tavern_entrance(0.8)
	_tavern_return_point = _tavern_entrance(1.5)
	_ground.build_ground(self, data, _art)
	var buildings := TownBuildings.new()
	var tavern_facade: bool = buildings.build_buildings(self, data, _art)
	_props.build_props(self, data, _art, tavern_facade)
	_props.build_forest_sign(self, _art, data)
	_ground.build_stairs(self, data, _art)
	_ground.build_backdrop(self)
	_ground.build_lighting(self)
	sun = _ground.sun
	world_env = _ground.world_env
	_build_camera()
	npc_dialogues = Interaction.load_npc_dialogues(NPC_DIALOGUES_PATH)
	if not skip_actors:
		_build_npcs()
		_build_pickups()
		_build_player()
		snap_camera()
	_refresh_quest_markers()


func _process(delta: float) -> void:
	tick_player(delta)
	advance_npcs(delta)
	update_prompt()
	if not is_dialogue_active() and InputMap.has_action("interact") \
			and Input.is_action_just_pressed("interact"):
		try_interact()
	_time += delta
	_roster.update_markers(delta, _time)
	_ground.advance(delta)
	_props.advance(delta)
	update_camera(delta)


# ---------------------------------------------------------------- camera

func _build_camera() -> void:
	camera = WorldCamera.build(self, CAMERA_OFFSET, 28.0)


func update_camera(delta: float) -> void:
	_focus = WorldCamera.update(
		camera, follow_target, _focus, CAMERA_OFFSET, LOOK_AHEAD, delta,
		_spawn_position(), TownData.camera_clamp(data))


func snap_camera() -> void:
	_focus = WorldCamera.snap(camera, follow_target, CAMERA_OFFSET, LOOK_AHEAD, _spawn_position())


func _spawn_position() -> Vector3:
	var spawn_value: Variant = data.get("spawn", null)
	if typeof(spawn_value) == TYPE_DICTIONARY:
		var spawn: Dictionary = spawn_value
		return Vector3(float(spawn.get("x", 0.0)), 0.0, float(spawn.get("z", 0.0)))
	return Vector3.ZERO


# ---------------------------------------------------------------- npcs

func _build_npcs() -> void:
	var skip_ids: Array = []
	if GameState.has_flag("boss_defeated"):
		skip_ids = DEFEATED_NPC_IDS
	var npcs: Array = data.get("npcs", [])
	_roster.build(
		self, npcs, bounds_rect, blockers, skip_ids, Callable(self, "_marker_info"), data
	)


func _marker_info(npc_id: String) -> Dictionary:
	return {
		"supported": Quest_flow.has_quests(npc_id),
		"text": Quest_flow.marker(npc_id),
	}


func advance_npcs(delta: float) -> void:
	_roster.advance(delta, player_pos, current_npc_id, is_dialogue_active())


func _refresh_quest_markers() -> void:
	_roster.refresh_markers()


# ---------------------------------------------------------------- player

func _build_player() -> void:
	var spawn := _spawn_data()
	var px := float(spawn.get("x", 0.0))
	var pz := float(spawn.get("z", 0.0))
	var return_value: Variant = GameState.town_return_pos
	if return_value is Vector2:
		var return_pos: Vector2 = return_value
		if _spawn_walkable(return_pos):
			px = return_pos.x
			pz = return_pos.y
	var start_y: float = TownData.ground_height(data, px, pz)
	var character := CharacterSprite.new()
	character.name = "Player"
	character.setup("ren_xiaoyao")
	character.position = Vector3(px, start_y, pz)
	character.set_facing(str(spawn.get("facing", "down")))
	add_child(character)
	player = character
	player_pos = Vector2(px, pz)
	blockers.append_array(TownData.extra_blockers(data))
	follow_target = player


func _spawn_data() -> Dictionary:
	var spawn_value: Variant = data.get("spawn", null)
	if typeof(spawn_value) == TYPE_DICTIONARY:
		var spawn: Dictionary = spawn_value
		return spawn
	return {}


func _spawn_walkable(point: Vector2) -> bool:
	if bounds_rect.size != Vector2.ZERO \
			and not bounds_rect.grow(-PlayerMotion.RADIUS).has_point(point):
		return false
	var all_blockers: Array = blockers.duplicate()
	all_blockers.append_array(TownData.extra_blockers(data))
	return not PlayerMotion.blocked(point, all_blockers)


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


func _read_pickups() -> void:
	pickups = Pickups.parse_entries(data.get("pickups", []))


func _build_pickups() -> void:
	var root := Node3D.new()
	root.name = "Pickups"
	add_child(root)
	for pickup_value in pickups:
		if not (pickup_value is Dictionary):
			continue
		var pickup: Dictionary = pickup_value
		Pickups.spawn(root, pickup, func(x: float, z: float) -> float: return TownData.ground_height(data, x, z))


func _nearest_pickup() -> Dictionary:
	return Pickups.nearest(pickups, player_pos)


# Point just outside the tavern door, `offset` world units in front of the facade.
func _tavern_entrance(offset: float) -> Vector2:
	var buildings: Array = data.get("buildings", [])
	for building_value in buildings:
		if typeof(building_value) != TYPE_DICTIONARY:
			continue
		var building: Dictionary = building_value
		if str(building.get("id", "")) != "tavern":
			continue
		var x0 := float(building.get("x0", 0.0))
		var x1 := float(building.get("x1", 0.0))
		var door_x := float(building.get("door_x", (x0 + x1) * 0.5))
		var z_front := float(building.get("z_front", 0.0))
		return Vector2(door_x, z_front + offset)
	return Vector2.INF


func tavern_door() -> Vector2:
	return _tavern_door_point


func tavern_return_pos() -> Vector2:
	return _tavern_return_point


func _near_tavern_door() -> bool:
	if _tavern_door_point == Vector2.INF:
		return false
	return player_pos.distance_to(_tavern_door_point) <= 2.0


func set_input_override(v: Variant) -> void:
	_input_override = v


func get_move_input() -> Vector2:
	if input_blocked:
		return Vector2.ZERO
	if _input_override != null:
		if typeof(_input_override) == TYPE_VECTOR2:
			var override_value: Vector2 = _input_override
			return override_value
		return Vector2.ZERO
	if not InputMap.has_action("move_left") or not InputMap.has_action("move_right") \
			or not InputMap.has_action("move_up") or not InputMap.has_action("move_down"):
		return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


func tick_player(delta: float) -> void:
	if player == null:
		return
	var input := get_move_input()
	if is_dialogue_active():
		input = Vector2.ZERO
	player_pos = PlayerMotion.step(player_pos, input, delta, blockers, bounds_rect)
	var target_y: float = TownData.ground_height(data, player_pos.x, player_pos.y)
	var weight: float = 1.0 - exp(-14.0 * delta)
	var next_y: float = lerpf(player.position.y, target_y, weight)
	player.position = Vector3(player_pos.x, next_y, player_pos.y)
	var facing: String = PlayerMotion.facing_from_input(input, str(player.get("facing")))
	player.call("set_facing", facing)
	player.call("set_moving", input.length() > 0.01)


# ---------------------------------------------------------------- interaction

func build_hud() -> void:
	if _hud_layer != null:
		return
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "Hud"
	_hud_layer.layer = 10
	add_child(_hud_layer)

	var view: Variant = load("res://shared/ui/dialogue_view.gd").new()
	view.name = "DialogueView"
	_hud_layer.add_child(view)
	view.build_ui()
	view.visible = false
	view.connect("finished", Callable(self, "_on_dialogue_finished"))
	dialogue_view = view

	prompt_label = Label.new()
	prompt_label.name = "PromptLabel"
	prompt_label.text = ""
	prompt_label.visible = false
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt_label.anchor_left = 0.0
	prompt_label.anchor_right = 1.0
	prompt_label.anchor_top = 1.0
	prompt_label.anchor_bottom = 1.0
	prompt_label.offset_left = 0.0
	prompt_label.offset_right = 0.0
	prompt_label.offset_top = -160.0
	prompt_label.offset_bottom = -110.0
	prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(prompt_label)


func nearby_npc() -> String:
	var positions: Dictionary = {}
	for id in npc_nodes.keys():
		var node_value: Variant = npc_nodes[id]
		if not (node_value is Node3D):
			continue
		var node: Node3D = node_value
		positions[str(id)] = Vector2(node.position.x, node.position.z)
	return Interaction.nearest_npc(player_pos, positions)


func try_interact() -> bool:
	if input_blocked:
		return false
	if is_dialogue_active():
		return false
	var npc_id: String = nearby_npc()
	if npc_id == "" or not npc_dialogues.has(npc_id):
		var pickup := _nearest_pickup()
		if not pickup.is_empty():
			Pickups.collect(pickup)
			return true
		if _try_enter_tavern():
			return true
		return _try_enter_forest()
	var entry_value: Variant = npc_dialogues[npc_id]
	if not (entry_value is Dictionary):
		return false
	var entry: Dictionary = entry_value
	var path := str(entry.get("file", ""))
	if path == "":
		path = _pick_pool_dialogue(npc_id, entry)
	if path == "":
		return false

	current_npc_id = npc_id
	_face_player(npc_id)

	var picked: Dictionary = Quest_flow.pick(npc_id, path)
	var dialogue_path := str(picked.get("file", path))
	var after_value: Variant = picked.get("after", {})
	pending_after = after_value if after_value is Dictionary else {"kind": "none"}

	var speakers: Dictionary = Dialogue.load_speakers(SPEAKERS_PATH).get("defs", {})
	var loaded: Dictionary = Dialogue.load_file(dialogue_path, speakers)
	var errors: Array = loaded.get("errors", [])
	if not errors.is_empty():
		for error_text in errors:
			push_warning("town dialogue: %s" % str(error_text))
		current_npc_id = ""
		pending_after = {}
		return false

	pending_encounter = {}
	if entry.has("encounter"):
		var encounter_value: Variant = entry["encounter"]
		if encounter_value is Dictionary:
			var encounter: Dictionary = encounter_value
			pending_encounter = {
				"enemy": str(encounter.get("enemy", npc_id)),
				"count": int(encounter.get("count", 1)),
				"first_strike": bool(encounter.get("first_strike", false)),
			}

	if dialogue_view == null:
		build_hud()
	if dialogue_view == null:
		pending_after = {}
		return false
	var lines: Array = loaded.get("lines", [])
	dialogue_view.call("start", lines)
	if prompt_label != null:
		prompt_label.visible = false
	return true


func _pick_pool_dialogue(npc_id: String, entry: Dictionary) -> String:
	var pool_value: Variant = entry.get("pool", null)
	if not (pool_value is Array):
		return ""
	var pool: Array = pool_value
	if pool.is_empty():
		return ""
	var count := int(GameState.dialogue_counters.get(npc_id, 0))
	GameState.dialogue_counters[npc_id] = count + 1
	return str(pool[count % pool.size()])


func _try_enter_tavern() -> bool:
	if not _near_tavern_door():
		return false
	emit_signal("enter_requested", "tavern")
	return true


func is_in_forest_exit() -> bool:
	return TownData.forest_exit_rect(data).has_point(player_pos)


func _try_enter_forest() -> bool:
	if not is_in_forest_exit():
		return false
	emit_signal("enter_requested", "forest")
	return true


func is_dialogue_active() -> bool:
	return dialogue_view != null and bool(dialogue_view.call("is_active"))


func update_prompt() -> void:
	if prompt_label == null:
		return
	if is_dialogue_active():
		prompt_label.visible = false
		return
	var npc_id: String = nearby_npc()
	if npc_id == "":
		var pickup := _nearest_pickup()
		if not pickup.is_empty():
			prompt_label.text = Pickups.prompt_text(pickup)
			prompt_label.visible = true
			return
		if _near_tavern_door():
			prompt_label.text = "按 E 进入酒馆"
			prompt_label.visible = true
			return
		if is_in_forest_exit():
			prompt_label.text = "按 E 前往紫霞林"
			prompt_label.visible = true
			return
		prompt_label.visible = false
		return
	prompt_label.text = "按 E 与 %s 交谈" % _npc_display_name(npc_id)
	prompt_label.visible = true


func _npc_display_name(npc_id: String) -> String:
	var npcs: Array = data.get("npcs", [])
	for npc_value in npcs:
		if typeof(npc_value) != TYPE_DICTIONARY:
			continue
		var npc: Dictionary = npc_value
		if str(npc.get("id", "")) == npc_id:
			return str(npc.get("name", npc_id))
	return npc_id


func _face_player(npc_id: String) -> void:
	var npc_value: Variant = npc_nodes.get(npc_id, null)
	if not (npc_value is Node3D):
		return
	var npc: Node3D = npc_value
	var dx: float = player_pos.x - npc.position.x
	var dz: float = player_pos.y - npc.position.z
	var facing := "down"
	if absf(dx) >= absf(dz):
		facing = "right" if dx > 0.0 else "left"
	else:
		facing = "down" if dz > 0.0 else "up"
	npc.call("set_facing", facing)


func _on_dialogue_finished() -> void:
	if not pending_encounter.is_empty():
		var encounter: Dictionary = pending_encounter
		pending_encounter = {}
		emit_signal(
			"encounter_requested",
			str(encounter.get("enemy", "")),
			int(encounter.get("count", 1)),
			bool(encounter.get("first_strike", false))
		)
	var after: Dictionary = pending_after
	pending_after = {}
	_apply_quest_after(after)
	current_npc_id = ""
	_refresh_quest_markers()


func _apply_quest_after(after: Dictionary) -> void:
	var kind := str(after.get("kind", "none"))
	var quest_id := str(after.get("quest", ""))
	match kind:
		"start":
			Quests.start(quest_id)
		"turn_in":
			Quests.turn_in(quest_id)
		"talk":
			Quests.notify("talk", str(after.get("key", "")), 1)
		"encounter":
			var encounter_value: Variant = after.get("encounter", {})
			if not (encounter_value is Dictionary):
				return
			var encounter: Dictionary = encounter_value
			emit_signal(
				"encounter_requested",
				str(encounter.get("enemy", "")),
				int(encounter.get("count", 1)),
				bool(encounter.get("first_strike", false))
			)

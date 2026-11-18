extends Node3D

signal exit_requested
signal encounter_requested(enemy_id: String, count: int, first_strike: bool)
signal state_changed(new_state: String)

const DataLoader = preload("res://core/data_loader.gd")

const TAVERN_PATH := DataLoader.TAVERN_PATH
const SPEAKERS_PATH := DataLoader.SPEAKERS_PATH
const CAMERA_OFFSET := Vector3(0.0, 13.0, 30.0)
const LOOK_AHEAD := Vector3(0.0, 1.5, -7.5)
const CAMERA_FOV := 28.0

const TavernArt = preload("res://shared/scenery/tavern/tavern_art.gd")
const TavernLayout = preload("res://shared/scenery/tavern/tavern_layout.gd")
const TavernRoomBuilder = preload("res://shared/scenery/tavern/tavern_room_builder.gd")
const TavernAtmosphereBuilder = preload("res://shared/scenery/tavern/tavern_atmosphere_builder.gd")
const TavernFurnitureBuilder = preload("res://shared/scenery/tavern/tavern_furniture_builder.gd")
const WorldCamera = preload("res://shared/scene/world_camera.gd")
const CharacterSprite = preload("res://shared/scene/character_sprite.gd")
const PlayerMotion = preload("res://shared/gameplay/player_motion.gd")
const Dialogue = preload("res://core/dialogue.gd")
const GameState = preload("res://core/game_state.gd")
const Prefight = preload("res://core/prefight.gd")
const TavernStateAnimation = preload("res://features/tavern/tavern_state_animation.gd")
const TavernFurnitureSystem = preload("res://features/tavern/tavern_furniture_system.gd")
const TavernNpcRoster = preload("res://features/tavern/tavern_npc_roster.gd")
const TavernPrefightShow = preload("res://features/tavern/tavern_prefight_show.gd")
const TavernStoryDirector = preload("res://features/tavern/tavern_story_director.gd")

var data: Dictionary = {}
var room: Dictionary = {}
var blockers: Array = []
var bounds_rect: Rect2 = Rect2()
var camera: Camera3D = null
var follow_target: Node3D = null
var player: Node3D = null
var player_pos: Vector2 = Vector2.ZERO
var dialogue_view: Control = null
var prompt_label: Label = null
var pending_encounter: Dictionary = {}
var current_npc_id: String = ""
var skip_actors: bool = false
var force_state: String = ""
var input_blocked: bool = false
var cutscene_running: bool = false
var exit_rect: Rect2 = Rect2()
var exit_prompt: String = "按 E 走出酒馆"
var arena_origin: Vector3 = Vector3.ZERO

var _furniture: TavernFurnitureSystem = null
var _npcs: TavernNpcRoster = null
var _prefight: TavernPrefightShow = null
var _story: TavernStoryDirector = null
var _animation: TavernStateAnimation = null
var _input_override: Variant = null
var _built: bool = false
var _art: TavernArt = null
var _focus: Vector3 = Vector3.ZERO
var _hud_layer: CanvasLayer = null

var furniture_nodes: Dictionary:
	get:
		return _furniture.nodes if _furniture != null else {}
	set(value):
		if _furniture != null:
			_furniture.nodes = value

var npc_nodes: Dictionary:
	get:
		return _npcs.nodes if _npcs != null else {}
	set(value):
		if _npcs != null:
			_npcs.nodes = value

var _prefight_active: bool:
	get:
		return _prefight.active if _prefight != null else false
	set(value):
		if _prefight != null:
			_prefight.active = value

var _boss_bar: Node3D:
	get:
		return _prefight.boss_bar if _prefight != null else null
	set(value):
		if _prefight != null:
			_prefight.boss_bar = value

var _boss_bar_fill: Sprite3D:
	get:
		return _prefight.boss_bar_fill if _prefight != null else null
	set(value):
		if _prefight != null:
			_prefight.boss_bar_fill = value


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
	_add_action("cycle_tavern_state", KEY_F3, KEY_NONE)


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
	_art = TavernArt.new()
	_load_data()
	_animation = TavernStateAnimation.new()
	_story = TavernStoryDirector.new()
	_story.setup(data)
	_story.set_initial_state(force_state)
	TavernRoomBuilder.build_room(self, room, _art)
	TavernRoomBuilder.build_beams(self, room, _art)
	TavernRoomBuilder.build_wall_decor(self, room, _art)
	var entries: Dictionary = TavernFurnitureSystem.collect_entries(data)
	var furniture: Dictionary = TavernFurnitureBuilder.build_furniture(self, entries, _art)
	TavernRoomBuilder.build_stairs(self, data, _art)
	TavernRoomBuilder.build_windows(self, room, _art)
	TavernAtmosphereBuilder.build_light_shafts(self, room)
	TavernAtmosphereBuilder.build_dust(self)
	TavernAtmosphereBuilder.build_lanterns(self)
	TavernAtmosphereBuilder.build_lighting(self, data)
	_build_camera()
	_furniture = TavernFurnitureSystem.new()
	_furniture.setup(entries, furniture.get("nodes", {}), furniture.get("debris_root", null))
	_npcs = TavernNpcRoster.new()
	_npcs.setup(self, data)
	_prefight = TavernPrefightShow.new()
	_prefight.setup(self)
	_connect_systems()
	_apply_state(_story.state, false, false)
	if not skip_actors:
		_build_player()
		snap_camera()


func _process(delta: float) -> void:
	tick_player(delta)
	advance(delta)
	check_story(delta)
	update_prompt()
	if not is_dialogue_active() and InputMap.has_action("interact") \
			and Input.is_action_just_pressed("interact"):
		try_interact()
	if InputMap.has_action("cycle_tavern_state") \
			and Input.is_action_just_pressed("cycle_tavern_state"):
		_cycle_state()
	update_camera(delta)


# ---------------------------------------------------------------- data

func _load_data() -> void:
	blockers.clear()
	if not FileAccess.file_exists(TAVERN_PATH):
		push_warning("tavern: %s not found" % TAVERN_PATH)
		return
	var text: String = FileAccess.get_file_as_string(TAVERN_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("tavern: invalid JSON in %s" % TAVERN_PATH)
		return
	data = parsed
	var room_value: Variant = data.get("room", {})
	if room_value is Dictionary:
		room = room_value
	var bounds_value: Variant = data.get("bounds", null)
	if bounds_value is Dictionary:
		var bounds: Dictionary = bounds_value
		var bx0 := float(bounds.get("x0", 0.0))
		var bx1 := float(bounds.get("x1", 0.0))
		var bz0 := float(bounds.get("z0", 0.0))
		var bz1 := float(bounds.get("z1", 0.0))
		bounds_rect = Rect2(bx0, bz0, bx1 - bx0, bz1 - bz0)
	var exit_value: Variant = data.get("exit", null)
	if exit_value is Dictionary:
		var exit_data: Dictionary = exit_value
		exit_prompt = str(exit_data.get("prompt", exit_prompt))
		var rect_value: Variant = exit_data.get("rect", null)
		if rect_value is Array:
			var rect: Array = rect_value
			if rect.size() >= 4:
				var ex0 := float(rect[0])
				var ez0 := float(rect[1])
				exit_rect = Rect2(ex0, ez0, float(rect[2]) - ex0, float(rect[3]) - ez0)
	var arena_value: Variant = data.get("arena", null)
	if arena_value is Dictionary:
		var origin_value: Variant = (arena_value as Dictionary).get("origin", null)
		if origin_value is Array:
			var origin: Array = origin_value
			if origin.size() >= 3:
				arena_origin = Vector3(float(origin[0]), float(origin[1]), float(origin[2]))
	for blocker_value in data.get("blockers", []):
		var rect_value: Variant = blocker_value
		if rect_value is Dictionary:
			rect_value = (rect_value as Dictionary).get("rect", [])
		if not (rect_value is Array):
			continue
		var rect: Array = rect_value
		if rect.size() < 4:
			continue
		var x0 := float(rect[0])
		var z0 := float(rect[1])
		var x1 := float(rect[2])
		var z1 := float(rect[3])
		if x1 > x0 and z1 > z0:
			blockers.append(Rect2(x0, z0, x1 - x0, z1 - z0))


func _connect_systems() -> void:
	_story.state_requested.connect(_on_state_requested)
	_story.cutscene_requested.connect(_on_cutscene_requested)
	_story.dialogue_requested.connect(_on_dialogue_requested)
	_story.prefight_requested.connect(_on_prefight_requested)
	_story.encounter_requested.connect(func(enemy_id, count, first_strike):
		emit_signal("encounter_requested", enemy_id, count, first_strike))
	_animation.finished.connect(_story.on_animation_finished)
	_prefight.finished.connect(_story.finish_prefight)


func current_state() -> String:
	return _story.state if _story != null else "normal"


func set_state(new_state: String, animate: bool = false) -> void:
	_story.set_state(new_state, animate, _animation.active)


func _cycle_state() -> void:
	_story.cycle_state(_animation.active)


func bandit_count() -> int:
	return _story.bandit_count()


func check_story(delta: float) -> void:
	_story.check_story(
		delta, player_pos, skip_actors, cutscene_running, is_dialogue_active()
	)


func _on_state_requested(new_state: String, animate: bool, stagger: bool) -> void:
	_apply_state(new_state, animate, stagger)
	emit_signal("state_changed", new_state)
	_story.on_state_applied(_animation.active)


func _on_cutscene_requested(active: bool) -> void:
	input_blocked = active
	cutscene_running = active


func _on_dialogue_requested(path: String) -> void:
	if _play_story_dialogue(path):
		_story.dialogue_started()


func _on_prefight_requested() -> void:
	if _npcs.nodes.get("zixia") == null:
		_story.prefight_unavailable()
		return
	_prefight.begin(Prefight.simulate(_story.bandit_count()), _npcs.nodes)


func _start_boss_challenge() -> bool:
	current_npc_id = "ma_youwei"
	_npcs.face_towards("ma_youwei", player_pos)
	pending_encounter = {}
	if not _story.begin_challenge():
		current_npc_id = ""
		return false
	if prompt_label != null:
		prompt_label.visible = false
	return true


func _play_story_dialogue(path: String) -> bool:
	if dialogue_view == null:
		build_hud()
	if dialogue_view == null:
		return false
	var speakers: Dictionary = Dialogue.load_speakers(SPEAKERS_PATH).get("defs", {})
	var loaded: Dictionary = Dialogue.load_file(path, speakers)
	var errors: Array = loaded.get("errors", [])
	if not errors.is_empty():
		for error_text in errors:
			push_warning("tavern story dialogue: %s" % str(error_text))
		return false
	var lines: Array = loaded.get("lines", [])
	if lines.is_empty():
		return false
	dialogue_view.call("start", lines)
	if prompt_label != null:
		prompt_label.visible = false
	return true


# ---------------------------------------------------------------- helpers

func furniture_target(id: String) -> Transform3D:
	return _furniture.furniture_target(id, _story.state)


func fallen_table_count() -> int:
	return _furniture.fallen_table_count()


# ---------------------------------------------------------------- state changes

func _apply_state(new_state: String, animate: bool, stagger: bool) -> void:
	_animation.begin()
	_furniture.apply_state(new_state, animate, _animation)
	_npcs.apply_state(
		new_state,
		animate,
		stagger,
		skip_actors,
		_story.bandit_count(),
		GameState.has_flag("prefight_done"),
		_animation
	)
	_animation.commit(animate)
	_prefight.sync_state(
		new_state, GameState.has_flag("prefight_done"), _story.bandit_count(), skip_actors
	)


func advance(delta: float) -> void:
	var remaining: float = _animation.advance(delta)
	if remaining <= 0.0:
		return
	if _prefight.active:
		_prefight.advance(remaining)
	else:
		_prefight.advance_popups(remaining)


# ---------------------------------------------------------------- npcs

func npc_target_position(id: String) -> Vector3:
	return _npcs.target_position(id, _story.state)


func nearby_npc() -> String:
	return _npcs.nearby_npc(player_pos)


# ---------------------------------------------------------------- player

func _build_player() -> void:
	var spawn_value: Variant = data.get("spawn", null)
	var px := 11.0
	var pz := 3.5
	var facing := "up"
	if spawn_value is Dictionary:
		var spawn: Dictionary = spawn_value
		px = float(spawn.get("x", px))
		pz = float(spawn.get("z", pz))
		facing = str(spawn.get("facing", facing))
	var override_value: Variant = GameState.tavern_return_pos
	if override_value is Vector2:
		var override_pos: Vector2 = override_value
		GameState.tavern_return_pos = null
		if _spawn_walkable(override_pos):
			px = override_pos.x
			pz = override_pos.y
	var character := CharacterSprite.new()
	character.name = "Player"
	character.setup("ren_xiaoyao")
	character.position = Vector3(px, 0.0, pz)
	character.set_facing(facing)
	add_child(character)
	player = character
	player_pos = Vector2(px, pz)
	follow_target = player


func _spawn_walkable(point: Vector2) -> bool:
	if bounds_rect.size != Vector2.ZERO \
			and not bounds_rect.grow(-PlayerMotion.RADIUS).has_point(point):
		return false
	return not PlayerMotion.blocked(point, blockers)


func is_cutscene_running() -> bool:
	return cutscene_running


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
	var weight: float = 1.0 - exp(-14.0 * delta)
	var next_y: float = lerpf(player.position.y, 0.0, weight)
	player.position = Vector3(player_pos.x, next_y, player_pos.y)
	var facing: String = PlayerMotion.facing_from_input(input, str(player.get("facing")))
	player.call("set_facing", facing)
	player.call("set_moving", input.length() > 0.01)


# ---------------------------------------------------------------- camera

func _build_camera() -> void:
	camera = WorldCamera.build(self, CAMERA_OFFSET, CAMERA_FOV)


func update_camera(delta: float) -> void:
	_focus = WorldCamera.update(
		camera, follow_target, _focus, CAMERA_OFFSET, LOOK_AHEAD, delta, Vector3(11.0, 0.0, 3.5)
	)


func snap_camera() -> void:
	_focus = WorldCamera.snap(camera, follow_target, CAMERA_OFFSET, LOOK_AHEAD, Vector3(11.0, 0.0, 3.5))


# ---------------------------------------------------------------- hud / interaction

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


func is_in_exit() -> bool:
	if exit_rect.size != Vector2.ZERO and exit_rect.has_point(player_pos):
		return true
	var z_front := TavernLayout.room_float(room, "z_front", 6.0)
	return player_pos.y >= z_front - 1.0


func try_interact() -> bool:
	if input_blocked:
		return false
	if is_dialogue_active():
		return false
	var npc_id: String = nearby_npc()
	if npc_id != "" and not _npcs.entry(npc_id).is_empty():
		if _story.state == "brawl" and npc_id == "ma_youwei":
			return _start_boss_challenge()
		var path := _npcs.dialogue_path(npc_id, _story.state)
		if path != "":
			return _start_npc_dialogue(npc_id, path)
	if is_in_exit():
		emit_signal("exit_requested")
		return true
	return false


func _start_npc_dialogue(npc_id: String, path: String) -> bool:
	current_npc_id = npc_id
	_npcs.face_towards(npc_id, player_pos)

	var speakers: Dictionary = Dialogue.load_speakers(SPEAKERS_PATH).get("defs", {})
	var loaded: Dictionary = Dialogue.load_file(path, speakers)
	var errors: Array = loaded.get("errors", [])
	if not errors.is_empty():
		for error_text in errors:
			push_warning("tavern dialogue: %s" % str(error_text))
		current_npc_id = ""
		return false

	pending_encounter = {}
	var entry: Dictionary = _npcs.entry(npc_id)
	var encounter_value: Variant = entry.get("encounter", null)
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
		return false
	var lines: Array = loaded.get("lines", [])
	dialogue_view.call("start", lines)
	if prompt_label != null:
		prompt_label.visible = false
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
	if npc_id != "":
		prompt_label.text = "按 E 与 %s 交谈" % _npcs.display_name(npc_id)
		prompt_label.visible = true
		return
	if is_in_exit():
		prompt_label.text = exit_prompt
		prompt_label.visible = true
		return
	prompt_label.visible = false


func _on_dialogue_finished() -> void:
	if _story.on_dialogue_finished():
		current_npc_id = ""
		return
	if not pending_encounter.is_empty():
		var encounter: Dictionary = pending_encounter
		pending_encounter = {}
		emit_signal(
			"encounter_requested",
			str(encounter.get("enemy", "")),
			int(encounter.get("count", 1)),
			bool(encounter.get("first_strike", false))
		)
	current_npc_id = ""

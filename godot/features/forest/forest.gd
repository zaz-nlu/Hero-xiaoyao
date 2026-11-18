extends Node3D

signal exit_requested(place: String)
signal encounter_requested(enemy_id: String, count: int, first_strike: bool)

const DataLoader = preload("res://core/data_loader.gd")
const CharacterSprite = preload("res://shared/scene/character_sprite.gd")
const PlayerMotion = preload("res://shared/gameplay/player_motion.gd")
const WorldCamera = preload("res://shared/scene/world_camera.gd")
const GameState = preload("res://core/game_state.gd")
const ForestLayout = preload("res://shared/resources/forest_layout.gd")
const ForestArt = preload("res://shared/scenery/forest/forest_art.gd")
const ForestTerrain = preload("res://shared/scenery/forest/forest_terrain.gd")
const ForestVegetation = preload("res://shared/scenery/forest/forest_vegetation.gd")
const ForestLandmarks = preload("res://shared/scenery/forest/forest_landmarks.gd")
const ForestVisuals = preload("res://shared/scenery/forest/forest_visuals.gd")
const ForestPatrol = preload("res://features/forest/forest_patrol.gd")
const ForestAlert = preload("res://features/forest/forest_alert.gd")
const ForestPickups = preload("res://features/forest/forest_pickups.gd")

const FOREST_PATH := DataLoader.FOREST_PATH
const CAMERA_OFFSET := Vector3(0.0, 16.7, 37.5)
# Look slightly north of the player so the characters sit in the lower half of the frame.
const LOOK_AHEAD := Vector3(0.0, 1.0, -4.0)
const CAMERA_FOV := 28.0
const CROUCH_SPEED_MULT := 0.5
const CROUCH_SCALE_Y := 0.8
const CROUCH_TINT := Color(0.8, 0.8, 0.8, 1.0)

var _layout: ForestLayout = ForestLayout.new()
var _art: ForestArt = ForestArt.new()
var _terrain: ForestTerrain = ForestTerrain.new()
var _vegetation: ForestVegetation = ForestVegetation.new()
var _landmarks: ForestLandmarks = ForestLandmarks.new()
var _visuals: ForestVisuals = ForestVisuals.new()
var _patrol: ForestPatrol = ForestPatrol.new()
var _alert: ForestAlert = ForestAlert.new()
var _pickups: ForestPickups = ForestPickups.new()

var data: Dictionary:
	get:
		return _layout.data
var blockers: Array:
	get:
		return _layout.blockers
var bounds_rect: Rect2:
	get:
		return _layout.bounds_rect
var camera: Camera3D = null
var follow_target: Node3D = null
var sun: DirectionalLight3D:
	get:
		return _visuals.sun
var world_env: WorldEnvironment:
	get:
		return _visuals.world_env
var player: Node3D = null
var player_pos: Vector2 = Vector2.ZERO
var dialogue_view: Control = null
var prompt_label: Label = null
var current_npc_id: String = ""
var skip_actors: bool = false
var input_blocked: bool = false
var arena_origin: Vector3:
	get:
		return _layout.arena_origin
var tree_positions: Array[Vector2]:
	get:
		return _layout.tree_positions
var rock_positions: Array[Vector2]:
	get:
		return _layout.rock_positions
var hide_spots: Array:
	get:
		return _layout.hide_spots
var exits: Dictionary:
	get:
		return _layout.exits
var pickups: Array:
	get:
		return _layout.pickups
var chest_node: Node3D:
	get:
		return _pickups.chest_node
var chest_pivot: Node3D:
	get:
		return _pickups.chest_pivot
var chest_sprite: Sprite3D:
	get:
		return _pickups.chest_sprite
var chest_opened: bool:
	get:
		return _pickups.chest_opened
	set(value):
		_pickups.chest_opened = bool(value)
var patrol_groups: Array:
	get:
		return _patrol.groups
var scout: Dictionary:
	get:
		return _patrol.scout
var crouch_hint: Label = null

var _input_override: Variant = null
var _crouch_override: Variant = null
var _built: bool = false
var _time: float = 0.0
var _focus: Vector3 = Vector3.ZERO
var _hud_layer: CanvasLayer = null


func _init() -> void:
	_alert.encounter_requested.connect(_on_alert_encounter)


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
	_add_action("crouch", KEY_SHIFT, KEY_NONE)


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
	_layout.load_data(FOREST_PATH)
	_layout.begin_generation()
	_terrain.build(self, _layout, _art)
	var vegetation_root: Node3D = _vegetation.build(self, _layout, _art)
	_landmarks.build(self, _layout, vegetation_root, _art)
	_visuals.build(self, _layout)
	_build_camera()
	if not skip_actors:
		_build_actors()
		snap_camera()


func _process(delta: float) -> void:
	tick_player(delta)
	advance_patrols(delta)
	advance_chest(delta)
	update_prompt()
	if not is_dialogue_active() and InputMap.has_action("interact") \
			and Input.is_action_just_pressed("interact"):
		try_interact()
	_time += delta
	_landmarks.update_camp_light(_time)
	update_camera(delta)


func _build_actors() -> void:
	_patrol.build(
		self, _layout, _defeated_route_indices(), not GameState.has_flag("scout_defeated")
	)
	_pickups.build_pickups(self, _layout)
	_pickups.build_chest(self, _layout, _art)
	_build_player()


func _defeated_route_indices() -> Array:
	var result: Array = []
	var slots_value: Variant = _layout.data.get("patrol_slots", null)
	if not (slots_value is Dictionary):
		return result
	var slots: Dictionary = slots_value
	var routes_value: Variant = slots.get("routes", [])
	if not (routes_value is Array):
		return result
	var routes: Array = routes_value
	for i in range(routes.size()):
		if GameState.has_flag("patrol_defeated_%d" % i):
			result.append(i)
	return result


# ---------------------------------------------------------------- stealth orchestration

func set_crouch_override(value: Variant) -> void:
	_crouch_override = value


func is_crouching() -> bool:
	if _crouch_override != null:
		return bool(_crouch_override)
	if not InputMap.has_action("crouch"):
		return false
	return Input.is_action_pressed("crouch")


func _in_hide_spot(point: Vector2) -> bool:
	for spot_value in _layout.hide_spots:
		var spot: Dictionary = spot_value
		var pos_value: Variant = spot.get("pos", Vector2.ZERO)
		if not (pos_value is Vector2):
			continue
		var spot_pos: Vector2 = pos_value
		if point.distance_to(spot_pos) <= float(spot.get("radius", 1.8)):
			return true
	return false


func advance_patrols(delta: float) -> void:
	if _patrol.groups.is_empty() and _patrol.scout.is_empty():
		return
	var crouched := is_crouching()
	var in_hide := _in_hide_spot(player_pos)
	if _alert.alerted:
		_patrol.update_view_cones(player_pos, crouched, in_hide, true)
		if not _alert.encounter_sent:
			_alert.tick(delta)
		return
	_patrol.advance_motion(delta, _layout.blockers, _layout.bounds_rect)
	_patrol.update_view_cones(player_pos, crouched, in_hide, false)
	_alert.check_detection(_patrol, player_pos, crouched, in_hide, _layout.blockers)
	if _alert.alerted and not _alert.encounter_sent:
		# The alert timer starts on the frame the player is spotted. Large test
		# ticks can therefore complete the 0.6s delay immediately.
		_alert.tick(delta)


func advance_chest(delta: float) -> void:
	_pickups.advance_chest(delta)


func _nearest_sneak_target() -> Dictionary:
	if _alert.alerted or player == null:
		return {}
	return _alert.nearest_sneak_target(
		_patrol, player_pos, is_crouching(), _in_hide_spot(player_pos), _layout.blockers
	)


func _on_alert_encounter(enemy_id: String, count: int, first_strike: bool) -> void:
	encounter_requested.emit(enemy_id, count, first_strike)


# ---------------------------------------------------------------- camera

func _build_camera() -> void:
	camera = WorldCamera.build(self, CAMERA_OFFSET, CAMERA_FOV)


func _spawn_position() -> Vector3:
	var spawn := _layout.spawn_point()
	return Vector3(spawn.x, 0.0, spawn.y)


func update_camera(delta: float) -> void:
	if camera == null:
		return
	_focus = WorldCamera.update(
		camera, follow_target, _focus, CAMERA_OFFSET, LOOK_AHEAD, delta, _spawn_position()
	)


func snap_camera() -> void:
	if camera == null:
		return
	_focus = WorldCamera.snap(
		camera, follow_target, CAMERA_OFFSET, LOOK_AHEAD, _spawn_position()
	)


# ---------------------------------------------------------------- player

func _build_player() -> void:
	var spawn := _layout.spawn_point()
	var px := spawn.x
	var pz := spawn.y
	var return_value: Variant = GameState.forest_return_pos
	if return_value is Vector2:
		var return_pos: Vector2 = return_value
		if _spawn_walkable(return_pos):
			px = return_pos.x
			pz = return_pos.y
	var character := CharacterSprite.new()
	character.name = "Player"
	character.setup("ren_xiaoyao")
	character.position = Vector3(px, 0.0, pz)
	character.set_facing(str(_layout.spawn.get("facing", "up")))
	add_child(character)
	player = character
	player_pos = Vector2(px, pz)
	follow_target = player


func _spawn_walkable(point: Vector2) -> bool:
	if bounds_rect.size != Vector2.ZERO \
			and not bounds_rect.grow(-PlayerMotion.RADIUS).has_point(point):
		return false
	return not PlayerMotion.blocked(point, blockers)


# 兼容测试与旧调用：边界查询属于 ForestLayout。
func _in_bounds(point: Vector2) -> bool:
	return _layout.in_bounds(point)


func set_input_override(v: Variant) -> void:
	_input_override = v


func get_move_input() -> Vector2:
	if input_blocked or _alert.alerted:
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
	var crouched := is_crouching()
	_update_crouch_visual(crouched)
	if crouched:
		input *= CROUCH_SPEED_MULT
	player_pos = PlayerMotion.step(player_pos, input, delta, blockers, bounds_rect)
	var weight: float = 1.0 - exp(-14.0 * delta)
	var next_y: float = lerpf(player.position.y, 0.0, weight)
	player.position = Vector3(player_pos.x, next_y, player_pos.y)
	var facing: String = PlayerMotion.facing_from_input(input, str(player.get("facing")))
	player.call("set_facing", facing)
	player.call("set_moving", input.length() > 0.01)


func _update_crouch_visual(crouched: bool) -> void:
	var sprite_value: Variant = player.get("sprite")
	if not (sprite_value is Sprite3D):
		return
	var sprite: Sprite3D = sprite_value
	if crouched:
		sprite.scale = Vector3(1.0, CROUCH_SCALE_Y, 1.0)
		sprite.modulate = CROUCH_TINT
	else:
		sprite.scale = Vector3.ONE
		sprite.modulate = Color.WHITE


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

	crouch_hint = Label.new()
	crouch_hint.name = "CrouchHint"
	crouch_hint.text = "Shift 蹲伏"
	crouch_hint.add_theme_font_size_override("font_size", 14)
	crouch_hint.modulate = Color(1.0, 1.0, 1.0, 0.55)
	crouch_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	crouch_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crouch_hint.anchor_left = 0.0
	crouch_hint.anchor_right = 0.0
	crouch_hint.anchor_top = 1.0
	crouch_hint.anchor_bottom = 1.0
	crouch_hint.offset_left = 16.0
	crouch_hint.offset_right = 160.0
	crouch_hint.offset_top = -40.0
	crouch_hint.offset_bottom = -16.0
	crouch_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(crouch_hint)


func is_dialogue_active() -> bool:
	return dialogue_view != null and bool(dialogue_view.call("is_active"))


func exit_at(point: Vector2) -> String:
	for key in exits.keys():
		var entry_value: Variant = exits[key]
		if not (entry_value is Dictionary):
			continue
		var entry: Dictionary = entry_value
		var rect_value: Variant = entry.get("rect", Rect2())
		if not (rect_value is Rect2):
			continue
		var rect: Rect2 = rect_value
		if rect.has_point(point):
			return str(key)
	return ""


func _exit_prompt(place: String) -> String:
	var entry_value: Variant = exits.get(place, null)
	if entry_value is Dictionary:
		var entry: Dictionary = entry_value
		return str(entry.get("prompt", ""))
	return ""


func update_prompt() -> void:
	if prompt_label == null:
		return
	if is_dialogue_active() or _alert.alerted:
		prompt_label.visible = false
		return
	var sneak_target := _nearest_sneak_target()
	if not sneak_target.is_empty():
		prompt_label.text = "按 E 偷袭"
		prompt_label.visible = true
		return
	var pickup := _pickups.nearest(player_pos)
	if not pickup.is_empty():
		prompt_label.text = _pickups.prompt_text(pickup)
		prompt_label.visible = true
		return
	var place := exit_at(player_pos)
	if place != "":
		prompt_label.text = _exit_prompt(place)
		prompt_label.visible = true
		return
	prompt_label.visible = false


func try_interact() -> bool:
	if input_blocked or _alert.alerted:
		return false
	if is_dialogue_active():
		return false
	var sneak_target := _nearest_sneak_target()
	if not sneak_target.is_empty():
		_alert.trigger_sneak(sneak_target, _patrol)
		return true
	var pickup := _pickups.nearest(player_pos)
	if not pickup.is_empty():
		_pickups.collect(pickup)
		return true
	var place := exit_at(player_pos)
	if place != "":
		emit_signal("exit_requested", place)
		return true
	return false


func _on_dialogue_finished() -> void:
	current_npc_id = ""

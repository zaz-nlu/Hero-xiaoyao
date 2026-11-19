extends Node3D

# 探索地图试跑场景（未来也是地图运行场景）。
#
# 直接运行本场景：打开 res://data/layouts/zixia_sect.json。
# 工具试玩变体 res://tools/layout_playtest.tscn 通过 exported map_path 指向
# user://map_editor_playtest.json，不会误改游戏内地图，也不会读旧缓存覆盖正式数据。
#
# 操作：WASD / 方向键移动，E 与弟子、出口或物件触发器互动。
# 触发器分按键（E）与进入感应圈两种；进入只在从圈外走进来时触发一次。
# 试跑模式（playtest_mode）下遭遇/任务/出口只弹确认提示，不写存档；
# 正式模式把遭遇/出口交给 app 调度，任务走现有 Quests。
# 加载失败会在地图上方的状态栏显示具体错误，而不是悄悄留一个空世界。

signal encounter_requested(enemy_id: String, count: int, first_strike: bool)
signal exit_requested(target: String)
signal quest_resolved(quest_id: String, action: String, ok: bool)

const LayoutDocument = preload("res://core/layouts/layout_document.gd")
const LayoutTerrain = preload("res://core/layouts/layout_terrain.gd")
const LayoutBuilder = preload("res://shared/scenery/layouts/layout_builder.gd")
const LayoutEnvironmentBuilder = preload("res://shared/scenery/layouts/layout_environment_builder.gd")
const LayoutTriggerRunner = preload("res://features/layouts/layout_trigger_runner.gd")
const CharacterSprite = preload("res://shared/scene/character_sprite.gd")
const PlayerMotion = preload("res://shared/gameplay/player_motion.gd")
const WorldCamera = preload("res://shared/scene/world_camera.gd")

const CAMERA_OFFSET := Vector3(0.0, 16.7, 37.5)
# Look slightly north of the player so the characters sit in the lower half of the frame.
const LOOK_AHEAD := Vector3(0.0, 1.0, -4.0)
const CAMERA_FOV := 28.0
const INTERACT_RADIUS := 2.6
const MESSAGE_SECONDS := 3.0
# 短步位移：防止卡顿帧直接跨过 0.4 厚的挡墙。
const MAX_SUBSTEP := 0.25
# 隔层互动：高差超过一个台阶多一点就不再触发（不跨高墙互动）。
const MAX_INTERACT_HEIGHT_DIFF := 0.75

@export var map_path: String = "res://data/layouts/zixia_sect.json"
@export var playtest_mode: bool = false

# 正式战斗返回时由 app 传入；位置非法或缺失时退回地图出生点。
var return_position: Variant = null

var document: Dictionary = {}
var catalog: Dictionary = {}
var terrain: Dictionary = {}
var blockers: Array = []
var anchors: Array = []
var trigger_runner: LayoutTriggerRunner = null
var bounds_rect: Rect2 = Rect2()
var camera_clamp_rect: Rect2 = Rect2()
var spawn: Vector2 = Vector2.ZERO
var player: Node3D = null
var player_pos: Vector2 = Vector2.ZERO
var player_height := 0.0
var camera: Camera3D = null

var _built := false
var _failed := false
var _time := 0.0
var _message_until := 0.0
var _focus := Vector3.ZERO
var _hud_layer: CanvasLayer = null
var _map_label: Label = null
var _prompt_label: Label = null
var _status_label: Label = null


func _ready() -> void:
	_register_input_actions()
	_build_hud()
	build()


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
	var loaded := LayoutDocument.load_document(map_path)
	if not bool(loaded.get("ok", false)):
		_show_failure(loaded.get("errors", []))
		return
	document = loaded.get("document", {})
	catalog = loaded.get("catalog", {})
	bounds_rect = LayoutDocument.world_bounds(document)
	camera_clamp_rect = LayoutEnvironmentBuilder.camera_clamp(document)
	spawn = LayoutDocument.spawn_point(document)

	var built := LayoutBuilder.build(self, document, catalog)
	if not bool(built.get("ok", false)):
		_show_failure(built.get("errors", []))
		return
	blockers = built.get("blockers", [])
	anchors = built.get("anchors", [])
	terrain = built.get("terrain", {})
	spawn = _resolve_spawn(spawn)
	player_height = LayoutTerrain.height_at(terrain, spawn)

	_build_lighting()
	LayoutEnvironmentBuilder.build_border(self, document, terrain)
	_build_camera()
	_build_player()
	_setup_triggers()
	_update_heading()
	snap_camera()


func _process(delta: float) -> void:
	if not _built or _failed or player == null:
		return
	# 对话进行中暂停行走；E 只推进/关闭当前对话，不再触发新的触发器。
	if is_dialogue_active():
		if _interact_just_pressed() and trigger_runner != null:
			trigger_runner.advance_dialogue()
		_time += delta
		if _message_until > 0.0 and _time >= _message_until:
			_clear_message()
		update_camera(delta)
		return
	tick_player(delta)
	if trigger_runner != null:
		trigger_runner.update_enter_triggers(player_pos, player_height)
		if is_dialogue_active():
			# 本帧刚由进入感应圈打开对话：同一个按键不能立刻又推进它。
			_time += delta
			update_camera(delta)
			return
	update_prompt()
	if _interact_just_pressed():
		try_interact()
	_time += delta
	if _message_until > 0.0 and _time >= _message_until:
		_clear_message()
	update_camera(delta)


func _interact_just_pressed() -> bool:
	return InputMap.has_action("interact") and Input.is_action_just_pressed("interact")


# ---------------------------------------------------------------- scene setup

func _build_lighting() -> void:
	LayoutEnvironmentBuilder.build_lighting(self, document)


func _build_camera() -> void:
	camera = WorldCamera.build(self, CAMERA_OFFSET, CAMERA_FOV)


func _build_player() -> void:
	var character := CharacterSprite.new()
	character.name = "Player"
	character.setup("ren_xiaoyao")
	character.position = Vector3(spawn.x, player_height, spawn.y)
	character.set_facing("up")
	add_child(character)
	player = character
	player_pos = spawn


# 正式战斗返回的位置可能已经失效；只在仍在地图内且不压阻挡时沿用。
func _resolve_spawn(default_pos: Vector2) -> Vector2:
	if not (return_position is Vector2):
		return default_pos
	var wanted: Vector2 = return_position
	if not bounds_rect.has_point(wanted):
		return default_pos
	for rect_value in blockers:
		var rect: Rect2 = rect_value
		if rect.grow(LayoutDocument.PLAYER_RADIUS).has_point(wanted):
			return default_pos
	return wanted


func _setup_triggers() -> void:
	trigger_runner = LayoutTriggerRunner.new()
	trigger_runner.message.connect(_show_message)
	trigger_runner.encounter_requested.connect(_on_trigger_encounter)
	trigger_runner.exit_requested.connect(_on_trigger_exit)
	trigger_runner.quest_resolved.connect(_on_trigger_quest)
	var ui_parent: Node = _hud_layer if _hud_layer != null else self
	trigger_runner.setup(ui_parent, document, catalog, terrain, playtest_mode)
	trigger_runner.prime_inside(player_pos, player_height)


func document_id() -> String:
	return str(document.get("id", ""))


func is_dialogue_active() -> bool:
	return trigger_runner != null and trigger_runner.dialogue_active()


func _on_trigger_encounter(enemy_id: String, count: int) -> void:
	encounter_requested.emit(enemy_id, count, false)


func _on_trigger_exit(target: String) -> void:
	exit_requested.emit(target)


func _on_trigger_quest(quest_id: String, action: String, ok: bool) -> void:
	quest_resolved.emit(quest_id, action, ok)


func _spawn_position() -> Vector3:
	return Vector3(spawn.x, player_height, spawn.y)


func update_camera(delta: float) -> void:
	if camera == null:
		return
	_focus = WorldCamera.update(
		camera, player, _focus, CAMERA_OFFSET, LOOK_AHEAD, delta, _spawn_position(),
		camera_clamp_rect
	)


func snap_camera() -> void:
	if camera == null:
		return
	_focus = WorldCamera.snap(
		camera, player, CAMERA_OFFSET, LOOK_AHEAD, _spawn_position(), camera_clamp_rect
	)


# ---------------------------------------------------------------- player

func get_move_input() -> Vector2:
	if not InputMap.has_action("move_left") or not InputMap.has_action("move_right") \
			or not InputMap.has_action("move_up") or not InputMap.has_action("move_down"):
		return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


func tick_player(delta: float) -> void:
	if player == null:
		return
	var input := get_move_input()
	player_pos = _advance(player_pos, input, delta)
	player_height = LayoutTerrain.height_at(terrain, player_pos)
	player.position = Vector3(player_pos.x, player_height, player_pos.y)
	var facing: String = PlayerMotion.facing_from_input(input, str(player.get("facing")))
	player.call("set_facing", facing)
	player.call("set_moving", input.length() > 0.01)


# 分短步复用 PlayerMotion 的半径与边界处理，避免一帧位移穿过窄挡墙。
func _advance(pos: Vector2, input: Vector2, delta: float) -> Vector2:
	var move := input
	if move.length() > 1.0:
		move = move.normalized()
	var displacement := move * PlayerMotion.SPEED * delta
	var steps := maxi(1, int(ceil(displacement.length() / MAX_SUBSTEP)))
	var step_delta := delta / float(steps)
	var result := pos
	for i in range(steps):
		result = PlayerMotion.step(result, input, step_delta, blockers, bounds_rect)
	return result


# ---------------------------------------------------------------- interaction

func nearest_anchor() -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	for anchor_value in anchors:
		if not (anchor_value is Dictionary):
			continue
		var anchor: Dictionary = anchor_value
		var pos_value: Variant = anchor.get("pos", null)
		if not (pos_value is Vector2):
			continue
		var distance := player_pos.distance_to(pos_value)
		var radius := float(anchor.get("radius", INTERACT_RADIUS))
		var anchor_height := float(anchor.get("height", player_height))
		if absf(anchor_height - player_height) > MAX_INTERACT_HEIGHT_DIFF:
			continue
		if distance <= radius and distance < best_distance:
			best = anchor
			best_distance = distance
	return best


func update_prompt() -> void:
	if _prompt_label == null:
		return
	if is_dialogue_active():
		_prompt_label.visible = false
		return
	if trigger_runner != null:
		var trigger_prompt := trigger_runner.prompt_for(player_pos, player_height)
		if trigger_prompt != "":
			_prompt_label.text = trigger_prompt
			_prompt_label.visible = true
			return
	var anchor := nearest_anchor()
	if anchor.is_empty():
		_prompt_label.visible = false
		return
	var display := str(anchor.get("name", "?"))
	if str(anchor.get("kind", "")) == "exit":
		_prompt_label.text = "按 E 查看出口：%s" % display
	else:
		_prompt_label.text = "按 E 与 %s 互动" % display
	_prompt_label.visible = true


func try_interact() -> bool:
	# 同一按键只做一件事：对话进行中优先推进/关闭当前对话。
	if is_dialogue_active():
		trigger_runner.advance_dialogue()
		return true
	if trigger_runner != null and trigger_runner.activate_at(player_pos, player_height):
		return true
	var anchor := nearest_anchor()
	if anchor.is_empty():
		return false
	var display := str(anchor.get("name", "?"))
	if str(anchor.get("kind", "")) == "exit":
		_show_message("出口：%s（试跑返回起点）" % display)
		player_pos = spawn
		player_height = LayoutTerrain.height_at(terrain, spawn)
		if player != null:
			player.position = Vector3(spawn.x, player_height, spawn.y)
		return true
	_show_message("[预览] 与 %s 互动（对话待布置）" % display)
	return true


# ---------------------------------------------------------------- hud

func _build_hud() -> void:
	if _hud_layer != null:
		return
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "Hud"
	_hud_layer.layer = 10
	add_child(_hud_layer)

	_map_label = _make_label("MapLabel", 20, Color("#f2e2b0"))
	_map_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_map_label.anchor_left = 0.0
	_map_label.anchor_right = 1.0
	_map_label.anchor_top = 0.0
	_map_label.anchor_bottom = 0.0
	_map_label.offset_left = 16.0
	_map_label.offset_right = -16.0
	_map_label.offset_top = 12.0
	_map_label.offset_bottom = 44.0
	_hud_layer.add_child(_map_label)

	var hint := _make_label("HintLabel", 14, Color(1.0, 1.0, 1.0, 0.6))
	hint.text = "WASD / 方向键 移动    E 互动    每格 2 单位"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.anchor_left = 0.0
	hint.anchor_right = 0.0
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = 16.0
	hint.offset_right = 460.0
	hint.offset_top = -40.0
	hint.offset_bottom = -16.0
	_hud_layer.add_child(hint)

	_prompt_label = _make_label("PromptLabel", 18, Color.WHITE)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt_label.anchor_left = 0.0
	_prompt_label.anchor_right = 1.0
	_prompt_label.anchor_top = 1.0
	_prompt_label.anchor_bottom = 1.0
	_prompt_label.offset_top = -160.0
	_prompt_label.offset_bottom = -110.0
	_prompt_label.visible = false
	_hud_layer.add_child(_prompt_label)

	_status_label = _make_label("StatusLabel", 16, Color("#f2e2b0"))
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_status_label.anchor_left = 0.0
	_status_label.anchor_right = 1.0
	_status_label.anchor_top = 0.0
	_status_label.anchor_bottom = 0.0
	_status_label.offset_left = 24.0
	_status_label.offset_right = -24.0
	_status_label.offset_top = 56.0
	_status_label.offset_bottom = 220.0
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.visible = false
	_hud_layer.add_child(_status_label)


func _make_label(node_name: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color("#202729"))
	label.add_theme_constant_override("outline_size", 5)
	label.modulate = color
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _update_heading() -> void:
	if _map_label == null:
		return
	var display_name := str(document.get("name", map_path))
	var width := int(document.get("width", 0))
	var depth := int(document.get("depth", 0))
	_map_label.text = "%s  ·  %d×%d 格  ·  地图试跑" % [display_name, width, depth]


func _show_message(text: String) -> void:
	if _status_label == null:
		return
	_status_label.text = text
	_status_label.modulate = Color("#f2e2b0")
	_status_label.visible = true
	_message_until = _time + MESSAGE_SECONDS


func _clear_message() -> void:
	_message_until = 0.0
	if _status_label != null and not _failed:
		_status_label.visible = false


func _show_failure(errors: Variant) -> void:
	_failed = true
	var lines: Array[String] = []
	if errors is Array:
		for message in errors:
			lines.append(str(message))
	var text := "地图加载失败：%s" % map_path
	if not lines.is_empty():
		text += "\n" + "\n".join(PackedStringArray(lines))
	if _status_label != null:
		_status_label.text = text
		_status_label.modulate = Color("#ff8a7a")
		_status_label.visible = true
	if _map_label != null:
		_map_label.text = "试跑：加载失败"
	if _prompt_label != null:
		_prompt_label.visible = false
	push_warning(text)

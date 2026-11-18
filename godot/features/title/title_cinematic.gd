extends Control

# 标题页的分镜式背景：若干段平稳的由远及近推镜，镜头之间黑场过渡。
# 可展示的地点随玩家档案（core/profile.gd）逐渐增多。
# 无渲染（headless）环境下不创建 SubViewport / 3D 世界，只跑时间轴与地点名，
# 方便单元测试覆盖镜头逻辑。

const Profile = preload("res://core/profile.gd")
const GameState = preload("res://core/game_state.gd")
const BackdropFactory = preload("res://shared/scenery/backdrop_factory.gd")

const SHOTS_PATH := "res://data/title_shots.json"
const DEFEATED_TOWN_NPC_IDS: Array[String] = ["ma_youwei", "bandit_1", "bandit_2"]

const FADE_TIME := 0.8
const CAPTION_IN_DELAY := 1.0
const CAPTION_IN_TIME := 0.8
const CAPTION_OUT_BEFORE_END := 1.6
const CAPTION_OUT_TIME := 0.8

const CAPTION_GOLD := Color(0.95, 0.8, 0.4)
const CAPTION_SUBTITLE := Color(0.95, 0.92, 0.85)
const CAPTION_FONT_SIZE := 34
const SUBTITLE_FONT_SIZE := 18
const CAPTION_LEFT := 48.0
const CAPTION_BOTTOM := 120.0

var shots: Array = []
var current_index: int = 0
var shot_time: float = 0.0

var _profile_path: String = ""
var _built: bool = false
var _fallback: bool = false
var _shot_end_pending: bool = false
var _active_world: String = ""
var _world_root: Control = null
var _world_containers: Dictionary = {}
var _world_viewports: Dictionary = {}
var _world_cameras: Dictionary = {}
var _world_nodes: Dictionary = {}
var _caption_name: Label = null
var _caption_subtitle: Label = null
var _fade_rect: ColorRect = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_right = 1.0
	anchor_bottom = 1.0


func build(profile_path: String = Profile.PROFILE_PATH) -> void:
	if _built:
		return
	_built = true
	_profile_path = profile_path
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fallback = _is_fallback_environment()

	_world_root = Control.new()
	_world_root.name = "Worlds"
	_world_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_world_root)

	_build_caption()
	_build_fade()

	shots = _filtered_shots()
	current_index = 0
	shot_time = 0.0
	_shot_end_pending = false
	_update_caption_text()
	if not _fallback:
		_activate_current_world()
	_apply_pose()
	_update_caption_alpha()
	_update_fade()


func advance(delta: float) -> void:
	if not _built:
		build()
	if shots.is_empty():
		return
	if _shot_end_pending:
		_shot_end_pending = false
		_advance_shot()
	else:
		shot_time += maxf(0.0, delta)
		var duration := _shot_duration()
		if shot_time >= duration:
			shot_time = duration
			_shot_end_pending = true
	_apply_pose()
	_update_caption_alpha()
	_update_fade()


func skip_to_next() -> void:
	if not _built:
		build()
	if shots.is_empty():
		return
	_advance_shot()


func current_shot() -> Dictionary:
	if current_index < 0 or current_index >= shots.size():
		return {}
	var value: Variant = shots[current_index]
	if value is Dictionary:
		return value
	return {}


func camera_pose() -> Dictionary:
	var shot := current_shot()
	if shot.is_empty():
		return {"pos": Vector3.ZERO, "look": Vector3.ZERO, "fov": 30.0}
	var from_value: Variant = shot.get("from", {})
	var to_value: Variant = shot.get("to", {})
	var from: Dictionary = {}
	if from_value is Dictionary:
		from = from_value
	var to: Dictionary = {}
	if to_value is Dictionary:
		to = to_value
	var from_pos := _vec3(from.get("pos", []), Vector3.ZERO)
	var from_look := _vec3(from.get("look", []), Vector3.ZERO)
	var to_pos := _vec3(to.get("pos", []), from_pos)
	var to_look := _vec3(to.get("look", []), from_look)
	var from_fov := float(from.get("fov", 30.0))
	var to_fov := float(to.get("fov", from_fov))
	var duration := maxf(0.001, _shot_duration())
	var raw := clampf(shot_time / duration, 0.0, 1.0)
	var eased := raw * raw * (3.0 - 2.0 * raw)
	return {
		"pos": from_pos.lerp(to_pos, eased),
		"look": from_look.lerp(to_look, eased),
		"fov": lerpf(from_fov, to_fov, eased),
	}


func fade_alpha() -> float:
	if shots.is_empty():
		return 1.0
	var duration := _shot_duration()
	if shot_time < FADE_TIME:
		return clampf(1.0 - shot_time / FADE_TIME, 0.0, 1.0)
	var remaining := duration - shot_time
	if remaining < FADE_TIME:
		return clampf(1.0 - remaining / FADE_TIME, 0.0, 1.0)
	return 0.0


func caption_text() -> String:
	return str(current_shot().get("caption", ""))


func is_fallback() -> bool:
	return _fallback


# ---------------------------------------------------------------- timeline

func _advance_shot() -> void:
	if shots.is_empty():
		return
	if current_index + 1 >= shots.size():
		_reload_shots()
		current_index = 0
	else:
		current_index += 1
	shot_time = 0.0
	_shot_end_pending = false
	_update_caption_text()
	if not _fallback:
		_activate_current_world()
	_apply_pose()
	_update_caption_alpha()
	_update_fade()


func _reload_shots() -> void:
	var previous := shots
	var reloaded := _filtered_shots()
	if not reloaded.is_empty():
		shots = reloaded
	else:
		shots = previous


func _shot_duration() -> float:
	return maxf(0.001, float(current_shot().get("duration", 11.0)))


func _apply_pose() -> void:
	if _fallback:
		return
	var camera_value: Variant = _world_cameras.get(_active_world, null)
	if not (camera_value is Camera3D):
		return
	var camera: Camera3D = camera_value
	var pose := camera_pose()
	var pos: Vector3 = pose["pos"]
	var look: Vector3 = pose["look"]
	camera.fov = float(pose["fov"])
	camera.look_at_from_position(pos, look, Vector3.UP)


func _update_caption_alpha() -> void:
	if _caption_name == null or _caption_subtitle == null:
		return
	var alpha := 0.0
	if not shots.is_empty():
		var duration := _shot_duration()
		if shot_time >= CAPTION_IN_DELAY:
			alpha = clampf((shot_time - CAPTION_IN_DELAY) / CAPTION_IN_TIME, 0.0, 1.0)
		var out_start := duration - CAPTION_OUT_BEFORE_END
		if shot_time > out_start:
			alpha = minf(alpha, clampf(1.0 - (shot_time - out_start) / CAPTION_OUT_TIME, 0.0, 1.0))
	_caption_name.modulate.a = alpha
	_caption_subtitle.modulate.a = alpha


func _update_fade() -> void:
	if _fade_rect == null:
		return
	_fade_rect.color = Color(0.0, 0.0, 0.0, fade_alpha())


# ---------------------------------------------------------------- shots table

func _filtered_shots() -> Array:
	var unlocked: Array = Profile.unlocked_ids(_profile_path)
	var result: Array = []
	for shot_value in _load_shot_table():
		if not (shot_value is Dictionary):
			continue
		var shot: Dictionary = shot_value
		var place := str(shot.get("place", ""))
		if unlocked.has(place):
			result.append(shot)
	if result.is_empty():
		result.append(_default_shot())
	if not _has_shot(result, "town_far"):
		var town_far := _find_json_shot("town_far")
		if town_far.is_empty():
			town_far = _default_shot()
		result.push_front(town_far)
	return result


func _load_shot_table() -> Array:
	if not FileAccess.file_exists(SHOTS_PATH):
		return []
	var text := FileAccess.get_file_as_string(SHOTS_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return []
	var parsed_dict: Dictionary = parsed
	var value: Variant = parsed_dict.get("shots", [])
	if not (value is Array):
		return []
	var result: Array = value
	return result


func _find_json_shot(id: String) -> Dictionary:
	for shot_value in _load_shot_table():
		if not (shot_value is Dictionary):
			continue
		var shot: Dictionary = shot_value
		if str(shot.get("id", "")) == id:
			return shot
	return {}


func _has_shot(shot_list: Array, id: String) -> bool:
	for shot_value in shot_list:
		if not (shot_value is Dictionary):
			continue
		var shot: Dictionary = shot_value
		if str(shot.get("id", "")) == id:
			return true
	return false


func _default_shot() -> Dictionary:
	return {
		"id": "town_far",
		"place": "town",
		"world": "town",
		"caption": "紫霞镇",
		"subtitle": "清晨",
		"duration": 12.0,
		"from": {
			"pos": [-16.0, 46.0, 66.0],
			"look": [6.0, 1.0, -2.0],
			"fov": 34.0,
		},
		"to": {
			"pos": [8.0, 11.0, 30.0],
			"look": [6.0, 2.5, -2.0],
			"fov": 30.0,
		},
	}


func _vec3(value: Variant, fallback: Vector3) -> Vector3:
	if not (value is Array):
		return fallback
	var array: Array = value
	if array.size() < 3:
		return fallback
	return Vector3(float(array[0]), float(array[1]), float(array[2]))


# ---------------------------------------------------------------- overlays

func _build_caption() -> void:
	_caption_name = Label.new()
	_caption_name.name = "PlaceName"
	_caption_name.anchor_top = 1.0
	_caption_name.anchor_bottom = 1.0
	_caption_name.offset_left = CAPTION_LEFT
	_caption_name.offset_right = CAPTION_LEFT + 640.0
	_caption_name.offset_top = -(CAPTION_BOTTOM + 80.0)
	_caption_name.offset_bottom = -(CAPTION_BOTTOM + 32.0)
	_caption_name.text = ""
	_caption_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_caption_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption_name.add_theme_font_size_override("font_size", CAPTION_FONT_SIZE)
	_caption_name.add_theme_color_override("font_color", CAPTION_GOLD)
	_caption_name.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	_caption_name.add_theme_constant_override("outline_size", 6)
	_caption_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caption_name)

	_caption_subtitle = Label.new()
	_caption_subtitle.name = "PlaceSubtitle"
	_caption_subtitle.anchor_top = 1.0
	_caption_subtitle.anchor_bottom = 1.0
	_caption_subtitle.offset_left = CAPTION_LEFT
	_caption_subtitle.offset_right = CAPTION_LEFT + 640.0
	_caption_subtitle.offset_top = -(CAPTION_BOTTOM + 28.0)
	_caption_subtitle.offset_bottom = -CAPTION_BOTTOM
	_caption_subtitle.text = ""
	_caption_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_caption_subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption_subtitle.add_theme_font_size_override("font_size", SUBTITLE_FONT_SIZE)
	_caption_subtitle.add_theme_color_override("font_color", CAPTION_SUBTITLE)
	_caption_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caption_subtitle)


func _build_fade() -> void:
	_fade_rect = ColorRect.new()
	_fade_rect.name = "Fade"
	_fade_rect.color = Color(0.0, 0.0, 0.0, 1.0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fade_rect)


func _update_caption_text() -> void:
	var shot := current_shot()
	if _caption_name != null:
		_caption_name.text = str(shot.get("caption", ""))
	if _caption_subtitle != null:
		_caption_subtitle.text = str(shot.get("subtitle", ""))


# ---------------------------------------------------------------- worlds

func _is_fallback_environment() -> bool:
	var server_name := DisplayServer.get_name()
	if server_name == "headless" or server_name == "dummy":
		return true
	return get_viewport() == null


func _activate_current_world() -> void:
	if _fallback:
		return
	var world := str(current_shot().get("world", "town"))
	if not _world_containers.has(world):
		_build_world(world)
	_active_world = world
	for key in _world_containers.keys():
		var world_name := str(key)
		var container: SubViewportContainer = _world_containers[key]
		var active := world_name == world
		container.visible = active
		var viewport_value: Variant = _world_viewports.get(world_name, null)
		if viewport_value is SubViewport:
			if active:
				(viewport_value as SubViewport).render_target_update_mode = \
					SubViewport.UPDATE_ALWAYS
			else:
				(viewport_value as SubViewport).render_target_update_mode = \
					SubViewport.UPDATE_DISABLED
	_apply_pose()


func _build_world(world: String) -> void:
	var container := SubViewportContainer.new()
	container.name = "World_%s" % world
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.visible = false
	_world_root.add_child(container)

	var viewport := SubViewport.new()
	viewport.name = "Viewport_%s" % world
	viewport.handle_input_locally = false
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var window := get_viewport()
	if window != null:
		viewport.size = Vector2i(window.get_visible_rect().size)
	else:
		viewport.size = Vector2i(1280, 720)
	container.add_child(viewport)

	var node: Node3D = BackdropFactory.create(world, _backdrop_options(world))
	node.name = "WorldScene_%s" % world
	viewport.add_child(node)
	node.call("build")
	_finish_scene(world, node)

	var camera := Camera3D.new()
	camera.name = "TitleCamera"
	camera.attributes = null
	viewport.add_child(camera)
	camera.current = true

	_world_containers[world] = container
	_world_viewports[world] = viewport
	_world_cameras[world] = camera
	_world_nodes[world] = node


# The backdrop owns display preparation: hide the ambient player, release the
# scene camera, and (tavern) settle on the normal furniture state.
func _finish_scene(world: String, node: Node3D) -> void:
	node.call("prepare_cinematic")
	if world == "tavern":
		node.call("set_state", "normal", false)


# Town keeps its ambient NPCs but runs no quest markers or gameplay actors.
# The caller decides which NPCs the save has already retired, which pickups
# are collected, and where the hidden player anchors NPC stopping.
func _backdrop_options(world: String) -> Dictionary:
	if world != "town":
		return {"skip_actors": true, "cinematic": true}
	var skip_ids: Array = []
	if GameState.has_flag("boss_defeated"):
		skip_ids = DEFEATED_TOWN_NPC_IDS
	var picked_provider := func(flag: String) -> bool:
		return bool(GameState.has_flag(flag))
	var anchor: Variant = null
	var return_pos: Variant = GameState.town_return_pos
	if return_pos is Vector2:
		anchor = return_pos
	return {
		"skip_actors": false,
		"hide_player": true,
		"quest_markers": false,
		"input_blocked": true,
		"cinematic": true,
		"skip_npc_ids": skip_ids,
		"picked_flag_provider": picked_provider,
		"player_anchor": anchor,
	}

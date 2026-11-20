extends Control

# 书生讲故事小场景：紫霞镇茶棚前，任逍遥和镇民围着书生听书。
# 独立的 3D 小场景（SubViewport），不搭建也不改动小镇本身。
# 时间轴完全由 advance(delta) 推进：黑场淡入 1 秒 → 播放对话 → 黑场淡出 0.8 秒 → finished。
# 无渲染（headless / 未入树）环境不创建 SubViewport，只构建节点与时间轴，方便单元测试。

signal finished

const Dialogue = preload("res://core/dialogue.gd")
const DataLoader = preload("res://core/data_loader.gd")
const DialogueView = preload("res://shared/ui/dialogue_view.gd")
const CharacterSprite = preload("res://shared/scene/character_sprite.gd")
const AiAssets = preload("res://shared/resources/ai_assets.gd")
const SceneKit = preload("res://shared/scene/scene_kit.gd")
const Texgen = preload("res://shared/scene/texgen.gd")

const PHASE_FADE_IN := 0
const PHASE_DIALOGUE := 1
const PHASE_FADE_OUT := 2
const PHASE_DONE := 3

const FADE_IN := 1.0
const FADE_OUT := 0.8
const CAMERA_PUSH := 3.0
const CAMERA_FAR := Vector3(0.0, 5.6, 18.0)
const CAMERA_NEAR := Vector3(0.0, 3.4, 10.8)
const CAMERA_LOOK := Vector3(0.0, 1.5, -2.4)
const CAMERA_FOV := 34.0
const DOF_FAR_MARGIN := 14.0
const DOF_FAR_TRANSITION := 22.0
const DOF_NEAR_MARGIN := 9.0
const DOF_NEAR_TRANSITION := 8.0
const DOF_AMOUNT := 0.08

const STORY_CUE := "opening_town"
const REN_ID := "ren_xiaoyao"
const SCHOLAR_Z := -4.0
const CROWD_GAP_DEG := 26.0
const CROWD_STEP_DEG := 19.0
const CROWD_RADIUS_X := 4.6
const CROWD_RADIUS_Z := 3.1
const REN_POS := Vector3(-2.0, 0.0, -1.6)
const BOB_SPEED := 1.6
const BOB_AMPLITUDE := 0.03

const GROUND_TEXTURE := "tex_cobblestone.png"
const GROUND_FALLBACK := "tex_flagstone_large.png"
const GROUND_SIZE := Vector2(44.0, 36.0)
const GROUND_UV_METERS := 3.0

const FACADES := [
	{"file": "facade_general_store.png", "x": -9.0, "width": 7.0, "z": -9.0},
	{"file": "facade_residence.png", "x": -3.0, "width": 6.0, "z": -9.6},
	{"file": "facade_herb_shop.png", "x": 2.7, "width": 5.4, "z": -9.2},
	{"file": "facade_tavern.png", "x": 8.4, "width": 7.0, "z": -9.8},
]

const PROPS := [
	{"file": "prop_tea_stall.png", "height": 4.2, "x": 0.0, "y": 0.0, "z": -6.6},
	{"file": "prop_tea_storyteller_table.png", "height": 1.25, "x": 0.1, "y": 0.0, "z": -5.0},
	{"file": "prop_tea_table.png", "height": 1.0, "x": 4.9, "y": 0.0, "z": -4.6},
	{"file": "prop_tea_flag.png", "height": 2.7, "x": -3.0, "y": 0.0, "z": -5.6},
	{"file": "prop_tea_stool_a.png", "height": 0.75, "x": -5.6, "y": 0.0, "z": -2.4},
	{"file": "prop_tea_stool_b.png", "height": 0.75, "x": 5.9, "y": 0.0, "z": -2.0},
	{"file": "prop_tea_bench.png", "height": 0.7, "x": -4.6, "y": 0.0, "z": -0.6},
	{"file": "town_lanterns_day_red.png", "height": 1.0, "x": -2.2, "y": 2.9, "z": -6.2},
]

var audio: Variant = null
var dialogue_view: DialogueView = null
var actors: Array[Node3D] = []
var scholar: CharacterSprite = null

var _storyteller: Dictionary = {}
var _built: bool = false
var _finished: bool = false
var _fallback: bool = false
var _phase: int = PHASE_FADE_IN
var _phase_time: float = 0.0
var _elapsed: float = 0.0

var _world: Node3D = null
var _camera: Camera3D = null
var _fade_rect: ColorRect = null
var _bob_phases: Array[float] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	if _built and not _finished:
		advance(delta)


func _unhandled_input(event: InputEvent) -> void:
	if _finished:
		return
	if event is InputEventKey:
		var key_event: InputEventKey = event
		if not key_event.pressed or key_event.echo:
			return
		var key := key_event.keycode
		if key == KEY_NONE:
			key = key_event.physical_keycode
		if key == KEY_ESCAPE:
			skip_all()


# ---------------------------------------------------------------- public API

func build(data: Dictionary) -> void:
	if _built:
		return
	_built = true
	_storyteller = _storyteller_of(data)
	_fallback = _is_fallback_environment()
	_build_layers()
	_play_story_cue(data)
	_apply_camera()


func advance(delta: float) -> void:
	if not _built:
		build({})
	if _finished:
		return
	var step := maxf(delta, 0.0)
	_elapsed += step
	_apply_camera()
	_apply_breathing()
	if _phase == PHASE_FADE_IN:
		_phase_time += step
		if _phase_time >= FADE_IN:
			_update_fade()
			_start_dialogue()
		else:
			_update_fade()
	elif _phase == PHASE_FADE_OUT:
		_phase_time += step
		_update_fade()
		if _phase_time >= FADE_OUT:
			_finish()


func skip_all() -> void:
	if not _built:
		build({})
	if _finished:
		return
	_finish()


func is_finished() -> bool:
	return _finished


func is_dialogue_active() -> bool:
	return dialogue_view != null and bool(dialogue_view.is_active())


func camera_position() -> Vector3:
	if _camera == null:
		return Vector3.ZERO
	return _camera.position


# ---------------------------------------------------------------- timeline

func _start_dialogue() -> void:
	_phase = PHASE_DIALOGUE
	_phase_time = 0.0
	var lines := _load_dialogue_lines(str(_storyteller.get("dialogue", "")))
	if lines.is_empty() or dialogue_view == null:
		_begin_fade_out()
		return
	dialogue_view.start(lines)


func _begin_fade_out() -> void:
	if _phase == PHASE_FADE_OUT or _finished:
		return
	_phase = PHASE_FADE_OUT
	_phase_time = 0.0
	_update_fade()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_phase = PHASE_DONE
	if dialogue_view != null:
		dialogue_view.visible = false
	_update_fade()
	finished.emit()


func _on_dialogue_finished() -> void:
	if _phase == PHASE_DIALOGUE:
		_begin_fade_out()


func _fade_alpha() -> float:
	match _phase:
		PHASE_FADE_IN:
			return 1.0 - clampf(_phase_time / FADE_IN, 0.0, 1.0)
		PHASE_FADE_OUT:
			return clampf(_phase_time / FADE_OUT, 0.0, 1.0)
		PHASE_DONE:
			return 1.0
		_:
			return 0.0


func _update_fade() -> void:
	if _fade_rect == null:
		return
	_fade_rect.color = Color(0.0, 0.0, 0.0, _fade_alpha())


func _load_dialogue_lines(path: String) -> Array:
	if path == "" or not FileAccess.file_exists(path):
		return []
	var speakers: Dictionary = Dialogue.load_speakers(DataLoader.SPEAKERS_PATH).get("defs", {})
	var loaded: Dictionary = Dialogue.load_file(path, speakers)
	var errors: Array = loaded.get("errors", [])
	if not errors.is_empty():
		push_warning("opening storyteller dialogue skipped: %s (%s)" % [path, str(errors)])
		return []
	return loaded.get("lines", [])


# ---------------------------------------------------------------- data

func _storyteller_of(data: Dictionary) -> Dictionary:
	var value: Variant = data.get("storyteller", {})
	if value is Dictionary:
		return value
	return {}


func _storyteller_ids() -> Array:
	var value: Variant = _storyteller.get("crowd", [])
	if value is Array:
		return value
	return []


func _play_story_cue(data: Dictionary) -> void:
	var cue := STORY_CUE
	var music_value: Variant = data.get("music", {})
	if music_value is Dictionary:
		var town_cue := str((music_value as Dictionary).get("town", ""))
		if town_cue != "":
			cue = town_cue
	if audio == null or not (audio is Object) or not audio.has_method("play_cue"):
		return
	audio.play_cue(cue)


# ---------------------------------------------------------------- layers

func _build_layers() -> void:
	_build_world()
	_fade_rect = ColorRect.new()
	_fade_rect.name = "Fade"
	_fade_rect.color = Color(0.0, 0.0, 0.0, 1.0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.z_index = 50
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fade_rect)

	dialogue_view = DialogueView.new()
	dialogue_view.name = "Dialogue"
	dialogue_view.build_ui()
	dialogue_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialogue_view.visible = false
	dialogue_view.z_index = 100
	dialogue_view.connect("finished", _on_dialogue_finished)
	add_child(dialogue_view)


func _is_fallback_environment() -> bool:
	var server_name := DisplayServer.get_name()
	if server_name == "headless" or server_name == "dummy":
		return true
	return get_viewport() == null


# ---------------------------------------------------------------- world

func _build_world() -> void:
	_world = Node3D.new()
	_world.name = "World"
	_build_ground()
	_build_backdrop()
	_build_facades()
	_build_props()
	_build_actors()
	_build_lighting()
	_build_camera()
	if _fallback:
		add_child(_world)
		return
	var container := SubViewportContainer.new()
	container.name = "StoryStage"
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(container)
	var viewport := SubViewport.new()
	viewport.name = "StoryViewport"
	viewport.own_world_3d = true
	viewport.handle_input_locally = false
	container.add_child(viewport)
	viewport.add_child(_world)
	var window := get_viewport()
	if window != null:
		viewport.size = Vector2i(window.get_visible_rect().size)
	else:
		viewport.size = Vector2i(1280, 720)
	if _camera != null:
		_camera.current = true


func _build_ground() -> void:
	var tex: ImageTexture = AiAssets.load_texture(GROUND_TEXTURE)
	if tex == null:
		tex = AiAssets.load_texture(GROUND_FALLBACK)
	var uv := Vector2(GROUND_SIZE.x, GROUND_SIZE.y) / GROUND_UV_METERS
	var mat: StandardMaterial3D = Texgen.make_material(tex, uv)
	var plane := PlaneMesh.new()
	plane.size = GROUND_SIZE
	SceneKit.add_mesh(_world, plane, mat, Vector3(0.0, 0.0, -1.0), "Ground")


func _build_backdrop() -> void:  # Sky 在子视口里偶尔只渲出一片灰，垫一层远山保证画面稳定
	var quad := AiAssets.make_wall_quad("bg_mountains.png", 96.0, Vector3(0.0, -4.0, -34.0), "Backdrop")
	if quad != null:
		_world.add_child(quad)


func _build_facades() -> void:
	var root := Node3D.new()
	root.name = "Facades"
	_world.add_child(root)
	for index in range(FACADES.size()):
		var entry: Dictionary = FACADES[index]
		var facade := AiAssets.make_wall_quad(
			str(entry["file"]),
			float(entry["width"]),
			Vector3(float(entry["x"]), 0.0, float(entry["z"])),
			"Facade_%d" % index
		)
		if facade != null:
			root.add_child(facade)


func _build_props() -> void:
	var root := Node3D.new()
	root.name = "Props"
	_world.add_child(root)
	for index in range(PROPS.size()):
		var entry: Dictionary = PROPS[index]
		var sprite := AiAssets.make_sprite(
			str(entry["file"]),
			float(entry["height"]),
			Vector3(
				float(entry.get("x", 0.0)),
				float(entry.get("y", 0.0)),
				float(entry.get("z", 0.0))
			),
			"Prop_%d" % index
		)
		if sprite != null:
			root.add_child(sprite)


func _build_actors() -> void:
	var root := Node3D.new()
	root.name = "Actors"
	_world.add_child(root)
	var scholar_id := str(_storyteller.get("scholar", "scholar"))
	scholar = _make_actor(root, scholar_id, Vector3(0.0, 0.0, SCHOLAR_Z), "down")
	var crowd := _storyteller_ids()
	var left_count := (crowd.size() + 1) / 2
	for index in range(crowd.size()):
		var left_side := index < left_count
		var step := index if left_side else index - left_count
		var angle := deg_to_rad(CROWD_GAP_DEG + float(step) * CROWD_STEP_DEG)
		if left_side:
			angle = -angle
		var pos := Vector3(
			sin(angle) * CROWD_RADIUS_X,
			0.0,
			SCHOLAR_Z + cos(angle) * CROWD_RADIUS_Z
		)
		_make_actor(root, str(crowd[index]), pos, "right" if left_side else "left")
	_make_actor(root, REN_ID, REN_POS, "right")


func _make_actor(root: Node3D, sprite_id: String, base: Vector3, facing: String) -> CharacterSprite:
	var actor: CharacterSprite = CharacterSprite.new()
	actor.name = "Actor_%s_%d" % [sprite_id, actors.size()]
	actor.setup(sprite_id)
	actor.set_facing(facing)
	var drift := _unit_hash(sprite_id)
	var drift_z := _unit_hash(sprite_id + "_z")
	actor.position = base + Vector3((drift - 0.5) * 0.5, 0.0, (drift_z - 0.5) * 0.3)
	root.add_child(actor)
	actors.append(actor)
	_bob_phases.append(drift * TAU)
	return actor


func _unit_hash(text: String) -> float:
	return float(absi(text.hash()) % 1000) / 1000.0


func _apply_breathing() -> void:
	for index in range(actors.size()):
		var actor: Node3D = actors[index]
		if actor == null:
			continue
		actor.position.y = sin(_elapsed * BOB_SPEED + _bob_phases[index]) * BOB_AMPLITUDE


func _build_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-42.0, -34.0, 0.0)
	sun.light_color = Color("#ffd0a0")
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	sun.shadow_bias = 0.05
	_world.add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#8fb0d8")
	sky_mat.sky_horizon_color = Color("#f7dcb4")
	sky_mat.ground_horizon_color = Color("#eed0a8")
	sky_mat.ground_bottom_color = Color("#c8b08a")
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#f0d6b8")
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.1
	env.fog_enabled = true
	env.fog_light_color = Color("#f2e0c4")
	env.fog_density = 0.002
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	_world.add_child(world_env)


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "StoryCamera"
	_camera.fov = CAMERA_FOV
	_camera.attributes = _camera_attributes()
	_world.add_child(_camera)


func _camera_attributes() -> CameraAttributesPractical:
	var attributes := CameraAttributesPractical.new()
	var dist := CAMERA_NEAR.distance_to(CAMERA_LOOK)
	attributes.dof_blur_far_enabled = true
	attributes.dof_blur_far_distance = dist + DOF_FAR_MARGIN
	attributes.dof_blur_far_transition = DOF_FAR_TRANSITION
	attributes.dof_blur_near_enabled = true
	attributes.dof_blur_near_distance = maxf(dist - DOF_NEAR_MARGIN, 0.1)
	attributes.dof_blur_near_transition = DOF_NEAR_TRANSITION
	attributes.dof_blur_amount = DOF_AMOUNT
	return attributes


func _apply_camera() -> void:
	if _camera == null:
		return
	var t := clampf(_elapsed / CAMERA_PUSH, 0.0, 1.0)
	var eased := t * t * (3.0 - 2.0 * t)
	var pos := CAMERA_FAR.lerp(CAMERA_NEAR, eased)
	# 测试里节点可能还没入树；此时用 Transform3D 直接摆位，避免 look_at 的入树要求。
	if _camera.is_inside_tree():
		_camera.look_at_from_position(pos, CAMERA_LOOK, Vector3.UP)
	else:
		_camera.transform = Transform3D(Basis(), pos).looking_at(CAMERA_LOOK, Vector3.UP)

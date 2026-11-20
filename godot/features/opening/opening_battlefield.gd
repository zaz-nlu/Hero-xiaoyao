extends Control

# 序幕 3D 战场背景：按 backdrop 的 seed / palette / density 程序生成士兵混战小场景。
# 同一 seed 的兵种与站位完全一致（所有随机都走同一个 RandomNumberGenerator）。
# 时间由 advance(delta) 推进；headless / 未入树时不创建 SubViewport，只搭节点与逻辑。

const CharacterSprite = preload("res://shared/scene/character_sprite.gd")
const AiAssets = preload("res://shared/resources/ai_assets.gd")
const SceneKit = preload("res://shared/scene/scene_kit.gd")
const Texgen = preload("res://shared/scene/texgen.gd")

const MAX_ACTORS := 90
const PAIRS_CAP := MAX_ACTORS / 4
const PAIR_GAP := 0.9
const PAIR_CENTER := 6.0
const FIGHTER_Z_MIN := -9.0
const FIGHTER_Z_MAX := 4.0
const RANK_Z_MIN := -16.0
const RANK_Z_MAX := -9.5
const RANK_X_NEAR := 1.6
const RANK_X_FAR := 14.0
const SPRINT_AMPLITUDE := 0.35
const SPRINT_PERIOD_MIN := 1.2
const SPRINT_PERIOD_MAX := 2.0
const RANK_BREATH := 0.03

const GROUND_TEXTURE := "tex_battlefield_ground.png"
const GROUND_SIZE := Vector2(64.0, 52.0)
const GROUND_CENTER := Vector3(0.0, 0.0, -4.0)
const GROUND_UV_METERS := 4.0
const SKY_WIDTH := 110.0
const SKY_POS := Vector3(0.0, -6.0, -42.0)

const IMPERIAL_POOL: Array[String] = ["imperial_swordsman", "guard"]
const ENEMY_POOL: Array[String] = ["demon_soldier", "beastman_warrior", "elf_archer"]

const PALETTE_SKY := {
	"ash": "bg_battle_ash.png",
	"dawn": "bg_battle_dawn.png",
	"dusk": "bg_battle_dusk.png",
	"gold": "bg_battle_gold.png",
}

const PALETTE_PRESET := {
	"ash": {
		"light": Color(0.60, 0.64, 0.72), "energy": 0.80,
		"rotation": Vector3(-50.0, -28.0, 0.0),
		"ambient": Color(0.55, 0.58, 0.64), "ambient_energy": 0.55,
		"fog": Color(0.54, 0.55, 0.57), "fog_density": 0.007,
		"sky": Color(0.36, 0.37, 0.39), "ground": Color(0.49, 0.48, 0.44),
	},
	"dawn": {
		"light": Color(1.0, 0.69, 0.44), "energy": 1.35,
		"rotation": Vector3(-16.0, 38.0, 0.0),
		"ambient": Color(1.0, 0.79, 0.63), "ambient_energy": 0.50,
		"fog": Color(0.91, 0.71, 0.53), "fog_density": 0.005,
		"sky": Color(0.85, 0.63, 0.45), "ground": Color(0.56, 0.48, 0.36),
	},
	"dusk": {
		"light": Color(0.78, 0.42, 0.53), "energy": 1.10,
		"rotation": Vector3(-24.0, -52.0, 0.0),
		"ambient": Color(0.63, 0.44, 0.56), "ambient_energy": 0.50,
		"fog": Color(0.48, 0.29, 0.37), "fog_density": 0.008,
		"sky": Color(0.29, 0.16, 0.22), "ground": Color(0.43, 0.35, 0.34),
	},
	"gold": {
		"light": Color(1.0, 0.84, 0.52), "energy": 1.60,
		"rotation": Vector3(-38.0, -20.0, 0.0),
		"ambient": Color(1.0, 0.87, 0.62), "ambient_energy": 0.65,
		"fog": Color(0.85, 0.72, 0.47), "fog_density": 0.004,
		"sky": Color(0.69, 0.54, 0.27), "ground": Color(0.54, 0.45, 0.28),
	},
}

const PROP_HEIGHTS := {
	"prop_battle_flags.png": 3.6,
	"prop_battle_flag_imperial.png": 3.4,
	"prop_battle_flag_demon.png": 3.4,
	"prop_battle_flag_torn.png": 3.0,
	"prop_battle_spears.png": 2.2,
	"prop_battle_shield.png": 1.0,
	"prop_battle_wagon_burning.png": 3.2,
	"prop_battle_ballista.png": 2.6,
	"prop_battle_campfire.png": 1.6,
	"prop_battle_smoke.png": 6.0,
	"prop_battle_pole_fallen.png": 1.2,
}

const CAMERA_FOV := 40.0
const CAMERA_LOOK := Vector3(0.0, 1.6, -2.0)
const CAMERA_START_Y := 6.8
const CAMERA_END_Y := 5.4
const CAMERA_START_Z := 16.0
const CAMERA_END_Z := 12.0
const CAMERA_PAN := 5.0
const DOF_FAR_MARGIN := 16.0
const DOF_FAR_TRANSITION := 24.0
const DOF_NEAR_MARGIN := 10.0
const DOF_NEAR_TRANSITION := 9.0
const DOF_AMOUNT := 0.04

var actors: Array[CharacterSprite] = []
var built: bool = false

var _seed: int = 0
var _palette: String = "ash"
var _pairs: int = 0
var _seconds: float = 1.0
var _elapsed: float = 0.0
var _fallback: bool = false
var _world: Node3D = null
var _camera: Camera3D = null
var _sky_file: String = ""
var _actor_ids: Array[String] = []
var _actor_sides: Array[String] = []
var _actor_base: Array[Vector3] = []
var _actor_fighter: Array[bool] = []
var _actor_phase: Array[float] = []
var _actor_speed: Array[float] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func build(backdrop: Dictionary, seconds: float) -> Node:
	if built:
		return self
	built = true
	_seed = _int_of(backdrop.get("seed", 0))
	_palette = str(backdrop.get("palette", "ash"))
	if not PALETTE_PRESET.has(_palette):
		_palette = "ash"
	_pairs = mini(maxi(1, _int_of(backdrop.get("density", 1))), PAIRS_CAP)
	_seconds = maxf(seconds, 0.001)
	_sky_file = str(PALETTE_SKY.get(_palette, ""))
	_fallback = _is_fallback_environment()
	_build_world()
	_apply_camera()
	return self


func advance(delta: float) -> void:
	if not built:
		return
	_elapsed += maxf(delta, 0.0)
	_apply_motion()
	_apply_camera()


# ---------------------------------------------------------------- accessors

func actor_count() -> int:
	return actors.size()


func pair_count() -> int:
	return _pairs


func sky_file() -> String:
	return _sky_file


func palette() -> String:
	return _palette


func elapsed() -> float:
	return _elapsed


func camera_position() -> Vector3:
	if _camera == null:
		return Vector3.ZERO
	return _camera.position


# 逻辑站位（不含呼吸/冲刺偏移），用于校验同 seed 的确定性。
func actor_snapshot() -> Array:
	var out: Array = []
	for index in range(actors.size()):
		out.append({
			"id": _actor_ids[index],
			"side": _actor_sides[index],
			"position": _actor_base[index],
		})
	return out


func actor_positions() -> Array:
	var out: Array = []
	for actor in actors:
		out.append(actor.position)
	return out


# ---------------------------------------------------------------- world

func _build_world() -> void:
	_world = Node3D.new()
	_world.name = "BattlefieldWorld"
	_build_ground()
	_build_sky()
	_build_props()
	_build_actors()
	_build_lighting()
	_build_camera()
	if _fallback:
		add_child(_world)
		return
	var container := SubViewportContainer.new()
	container.name = "BattleStage"
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(container)
	var viewport := SubViewport.new()
	viewport.name = "BattleViewport"
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
	var mat: Material
	if tex != null:
		mat = Texgen.make_material(tex, GROUND_SIZE / GROUND_UV_METERS)
	else:
		mat = SceneKit.solid_material(_preset_color("ground"))
	var plane := PlaneMesh.new()
	plane.size = GROUND_SIZE
	SceneKit.add_mesh(_world, plane, mat, GROUND_CENTER, "Ground")


func _build_sky() -> void:
	var quad := AiAssets.make_wall_quad(_sky_file, SKY_WIDTH, SKY_POS, "Sky")
	if quad != null:
		_world.add_child(quad)


func _build_props() -> void:
	var root := Node3D.new()
	root.name = "Props"
	_world.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	var flags := 3 + rng.randi_range(0, 3)
	if _palette == "dawn":
		flags = maxi(2, flags - 2)
	elif _palette == "gold":
		flags += 3
	for index in range(flags):
		var roll := rng.randf()
		var file := "prop_battle_flag_imperial.png"
		if roll < 0.25:
			file = "prop_battle_flags.png"
		elif roll < 0.70:
			file = "prop_battle_flag_imperial.png"
		elif roll < 0.92:
			file = "prop_battle_flag_demon.png"
		else:
			file = "prop_battle_flag_torn.png"
		_add_prop(root, file, rng.randf_range(-15.0, 15.0), rng.randf_range(-14.0, 4.0), index)
	var debris := 4 + rng.randi_range(0, 4)
	var debris_files := [
		"prop_battle_spears.png", "prop_battle_shield.png", "prop_battle_pole_fallen.png"
	]
	for index in range(debris):
		var file: String = debris_files[rng.randi_range(0, debris_files.size() - 1)]
		_add_prop(root, file, rng.randf_range(-16.0, 16.0), rng.randf_range(-12.0, 6.0),
			100 + index)
	if _palette == "ash" or _palette == "dusk":
		var wagons := 1 + rng.randi_range(0, 1)
		for index in range(wagons):
			_add_prop(root, "prop_battle_wagon_burning.png", rng.randf_range(-14.0, 14.0),
				rng.randf_range(-12.0, 2.0), 200 + index)
		var smoke := 2 + rng.randi_range(0, 1)
		for index in range(smoke):
			_add_prop(root, "prop_battle_smoke.png", rng.randf_range(-14.0, 14.0),
				rng.randf_range(-16.0, -2.0), 300 + index)
	else:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		_add_prop(root, "prop_battle_ballista.png", side * rng.randf_range(4.0, 12.0),
			rng.randf_range(-10.0, 0.0), 400)


func _add_prop(root: Node3D, file: String, x: float, z: float, index: int) -> void:
	var height := float(PROP_HEIGHTS.get(file, 2.0))
	var node: Sprite3D = AiAssets.make_sprite(
		file, height, Vector3(x, 0.0, z), "Prop_%d_%s" % [index, file.get_basename()]
	)
	if node != null:
		root.add_child(node)


func _build_actors() -> void:
	var root := Node3D.new()
	root.name = "Actors"
	_world.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed + 7919
	for index in range(_pairs):
		var z := rng.randf_range(FIGHTER_Z_MIN, FIGHTER_Z_MAX)
		var center := rng.randf_range(-PAIR_CENTER, PAIR_CENTER)
		var imperial := str(IMPERIAL_POOL[rng.randi_range(0, IMPERIAL_POOL.size() - 1)])
		var enemy := str(ENEMY_POOL[rng.randi_range(0, ENEMY_POOL.size() - 1)])
		_make_actor(root, imperial, Vector3(center - PAIR_GAP * 0.5, 0.0, z),
			"right", "imperial", true, rng)
		_make_actor(root, enemy, Vector3(center + PAIR_GAP * 0.5, 0.0, z),
			"left", "enemy", true, rng)
	for index in range(_pairs * 2):
		var imperial_side := index % 2 == 0
		var dist := rng.randf_range(RANK_X_NEAR, RANK_X_FAR)
		var z := rng.randf_range(RANK_Z_MIN, RANK_Z_MAX)
		var pool: Array = IMPERIAL_POOL if imperial_side else ENEMY_POOL
		var sprite_id := str(pool[rng.randi_range(0, pool.size() - 1)])
		var x := -dist if imperial_side else dist
		var facing := "right" if imperial_side else "left"
		var side := "imperial" if imperial_side else "enemy"
		_make_actor(root, sprite_id, Vector3(x, 0.0, z), facing, side, false, rng)


func _make_actor(root: Node3D, sprite_id: String, base: Vector3, facing: String,
		side: String, fighter: bool, rng: RandomNumberGenerator) -> void:
	var actor: CharacterSprite = CharacterSprite.new()
	actor.name = "Actor_%02d_%s" % [actors.size(), sprite_id]
	actor.setup(sprite_id)
	# 人数多时只保留 CharacterSprite 自带的 blob 阴影，关闭逐角色方向光投影。
	if actor.sprite != null:
		actor.sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	actor.set_facing(facing)
	actor.position = base
	root.add_child(actor)
	actors.append(actor)
	_actor_ids.append(sprite_id)
	_actor_sides.append(side)
	_actor_base.append(base)
	_actor_fighter.append(fighter)
	_actor_phase.append(rng.randf_range(0.0, TAU))
	if fighter:
		_actor_speed.append(TAU / rng.randf_range(SPRINT_PERIOD_MIN, SPRINT_PERIOD_MAX))
	else:
		_actor_speed.append(rng.randf_range(0.8, 1.4))


func _apply_motion() -> void:
	for index in range(actors.size()):
		var actor := actors[index]
		if actor == null or not is_instance_valid(actor):
			continue
		var base: Vector3 = _actor_base[index]
		var phase := _elapsed * _actor_speed[index] + _actor_phase[index]
		if _actor_fighter[index]:
			var toward := 1.0 if _actor_sides[index] == "imperial" else -1.0
			actor.position = base + Vector3(toward * SPRINT_AMPLITUDE * sin(phase), 0.0, 0.0)
		else:
			actor.position = base + Vector3(0.0, sin(phase) * RANK_BREATH, 0.0)


func _build_lighting() -> void:
	var preset: Dictionary = PALETTE_PRESET[_palette]
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	var rotation: Vector3 = preset["rotation"]
	sun.rotation_degrees = rotation
	sun.light_color = preset["light"]
	sun.light_energy = float(preset["energy"])
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	sun.shadow_bias = 0.05
	_world.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = preset["sky"]
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = preset["ambient"]
	env.ambient_light_energy = float(preset["ambient_energy"])
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.fog_enabled = true
	env.fog_light_color = preset["fog"]
	env.fog_density = float(preset["fog_density"])
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	_world.add_child(world_env)


# ---------------------------------------------------------------- camera

func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "BattleCamera"
	_camera.fov = CAMERA_FOV
	_camera.attributes = _camera_attributes()
	_world.add_child(_camera)


func _camera_attributes() -> CameraAttributesPractical:
	var attributes := CameraAttributesPractical.new()
	var dist := Vector3(CAMERA_PAN, CAMERA_START_Y, CAMERA_START_Z).distance_to(CAMERA_LOOK)
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
	var t := clampf(_elapsed / _seconds, 0.0, 1.0)
	var eased := t * t * (3.0 - 2.0 * t)
	var direction := 1.0 if (_seed % 2) == 0 else -1.0
	var start := Vector3(-CAMERA_PAN * direction, CAMERA_START_Y, CAMERA_START_Z)
	var finish := Vector3(CAMERA_PAN * direction, CAMERA_END_Y, CAMERA_END_Z)
	var pos := start.lerp(finish, eased)
	# 纯横移：目标点随相机一起平移（不转向），天空面板两侧就不会露边。
	var look := Vector3(pos.x, CAMERA_LOOK.y, CAMERA_LOOK.z)
	# 测试里节点可能还没入树；此时用 Transform3D 直接摆位，避免 look_at 的入树要求。
	if _camera.is_inside_tree():
		_camera.look_at_from_position(pos, look, Vector3.UP)
	else:
		_camera.transform = Transform3D(Basis(), pos).looking_at(look, Vector3.UP)


# ---------------------------------------------------------------- helpers

func _is_fallback_environment() -> bool:
	var server_name := DisplayServer.get_name()
	if server_name == "headless" or server_name == "dummy":
		return true
	return get_viewport() == null


func _preset_color(key: String) -> Color:
	var preset: Dictionary = PALETTE_PRESET[_palette]
	return preset[key]


func _int_of(value: Variant) -> int:
	if value is int or value is float:
		return int(value)
	return 0

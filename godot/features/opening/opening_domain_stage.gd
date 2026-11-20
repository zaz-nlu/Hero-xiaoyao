extends Control

# 序章战后演出（3D 舞台，由 opening_backdrop 的 "domain" 背景挂载）：
#   stage = "recover"：东方阳连续击倒东方云与索尔，二人倒地后泛着绿光瞬间复原，一次又一次；
#   stage = "domain" ：东方阳展开「帝王世纪」——调用 shared/scene/emperor_century 的 3D 演出控制器
#                      （领域展开、重力压制、无形切割），小人只在显示层受压。
# 无渲染（headless / 未入树）环境不创建 SubViewport，但仍构建节点与控制器，时间轴照常推进，方便测试。
# 时间完全由 advance(delta) 推进。

const CharacterSprite = preload("res://shared/scene/character_sprite.gd")
const AiAssets = preload("res://shared/resources/ai_assets.gd")
const SceneKit = preload("res://shared/scene/scene_kit.gd")
const Texgen = preload("res://shared/scene/texgen.gd")
const Controller = preload("res://shared/scene/emperor_century/emperor_century_controller.gd")

const CYCLE := 2.6
const DOMAIN_START := 0.3
const GROUND_TEXTURE := "tex_battlefield_ground.png"
const SKY := "bg_battle_dusk.png"
const CAMERA_BASE := Vector3(0.0, 7.0, 22.0)
const CAMERA_LOOK := Vector3(0.5, 1.6, -1.0)
const CAMERA_FOV := 40.0
const YANG_POS := Vector3(-2.8, 0.0, 0.5)
const YUN_POS := Vector3(1.8, 0.0, -0.3)
const SOL_POS := Vector3(4.2, 0.0, -1.0)
const HIT_TINT := Color(1.7, 0.55, 0.55)
const REGEN_TINT := Color(1.5, 1.9, 1.5)

var stage_kind: String = "recover"
var elapsed: float = 0.0
var seconds: float = 8.0
var controller: Node3D = null

var _world: Node3D = null
var _camera: Camera3D = null
var _figures: Dictionary = {}
var _fired: Dictionary = {}
var _fov_scale: float = 1.0
var _shake: Vector3 = Vector3.ZERO
var _flash: ColorRect = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true


func build(backdrop: Dictionary, p_seconds: float) -> void:
	stage_kind = str(backdrop.get("stage", "recover"))
	seconds = maxf(p_seconds, 0.001)
	_world = Node3D.new()
	_world.name = "World"
	_build_scene()
	controller = Controller.new()
	controller.name = "EmperorCentury"
	controller.auto_process = false
	_world.add_child(controller)
	controller.camera_changed.connect(_on_camera)
	var server := DisplayServer.get_name()
	if server == "headless" or server == "dummy" or get_viewport() == null:
		add_child(_world)
	else:
		var container := SubViewportContainer.new()
		container.stretch = true
		container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(container)
		var viewport := SubViewport.new()
		viewport.own_world_3d = true
		viewport.handle_input_locally = false
		viewport.size = Vector2i(get_viewport().get_visible_rect().size)
		container.add_child(viewport)
		viewport.add_child(_world)
		_camera.current = true
	_flash = ColorRect.new()
	_flash.color = Color(1.0, 0.96, 0.82, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_flash)
	_place_camera()


func advance(delta: float) -> void:
	elapsed += maxf(delta, 0.0)
	if _world == null:
		return
	if stage_kind == "domain":
		_run_domain(delta)
	else:
		_run_recover()
	_apply_pose()
	_place_camera()


func figure(id: String) -> Node3D:
	return _figures.get(id, {}).get("node", null)


func effect_count() -> int:
	return controller.vfx_node_count() if controller != null else 0


# ---------------------------------------------------------------- recover

func _run_recover() -> void:
	var p := fmod(elapsed, CYCLE) / CYCLE
	var cycle := int(elapsed / CYCLE)
	var yang: Dictionary = _figures["yang"]
	yang["lunge"] = 0.9 * sin(clampf(p / 0.3, 0.0, 1.0) * PI) if p < 0.3 else 0.0
	var down := 0.0
	if p >= 0.1 and p < 0.55:
		down = clampf((p - 0.1) / 0.12, 0.0, 1.0)
	elif p >= 0.55 and p < 0.8:
		down = 1.0 - clampf((p - 0.55) / 0.22, 0.0, 1.0)
	for id in ["yun", "sol"]:
		var fig: Dictionary = _figures[id]
		fig["fall"] = down
		var tint := Color.WHITE.lerp(Color(0.5, 0.5, 0.56), down)
		if p >= 0.1 and p < 0.2:
			tint = HIT_TINT
		if p >= 0.55 and p < 0.82:
			tint = Color.WHITE.lerp(REGEN_TINT, 0.5 + 0.5 * sin(elapsed * 22.0))
		fig["tint"] = tint
	if p >= 0.06 and not _fired.has("cut%d" % cycle):
		_fired["cut%d" % cycle] = true
		_pulse(yang)


func _pulse(fig: Dictionary) -> void:
	fig["tint"] = Color(1.5, 1.4, 1.0)


# ---------------------------------------------------------------- domain

func _run_domain(delta: float) -> void:
	if elapsed >= DOMAIN_START and not _fired.has("open"):
		_fired["open"] = true
		var targets: Array = [figure("yun"), figure("sol")]
		var points: Array = [YUN_POS, SOL_POS]
		controller.open_domain(YANG_POS, points, {"targets": targets, "radius": 8.0, "dim_amount": 0.18})
	if controller.state_name() != "inactive":
		controller.advance(delta)
	var white := clampf((elapsed - (seconds - 1.0)) / 0.9, 0.0, 1.0)
	_flash.color.a = white * white
	var yang: Dictionary = _figures["yang"]
	yang["tint"] = Color.WHITE.lerp(Color(1.4, 1.25, 0.9), 0.4 + 0.4 * sin(elapsed * 5.0)) if elapsed > 0.8 else Color.WHITE


# ---------------------------------------------------------------- 搭建

func _build_scene() -> void:
	var ground_tex: ImageTexture = AiAssets.load_texture(GROUND_TEXTURE)
	var plane := PlaneMesh.new()
	plane.size = Vector2(80.0, 60.0)
	SceneKit.add_mesh(_world, plane, Texgen.make_material(ground_tex, Vector2(16.0, 12.0)),
		Vector3(0.0, 0.0, -4.0), "Ground")
	var sky := AiAssets.make_wall_quad(SKY, 110.0, Vector3(0.0, -2.0, -26.0), "Sky")
	if sky != null:
		_world.add_child(sky)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30.0, -40.0, 0.0)
	sun.light_color = Color("#ff9a6a")
	sun.light_energy = 1.0
	_world.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#2a1a22")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#caa090")
	env.ambient_light_energy = 0.6
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_world.add_child(world_env)
	_camera = Camera3D.new()
	_camera.fov = CAMERA_FOV
	_world.add_child(_camera)
	_figures = {
		"yang": _make_figure("dongfang_yang", YANG_POS, "right", 2.0),
		"yun": _make_figure("dongfang_yun", YUN_POS, "left", 2.0),
		"sol": _make_figure("sol_demon_king", SOL_POS, "left", 2.5),
	}


func _make_figure(sprite_id: String, pos: Vector3, facing: String, scale_value: float) -> Dictionary:
	var actor: Node3D = CharacterSprite.new()
	actor.call("setup", sprite_id)
	actor.call("set_facing", facing)
	actor.position = pos
	actor.scale = Vector3.ONE * scale_value
	_world.add_child(actor)
	return {"node": actor, "base": pos, "lunge": 0.0, "fall": 0.0, "tint": Color.WHITE, "scale": scale_value}


# 倒地 = 绕 Z 轴躺倒；受击/复原用精灵染色表现。帝王世纪期间由控制器管理受压，这里不动位置以外的东西。
func _apply_pose() -> void:
	for id in _figures.keys():
		var fig: Dictionary = _figures[id]
		var node: Node3D = fig["node"]
		var base: Vector3 = fig["base"]
		var side := 1.0 if id == "yang" else -1.0
		node.position = Vector3(base.x + side * float(fig["lunge"]), base.y, base.z)
		if stage_kind == "recover":
			node.rotation.z = float(fig["fall"]) * PI * 0.5 * (-1.0 if id != "yang" else 0.0)
		var sprite: Sprite3D = node.get_node_or_null("Sprite") as Sprite3D
		if sprite != null:
			sprite.modulate = fig["tint"]
		node.call("_sync_lying")


func _place_camera() -> void:
	if _camera == null:
		return
	_camera.fov = CAMERA_FOV * _fov_scale
	var pos := CAMERA_BASE + Vector3(_shake.x, _shake.y, 0.0)
	if _camera.is_inside_tree():
		_camera.look_at_from_position(pos, CAMERA_LOOK, Vector3.UP)
	else:
		_camera.transform = Transform3D(Basis(), pos).looking_at(CAMERA_LOOK, Vector3.UP)


func _on_camera(effect: Dictionary) -> void:
	_fov_scale = float(effect.get("fov_scale", 1.0))
	_shake = effect.get("shake", Vector3.ZERO)

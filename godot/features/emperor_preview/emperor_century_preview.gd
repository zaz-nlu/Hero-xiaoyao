extends Node3D

# 帝王世纪独立预览场景（不接入 app/game.gd）：
#   godot --path godot res://features/emperor_preview/emperor_century_preview.tscn
# 快捷键：
#   1 完整 8 秒演出   2 只播领域展开   3 只播重力压制   4 只播自动切割
#   5 直接进入常驻领域   6 关闭领域   7 规则层驱动的自动切割（对敌人）   Esc 取消并清理
#   [ / ]  领域半径 -/+     - / =  演出速度 -/+     Q / E  旋转相机
# 左上角面板显示生命周期状态、阶段、时间、特效节点数。

const CharacterSprite = preload("res://shared/scene/character_sprite.gd")
const Controller = preload("res://shared/scene/emperor_century/emperor_century_controller.gd")

const CAMERA_BASE := Vector3(0.0, 13.0, 15.0)
const FOV_BASE := 40.0

var controller: Node3D = null
var camera: Camera3D = null
var emperor: Node3D = null
var enemies: Array = []
var radius: float = 7.0
var speed: float = 1.0

var _panel: Label = null
var _log: Array = []
var _yaw: float = 0.0
var _shake: Vector3 = Vector3.ZERO
var _fov_scale: float = 1.0


func _ready() -> void:
	_build_world()
	controller = Controller.new()
	controller.name = "EmperorCentury"
	add_child(controller)
	controller.audio_event.connect(_on_audio)
	controller.camera_changed.connect(_on_camera)
	controller.phase_changed.connect(func(p: String) -> void: _note("phase → " + p))
	controller.state_changed.connect(func(s: String) -> void: _note("state → " + s))
	_build_panel()
	_note("按 1 播放完整演出，Esc 清理")


func _process(_delta: float) -> void:
	if camera != null:
		camera.fov = FOV_BASE * _fov_scale
		_place_camera()
	if _panel != null:
		_panel.text = _status()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not (event as InputEventKey).pressed:
		return
	var key: int = (event as InputEventKey).keycode
	match key:
		KEY_1: _start({})
		KEY_2: _start({"only_phase": "expansion"})
		KEY_3: _start({"only_phase": "gravity"})
		KEY_4: _start({"only_phase": "slash"})
		KEY_5:
			_start({})
			controller.activate_domain()
		KEY_6: controller.close_domain()
		KEY_7: controller.play_auto_cut(enemies, {})
		KEY_ESCAPE: controller.cleanup()
		KEY_BRACKETLEFT: _set_radius(radius - 1.0)
		KEY_BRACKETRIGHT: _set_radius(radius + 1.0)
		KEY_MINUS: _set_speed(speed - 0.25)
		KEY_EQUAL: _set_speed(speed + 0.25)
		KEY_Q: _yaw -= PI * 0.25
		KEY_E: _yaw += PI * 0.25


func _start(options: Dictionary) -> void:
	var o := {"radius": radius, "targets": enemies, "speed": speed}
	o.merge(options)
	var points: Array = []
	for enemy in enemies:
		points.append((enemy as Node3D).position)
	controller.open_domain(emperor.position, points, o)


func _set_radius(value: float) -> void:
	radius = clampf(value, 3.0, 14.0)
	if controller.state_name() != "inactive":
		controller.update_domain_cells([emperor.position + Vector3(radius - 1.2, 0, 0)])


func _set_speed(value: float) -> void:
	speed = clampf(value, 0.25, 3.0)
	controller.set_speed(speed)


func _on_audio(id: String, _at: Vector3) -> void:
	_note("sfx: " + id)


func _on_camera(effect: Dictionary) -> void:
	_fov_scale = float(effect.get("fov_scale", 1.0))
	_shake = effect.get("shake", Vector3.ZERO)


func _place_camera() -> void:
	var base := CAMERA_BASE.rotated(Vector3.UP, _yaw)
	camera.position = base + Vector3(_shake.x, _shake.y, 0.0)
	camera.look_at(Vector3(0.0, 0.8, 0.0), Vector3.UP)


func _note(text: String) -> void:
	_log.append(text)
	while _log.size() > 6:
		_log.pop_front()


func _status() -> String:
	var head := "帝王世纪预览   状态: %s   阶段: %s   时间: %.1f/%.1f s" % [
		controller.state_name(), controller.current_phase(), controller.time, controller.total_duration()]
	var stats := "特效节点: %d   半径: %.1f   速度: x%.2f   受压单位: %d" % [
		controller.vfx_node_count(), radius, speed, controller.pressed_count()]
	var help := "1 完整  2 展开  3 重力  4 切割  5 常驻  6 关闭  7 战斗切割  Esc 取消  [ ] 半径  - = 速度  Q/E 转镜头"
	return head + "\n" + stats + "\n" + "\n".join(PackedStringArray(_log)) + "\n\n" + help


func _build_world() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60.0, 60.0)
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	var noise := NoiseTexture2D.new()
	noise.noise = FastNoiseLite.new()
	noise.width = 512
	noise.height = 512
	noise.seamless = true
	material.albedo_texture = noise
	material.albedo_color = Color(0.45, 0.38, 0.30)
	material.uv1_scale = Vector3(6.0, 6.0, 1.0)
	ground.material_override = material
	add_child(ground)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	sun.light_energy = 1.1
	add_child(sun)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.1, 0.09, 0.13)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.68, 0.75)
	env.ambient_light_energy = 0.7
	environment.environment = env
	add_child(environment)
	camera = Camera3D.new()
	camera.fov = FOV_BASE
	add_child(camera)
	_place_camera()
	emperor = _unit("dongfang_yang", Vector3(0.0, 0.0, 1.5), "down")
	for entry in [["bandit", Vector3(-4.0, 0.0, -3.0)], ["bandit", Vector3(3.5, 0.0, -3.5)],
			["dongfang_yun", Vector3(-2.0, 0.0, -5.5)], ["sol_demon_king", Vector3(2.0, 0.0, -6.0)]]:
		enemies.append(_unit(str(entry[0]), entry[1], "down"))


func _unit(sprite_id: String, pos: Vector3, facing: String) -> Node3D:
	var unit: Node3D = CharacterSprite.new()
	unit.setup(sprite_id)
	unit.set_facing(facing)
	unit.position = pos
	add_child(unit)
	return unit


func _build_panel() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	_panel = Label.new()
	_panel.position = Vector2(14.0, 10.0)
	_panel.add_theme_font_size_override("font_size", 15)
	_panel.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7))
	_panel.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_panel.add_theme_constant_override("outline_size", 4)
	layer.add_child(_panel)
	add_child(layer)

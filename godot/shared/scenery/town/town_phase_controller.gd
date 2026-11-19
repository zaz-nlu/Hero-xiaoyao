extends Node

# 小镇昼夜控制器：把时段预设写到太阳/环境/天空/雾，并切换带 meta 的道具与路灯。
# 场景搭建方负责创建并调用 setup()；按 N 键循环切换（调试入口）。

const GameState = preload("res://core/game_state.gd")
const TownPhase = preload("res://core/town_phase.gd")
const AiAssets = preload("res://shared/resources/ai_assets.gd")

const LAMP_ENERGY := 1.6
const LAMP_COLOR := Color("#ffb860")
const LAMP_RANGE := 7.0
const FADE_TIME := 1.5

var sun: DirectionalLight3D = null
var env: Environment = null
var mountain_backdrop: MeshInstance3D = null
var scene_root: Node3D = null

var _sky_mat: ProceduralSkyMaterial = null
var _phase: String = TownPhase.PHASES[0]
var _tween: Tween = null
var _switch_applied := false


func setup(
	sun_node: DirectionalLight3D,
	environment: Environment,
	mountain: MeshInstance3D,
	root: Node3D
) -> void:
	sun = sun_node
	env = environment
	mountain_backdrop = mountain
	scene_root = root
	_sky_mat = null
	if env != null and env.sky != null:
		var material: Material = env.sky.sky_material
		if material is ProceduralSkyMaterial:
			_sky_mat = material as ProceduralSkyMaterial


func current_phase() -> String:
	return _phase


func apply_phase(p: String, animate := false) -> void:
	var target := p if TownPhase.is_valid(p) else TownPhase.PHASES[0]
	if animate and is_inside_tree():
		_start_transition(TownPhase.preset(_phase), TownPhase.preset(target), target)
		return
	_stop_tween()
	_phase = target
	_apply_preset(TownPhase.preset(target))


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event: InputEventKey = event
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode != KEY_N and key_event.physical_keycode != KEY_N:
		return
	var target := TownPhase.next(_phase)
	apply_phase(target, true)
	GameState.town_phase = target


func _start_transition(from_preset: Dictionary, to_preset: Dictionary, target: String) -> void:
	_stop_tween()
	_switch_applied = false
	_tween = create_tween()
	_tween.tween_method(
		_lerp_step.bind(from_preset, to_preset, target), 0.0, 1.0, FADE_TIME
	)
	_tween.tween_callback(_finish_transition.bind(to_preset, target))


func _lerp_step(
	weight: float, from_preset: Dictionary, to_preset: Dictionary, target: String
) -> void:
	var blended := TownPhase.lerp_preset(from_preset, to_preset, weight)
	_apply_atmosphere(blended)
	if not _switch_applied and weight >= 0.5:
		_switch_applied = true
		_phase = target
		_apply_scene_switches(blended)


func _finish_transition(to_preset: Dictionary, target: String) -> void:
	_phase = target
	_apply_preset(to_preset)
	_tween = null


func _stop_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _apply_preset(p: Dictionary) -> void:
	_apply_atmosphere(p)
	_apply_scene_switches(p)


func _apply_atmosphere(p: Dictionary) -> void:
	if sun != null:
		var sun_rotation: Vector3 = p["sun_rotation"]
		var sun_color: Color = p["sun_color"]
		sun.rotation_degrees = sun_rotation
		sun.light_color = sun_color
		sun.light_energy = float(p["sun_energy"])
	if env != null:
		env.ambient_light_energy = float(p["ambient_energy"])
		var fog_color: Color = p["fog_color"]
		env.fog_light_color = fog_color
	if _sky_mat != null:
		var sky_top: Color = p["sky_top"]
		var sky_horizon: Color = p["sky_horizon"]
		var sky_ground_horizon: Color = p["sky_ground_horizon"]
		var sky_ground_bottom: Color = p["sky_ground_bottom"]
		_sky_mat.sky_top_color = sky_top
		_sky_mat.sky_horizon_color = sky_horizon
		_sky_mat.ground_horizon_color = sky_ground_horizon
		_sky_mat.ground_bottom_color = sky_ground_bottom


func _apply_scene_switches(p: Dictionary) -> void:
	_apply_phase_visibility(_phase)
	_apply_lamps(bool(p["lamps_on"]))
	_apply_mountain(str(p["mountain"]))


func _apply_phase_visibility(phase: String) -> void:
	if scene_root != null:
		_set_phase_visible(scene_root, phase)


func _set_phase_visible(node: Node, phase: String) -> void:
	if node is Node3D and node.has_meta("phase"):
		var target := node as Node3D
		match str(node.get_meta("phase")):
			"night":
				target.visible = phase == "night"
			"both":
				target.visible = true
			_:
				target.visible = phase != "night"
	for child in node.get_children():
		_set_phase_visible(child, phase)


func _apply_lamps(on: bool) -> void:
	if scene_root != null:
		_set_lamp_lights(scene_root, on)


func _set_lamp_lights(node: Node, on: bool) -> void:
	if node is Node3D and node.has_meta("night_light"):
		for child in node.get_children():
			if child is OmniLight3D:
				var light := child as OmniLight3D
				light.light_energy = LAMP_ENERGY if on else 0.0
				if on:
					light.light_color = LAMP_COLOR
					light.omni_range = LAMP_RANGE
	for child in node.get_children():
		_set_lamp_lights(child, on)


func _apply_mountain(file: String) -> void:
	if mountain_backdrop == null or file == "":
		return
	var texture: ImageTexture = AiAssets.load_texture(file)
	if texture == null:
		return
	var material: Material = mountain_backdrop.material_override
	if material is StandardMaterial3D:
		var standard := material as StandardMaterial3D
		standard.albedo_texture = texture

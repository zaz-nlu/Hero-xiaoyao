extends Node3D

# 战旗 3D 舞台：与 2D 版 TacticsBoard 接口一致（build / set_state / cell_clicked /
# cell_hovered / cell_inspected），可直接替换。负责环境光、相机、地块、演员与特效的组装和鼠标拾取。

signal cell_clicked(cell: Vector2i)
signal cell_hovered(cell: Vector2i)
signal cell_inspected(cell: Vector2i)

const TacticsTheme = preload("res://features/tactics/tactics_theme.gd")
const StageTiles = preload("res://features/tactics/tactics_stage_tiles.gd")
const StageUnits = preload("res://features/tactics/tactics_stage_units.gd")
const StageFx = preload("res://features/tactics/tactics_stage_fx.gd")
const Picker = preload("res://features/tactics/tactics_picker.gd")
const StageCamera = preload("res://features/tactics/tactics_stage_camera.gd")
const StageOrbit = preload("res://features/tactics/tactics_stage_orbit.gd")
const StageShellFade = preload("res://features/tactics/tactics_stage_shell_fade.gd")
const AiAssets = preload("res://shared/resources/ai_assets.gd")
const SceneKit = preload("res://shared/scene/scene_kit.gd")

const VIGNETTE_SHADER := """
shader_type canvas_item;

uniform float vignette_strength = 0.45;

void fragment() {
	vec2 uv = SCREEN_UV - vec2(0.5);
	float d = length(uv);
	float v = smoothstep(0.32, 0.85, d);
	COLOR = vec4(0.0, 0.0, 0.0, v * vignette_strength);
}
"""

var battle: Variant = null
var tiles: Variant = null
var units: Variant = null
var fx: Variant = null
var camera: Camera3D = null
var backdrop: String = "tavern"
var ui_controls: Array = []

var _theme: Dictionary = {}
var _hover: Vector2i = Vector2i(-1, -1)
var _focus := Vector3(0.0, StageCamera.FOCUS_HEIGHT, 0.0)
var _cam_dir := Vector3(0.0, 0.74, 0.66)
var _cam_distance := 40.0
var _compose := Vector3.ZERO
var _orbit: Variant = StageOrbit.new()
var _shell_fade: Variant = null
var _built := false


func build(p_battle, p_backdrop: String = "") -> void:
	if p_battle == null:
		return
	if p_backdrop != "":
		backdrop = p_backdrop
	if _built and p_battle == battle:
		return
	_clear()
	battle = p_battle
	_theme = TacticsTheme.for_backdrop(backdrop)
	_build_environment()
	tiles = StageTiles.new()
	tiles.name = "Tiles"
	add_child(tiles)
	tiles.build(battle.grid, _theme)
	units = StageUnits.new()
	units.name = "Units"
	add_child(units)
	units.build(battle, tiles)
	fx = StageFx.new()
	fx.name = "Fx"
	add_child(fx)
	fx.setup(battle, tiles, units)
	_build_shell()
	_build_camera()
	_built = true


func set_backdrop(backdrop_id: String) -> void:
	if backdrop_id == "" or backdrop_id == backdrop:
		return
	backdrop = backdrop_id
	if _built and battle != null:
		var current = battle
		battle = null
		_built = false
		build(current)


func set_state(p_battle, p_overlays: Dictionary = {}) -> void:
	if p_battle == null:
		return
	if p_battle != battle or not _built:
		build(p_battle)
	battle = p_battle
	var overlays := p_overlays.duplicate()
	var active := Vector2i(-1, -1)
	var actor = p_battle.get_unit(str(p_battle.current_actor))
	if actor != null and actor.is_alive():
		active = actor.pos
	overlays["active"] = active
	if tiles != null:
		tiles.set_highlights(overlays)
	if units != null:
		units.sync(p_battle)
	if fx != null:
		fx.set_battle(p_battle)


func show_events(events: Array, context: Dictionary = {}) -> void:
	if fx != null:
		fx.show_events(events, context)


func cell_center(cell: Vector2i) -> Vector3:
	if tiles == null:
		return Vector3.ZERO
	return tiles.cell_center(cell)


# Q/E 旋转视角：direction=+1 顺时针、-1 逆时针，每次 90°，平滑过渡后停在 90° 倍数。
func rotate_view(direction: int) -> void:
	if camera == null or battle == null:
		return
	_orbit.rotate(direction)
	if not is_inside_tree():
		_orbit.snap()
		if _shell_fade != null:
			_shell_fade.snap(_orbit.direction())
	_update_composition()
	_position_camera()


func view_yaw() -> float:
	return _orbit.current_yaw()


func view_yaw_target() -> float:
	return fposmod(_orbit.target_deg, 360.0)


func view_direction() -> Vector3:
	return _orbit.direction()


func _process(delta: float) -> void:
	if camera == null or battle == null or tiles == null:
		return
	var turning: bool = _orbit.advance(delta)
	var board_center := Vector3(0.0, StageCamera.FOCUS_HEIGHT, 0.0)
	var desired := board_center
	var actor = battle.get_unit(str(battle.current_actor))
	if actor != null and actor.is_alive():
		desired += (tiles.cell_center(actor.pos) - board_center) * StageCamera.FOLLOW_WEIGHT
		desired.y = StageCamera.FOCUS_HEIGHT
	_focus = _focus.lerp(desired, 1.0 - exp(-2.0 * delta))
	if turning:
		_update_composition()
	_position_camera()
	if _shell_fade != null:
		_shell_fade.update(_orbit.direction(), delta)


func _unhandled_input(event: InputEvent) -> void:
	if battle == null or tiles == null or camera == null:
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _point_on_ui(motion.position):
			return
		var cell: Vector2i = Picker.cell_at_screen(
			camera, motion.position, battle.grid, tiles)
		if cell != _hover:
			_hover = cell
			tiles.set_hover(cell)
			cell_hovered.emit(cell)
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if not button.pressed:
			return
		if _point_on_ui(button.position):
			return
		var cell: Vector2i = Picker.cell_at_screen(
			camera, button.position, battle.grid, tiles)
		if cell.x < 0 or cell.y < 0:
			return
		if button.button_index == MOUSE_BUTTON_RIGHT:
			cell_inspected.emit(cell)
		elif button.button_index == MOUSE_BUTTON_LEFT:
			cell_clicked.emit(cell)


func _point_on_ui(pos: Vector2) -> bool:
	for raw in ui_controls:
		if raw is Control and is_instance_valid(raw):
			var control := raw as Control
			if control.visible and control.get_global_rect().has_point(pos):
				return true
	var viewport := get_viewport()
	if viewport != null:
		var hovered := viewport.gui_get_hovered_control()
		if hovered != null and hovered.mouse_filter == Control.MOUSE_FILTER_STOP:
			return true
	return false


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = _theme.get("bg_color", Color(0.06, 0.05, 0.07))
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = _theme.get(
		"ambient_color", Color(0.42, 0.34, 0.26))
	env.ambient_light_energy = float(_theme.get("ambient_energy", 0.7))
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = _theme.get("fog_color", Color(0.08, 0.06, 0.08))
	env.fog_density = float(_theme.get("fog_density", 0.004))
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = float(_theme.get("glow_intensity", 0.35))
	env.glow_bloom = float(_theme.get("glow_bloom", 0.08))
	var world := WorldEnvironment.new()
	world.name = "StageEnvironment"
	world.environment = env
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.name = "StageSun"
	sun.light_color = _theme.get("sun_color", Color(1.0, 0.86, 0.66))
	sun.light_energy = float(_theme.get("sun_energy", 1.5))
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 80.0
	sun.rotation_degrees = _theme.get(
		"sun_rotation", Vector3(-52.0, -38.0, 0.0))
	add_child(sun)


func _build_shell() -> void:
	if battle == null or battle.grid == null:
		return
	var board_w := float(battle.grid.width) * TacticsTheme.CELL_SIZE
	var board_d := float(battle.grid.height) * TacticsTheme.CELL_SIZE
	_build_ground(board_w, board_d)
	if str(_theme.get("shell", "")) == "forest":
		_build_forest_ring(board_w, board_d)
	else:
		_build_tavern_shell(board_w, board_d)
	_build_vignette()
	_shell_fade = StageShellFade.new()
	_shell_fade.setup(self, battle.grid)


func _build_vignette() -> void:
	SceneKit.build_vignette(self, VIGNETTE_SHADER)
	var layer := get_node_or_null("Vignette")
	if layer is CanvasLayer:
		(layer as CanvasLayer).layer = -1


func _build_ground(board_w: float, board_d: float) -> void:
	var file := str(_theme.get("shell_wall", "tex_aged_plaster.png"))
	var floor_table: Dictionary = _theme.get("top", {})
	var floor_file := str(floor_table.get("floor", file))
	var ground_tint: Color = _theme.get(
		"ground_tint", Color(0.52, 0.42, 0.34))
	var mat := _texture_material(floor_file, Vector2(8.0, 8.0), ground_tint)
	var ground_w := board_w + 10.0
	var ground_d := board_d + 10.0
	var quad := QuadMesh.new()
	quad.size = Vector2(ground_w, ground_d)
	var ground := MeshInstance3D.new()
	ground.name = "ShellGround"
	ground.mesh = quad
	ground.material_override = mat
	ground.rotation.x = -PI / 2.0
	ground.position = Vector3(0.0, -0.36, 0.0)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)

	# 地板外围的深色木边框。
	var border_tint: Color = _theme.get(
		"border_tint", Color(0.40, 0.30, 0.24))
	var border_mat := _texture_material(
		str(_theme.get("shell_beam", "tex_dark_wood.png")), Vector2(3.0, 1.0),
		border_tint)
	var edge_x := ground_w * 0.5 - 0.15
	var edge_z := ground_d * 0.5 - 0.15
	_add_box(self, Vector3(ground_w, 0.06, 0.3), border_mat,
		Vector3(0.0, -0.33, edge_z), "GroundBorderFront")
	_add_box(self, Vector3(ground_w, 0.06, 0.3), border_mat,
		Vector3(0.0, -0.33, -edge_z), "GroundBorderBack")
	_add_box(self, Vector3(0.3, 0.06, ground_d), border_mat,
		Vector3(edge_x, -0.33, 0.0), "GroundBorderRight")
	_add_box(self, Vector3(0.3, 0.06, ground_d), border_mat,
		Vector3(-edge_x, -0.33, 0.0), "GroundBorderLeft")


func _build_tavern_shell(board_w: float, board_d: float) -> void:
	var shell := Node3D.new()
	shell.name = "TavernShell"
	add_child(shell)
	var wall_h := float(_theme.get("wall_height", 6.4))
	var side_h := float(_theme.get("side_wall_height", 1.2))
	var wall_tint: Color = _theme.get("wall_tint", Color(0.62, 0.54, 0.46))
	var beam_tint: Color = _theme.get("beam_tint", Color(0.58, 0.48, 0.40))
	var wall_mat := _texture_material(
		str(_theme.get("shell_wall", "tex_aged_plaster.png")), Vector2(4.0, 2.0),
		wall_tint)
	var beam_mat := _texture_material(
		str(_theme.get("shell_beam", "tex_dark_wood.png")), Vector2(1.0, 1.0),
		beam_tint)
	var back_z := -board_d * 0.5 - 1.2
	var side_x := board_w * 0.5 + 1.2

	# 剖开的房间：后墙完整，左右只留约 1.2 高的矮墙，前面无墙。
	_add_box(shell, Vector3(board_w + 8.0, wall_h, 0.8), wall_mat,
		Vector3(0.0, wall_h * 0.5, back_z), "ShellBack")
	_add_box(shell, Vector3(0.8, side_h, board_d + 3.2), wall_mat,
		Vector3(-side_x, side_h * 0.5, 0.0), "ShellLeft")
	_add_box(shell, Vector3(0.8, side_h, board_d + 3.2), wall_mat,
		Vector3(side_x, side_h * 0.5, 0.0), "ShellRight")
	_add_box(shell, Vector3(1.0, 0.14, board_d + 3.2), beam_mat,
		Vector3(-side_x, side_h + 0.07, 0.0), "SideCapLeft")
	_add_box(shell, Vector3(1.0, 0.14, board_d + 3.2), beam_mat,
		Vector3(side_x, side_h + 0.07, 0.0), "SideCapRight")

	# 后墙的深色木梁。
	var columns := 4
	for i in range(columns):
		var x := -board_w * 0.5 + float(i) * board_w / float(columns - 1)
		_add_box(shell, Vector3(0.22, wall_h, 0.18), beam_mat,
			Vector3(x, wall_h * 0.5, back_z + 0.46), "BeamCol%d" % i)
	_add_box(shell, Vector3(board_w + 1.4, 0.28, 0.2), beam_mat,
		Vector3(0.0, wall_h - 0.35, back_z + 0.46), "BeamTop")

	# 后墙上的亮窗：暖色自发光加木质窗框与十字窗棂。
	var window_mat := SceneKit.emissive_material(Color(1.0, 0.80, 0.48), 1.1)
	for i in range(3):
		var x := (float(i) - 1.0) * board_w * 0.28
		_add_box(shell, Vector3(1.5, 1.3, 0.12), window_mat,
			Vector3(x, 3.5, back_z + 0.48), "Window%d" % i)
		_add_box(shell, Vector3(1.72, 0.1, 0.16), beam_mat,
			Vector3(x, 4.2, back_z + 0.5), "WinTop%d" % i)
		_add_box(shell, Vector3(1.72, 0.1, 0.16), beam_mat,
			Vector3(x, 2.8, back_z + 0.5), "WinBottom%d" % i)
		_add_box(shell, Vector3(0.08, 1.3, 0.16), beam_mat,
			Vector3(x, 3.5, back_z + 0.53), "WinBar%d" % i)

	# 墙灯与悬在棋盘上方的灯笼（暖色主光）。
	var lamp_mat := SceneKit.emissive_material(Color(1.0, 0.68, 0.36), 2.2)
	_add_box(shell, Vector3(board_w + 2.0, 0.24, 0.24), beam_mat,
		Vector3(0.0, 6.3, -1.0), "CeilingBeam")
	for i in range(2):
		var x := (float(i) * 2.0 - 1.0) * board_w * 0.36
		_add_box(shell, Vector3(0.3, 0.5, 0.3), lamp_mat,
			Vector3(x, 2.2, back_z + 0.7), "WallLamp%d" % i)
		SceneKit.add_omni_light(shell, Vector3(x, 2.2, back_z + 1.2),
			Color(1.0, 0.70, 0.38), 10.0, 1.4)
	for i in range(3):
		var x := (float(i) - 1.0) * board_w * 0.3
		_add_box(shell, Vector3(0.05, wall_h - 4.6, 0.05), beam_mat,
			Vector3(x, (wall_h + 4.4) * 0.5, -1.0), "LanternCord%d" % i)
		_add_box(shell, Vector3(0.32, 0.5, 0.32), lamp_mat,
			Vector3(x, 4.4, -1.0), "Lantern%d" % i)
		SceneKit.add_omni_light(shell, Vector3(x, 4.2, -0.6),
			Color(1.0, 0.72, 0.40), 16.0, 2.0)


func _build_forest_ring(board_w: float, board_d: float) -> void:
	var ring := Node3D.new()
	ring.name = "ForestRing"
	add_child(ring)
	var count := 18
	var radius := maxf(board_w, board_d) * 0.5 + 4.5
	for i in range(count):
		var angle := TAU * float(i) / float(count)
		var pos := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		var file := "prop_willow.png" if i % 3 != 0 else "tree_camphor.png"
		var height := 6.0 + float(i % 4)
		var sprite = AiAssets.make_sprite(file, height, pos, "Ring%d" % i)
		if sprite != null:
			sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
			ring.add_child(sprite)


func _build_camera() -> void:
	var board_w := 12.0
	var board_d := 10.0
	if battle != null and battle.grid != null:
		board_w = float(battle.grid.width) * TacticsTheme.CELL_SIZE
		board_d = float(battle.grid.height) * TacticsTheme.CELL_SIZE
	_cam_dir = _orbit.direction()
	_cam_distance = StageCamera.initial_distance(board_w, board_d)
	_focus = Vector3(0.0, StageCamera.FOCUS_HEIGHT, 0.0)
	camera = Camera3D.new()
	camera.name = "StageCamera"
	camera.fov = StageCamera.CAM_FOV
	camera.near = 0.1
	camera.far = 500.0
	add_child(camera)
	_update_composition()
	camera.attributes = StageCamera.dof_attributes(_cam_distance)
	_position_camera()
	if camera.is_inside_tree():
		camera.current = true
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_on_viewport_resized):
		viewport.size_changed.connect(_on_viewport_resized)


func _on_viewport_resized() -> void:
	_update_composition()
	if camera != null:
		camera.attributes = StageCamera.dof_attributes(_cam_distance)
	_position_camera()


# 按屏幕可用区域计算相机距离与横向/纵向构图偏移。
func _update_composition() -> void:
	_cam_dir = _orbit.direction()
	_compose = Vector3.ZERO
	var viewport := get_viewport()
	if viewport == null or battle == null or battle.grid == null:
		return
	var board_w := float(battle.grid.width) * TacticsTheme.CELL_SIZE
	var board_d := float(battle.grid.height) * TacticsTheme.CELL_SIZE
	var framed: Dictionary = StageCamera.framing(
		viewport.get_visible_rect().size, board_w, board_d,
		float(_theme.get("wall_height", 6.4)), _cam_dir, _orbit.yaw_deg)
	if not bool(framed.get("ok", false)):
		return
	_cam_distance = float(framed["distance"])
	_compose = framed["compose"]


func _position_camera() -> void:
	if camera == null:
		return
	var pos := StageCamera.camera_position(
		_focus, _cam_dir, _cam_distance, _compose)
	var target := StageCamera.camera_target(_focus, _compose)
	camera.position = pos
	if camera.is_inside_tree():
		camera.look_at(target, Vector3.UP)
	else:
		var direction := target - pos
		if direction.length() > 0.001:
			camera.transform = Transform3D(
				Basis.looking_at(direction, Vector3.UP), pos)


func _add_box(
	parent: Node3D, size: Vector3, mat: Material, pos: Vector3, node_name: String
) -> MeshInstance3D:
	var node := SceneKit.add_box(parent, size, mat, pos, node_name)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return node


func _texture_material(
	file: String, uv_scale: Vector2 = Vector2.ONE, tint: Color = Color.WHITE
) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var texture: Texture2D = AiAssets.load_texture(file)
	if texture != null:
		mat.albedo_texture = texture
	mat.albedo_color = tint
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.texture_repeat = true
	mat.uv1_scale = Vector3(uv_scale.x, uv_scale.y, 1.0)
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.metallic_specular = 0.0
	return mat


func _clear() -> void:
	for child in get_children():
		remove_child(child)
		if is_inside_tree():
			child.queue_free()
		else:
			child.free()
	tiles = null
	units = null
	fx = null
	camera = null
	_hover = Vector2i(-1, -1)
	_orbit.reset()

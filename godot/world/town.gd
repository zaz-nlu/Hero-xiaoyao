extends Node3D

signal encounter_requested(enemy_id: String, count: int, first_strike: bool)

const TOWN_PATH := "res://data/town.json"
const NPC_DIALOGUES_PATH := "res://data/npc_dialogues.json"
const SPEAKERS_PATH := "res://data/speakers.json"
const CAMERA_OFFSET := Vector3(0.0, 13.0, 17.0)
const DEFEATED_NPC_IDS: Array[String] = ["ma_youwei", "bandit_1", "bandit_2"]

const TownData = preload("res://world/town_data.gd")
const Texgen = preload("res://world/texgen.gd")
const CharacterSprite = preload("res://world/character_sprite.gd")
const PlayerMotion = preload("res://world/player_motion.gd")
const Dialogue = preload("res://core/dialogue.gd")
const GameState = preload("res://core/game_state.gd")
const Interaction = preload("res://world/interaction.gd")

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

var data: Dictionary = {}
var blockers: Array = []
var npc_nodes: Dictionary = {}
var npc_dialogues: Dictionary = {}
var camera: Camera3D = null
var follow_target: Node3D = null
var sun: DirectionalLight3D = null
var world_env: WorldEnvironment = null
var player: Node3D = null
var player_pos: Vector2 = Vector2.ZERO
var bounds_rect: Rect2 = Rect2()
var dialogue_view: Control = null
var prompt_label: Label = null
var pending_encounter: Dictionary = {}
var current_npc_id: String = ""
var skip_actors: bool = false

var _input_override: Variant = null
var _built: bool = false
var _textures: Dictionary = {}
var _water_material: StandardMaterial3D = null
var _banners: Array[Node3D] = []
var _banner_phases: Array[float] = []
var _time: float = 0.0
var _focus: Vector3 = Vector3.ZERO
var _hud_layer: CanvasLayer = null


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
	var loaded: Dictionary = TownData.load_town(TOWN_PATH)
	data = loaded["data"]
	var errors: Array = loaded["errors"]
	for error_text in errors:
		push_warning("town: %s" % str(error_text))
	blockers = TownData.footprints(data)
	bounds_rect = _read_bounds()
	_build_ground()
	_build_buildings()
	_build_props()
	_build_stairs()
	_build_backdrop()
	_build_lighting()
	_build_camera()
	npc_dialogues = Interaction.load_npc_dialogues(NPC_DIALOGUES_PATH)
	if not skip_actors:
		_build_npcs()
		_build_player()
		snap_camera()


func _process(delta: float) -> void:
	tick_player(delta)
	update_prompt()
	if not is_dialogue_active() and InputMap.has_action("interact") \
			and Input.is_action_just_pressed("interact"):
		try_interact()
	_time += delta
	if _water_material != null:
		_water_material.uv1_offset.x += 0.05 * delta
	for i in range(_banners.size()):
		var banner: Node3D = _banners[i]
		if not is_instance_valid(banner):
			continue
		var phase: float = _banner_phases[i]
		banner.rotation.y = sin(_time * TAU / 3.0 + phase) * deg_to_rad(6.0)
	update_camera(delta)


# ---------------------------------------------------------------- helpers

func _get_tex(key: String) -> ImageTexture:
	if _textures.has(key):
		var cached: ImageTexture = _textures[key]
		return cached
	var img: Image
	match key:
		"grass":
			img = Texgen.grass()
		"stone_street":
			img = Texgen.stone_street()
		"step_stone":
			img = Texgen.step_stone()
		"wood_planks":
			img = Texgen.wood_planks()
		"plaster":
			img = Texgen.plaster()
		"roof_tiles":
			img = Texgen.roof_tiles()
		"water":
			img = Texgen.water()
		"door":
			img = Texgen.door()
		"window":
			img = Texgen.window()
		"awning_stripes":
			img = Texgen.awning_stripes()
		"cloth_red":
			img = Texgen.cloth(Color(0.75, 0.22, 0.18))
		"tree":
			img = Texgen.tree_sprite()
		"blob_shadow":
			img = Texgen.blob_shadow()
		_:
			img = Texgen.grass()
	var texture: ImageTexture = Texgen.make_texture(img, true)
	_textures[key] = texture
	return texture


func _add_mesh(
	parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, node_name: String = ""
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	if node_name != "":
		instance.name = node_name
	instance.mesh = mesh
	if mat != null:
		instance.material_override = mat
	instance.position = pos
	parent.add_child(instance)
	return instance


func _add_box(
	parent: Node3D, size: Vector3, mat: Material, pos: Vector3, node_name: String = ""
) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	return _add_mesh(parent, box, mat, pos, node_name)


func _add_quad(
	parent: Node3D, size: Vector2, mat: Material, pos: Vector3, node_name: String = ""
) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = size
	return _add_mesh(parent, quad, mat, pos, node_name)


func _solid_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.metallic_specular = 0.0
	return mat


func _emissive_material(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.metallic_specular = 0.0
	return mat


func _add_omni_light(
	parent: Node3D, pos: Vector3, color: Color, range_m: float, energy: float
) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.omni_range = range_m
	light.light_energy = energy
	light.shadow_enabled = false
	parent.add_child(light)
	return light


func _make_label(text: String, pixel_size: float, font_size: int) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.pixel_size = pixel_size
	label.font_size = font_size
	label.modulate = Color("#f2e2b0")
	label.outline_modulate = Color(0.0, 0.0, 0.0)
	label.outline_size = 10
	label.no_depth_test = false
	label.double_sided = false
	return label


# ---------------------------------------------------------------- ground

func _build_ground() -> void:
	var root := Node3D.new()
	root.name = "Ground"
	add_child(root)
	var grounds: Array = data.get("ground", [])
	for i in range(grounds.size()):
		var ground_value: Variant = grounds[i]
		if typeof(ground_value) != TYPE_DICTIONARY:
			continue
		var ground: Dictionary = ground_value
		var ground_type := str(ground.get("type", "grass"))
		var rect_value: Variant = ground.get("rect", [])
		if typeof(rect_value) != TYPE_ARRAY:
			continue
		var rect: Array = rect_value
		if rect.size() < 4:
			continue
		var x0 := float(rect[0])
		var z0 := float(rect[1])
		var x1 := float(rect[2])
		var z1 := float(rect[3])
		var width := x1 - x0
		var depth := z1 - z0
		if width <= 0.0 or depth <= 0.0:
			continue
		var y := 0.0
		var tex: ImageTexture
		var node_name := "Ground_%d" % i
		match ground_type:
			"stone":
				y = 0.01
				tex = _get_tex("stone_street")
			"water":
				y = 0.02
				tex = _get_tex("water")
				node_name = "WaterSurface"
			_:
				y = 0.0
				tex = _get_tex("grass")
		var plane := PlaneMesh.new()
		plane.size = Vector2(width, depth)
		var mat: StandardMaterial3D = Texgen.make_material(tex, Vector2(width, depth))
		if ground_type == "water":
			_water_material = mat
		_add_mesh(root, plane, mat, Vector3((x0 + x1) * 0.5, y, (z0 + z1) * 0.5), node_name)
	_build_bridges(root)


func _build_bridges(parent: Node3D) -> void:
	var wood_mat: StandardMaterial3D = Texgen.make_material(_get_tex("wood_planks"), Vector2(1.0, 1.0))
	var bridges: Array = data.get("bridges", [])
	for i in range(bridges.size()):
		var bridge_value: Variant = bridges[i]
		if typeof(bridge_value) != TYPE_DICTIONARY:
			continue
		var bridge: Dictionary = bridge_value
		if not TownData._has_numbers(bridge, ["x0", "x1", "z0", "z1"]):
			continue
		var x0 := float(bridge["x0"])
		var x1 := float(bridge["x1"])
		var z0 := float(bridge["z0"])
		var z1 := float(bridge["z1"])
		var width := x1 - x0
		var depth := z1 - z0
		var bridge_root := Node3D.new()
		bridge_root.name = "Bridge%d" % i
		parent.add_child(bridge_root)
		_add_box(
			bridge_root,
			Vector3(width, 0.3, depth),
			wood_mat,
			Vector3((x0 + x1) * 0.5, 0.1, (z0 + z1) * 0.5)
		)
		for side in range(2):
			var rail_x := x0 + 0.08
			if side == 1:
				rail_x = x1 - 0.08
			var z := z0
			while z <= z1 + 0.001:
				_add_box(
					bridge_root,
					Vector3(0.15, 0.9, 0.15),
					wood_mat,
					Vector3(rail_x, 0.7, z)
				)
				z += 1.0
			_add_box(
				bridge_root,
				Vector3(0.1, 0.08, depth),
				wood_mat,
				Vector3(rail_x, 0.75, (z0 + z1) * 0.5)
			)
			_add_box(
				bridge_root,
				Vector3(0.1, 0.08, depth),
				wood_mat,
				Vector3(rail_x, 1.05, (z0 + z1) * 0.5)
			)


# ---------------------------------------------------------------- buildings

func _build_buildings() -> void:
	var root := Node3D.new()
	root.name = "Buildings"
	add_child(root)
	var buildings: Array = data.get("buildings", [])
	for i in range(buildings.size()):
		var building_value: Variant = buildings[i]
		if typeof(building_value) != TYPE_DICTIONARY:
			continue
		var building: Dictionary = building_value
		var building_root := Node3D.new()
		building_root.name = str(building.get("id", "building_%d" % i))
		root.add_child(building_root)
		_build_building(building_root, building)


func _build_building(parent: Node3D, building: Dictionary) -> void:
	var x0 := float(building.get("x0", 0.0))
	var x1 := float(building.get("x1", 0.0))
	var z_front := float(building.get("z_front", 0.0))
	var depth := float(building.get("depth", 0.0))
	var wall_h := float(building.get("wall_h", 4.5))
	var roof_h := float(building.get("roof_h", 2.5))
	var door_x := float(building.get("door_x", (x0 + x1) * 0.5))
	var door_w := float(building.get("door_w", 1.6))
	var kind := str(building.get("kind", "house"))
	if x1 <= x0 or depth <= 0.0:
		return
	var width := x1 - x0
	var z_back := z_front - depth
	var cx := (x0 + x1) * 0.5
	var cz := (z_back + z_front) * 0.5
	var base_y := 0.6
	var top_y := base_y + wall_h
	var door_h := 3.6 if kind == "tavern" else 3.2

	# stone base
	var base_mat: StandardMaterial3D = Texgen.make_material(
		_get_tex("step_stone"), Vector2(width, depth)
	)
	_add_box(
		parent,
		Vector3(width + 0.2, base_y, depth + 0.2),
		base_mat,
		Vector3(cx, base_y * 0.5, cz)
	)

	# plaster wall
	var wall_mat: StandardMaterial3D = Texgen.make_material(
		_get_tex("plaster"), Vector2(width, wall_h)
	)
	_add_box(
		parent,
		Vector3(width, wall_h, depth),
		wall_mat,
		Vector3(cx, base_y + wall_h * 0.5, cz)
	)

	# timber frames
	var wood_mat: StandardMaterial3D = Texgen.make_material(
		_get_tex("wood_planks"), Vector2(1.0, 3.0)
	)
	var beam_x := x0 + 0.15
	while beam_x <= x1 - 0.15 + 0.001:
		_add_box(
			parent,
			Vector3(0.25, wall_h, 0.16),
			wood_mat,
			Vector3(beam_x, base_y + wall_h * 0.5, z_front + 0.08)
		)
		beam_x += 2.5
	_add_box(
		parent,
		Vector3(width, 0.35, 0.2),
		wood_mat,
		Vector3(cx, top_y - 0.175, z_front + 0.08)
	)

	# door
	var door_mat: StandardMaterial3D = Texgen.make_material(_get_tex("door"), Vector2.ONE)
	_add_quad(
		parent,
		Vector2(door_w, door_h),
		door_mat,
		Vector3(door_x, base_y + door_h * 0.5, z_front + 0.05)
	)
	_add_box(
		parent,
		Vector3(door_w + 0.3, 0.3, 0.16),
		wood_mat,
		Vector3(door_x, base_y + door_h + 0.15, z_front + 0.06)
	)

	# sign position, used to keep windows clear
	var sign_text := str(building.get("sign", ""))
	var sign_x := door_x - door_w * 0.5 - 0.85

	# windows
	var window_mat: StandardMaterial3D = Texgen.make_material(
		_get_tex("window"), Vector2.ONE
	)
	var window_y := base_y + 1.6
	var window_x := x0 + 1.5
	while window_x <= x1 - 1.5 + 0.001:
		var near_door := absf(window_x - door_x) < door_w * 0.5 + 0.6
		var near_sign := sign_text != "" and absf(window_x - sign_x) < 1.1
		if not near_door and not near_sign:
			_add_quad(
				parent,
				Vector2(1.2, 1.2),
				window_mat,
				Vector3(window_x, window_y, z_front + 0.06)
			)
		window_x += 3.0

	if kind == "tavern":
		var upper_x := x0 + 1.5
		while upper_x <= x1 - 1.5 + 0.001:
			_add_quad(
				parent,
				Vector2(1.2, 1.2),
				window_mat,
				Vector3(upper_x, 4.2, z_front + 0.06)
			)
			upper_x += 3.0

	# roof
	_build_roof(parent, x0, x1, z_front, depth, top_y, roof_h)

	# sign board
	if sign_text != "":
		_build_sign(parent, sign_x, z_front, sign_text)

	# awning
	if bool(building.get("awning", false)):
		var awning_mat: StandardMaterial3D = Texgen.make_material(
			_get_tex("awning_stripes"), Vector2(door_w + 1.5, 1.6)
		)
		var awning := _add_quad(
			parent,
			Vector2(door_w + 1.5, 1.6),
			awning_mat,
			Vector3(door_x, base_y + door_h + 0.55, z_front + 0.75)
		)
		awning.rotation.x = -deg_to_rad(25.0)

	# lanterns
	if bool(building.get("lantern", false)):
		var lantern_y := base_y + door_h + 0.35
		_build_lantern(parent, door_x - door_w * 0.5 - 0.8, lantern_y, z_front + 0.4)
		_build_lantern(parent, door_x + door_w * 0.5 + 0.8, lantern_y, z_front + 0.4)

	if kind == "tavern":
		_build_balcony(parent, door_x, z_front)

	if kind == "smith":
		var chimney_mat: StandardMaterial3D = Texgen.make_material(
			_get_tex("step_stone"), Vector2(0.8, 2.0)
		)
		_add_box(
			parent,
			Vector3(0.8, 2.0, 0.8),
			chimney_mat,
			Vector3(x1 - 2.0, top_y + roof_h + 0.4, z_back + 2.0)
		)


func _build_roof(
	parent: Node3D, x0: float, x1: float, z_front: float, depth: float, eave_y: float, roof_h: float
) -> void:
	var z_back := z_front - depth
	var xl := x0 - 0.8
	var xr := x1 + 0.8
	var zf := z_front + 1.0
	var zb := z_back - 1.0
	var zm := (zf + zb) * 0.5
	var ridge_y := eave_y + roof_h
	var span := xr - xl
	var slope_len := sqrt((zf - zm) * (zf - zm) + roof_h * roof_h)
	var slope_len_b := sqrt((zm - zb) * (zm - zb) + roof_h * roof_h)

	var roof_mat: StandardMaterial3D = Texgen.make_material(
		_get_tex("roof_tiles"), Vector2.ONE
	)
	roof_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var front_normal := Vector3(0.0, roof_h, zf - zm).normalized()
	var back_normal := Vector3(0.0, roof_h, zb - zm).normalized()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# front slope
	_roof_vertex(st, Vector3(xl, eave_y, zf), Vector2(0.0, 0.0), front_normal)
	_roof_vertex(st, Vector3(xr, eave_y, zf), Vector2(span, 0.0), front_normal)
	_roof_vertex(st, Vector3(xr, ridge_y, zm), Vector2(span, slope_len), front_normal)
	_roof_vertex(st, Vector3(xl, eave_y, zf), Vector2(0.0, 0.0), front_normal)
	_roof_vertex(st, Vector3(xr, ridge_y, zm), Vector2(span, slope_len), front_normal)
	_roof_vertex(st, Vector3(xl, ridge_y, zm), Vector2(0.0, slope_len), front_normal)
	# back slope
	_roof_vertex(st, Vector3(xr, eave_y, zb), Vector2(span, 0.0), back_normal)
	_roof_vertex(st, Vector3(xl, eave_y, zb), Vector2(0.0, 0.0), back_normal)
	_roof_vertex(st, Vector3(xl, ridge_y, zm), Vector2(0.0, slope_len_b), back_normal)
	_roof_vertex(st, Vector3(xr, eave_y, zb), Vector2(span, 0.0), back_normal)
	_roof_vertex(st, Vector3(xl, ridge_y, zm), Vector2(0.0, slope_len_b), back_normal)
	_roof_vertex(st, Vector3(xr, ridge_y, zm), Vector2(span, slope_len_b), back_normal)
	var roof_mesh: ArrayMesh = st.commit()
	_add_mesh(parent, roof_mesh, roof_mat, Vector3.ZERO)

	# gable ends
	var gable_mat: StandardMaterial3D = Texgen.make_material(
		_get_tex("plaster"), Vector2.ONE
	)
	gable_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var gs := SurfaceTool.new()
	gs.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z_mid := (z_front + z_back) * 0.5
	var west_normal := Vector3(-1.0, 0.0, 0.0)
	var east_normal := Vector3(1.0, 0.0, 0.0)
	_roof_vertex(gs, Vector3(x0 - 0.01, eave_y, z_front), Vector2(0.0, 0.0), west_normal)
	_roof_vertex(gs, Vector3(x0 - 0.01, ridge_y, z_mid), Vector2(depth * 0.5, roof_h), west_normal)
	_roof_vertex(gs, Vector3(x0 - 0.01, eave_y, z_back), Vector2(depth, 0.0), west_normal)
	_roof_vertex(gs, Vector3(x1 + 0.01, eave_y, z_front), Vector2(0.0, 0.0), east_normal)
	_roof_vertex(gs, Vector3(x1 + 0.01, eave_y, z_back), Vector2(depth, 0.0), east_normal)
	_roof_vertex(gs, Vector3(x1 + 0.01, ridge_y, z_mid), Vector2(depth * 0.5, roof_h), east_normal)
	var gable_mesh: ArrayMesh = gs.commit()
	_add_mesh(parent, gable_mesh, gable_mat, Vector3.ZERO)

	# ridge cap
	var ridge_mat: StandardMaterial3D = _solid_material(Color("#3d4248"))
	_add_box(
		parent,
		Vector3(span, 0.25, 0.5),
		ridge_mat,
		Vector3((xl + xr) * 0.5, ridge_y + 0.05, zm)
	)


func _roof_vertex(st: SurfaceTool, pos: Vector3, uv: Vector2, normal: Vector3) -> void:
	st.set_normal(normal)
	st.set_uv(uv)
	st.add_vertex(pos)


func _build_sign(parent: Node3D, sign_x: float, z_front: float, text: String) -> void:
	var sign_mat: StandardMaterial3D = Texgen.make_material(
		_get_tex("wood_planks"), Vector2(1.0, 2.0)
	)
	_add_box(
		parent,
		Vector3(1.1, 2.2, 0.12),
		sign_mat,
		Vector3(sign_x, 2.2, z_front + 0.12)
	)
	var label := _make_label(text, 0.02, 96)
	label.position = Vector3(sign_x, 2.2, z_front + 0.2)
	parent.add_child(label)


func _build_lantern(parent: Node3D, x: float, y: float, z: float) -> void:
	var lamp_mat: StandardMaterial3D = _emissive_material(Color("#d9582b"), 2.0)
	var mesh := SphereMesh.new()
	mesh.radius = 0.35
	mesh.height = 0.7
	_add_mesh(parent, mesh, lamp_mat, Vector3(x, y, z))
	var hanger_mat: StandardMaterial3D = _solid_material(Color("#3e2a1a"))
	_add_box(parent, Vector3(0.06, 0.6, 0.06), hanger_mat, Vector3(x, y + 0.55, z))
	_add_omni_light(parent, Vector3(x, y, z), Color("#ffb066"), 7.0, 1.4)


func _build_balcony(parent: Node3D, center_x: float, z_front: float) -> void:
	var wood_mat: StandardMaterial3D = Texgen.make_material(
		_get_tex("wood_planks"), Vector2(6.0, 1.2)
	)
	_add_box(parent, Vector3(6.0, 0.2, 1.2), wood_mat, Vector3(center_x, 3.6, z_front + 0.6))
	_add_box(
		parent,
		Vector3(6.0, 0.08, 0.08),
		wood_mat,
		Vector3(center_x, 4.05, z_front + 1.2)
	)
	_add_box(
		parent,
		Vector3(0.08, 0.9, 1.2),
		wood_mat,
		Vector3(center_x - 3.0, 4.05, z_front + 0.6)
	)
	_add_box(
		parent,
		Vector3(0.08, 0.9, 1.2),
		wood_mat,
		Vector3(center_x + 3.0, 4.05, z_front + 0.6)
	)


# ---------------------------------------------------------------- props

func _build_props() -> void:
	var root := Node3D.new()
	root.name = "Props"
	add_child(root)
	var props: Array = data.get("props", [])
	for i in range(props.size()):
		var prop_value: Variant = props[i]
		if typeof(prop_value) != TYPE_DICTIONARY:
			continue
		var prop: Dictionary = prop_value
		var kind := str(prop.get("kind", ""))
		var x := float(prop.get("x", 0.0))
		var z := float(prop.get("z", 0.0))
		match kind:
			"barrel":
				_build_barrel(root, x, z)
			"crate":
				_build_crate(root, x, z)
			"bench":
				_build_bench(root, x, z)
			"lamp_post":
				_build_lamp_post(root, x, z)
			"banner":
				_build_banner(root, x, z, str(prop.get("text", "")))
			"cart":
				_build_cart(root, x, z, float(prop.get("rot", 0.0)))
			"stall":
				_build_stall(
					root,
					x,
					z,
					float(prop.get("w", 4.0)),
					float(prop.get("d", 2.0)),
					str(prop.get("text", ""))
				)
			"tree":
				_build_tree(root, x, z)


func _build_barrel(parent: Node3D, x: float, z: float) -> void:
	var wood_mat: StandardMaterial3D = Texgen.make_material(
		_get_tex("wood_planks"), Vector2(1.0, 1.0)
	)
	var body := CylinderMesh.new()
	body.top_radius = 0.45
	body.bottom_radius = 0.45
	body.height = 0.9
	_add_mesh(parent, body, wood_mat, Vector3(x, 0.45, z))
	var hoop_mat: StandardMaterial3D = _solid_material(Color("#3e2a1a"))
	var hoop_heights: Array[float] = [0.22, 0.68]
	for hoop_y in hoop_heights:
		var hoop := CylinderMesh.new()
		hoop.top_radius = 0.47
		hoop.bottom_radius = 0.47
		hoop.height = 0.08
		_add_mesh(parent, hoop, hoop_mat, Vector3(x, hoop_y, z))


func _build_crate(parent: Node3D, x: float, z: float) -> void:
	var wood_mat: StandardMaterial3D = Texgen.make_material(
		_get_tex("wood_planks"), Vector2(0.9, 0.9)
	)
	_add_box(parent, Vector3(0.9, 0.9, 0.9), wood_mat, Vector3(x, 0.45, z))


func _build_bench(parent: Node3D, x: float, z: float) -> void:
	var wood_mat: StandardMaterial3D = Texgen.make_material(
		_get_tex("wood_planks"), Vector2(2.0, 0.6)
	)
	var leg_mat: StandardMaterial3D = _solid_material(Color("#4a3020"))
	_add_box(parent, Vector3(2.0, 0.15, 0.6), wood_mat, Vector3(x, 0.5, z))
	_add_box(parent, Vector3(0.15, 0.5, 0.5), leg_mat, Vector3(x - 0.7, 0.25, z))
	_add_box(parent, Vector3(0.15, 0.5, 0.5), leg_mat, Vector3(x + 0.7, 0.25, z))


func _build_lamp_post(parent: Node3D, x: float, z: float) -> void:
	var wood_mat: StandardMaterial3D = Texgen.make_material(
		_get_tex("wood_planks"), Vector2(0.5, 4.0)
	)
	_add_box(parent, Vector3(0.12, 3.2, 0.12), wood_mat, Vector3(x, 1.6, z))
	var lamp_mat: StandardMaterial3D = _emissive_material(Color("#ffc070"), 1.6)
	_add_box(parent, Vector3(0.35, 0.45, 0.35), lamp_mat, Vector3(x, 3.35, z))
	var cap_mat: StandardMaterial3D = _solid_material(Color("#3e2a1a"))
	_add_box(parent, Vector3(0.45, 0.08, 0.45), cap_mat, Vector3(x, 3.62, z))
	_add_omni_light(parent, Vector3(x, 3.35, z), Color("#ffb870"), 8.0, 0.9)


func _build_banner(parent: Node3D, x: float, z: float, text: String) -> void:
	var banner := Node3D.new()
	banner.name = "Banner%d" % _banners.size()
	banner.position = Vector3(x, 0.0, z)
	parent.add_child(banner)
	_banners.append(banner)
	_banner_phases.append(float(_banners.size()) * 1.7)

	var pole_mat: StandardMaterial3D = Texgen.make_material(
		_get_tex("wood_planks"), Vector2(0.5, 4.0)
	)
	_add_box(banner, Vector3(0.12, 4.0, 0.12), pole_mat, Vector3(0.0, 2.0, 0.0))
	var cloth_mat: StandardMaterial3D = Texgen.make_material(
		_get_tex("cloth_red"), Vector2.ONE
	)
	cloth_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_add_quad(banner, Vector2(1.2, 2.4), cloth_mat, Vector3(0.66, 2.6, 0.0))
	if text != "":
		var label := _make_label(text, 0.01, 96)
		label.position = Vector3(0.66, 2.6, 0.06)
		banner.add_child(label)


func _build_cart(parent: Node3D, x: float, z: float, rot: float) -> void:
	var cart := Node3D.new()
	cart.name = "Cart"
	cart.position = Vector3(x, 0.0, z)
	cart.rotation.y = rot
	parent.add_child(cart)
	var wood_mat: StandardMaterial3D = Texgen.make_material(
		_get_tex("wood_planks"), Vector2(2.4, 1.3)
	)
	_add_box(cart, Vector3(2.4, 0.2, 1.3), wood_mat, Vector3(0.0, 0.65, 0.0))
	var wheel_mat: StandardMaterial3D = _solid_material(Color("#4a3020"))
	var wheel_xs: Array[float] = [-0.9, 0.9]
	for wheel_x in wheel_xs:
		var wheel := CylinderMesh.new()
		wheel.top_radius = 0.55
		wheel.bottom_radius = 0.55
		wheel.height = 0.12
		var wheel_node := _add_mesh(cart, wheel, wheel_mat, Vector3(wheel_x, 0.55, 0.0))
		wheel_node.rotation = Vector3(0.0, 0.0, PI / 2.0)
	var handle_xs: Array[float] = [-0.45, 0.45]
	for handle_x in handle_xs:
		_add_box(cart, Vector3(0.1, 0.1, 1.6), wood_mat, Vector3(handle_x, 0.8, 1.25))


func _build_stall(
	parent: Node3D, x: float, z: float, width: float, depth: float, text: String
) -> void:
	var stall := Node3D.new()
	stall.name = "Stall"
	stall.position = Vector3(x, 0.0, z)
	parent.add_child(stall)
	var post_mat: StandardMaterial3D = Texgen.make_material(
		_get_tex("wood_planks"), Vector2(0.5, 2.6)
	)
	var post_xs: Array[float] = [-width * 0.5 + 0.15, width * 0.5 - 0.15]
	var post_zs: Array[float] = [-depth * 0.5 + 0.15, depth * 0.5 - 0.15]
	for post_x in post_xs:
		for post_z in post_zs:
			_add_box(stall, Vector3(0.12, 2.6, 0.12), post_mat, Vector3(post_x, 1.3, post_z))
	var canopy_mat: StandardMaterial3D = Texgen.make_material(
		_get_tex("awning_stripes"), Vector2(width, depth)
	)
	var canopy := _add_box(
		stall,
		Vector3(width + 0.4, 0.08, depth + 0.4),
		canopy_mat,
		Vector3(0.0, 2.62, 0.0)
	)
	canopy.rotation.x = -deg_to_rad(6.0)
	var counter_mat: StandardMaterial3D = Texgen.make_material(
		_get_tex("wood_planks"), Vector2(width, 0.9)
	)
	_add_box(stall, Vector3(width, 0.15, 0.9), counter_mat, Vector3(0.0, 1.0, 0.15))
	var bamboo_mat: StandardMaterial3D = _solid_material(Color("#d8c090"))
	for i in range(3):
		var basket := CylinderMesh.new()
		basket.top_radius = 0.3
		basket.bottom_radius = 0.3
		basket.height = 0.25
		_add_mesh(stall, basket, bamboo_mat, Vector3(float(i) - 1.0, 1.2, 0.15))
	if text != "":
		var label := _make_label(text, 0.02, 96)
		label.position = Vector3(0.0, 2.3, depth * 0.5 + 0.1)
		stall.add_child(label)


func _build_tree(parent: Node3D, x: float, z: float) -> void:
	var tree := Sprite3D.new()
	tree.name = "Tree"
	tree.texture = _get_tex("tree")
	tree.pixel_size = 1.0 / 16.0
	tree.offset = Vector2(0, 32)
	tree.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	tree.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	tree.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	tree.shaded = true
	tree.double_sided = true
	tree.position = Vector3(x, 0.0, z)
	parent.add_child(tree)

	var shadow := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.4, 1.2)
	shadow.mesh = quad
	var shadow_mat: StandardMaterial3D = Texgen.make_material(
		_get_tex("blob_shadow"), Vector2.ONE, true, true
	)
	shadow_mat.alpha_scissor_threshold = 0.05
	shadow.material_override = shadow_mat
	shadow.position = Vector3(x, 0.03, z)
	shadow.rotation.x = -PI / 2.0
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(shadow)


# ---------------------------------------------------------------- stairs, platform, gate

func _build_stairs() -> void:
	var root := Node3D.new()
	root.name = "Stairs"
	add_child(root)
	var stairs_value: Variant = data.get("stairs", null)
	if typeof(stairs_value) == TYPE_DICTIONARY:
		var stairs: Dictionary = stairs_value
		var x0 := float(stairs.get("x0", 0.0))
		var x1 := float(stairs.get("x1", 0.0))
		var z_start := float(stairs.get("z_start", 0.0))
		var z_end := float(stairs.get("z_end", 0.0))
		var steps: int = int(ceil(absf(z_start - z_end)))
		var step_mat: StandardMaterial3D = Texgen.make_material(
			_get_tex("step_stone"), Vector2(1.0, 1.0)
		)
		for i in range(steps):
			var height := 0.5 * float(i + 1)
			var z_center := z_start - float(i) - 0.5
			_add_box(
				root,
				Vector3(x1 - x0, height, 1.0),
				step_mat,
				Vector3((x0 + x1) * 0.5, height * 0.5, z_center)
			)
		var wall_mat: StandardMaterial3D = Texgen.make_material(
			_get_tex("step_stone"), Vector2(1.0, 1.0)
		)
		var wall_len := absf(z_start - z_end)
		var wall_z := (z_start + z_end) * 0.5
		_add_box(root, Vector3(0.3, 1.0, wall_len), wall_mat, Vector3(x0 - 0.25, 0.5, wall_z))
		_add_box(root, Vector3(0.3, 1.0, wall_len), wall_mat, Vector3(x1 + 0.25, 0.5, wall_z))

	var platform_value: Variant = data.get("platform", null)
	if typeof(platform_value) == TYPE_DICTIONARY:
		var platform: Dictionary = platform_value
		var rect_value: Variant = platform.get("rect", [])
		if typeof(rect_value) == TYPE_ARRAY:
			var rect: Array = rect_value
			if rect.size() >= 4:
				var px0 := float(rect[0])
				var pz0 := float(rect[1])
				var px1 := float(rect[2])
				var pz1 := float(rect[3])
				var py := float(platform.get("y", 7.0))
				var side_mat: StandardMaterial3D = Texgen.make_material(
					_get_tex("step_stone"), Vector2(1.0, 1.0)
				)
				_add_box(
					root,
					Vector3(px1 - px0, py, pz1 - pz0),
					side_mat,
					Vector3((px0 + px1) * 0.5, py * 0.5, (pz0 + pz1) * 0.5)
				)
				var top_mat: StandardMaterial3D = Texgen.make_material(
					_get_tex("stone_street"), Vector2(px1 - px0, pz1 - pz0)
				)
				_add_box(
					root,
					Vector3(px1 - px0, 0.06, pz1 - pz0),
					top_mat,
					Vector3((px0 + px1) * 0.5, py + 0.03, (pz0 + pz1) * 0.5)
				)

	var gate_value: Variant = data.get("gate", null)
	if typeof(gate_value) == TYPE_DICTIONARY:
		var gate: Dictionary = gate_value
		var gx := float(gate.get("x", 0.0))
		var gz := float(gate.get("z", 0.0))
		var gy := float(gate.get("y", 0.0))
		var label_text := str(gate.get("label", ""))
		var post_mat: StandardMaterial3D = _solid_material(Color("#7a3a2a"))
		_add_box(root, Vector3(0.8, 5.0, 0.8), post_mat, Vector3(gx - 2.5, gy + 2.5, gz))
		_add_box(root, Vector3(0.8, 5.0, 0.8), post_mat, Vector3(gx + 2.5, gy + 2.5, gz))
		var beam_mat: StandardMaterial3D = _solid_material(Color("#6a3224"))
		_add_box(root, Vector3(6.0, 0.6, 0.8), beam_mat, Vector3(gx, gy + 5.3, gz))
		var roof_mat: StandardMaterial3D = Texgen.make_material(
			_get_tex("roof_tiles"), Vector2(7.0, 1.4)
		)
		var front := _add_box(
			root, Vector3(7.0, 0.15, 1.4), roof_mat, Vector3(gx, gy + 5.95, gz + 0.55)
		)
		front.rotation.x = -deg_to_rad(25.0)
		var back := _add_box(
			root, Vector3(7.0, 0.15, 1.4), roof_mat, Vector3(gx, gy + 5.95, gz - 0.55)
		)
		back.rotation.x = deg_to_rad(25.0)
		if label_text != "":
			var label := _make_label(label_text, 0.02, 96)
			label.position = Vector3(gx, gy + 4.8, gz + 0.45)
			root.add_child(label)


# ---------------------------------------------------------------- backdrop

func _build_backdrop() -> void:
	var root := Node3D.new()
	root.name = "Backdrop"
	add_child(root)
	var layers: Array[Dictionary] = [
		{"z": -46.0, "seed": 31, "color": Color("#6f7f9a")},
		{"z": -60.0, "seed": 32, "color": Color("#8e9bb2")},
		{"z": -76.0, "seed": 33, "color": Color("#b4bdcc")},
	]
	for i in range(layers.size()):
		var layer: Dictionary = layers[i]
		var seed_value := int(layer["seed"])
		var color_value: Color = layer["color"]
		var img: Image = Texgen.mountain_layer(256, 64, seed_value, color_value)
		var tex: ImageTexture = Texgen.make_texture(img, false)
		var mat: StandardMaterial3D = Texgen.make_material(tex, Vector2.ONE, true, true)
		var quad := QuadMesh.new()
		quad.size = Vector2(220.0, 40.0)
		_add_mesh(root, quad, mat, Vector3(0.0, 17.0, float(layer["z"])))


# ---------------------------------------------------------------- lights, sky, vignette

func _build_lighting() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48.0, -38.0, 0.0)
	sun.light_color = Color("#ffd9a8")
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	sun.shadow_bias = 0.05
	add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#7fa6d8")
	sky_mat.sky_horizon_color = Color("#f2d9b0")
	sky_mat.ground_horizon_color = Color("#f2d9b0")
	sky_mat.ground_bottom_color = Color("#c8b898")
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#8e9bb8")
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color("#e8d8c0")
	env.fog_density = 0.003
	world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)

	_build_vignette()


func _build_vignette() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Vignette"
	add_child(layer)
	var rect := ColorRect.new()
	rect.name = "VignetteRect"
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	rect.offset_left = 0.0
	rect.offset_top = 0.0
	rect.offset_right = 0.0
	rect.offset_bottom = 0.0
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = VIGNETTE_SHADER
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = shader
	rect.material = shader_mat
	layer.add_child(rect)


# ---------------------------------------------------------------- camera

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 28.0
	camera.attributes = _camera_attributes()
	add_child(camera)
	if camera.is_inside_tree():
		camera.current = true


func _camera_attributes() -> CameraAttributesPractical:
	var attributes := CameraAttributesPractical.new()
	attributes.dof_blur_far_enabled = true
	attributes.dof_blur_far_distance = 26.0
	attributes.dof_blur_far_transition = 22.0
	attributes.dof_blur_near_enabled = true
	attributes.dof_blur_near_distance = 9.0
	attributes.dof_blur_near_transition = 5.0
	attributes.dof_blur_amount = 0.08
	return attributes


func _follow_position() -> Vector3:
	if follow_target == null:
		return _spawn_position()
	if not follow_target.is_inside_tree():
		return follow_target.position
	return follow_target.global_position


func update_camera(delta: float) -> void:
	if camera == null:
		return
	var target_pos := _follow_position()
	var weight: float = 1.0 - exp(-8.0 * delta)
	_focus = _focus.lerp(target_pos, weight)
	camera.position = camera.position.lerp(target_pos + CAMERA_OFFSET, weight)
	camera.look_at_from_position(camera.position, _focus, Vector3.UP)


func snap_camera() -> void:
	if camera == null:
		return
	var target_pos := _follow_position()
	_focus = target_pos
	camera.position = target_pos + CAMERA_OFFSET
	camera.look_at_from_position(camera.position, _focus, Vector3.UP)


func _spawn_position() -> Vector3:
	var spawn_value: Variant = data.get("spawn", null)
	if typeof(spawn_value) == TYPE_DICTIONARY:
		var spawn: Dictionary = spawn_value
		return Vector3(float(spawn.get("x", 0.0)), 0.0, float(spawn.get("z", 0.0)))
	return Vector3.ZERO


# ---------------------------------------------------------------- npcs

func _build_npcs() -> void:
	var root := Node3D.new()
	root.name = "NPCs"
	add_child(root)
	var npcs: Array = data.get("npcs", [])
	for i in range(npcs.size()):
		var npc_value: Variant = npcs[i]
		if typeof(npc_value) != TYPE_DICTIONARY:
			continue
		var npc: Dictionary = npc_value
		var id := str(npc.get("id", "npc_%d" % i))
		if GameState.has_flag("boss_defeated") and DEFEATED_NPC_IDS.has(id):
			continue
		var character: Variant = CharacterSprite.new()
		character.name = id
		character.setup(str(npc.get("sprite", "")))
		character.position = Vector3(
			float(npc.get("x", 0.0)), 0.0, float(npc.get("z", 0.0))
		)
		character.set_facing(str(npc.get("facing", "down")))
		root.add_child(character)
		npc_nodes[id] = character


# ---------------------------------------------------------------- player

func _build_player() -> void:
	var spawn := _spawn_data()
	var px := float(spawn.get("x", 0.0))
	var pz := float(spawn.get("z", 0.0))
	var return_value: Variant = GameState.town_return_pos
	if return_value is Vector2:
		var return_pos: Vector2 = return_value
		px = return_pos.x
		pz = return_pos.y
	var start_y: float = TownData.ground_height(data, px, pz)
	var character := CharacterSprite.new()
	character.name = "Player"
	character.setup("ren_xiaoyao")
	character.position = Vector3(px, start_y, pz)
	character.set_facing(str(spawn.get("facing", "down")))
	add_child(character)
	player = character
	player_pos = Vector2(px, pz)
	blockers.append_array(TownData.extra_blockers(data))
	follow_target = player


func _spawn_data() -> Dictionary:
	var spawn_value: Variant = data.get("spawn", null)
	if typeof(spawn_value) == TYPE_DICTIONARY:
		var spawn: Dictionary = spawn_value
		return spawn
	return {}


func _read_bounds() -> Rect2:
	var bounds_value: Variant = data.get("bounds", null)
	if typeof(bounds_value) != TYPE_DICTIONARY:
		return Rect2()
	var bounds: Dictionary = bounds_value
	var x0 := float(bounds.get("x0", 0.0))
	var x1 := float(bounds.get("x1", 0.0))
	var z0 := float(bounds.get("z0", 0.0))
	var z1 := float(bounds.get("z1", 0.0))
	return Rect2(x0, z0, x1 - x0, z1 - z0)


func set_input_override(v: Variant) -> void:
	_input_override = v


func get_move_input() -> Vector2:
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
	var target_y: float = TownData.ground_height(data, player_pos.x, player_pos.y)
	var weight: float = 1.0 - exp(-14.0 * delta)
	var next_y: float = lerpf(player.position.y, target_y, weight)
	player.position = Vector3(player_pos.x, next_y, player_pos.y)
	var facing: String = PlayerMotion.facing_from_input(input, str(player.get("facing")))
	player.call("set_facing", facing)
	player.call("set_moving", input.length() > 0.01)


# ---------------------------------------------------------------- interaction

func build_hud() -> void:
	if _hud_layer != null:
		return
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "Hud"
	_hud_layer.layer = 10
	add_child(_hud_layer)

	var view: Variant = load("res://ui/dialogue_view.gd").new()
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


func nearby_npc() -> String:
	var positions: Dictionary = {}
	for id in npc_nodes.keys():
		var node_value: Variant = npc_nodes[id]
		if not (node_value is Node3D):
			continue
		var node: Node3D = node_value
		positions[str(id)] = Vector2(node.position.x, node.position.z)
	return Interaction.nearest_npc(player_pos, positions)


func try_interact() -> bool:
	if is_dialogue_active():
		return false
	var npc_id: String = nearby_npc()
	if npc_id == "" or not npc_dialogues.has(npc_id):
		return false
	var entry_value: Variant = npc_dialogues[npc_id]
	if not (entry_value is Dictionary):
		return false
	var entry: Dictionary = entry_value
	var path := str(entry.get("file", ""))
	if path == "":
		return false

	current_npc_id = npc_id
	_face_player(npc_id)

	var speakers: Dictionary = Dialogue.load_speakers(SPEAKERS_PATH).get("defs", {})
	var loaded: Dictionary = Dialogue.load_file(path, speakers)
	var errors: Array = loaded.get("errors", [])
	if not errors.is_empty():
		for error_text in errors:
			push_warning("town dialogue: %s" % str(error_text))
		current_npc_id = ""
		return false

	pending_encounter = {}
	if entry.has("encounter"):
		var encounter_value: Variant = entry["encounter"]
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
	if npc_id == "":
		prompt_label.visible = false
		return
	prompt_label.text = "按 E 与 %s 交谈" % _npc_display_name(npc_id)
	prompt_label.visible = true


func _npc_display_name(npc_id: String) -> String:
	var npcs: Array = data.get("npcs", [])
	for npc_value in npcs:
		if typeof(npc_value) != TYPE_DICTIONARY:
			continue
		var npc: Dictionary = npc_value
		if str(npc.get("id", "")) == npc_id:
			return str(npc.get("name", npc_id))
	return npc_id


func _face_player(npc_id: String) -> void:
	var npc_value: Variant = npc_nodes.get(npc_id, null)
	if not (npc_value is Node3D):
		return
	var npc: Node3D = npc_value
	var dx: float = player_pos.x - npc.position.x
	var dz: float = player_pos.y - npc.position.z
	var facing := "down"
	if absf(dx) >= absf(dz):
		facing = "right" if dx > 0.0 else "left"
	else:
		facing = "down" if dz > 0.0 else "up"
	npc.call("set_facing", facing)


func _on_dialogue_finished() -> void:
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

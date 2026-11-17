extends Node3D

signal exit_requested
signal encounter_requested(enemy_id: String, count: int, first_strike: bool)

const TAVERN_PATH := "res://data/tavern.json"
const SPEAKERS_PATH := "res://data/speakers.json"
const CAMERA_OFFSET := Vector3(0.0, 13.0, 30.0)
const LOOK_AHEAD := Vector3(0.0, 1.0, -3.0)
const ANIM_DURATION := 1.2
const STATES: Array[String] = ["normal", "brawl", "aftermath"]

const Texgen = preload("res://world/texgen.gd")
const AiAssets = preload("res://world/ai_assets.gd")
const CharacterSprite = preload("res://world/character_sprite.gd")
const PlayerMotion = preload("res://world/player_motion.gd")
const Dialogue = preload("res://core/dialogue.gd")
const GameState = preload("res://core/game_state.gd")
const Interaction = preload("res://world/interaction.gd")

const VIGNETTE_SHADER := """
shader_type canvas_item;

uniform float vignette_strength = 0.55;

void fragment() {
	vec2 uv = SCREEN_UV - vec2(0.5);
	float d = length(uv);
	float v = smoothstep(0.32, 0.85, d);
	COLOR = vec4(0.0, 0.0, 0.0, v * vignette_strength);
}
"""

var data: Dictionary = {}
var room: Dictionary = {}
var blockers: Array = []
var bounds_rect: Rect2 = Rect2()
var furniture_nodes: Dictionary = {}
var furniture_entries: Dictionary = {}
var npc_nodes: Dictionary = {}
var camera: Camera3D = null
var follow_target: Node3D = null
var sun: DirectionalLight3D = null
var world_env: WorldEnvironment = null
var player: Node3D = null
var player_pos: Vector2 = Vector2.ZERO
var dialogue_view: Control = null
var prompt_label: Label = null
var pending_encounter: Dictionary = {}
var current_npc_id: String = ""
var state: String = "normal"
var skip_actors: bool = false
var exit_rect: Rect2 = Rect2()
var exit_prompt: String = "按 E 走出酒馆"

var _npc_entries: Dictionary = {}
var _npc_root: Node3D = null
var _furniture_root: Node3D = null
var _input_override: Variant = null
var _built: bool = false
var _textures: Dictionary = {}
var _time: float = 0.0
var _focus: Vector3 = Vector3.ZERO
var _hud_layer: CanvasLayer = null
var _anim_active: bool = false
var _anim_t: float = 0.0
var _anim_furniture: Array = []
var _anim_npcs: Array = []


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
	_add_action("cycle_tavern_state", KEY_F3, KEY_NONE)


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
	_load_data()
	state = _initial_state()
	_build_room()
	_build_beams()
	_build_wall_decor()
	_build_furniture()
	_build_stairs()
	_build_windows()
	_build_light_shafts()
	_build_dust()
	_build_lanterns()
	_build_lighting()
	_build_camera()
	_apply_state(state, false)
	if not skip_actors:
		_build_player()
		snap_camera()


func _process(delta: float) -> void:
	tick_player(delta)
	advance(delta)
	update_prompt()
	if not is_dialogue_active() and InputMap.has_action("interact") \
			and Input.is_action_just_pressed("interact"):
		try_interact()
	if InputMap.has_action("cycle_tavern_state") \
			and Input.is_action_just_pressed("cycle_tavern_state"):
		_cycle_state()
	_time += delta
	update_camera(delta)


# ---------------------------------------------------------------- data

func _load_data() -> void:
	blockers.clear()
	furniture_entries.clear()
	_npc_entries.clear()
	if not FileAccess.file_exists(TAVERN_PATH):
		push_warning("tavern: %s not found" % TAVERN_PATH)
		return
	var text: String = FileAccess.get_file_as_string(TAVERN_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("tavern: invalid JSON in %s" % TAVERN_PATH)
		return
	data = parsed
	var room_value: Variant = data.get("room", {})
	if room_value is Dictionary:
		room = room_value
	bounds_rect = _read_bounds()
	exit_rect = _read_exit_rect()
	exit_prompt = str(_exit_data().get("prompt", exit_prompt))
	var furniture: Array = data.get("furniture", [])
	for i in range(furniture.size()):
		var entry_value: Variant = furniture[i]
		if typeof(entry_value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_value
		var id := str(entry.get("id", "furniture_%d" % i))
		furniture_entries[id] = entry
	var npcs: Array = data.get("npcs", [])
	for i in range(npcs.size()):
		var npc_value: Variant = npcs[i]
		if typeof(npc_value) != TYPE_DICTIONARY:
			continue
		var npc: Dictionary = npc_value
		_npc_entries[str(npc.get("id", "npc_%d" % i))] = npc
	for blocker_value in data.get("blockers", []):
		var rect_value: Variant = blocker_value
		if rect_value is Dictionary:
			rect_value = (rect_value as Dictionary).get("rect", [])
		if not (rect_value is Array):
			continue
		var rect: Array = rect_value
		if rect.size() < 4:
			continue
		var x0 := float(rect[0])
		var z0 := float(rect[1])
		var x1 := float(rect[2])
		var z1 := float(rect[3])
		if x1 > x0 and z1 > z0:
			blockers.append(Rect2(x0, z0, x1 - x0, z1 - z0))


func _read_bounds() -> Rect2:
	var bounds_value: Variant = data.get("bounds", null)
	if not (bounds_value is Dictionary):
		return Rect2()
	var bounds: Dictionary = bounds_value
	var x0 := float(bounds.get("x0", 0.0))
	var x1 := float(bounds.get("x1", 0.0))
	var z0 := float(bounds.get("z0", 0.0))
	var z1 := float(bounds.get("z1", 0.0))
	return Rect2(x0, z0, x1 - x0, z1 - z0)


func _exit_data() -> Dictionary:
	var exit_value: Variant = data.get("exit", null)
	if exit_value is Dictionary:
		return exit_value
	return {}


func _read_exit_rect() -> Rect2:
	var exit_data: Dictionary = _exit_data()
	var rect_value: Variant = exit_data.get("rect", null)
	if not (rect_value is Array):
		return Rect2()
	var rect: Array = rect_value
	if rect.size() < 4:
		return Rect2()
	var x0 := float(rect[0])
	var z0 := float(rect[1])
	var x1 := float(rect[2])
	var z1 := float(rect[3])
	return Rect2(x0, z0, x1 - x0, z1 - z0)


func _initial_state() -> String:
	if GameState.has_flag("boss_defeated"):
		return "aftermath"
	if GameState.has_flag("bandits_entered"):
		return "brawl"
	return "normal"


func current_state() -> String:
	return state


func set_state(new_state: String, animate: bool = false) -> void:
	if not STATES.has(new_state):
		return
	if new_state == state and not _anim_active:
		return
	state = new_state
	_apply_state(new_state, animate)


func _cycle_state() -> void:
	var next := "normal"
	if state == "normal":
		next = "brawl"
	elif state == "brawl":
		next = "aftermath"
	set_state(next, true)


# ---------------------------------------------------------------- helpers

func _room_float(key: String, fallback: float) -> float:
	var value: Variant = room.get(key, fallback)
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback


func _entry_float(entry: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = entry.get(key, fallback)
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback


func _get_tex(key: String) -> ImageTexture:
	if _textures.has(key):
		var cached: ImageTexture = _textures[key]
		return cached
	var img: Image
	match key:
		"plaster":
			img = Texgen.plaster()
		_:
			img = Texgen.wood_planks()
	var texture: ImageTexture = Texgen.make_texture(img, true)
	_textures[key] = texture
	return texture


# Dark wood texture from the AI pack, with the generated planks as a fallback.
func _wood_material(uv_scale: Vector2) -> StandardMaterial3D:
	var tex: ImageTexture = AiAssets.load_texture("tex_dark_wood.png")
	if tex != null:
		return Texgen.make_material(tex, uv_scale)
	return Texgen.make_material(_get_tex("wood_planks"), uv_scale)


# Aged plaster from the AI pack, repeated roughly every 2.5 world units.
func _plaster_material(uv_scale: Vector2) -> StandardMaterial3D:
	var tex: ImageTexture = AiAssets.load_texture("tex_aged_plaster.png")
	if tex != null:
		return Texgen.make_material(tex, uv_scale)
	return Texgen.make_material(_get_tex("plaster"), uv_scale)


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


# Crisp pixel-art material for the generated rug and scroll images.
func _image_material(img: Image) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
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


func _sprite_prop(
	parent: Node3D, file: String, height: float, fallback_size: Vector3, fallback_mat: Material
) -> void:
	var sprite := AiAssets.make_sprite(file, height, Vector3.ZERO, "")
	if sprite != null:
		parent.add_child(sprite)
		return
	_add_box(parent, fallback_size, fallback_mat, Vector3(0.0, fallback_size.y * 0.5, 0.0))


# ---------------------------------------------------------------- room

func _build_room() -> void:
	var root := Node3D.new()
	root.name = "Room"
	add_child(root)
	var x0 := _room_float("x0", 0.0)
	var x1 := _room_float("x1", 22.0)
	var z_back := _room_float("z_back", -12.0)
	var z_front := _room_float("z_front", 6.0)
	var wall_h := _room_float("wall_height", 6.5)
	var wall_t := _room_float("wall_thickness", 0.3)
	var width := x1 - x0
	var depth := z_front - z_back
	var cx := (x0 + x1) * 0.5
	var cz := (z_back + z_front) * 0.5

	# Floor: the AI wood tile repeats every 4 units. The plane is rotated a quarter
	# turn so the planks run across the room.
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(depth, width)
	var floor_mat: StandardMaterial3D = _wood_material(Vector2(depth / 4.0, width / 4.0))
	floor_mat.albedo_color = Color(0.5, 0.44, 0.4)
	var floor_instance := _add_mesh(
		root, floor_mesh, floor_mat, Vector3(cx, 0.0, cz), "Floor"
	)
	floor_instance.rotation.y = PI / 2.0

	var wainscot_h := 2.2
	var lower_wood: StandardMaterial3D = _wood_material(
		Vector2(width / 3.0, wainscot_h / 3.0)
	)
	var upper_plaster: StandardMaterial3D = _plaster_material(
		Vector2(width / 2.5, (wall_h - wainscot_h) / 2.5)
	)
	var side_lower_wood: StandardMaterial3D = _wood_material(
		Vector2(depth / 3.0, wainscot_h / 3.0)
	)
	var side_upper_plaster: StandardMaterial3D = _plaster_material(
		Vector2(depth / 2.5, (wall_h - wainscot_h) / 2.5)
	)

	# Back wall (z_back), only its inner face is ever seen.
	_add_box(
		root,
		Vector3(width, wainscot_h, wall_t),
		lower_wood,
		Vector3(cx, wainscot_h * 0.5, z_back - wall_t * 0.5),
		"WainscotBack"
	)
	_add_box(
		root,
		Vector3(width, wall_h - wainscot_h, wall_t),
		upper_plaster,
		Vector3(cx, wainscot_h + (wall_h - wainscot_h) * 0.5, z_back - wall_t * 0.5),
		"PlasterBack"
	)

	# Left and right walls.
	for side in range(2):
		var wall_x: float = x0 - wall_t * 0.5
		var side_name := "West"
		if side == 1:
			wall_x = x1 + wall_t * 0.5
			side_name = "East"
		_add_box(
			root,
			Vector3(wall_t, wainscot_h, depth),
			side_lower_wood,
			Vector3(wall_x, wainscot_h * 0.5, cz),
			"Wainscot%s" % side_name
		)
		_add_box(
			root,
			Vector3(wall_t, wall_h - wainscot_h, depth),
			side_upper_plaster,
			Vector3(wall_x, wainscot_h + (wall_h - wainscot_h) * 0.5, cz),
			"Plaster%s" % side_name
		)

	# Dark timber posts every 5 units along the back wall and both side walls.
	var post_mat: StandardMaterial3D = _solid_material(Color("#3e2a1a"))
	var post_x := x0 + 0.35
	while post_x <= x1 - 0.2:
		_add_box(
			root,
			Vector3(0.32, wall_h, 0.12),
			post_mat,
			Vector3(post_x, wall_h * 0.5, z_back + 0.06)
		)
		post_x += 5.0
	var post_z := z_back + 0.5
	while post_z <= z_front - 0.3:
		_add_box(
			root,
			Vector3(0.12, wall_h, 0.32),
			post_mat,
			Vector3(x0 + 0.06, wall_h * 0.5, post_z)
		)
		_add_box(
			root,
			Vector3(0.12, wall_h, 0.32),
			post_mat,
			Vector3(x1 - 0.06, wall_h * 0.5, post_z)
		)
		post_z += 5.0

	# Top beam across the back wall.
	_add_box(
		root,
		Vector3(width, 0.35, 0.45),
		post_mat,
		Vector3(cx, wall_h - 0.175, z_back + 0.12),
		"TopBeam"
	)

	# A very large dark board behind the building stops the sky from showing above
	# the walls and keeps the outside of the room from reading as pure black.
	var backdrop_mat: StandardMaterial3D = _solid_material(Color("#0f0a08"))
	backdrop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var backdrop := _add_quad(
		root, Vector2(120.0, 60.0), backdrop_mat, Vector3(cx, 15.0, -30.0), "Backdrop"
	)
	backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_beams() -> void:
	var root := Node3D.new()
	root.name = "Beams"
	add_child(root)
	var x0 := _room_float("x0", 0.0)
	var x1 := _room_float("x1", 22.0)
	var z_back := _room_float("z_back", -12.0)
	var z_front := _room_float("z_front", 6.0)
	var width := x1 - x0
	var depth := z_front - z_back
	var cx := (x0 + x1) * 0.5
	var cz := (z_back + z_front) * 0.5
	var beam_mat: StandardMaterial3D = _wood_material(Vector2(3.0, 1.0))
	beam_mat.albedo_color = Color(0.35, 0.3, 0.27)

	# Main beams run across the room; the three cross beams tie them together.
	for beam_z in [-10.5, -7.0, -3.5, 0.0, 3.5]:
		_add_box(
			root,
			Vector3(width, 0.4, 0.4),
			beam_mat,
			Vector3(cx, 6.2, float(beam_z))
		)
	for beam_x in [4.0, 11.0, 18.0]:
		_add_box(
			root,
			Vector3(0.3, 0.3, depth),
			beam_mat,
			Vector3(float(beam_x), 5.9, cz)
		)


func _build_windows() -> void:
	var root := Node3D.new()
	root.name = "Windows"
	add_child(root)
	var z_back := _room_float("z_back", -12.0)
	var glass_mat: StandardMaterial3D = _emissive_material(Color("#ffcf8a"), 1.2)
	var mullion_mat: StandardMaterial3D = _solid_material(Color("#3a2818"))
	var window_xs: Array[float] = [3.5, 11.0, 18.5]
	var window_y := 3.8
	for i in range(window_xs.size()):
		var wx: float = window_xs[i]
		_add_quad(
			root,
			Vector2(1.8, 1.4),
			glass_mat,
			Vector3(wx, window_y, z_back + 0.03),
			"WindowGlow%d" % i
		)
		for offset in [-0.6, -0.2, 0.2, 0.6]:
			_add_box(
				root,
				Vector3(0.05, 1.4, 0.05),
				mullion_mat,
				Vector3(wx + float(offset), window_y, z_back + 0.06)
			)
		_add_box(
			root,
			Vector3(1.8, 0.06, 0.05),
			mullion_mat,
			Vector3(wx, window_y, z_back + 0.06)
		)
		# Cold daylight spilling in from just inside the window.
		_add_omni_light(
			root,
			Vector3(wx, window_y, z_back + 0.6),
			Color(0.62, 0.72, 0.9),
			9.0,
			0.9
		)


func _build_wall_decor() -> void:
	var root := Node3D.new()
	root.name = "WallDecor"
	add_child(root)
	var x0 := _room_float("x0", 0.0)
	var x1 := _room_float("x1", 22.0)
	var z_back := _room_float("z_back", -12.0)
	var z_front := _room_float("z_front", 6.0)
	var wall_h := _room_float("wall_height", 6.5)
	var cx := (x0 + x1) * 0.5
	var cz := (z_back + z_front) * 0.5
	var post_mat: StandardMaterial3D = _solid_material(Color("#3e2a1a"))

	# Two extra timber posts on each side wall, matching the back wall rhythm.
	for side in range(2):
		var post_x := x0 + 0.08
		if side == 1:
			post_x = x1 - 0.08
		for post_z in [-8.0, 2.0]:
			_add_box(
				root,
				Vector3(0.12, wall_h, 0.32),
				post_mat,
				Vector3(post_x, wall_h * 0.5, float(post_z))
			)

	# A small glowing wall lamp and its warm pool in the middle of each side wall.
	var lamp_mat: StandardMaterial3D = _emissive_material(Color(1.0, 0.55, 0.28), 1.4)
	for side in range(2):
		var lamp_x := x0 + 0.15
		var light_x := x0 + 0.8
		if side == 1:
			lamp_x = x1 - 0.15
			light_x = x1 - 0.8
		_add_box(
			root,
			Vector3(0.18, 0.28, 0.18),
			lamp_mat,
			Vector3(lamp_x, 3.3, cz),
			"WallLampWest" if side == 0 else "WallLampEast"
		)
		_add_omni_light(
			root,
			Vector3(light_x, 3.3, cz),
			Color(1.0, 0.62, 0.32),
			4.0,
			0.7
		)

	# Two hanging scrolls flank the sign above the bar.
	var scroll_mat: StandardMaterial3D = _image_material(_scroll_image())
	var roller_mat: StandardMaterial3D = _solid_material(Color("#3e2a1a"))
	var scroll_xs: Array[float] = [3.3, 18.7]
	for i in range(scroll_xs.size()):
		var sx: float = scroll_xs[i]
		_add_quad(
			root,
			Vector2(0.9, 2.4),
			scroll_mat,
			Vector3(sx, 3.6, z_back + 0.15),
			"Scroll_%d" % (i + 1)
		)
		_add_box(
			root,
			Vector3(0.98, 0.07, 0.07),
			roller_mat,
			Vector3(sx, 4.83, z_back + 0.17)
		)
		_add_box(
			root,
			Vector3(0.98, 0.07, 0.07),
			roller_mat,
			Vector3(sx, 2.37, z_back + 0.17)
		)

	# The tavern sign, only when the painted prop is available.
	var sign := AiAssets.make_sprite(
		"prop_tavern_sign.png",
		1.7,
		Vector3(cx, 3.3, z_back + 0.2),
		"WallSign"
	)
	if sign != null:
		root.add_child(sign)


func _build_light_shafts() -> void:
	var root := Node3D.new()
	root.name = "LightShafts"
	add_child(root)
	var z_back := _room_float("z_back", -12.0)
	var gradient: ImageTexture = _shaft_gradient()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.92, 0.75, 0.12)
	mat.albedo_texture = gradient
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	var mesh: ArrayMesh = _shaft_mesh(1.6, 1.8, 3.05, 4.0)
	var window_xs: Array[float] = [3.5, 11.0, 18.5]
	for i in range(window_xs.size()):
		var shaft := _add_mesh(
			root,
			mesh,
			mat,
			Vector3(window_xs[i], 3.1, z_back + 0.1),
			"LightShaft_%d" % (i + 1)
		)
		shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_dust() -> void:
	var dust := CPUParticles3D.new()
	dust.name = "Dust"
	dust.position = Vector3(11.0, 1.6, -9.9)
	dust.amount = 60
	dust.lifetime = 6.0
	dust.preprocess = 6.0
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(8.4, 1.5, 2.0)
	dust.direction = Vector3(0.0, 1.0, 0.0)
	dust.spread = 20.0
	dust.gravity = Vector3.ZERO
	dust.initial_velocity_min = 0.05
	dust.initial_velocity_max = 0.12
	dust.scale_amount_min = 0.8
	dust.scale_amount_max = 1.2
	dust.color = Color(1.0, 0.95, 0.85, 0.55)
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.95, 0.85, 0.55)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.disable_receive_shadows = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.04, 0.04)
	quad.material = mat
	dust.mesh = quad
	add_child(dust)


func _shaft_gradient() -> ImageTexture:
	var img: Image = Image.create_empty(4, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		var alpha: float = lerpf(0.18, 0.0, float(y) / 63.0)
		for x in range(4):
			img.set_pixel(x, y, Color(1.0, 0.95, 0.85, alpha))
	return ImageTexture.create_from_image(img)


func _shaft_mesh(top_width: float, bottom_width: float, drop: float, forward: float) -> ArrayMesh:
	var verts := PackedVector3Array([
		Vector3(-top_width * 0.5, 0.0, 0.0),
		Vector3(top_width * 0.5, 0.0, 0.0),
		Vector3(bottom_width * 0.5, -drop, forward),
		Vector3(-bottom_width * 0.5, -drop, forward),
	])
	var uvs := PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(1.0, 0.0),
		Vector2(1.0, 1.0),
		Vector2(0.0, 1.0),
	])
	var normals := PackedVector3Array([
		Vector3(0.0, 0.6, 0.8),
		Vector3(0.0, 0.6, 0.8),
		Vector3(0.0, 0.6, 0.8),
		Vector3(0.0, 0.6, 0.8),
	])
	var indices := PackedInt32Array([0, 1, 2, 0, 2, 3])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _rug_image() -> Image:
	var img: Image = Image.create_empty(64, 36, false, Image.FORMAT_RGBA8)
	var base := Color("#7a2a2a")
	img.fill(base)
	var gold := Color("#a88438")
	var line := Color("#4a1414")
	for y in range(36):
		for x in range(64):
			if x < 2 or x >= 62 or y < 2 or y >= 34:
				img.set_pixel(x, y, gold)
			elif x == 2 or x == 61 or y == 2 or y == 33:
				img.set_pixel(x, y, line)
	var motif := Color("#c9a24a")
	for center_x in [20, 28, 36, 44]:
		for dy in range(-4, 5):
			var half_width: int = 4 - abs(dy)
			for dx in range(-half_width, half_width + 1):
				var px: int = int(center_x) + dx
				var py: int = 18 + dy
				if px >= 4 and px < 60 and py >= 4 and py < 32:
					img.set_pixel(px, py, motif)
	return img


func _scroll_image() -> Image:
	var img: Image = Image.create_empty(32, 84, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.88, 0.82, 0.68))
	var far := Color("#6a6a64")
	var near := Color("#3a3a38")
	for x in range(2, 30):
		var t := float(x - 2) / 27.0
		var top := int(57.0 - 8.0 * sin(t * PI))
		for y in range(top, 73):
			img.set_pixel(x, y, far)
	for x in range(3, 29):
		var t := float(x - 3) / 25.0
		var top := int(64.0 - 13.0 * sin(t * PI))
		for y in range(top, 79):
			img.set_pixel(x, y, near)
	var seal := Color("#a8322a")
	for y in range(7, 12):
		for x in range(23, 28):
			img.set_pixel(x, y, seal)
	img.set_pixel(25, 9, Color(0.88, 0.82, 0.68))
	return img


func _build_lanterns() -> void:
	var root := Node3D.new()
	root.name = "Lanterns"
	add_child(root)
	var positions: Array[Vector3] = [
		Vector3(4.5, 4.6, -2.0),
		Vector3(17.5, 4.6, -2.0),
		Vector3(11.0, 4.4, -6.5),
		Vector3(11.0, 4.4, 1.5),
	]
	for i in range(positions.size()):
		_build_lantern(root, positions[i], i + 1)


func _build_lantern(parent: Node3D, pos: Vector3, index: int) -> void:
	var node := Node3D.new()
	node.name = "Lantern_%d" % index
	node.position = pos
	parent.add_child(node)

	var lamp_mat: StandardMaterial3D = _emissive_material(Color(1.0, 0.45, 0.2), 2.0)
	var mesh := SphereMesh.new()
	mesh.radius = 0.275
	mesh.height = 0.7
	var lamp := _add_mesh(node, mesh, lamp_mat, Vector3.ZERO)
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var dark_mat: StandardMaterial3D = _solid_material(Color("#2e1e12"))
	var rope_height: float = 5.95 - (pos.y + 0.35)
	_add_box(
		node,
		Vector3(0.03, rope_height, 0.03),
		dark_mat,
		Vector3(0.0, 0.35 + rope_height * 0.5, 0.0),
		"Rope"
	)
	_add_mesh(node, _lantern_disc(0.12, 0.04), dark_mat, Vector3(0.0, 0.37, 0.0))
	_add_mesh(node, _lantern_disc(0.12, 0.04), dark_mat, Vector3(0.0, -0.37, 0.0))
	_add_box(
		node,
		Vector3(0.05, 0.14, 0.05),
		_solid_material(Color("#b03028")),
		Vector3(0.0, -0.46, 0.0),
		"Tassel"
	)

	var light := _add_omni_light(
		node, Vector3.ZERO, Color(1.0, 0.62, 0.32), 7.5, 1.6
	)
	light.shadow_enabled = true


func _lantern_disc(radius: float, height: float) -> CylinderMesh:
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = height
	return disc


# ---------------------------------------------------------------- furniture

func _build_furniture() -> void:
	_furniture_root = Node3D.new()
	_furniture_root.name = "Furniture"
	add_child(_furniture_root)
	for id in furniture_entries.keys():
		var entry: Dictionary = furniture_entries[id]
		var node := Node3D.new()
		node.name = str(id)
		node.transform = _transform_from_dict(entry.get("normal", {}))
		_furniture_root.add_child(node)
		_fill_furniture(node, str(entry.get("kind", "")), entry)
		furniture_nodes[str(id)] = node


func _fill_furniture(node: Node3D, kind: String, entry: Dictionary) -> void:
	var wood: StandardMaterial3D = _wood_material(Vector2(1.0, 1.0))
	var dark: StandardMaterial3D = _solid_material(Color("#3e2a1a"))
	match kind:
		"bar":
			_add_box(node, Vector3(8.0, 1.15, 1.2), wood, Vector3(0.0, 0.575, 0.0), "BarBody")
			_add_box(node, Vector3(8.3, 0.15, 1.4), wood, Vector3(0.0, 1.225, 0.0), "BarTop")
			var bar_porcelain: StandardMaterial3D = _solid_material(Color("#efe9da"))
			for offset in [-2.5, -1.9, 2.0]:
				var bar_bowl := CylinderMesh.new()
				bar_bowl.top_radius = 0.22
				bar_bowl.bottom_radius = 0.13
				bar_bowl.height = 0.12
				_add_mesh(node, bar_bowl, bar_porcelain, Vector3(float(offset), 1.36, 0.0))
		"shelf":
			_add_box(node, Vector3(8.0, 3.2, 0.2), wood, Vector3(0.0, 1.6, -0.05), "ShelfBack")
			_add_box(node, Vector3(8.0, 0.12, 0.5), wood, Vector3(0.0, 1.0, 0.1), "ShelfLow")
			_add_box(node, Vector3(8.0, 0.12, 0.5), wood, Vector3(0.0, 2.1, 0.1), "ShelfHigh")
			_add_box(node, Vector3(8.0, 0.12, 0.5), wood, Vector3(0.0, 2.7, 0.1), "ShelfTop")
			var jar_xs: Array[float] = [-3.0, -1.8, -0.6, 0.6, 1.8, 3.0]
			var jar_fallback: StandardMaterial3D = _solid_material(Color("#8a6a3a"))
			for jar_x in jar_xs:
				var sprite := AiAssets.make_sprite(
					"prop_jars.png", 0.9, Vector3(jar_x, 1.06, 0.15), "Jar"
				)
				if sprite != null:
					node.add_child(sprite)
				else:
					var jar := CylinderMesh.new()
					jar.top_radius = 0.2
					jar.bottom_radius = 0.24
					jar.height = 0.45
					_add_mesh(node, jar, jar_fallback, Vector3(jar_x, 1.29, 0.15))
			for jar_x in [-2.4, 0.0, 2.4]:
				var mid_jar := AiAssets.make_sprite(
					"prop_jars.png", 0.42, Vector3(float(jar_x), 2.16, 0.15), "JarMid"
				)
				if mid_jar != null:
					node.add_child(mid_jar)
			for basket_x in [-2.6, 0.0, 2.6]:
				var basket := AiAssets.make_sprite(
					"prop_baskets.png", 0.44, Vector3(float(basket_x), 2.76, 0.15), "Basket"
				)
				if basket != null:
					node.add_child(basket)
				else:
					_add_box(
						node,
						Vector3(0.45, 0.3, 0.45),
						jar_fallback,
						Vector3(float(basket_x), 2.91, 0.15)
					)
		"barrel":
			_sprite_prop(
				node, "prop_barrel.png", 1.2, Vector3(0.9, 0.9, 0.9), wood
			)
		"table":
			_add_box(node, Vector3(1.8, 0.12, 1.8), wood, Vector3(0.0, 0.89, 0.0), "TableTop")
			_add_box(node, Vector3(1.86, 0.04, 1.86), dark, Vector3(0.0, 0.9, 0.0), "TableRim")
			var leg_xs: Array[float] = [-0.75, 0.75]
			for leg_x in leg_xs:
				for leg_z in leg_xs:
					_add_box(
						node,
						Vector3(0.12, 0.83, 0.12),
						dark,
						Vector3(leg_x, 0.415, leg_z)
					)
			var stool := CylinderMesh.new()
			stool.top_radius = 0.34
			stool.bottom_radius = 0.36
			stool.height = 0.16
			_add_mesh(node, stool, dark, Vector3(0.0, 0.08, 0.0), "FootStool")
		"bench":
			_sprite_prop(
				node, "prop_bench.png", 0.9, Vector3(2.0, 0.45, 0.6), wood
			)
		"crates":
			var crate_h: float = _entry_float(entry, "height", 1.3)
			_sprite_prop(
				node, "prop_crates.png", crate_h, Vector3(0.9, crate_h, 0.9), wood
			)
		"baskets":
			var basket_h: float = _entry_float(entry, "height", 0.8)
			_sprite_prop(
				node, "prop_baskets.png", basket_h, Vector3(0.7, basket_h, 0.7), dark
			)
		"crate_lid":
			var lid_mat: StandardMaterial3D = _wood_material(Vector2(0.7, 0.7))
			var crate_lid_mesh := _add_box(
				node, Vector3(0.8, 0.07, 0.75), lid_mat, Vector3(0.0, 0.06, 0.0), "CrateLid"
			)
			crate_lid_mesh.rotation.x = deg_to_rad(-58.0)
		"jars":
			_sprite_prop(
				node, "prop_jars.png", 1.0, Vector3(0.5, 0.6, 0.5), dark
			)
		"bowl":
			var porcelain: StandardMaterial3D = _solid_material(Color("#efe9da"))
			var bowl := CylinderMesh.new()
			bowl.top_radius = 0.22
			bowl.bottom_radius = 0.13
			bowl.height = 0.12
			_add_mesh(node, bowl, porcelain, Vector3(0.0, 0.06, 0.0), "Bowl")
			var soup_mat: StandardMaterial3D = _solid_material(Color("#5e1c1a"))
			var soup := CylinderMesh.new()
			soup.top_radius = 0.185
			soup.bottom_radius = 0.185
			soup.height = 0.02
			_add_mesh(node, soup, soup_mat, Vector3(0.0, 0.115, 0.0), "Soup")
			var topping_mat: StandardMaterial3D = _solid_material(Color("#e0b070"))
			var topping := CylinderMesh.new()
			topping.top_radius = 0.055
			topping.bottom_radius = 0.055
			topping.height = 0.012
			_add_mesh(node, topping, topping_mat, Vector3(0.03, 0.126, -0.02), "Topping")
		"cup":
			var cup_porcelain: StandardMaterial3D = _solid_material(Color("#efe9da"))
			var cup := CylinderMesh.new()
			cup.top_radius = 0.06
			cup.bottom_radius = 0.045
			cup.height = 0.1
			_add_mesh(node, cup, cup_porcelain, Vector3(0.0, 0.05, 0.0), "Cup")
		"abacus":
			var abacus_mat: StandardMaterial3D = _solid_material(Color("#4a3020"))
			var rod_mat: StandardMaterial3D = _solid_material(Color("#2e1e12"))
			_add_box(
				node, Vector3(0.55, 0.06, 0.4), abacus_mat, Vector3(0.0, 0.03, 0.0), "AbacusBody"
			)
			for rod_z in [-0.1, 0.1]:
				_add_box(
					node,
					Vector3(0.5, 0.02, 0.02),
					rod_mat,
					Vector3(0.0, 0.075, float(rod_z))
				)
		"rug":
			var rug_mat: StandardMaterial3D = _image_material(_rug_image())
			var rug := _add_quad(
				node, Vector2(9.0, 5.0), rug_mat, Vector3(0.0, 0.006, 0.0), "RugMesh"
			)
			rug.rotation.x = -PI / 2.0
			rug.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		"teapot":
			var pot_mat: StandardMaterial3D = _solid_material(Color("#8a5a3a"))
			var body := CylinderMesh.new()
			body.top_radius = 0.16
			body.bottom_radius = 0.2
			body.height = 0.22
			_add_mesh(node, body, pot_mat, Vector3(0.0, 0.11, 0.0), "TeapotBody")
			var lid := SphereMesh.new()
			lid.radius = 0.09
			lid.height = 0.1
			_add_mesh(node, lid, pot_mat, Vector3(0.0, 0.24, 0.0))
			_add_box(node, Vector3(0.22, 0.04, 0.05), pot_mat, Vector3(0.0, 0.2, 0.26))
		"stain":
			var stain_mat := StandardMaterial3D.new()
			stain_mat.albedo_color = Color(0.32, 0.05, 0.04, 0.55)
			stain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			stain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			stain_mat.roughness = 1.0
			stain_mat.metallic = 0.0
			stain_mat.metallic_specular = 0.0
			var quad := _add_quad(node, Vector2(3.2, 2.2), stain_mat, Vector3.ZERO, "WineStain")
			quad.rotation.x = -PI / 2.0
			quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _transform_from_dict(entry_value: Variant) -> Transform3D:
	if not (entry_value is Dictionary):
		return Transform3D.IDENTITY
	var entry: Dictionary = entry_value
	var origin := Vector3.ZERO
	var pos_value: Variant = entry.get("pos", null)
	if pos_value is Array:
		var pos: Array = pos_value
		if pos.size() >= 3:
			origin = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	var basis := Basis.IDENTITY
	var rot_value: Variant = entry.get("rot", null)
	if rot_value is Array:
		var rot: Array = rot_value
		if rot.size() >= 3:
			var euler := Vector3(
				deg_to_rad(float(rot[0])),
				deg_to_rad(float(rot[1])),
				deg_to_rad(float(rot[2]))
			)
			basis = Basis.from_euler(euler)
	return Transform3D(basis, origin)


func _state_key(entry: Dictionary, s: String) -> String:
	if entry.has(s):
		return s
	if s != "normal" and entry.has("wrecked"):
		return "wrecked"
	return "normal"


func _transform_for(entry: Dictionary, s: String) -> Transform3D:
	var key: String = _state_key(entry, s)
	var value: Variant = entry.get(key, null)
	if value is Dictionary:
		return _transform_from_dict(value)
	var normal_value: Variant = entry.get("normal", null)
	return _transform_from_dict(normal_value)


func _visible_for(entry: Dictionary, s: String) -> bool:
	var hidden_value: Variant = entry.get("hidden_in", [])
	if hidden_value is Array:
		var hidden: Array = hidden_value
		return not hidden.has(s)
	return true


func furniture_target(id: String) -> Transform3D:
	var entry_value: Variant = furniture_entries.get(id, null)
	if not (entry_value is Dictionary):
		return Transform3D.IDENTITY
	return _transform_for(entry_value, state)


func fallen_table_count() -> int:
	var count := 0
	for id in furniture_entries.keys():
		var entry: Dictionary = furniture_entries[id]
		if str(entry.get("kind", "")) != "table":
			continue
		var node_value: Variant = furniture_nodes.get(id, null)
		if not (node_value is Node3D):
			continue
		var node: Node3D = node_value
		if absf(node.rotation.z) > 0.5 or absf(node.rotation.x) > 0.5:
			count += 1
	return count


# ---------------------------------------------------------------- state changes

func _apply_state(new_state: String, animate: bool) -> void:
	_anim_furniture.clear()
	_anim_npcs.clear()
	_anim_active = false
	_anim_t = 0.0
	for id in furniture_entries.keys():
		var entry: Dictionary = furniture_entries[id]
		var node_value: Variant = furniture_nodes.get(id, null)
		if not (node_value is Node3D):
			continue
		var node: Node3D = node_value
		var target: Transform3D = _transform_for(entry, new_state)
		node.visible = _visible_for(entry, new_state)
		if animate:
			_anim_furniture.append({
				"node": node,
				"from": node.transform,
				"to": target,
			})
		else:
			node.transform = target
	_sync_npcs(new_state, animate)
	if animate and (not _anim_furniture.is_empty() or not _anim_npcs.is_empty()):
		_anim_active = true


func advance(delta: float) -> void:
	if not _anim_active:
		return
	_anim_t += delta
	var weight := clampf(_anim_t / ANIM_DURATION, 0.0, 1.0)
	for record_value in _anim_furniture:
		if not (record_value is Dictionary):
			continue
		var record: Dictionary = record_value
		var node_value: Variant = record.get("node", null)
		if not (node_value is Node3D):
			continue
		var node: Node3D = node_value
		var from: Transform3D = record.get("from", Transform3D.IDENTITY)
		var to: Transform3D = record.get("to", Transform3D.IDENTITY)
		var from_q: Quaternion = from.basis.get_rotation_quaternion()
		var to_q: Quaternion = to.basis.get_rotation_quaternion()
		var basis := Basis(from_q.slerp(to_q, weight))
		node.transform = Transform3D(basis, from.origin.lerp(to.origin, weight))
	for record_value in _anim_npcs:
		if not (record_value is Dictionary):
			continue
		var record: Dictionary = record_value
		var node_value: Variant = record.get("node", null)
		if not (node_value is Node3D):
			continue
		var node: Node3D = node_value
		var from: Vector3 = record.get("from", Vector3.ZERO)
		var to: Vector3 = record.get("to", Vector3.ZERO)
		node.position = from.lerp(to, weight)
	if weight >= 1.0:
		_finish_animation()


func _finish_animation() -> void:
	for record_value in _anim_furniture:
		var record: Dictionary = record_value
		var node_value: Variant = record.get("node", null)
		if node_value is Node3D:
			var target_transform: Transform3D = record.get("to", Transform3D.IDENTITY)
			(node_value as Node3D).transform = target_transform
	for record_value in _anim_npcs:
		var record: Dictionary = record_value
		var node_value: Variant = record.get("node", null)
		if node_value is Node3D:
			var node: Node3D = node_value
			var target_position: Vector3 = record.get("to", Vector3.ZERO)
			node.position = target_position
			node.call("set_moving", false)
	_anim_furniture.clear()
	_anim_npcs.clear()
	_anim_active = false
	_anim_t = 0.0


# ---------------------------------------------------------------- npcs

func _sync_npcs(new_state: String, animate: bool) -> void:
	if _npc_root == null:
		_npc_root = Node3D.new()
		_npc_root.name = "NPCs"
		add_child(_npc_root)
	for id in npc_nodes.keys():
		var entry_value: Variant = _npc_entries.get(id, null)
		var present := false
		if entry_value is Dictionary:
			present = _npc_present(entry_value, new_state)
		if not present:
			_remove_npc(str(id))
	for id in _npc_entries.keys():
		var entry: Dictionary = _npc_entries[id]
		if not _npc_present(entry, new_state):
			continue
		var target: Vector3 = _npc_position(entry, new_state)
		if npc_nodes.has(id):
			var node: Node3D = npc_nodes[id]
			node.visible = true
			if animate:
				_anim_npcs.append({
					"node": node,
					"from": node.position,
					"to": target,
				})
			else:
				node.position = target
		else:
			var character: Variant = CharacterSprite.new()
			character.name = str(id)
			character.setup(str(entry.get("sprite", "")))
			character.set_facing(str(entry.get("facing", "down")))
			if animate:
				character.position = _entrance_position()
				character.call("set_moving", true)
				_anim_npcs.append({
					"node": character,
					"from": character.position,
					"to": target,
				})
			else:
				character.position = target
			_npc_root.add_child(character)
			npc_nodes[str(id)] = character


func _remove_npc(id: String) -> void:
	var node_value: Variant = npc_nodes.get(id, null)
	npc_nodes.erase(id)
	if not (node_value is Node):
		return
	var node: Node = node_value
	var parent: Node = node.get_parent()
	if parent != null:
		parent.remove_child(node)
	if node.is_inside_tree():
		node.queue_free()
	else:
		node.free()


func _npc_present(entry: Dictionary, s: String) -> bool:
	var states_value: Variant = entry.get("states", STATES)
	if states_value is Array:
		var states: Array = states_value
		return states.has(s)
	return true


func _npc_position(entry: Dictionary, s: String) -> Vector3:
	var positions_value: Variant = entry.get("positions", null)
	if not (positions_value is Dictionary):
		return Vector3.ZERO
	var positions: Dictionary = positions_value
	var key := "normal"
	if positions.has(s):
		key = s
	elif positions.size() > 0:
		key = str(positions.keys()[0])
	var pos_value: Variant = positions.get(key, null)
	if pos_value is Array:
		var pos: Array = pos_value
		if pos.size() >= 2:
			return Vector3(float(pos[0]), 0.0, float(pos[1]))
	return Vector3.ZERO


func npc_target_position(id: String) -> Vector3:
	var entry_value: Variant = _npc_entries.get(id, null)
	if not (entry_value is Dictionary):
		return Vector3.ZERO
	return _npc_position(entry_value, state)


func _entrance_position() -> Vector3:
	var entrance_value: Variant = data.get("entrance", null)
	if entrance_value is Dictionary:
		var entrance: Dictionary = entrance_value
		return Vector3(
			float(entrance.get("x", 11.0)), 0.0, float(entrance.get("z", 5.5))
		)
	return Vector3(11.0, 0.0, 5.5)


func nearby_npc() -> String:
	var positions: Dictionary = {}
	for id in npc_nodes.keys():
		var node_value: Variant = npc_nodes[id]
		if not (node_value is Node3D):
			continue
		var node: Node3D = node_value
		if not node.visible:
			continue
		positions[str(id)] = Vector2(node.position.x, node.position.z)
	return Interaction.nearest_npc(player_pos, positions)


func _npc_entry(npc_id: String) -> Dictionary:
	var value: Variant = _npc_entries.get(npc_id, null)
	if value is Dictionary:
		return value
	return {}


func _npc_dialogue_path(npc_id: String, s: String) -> String:
	var entry: Dictionary = _npc_entry(npc_id)
	var dialogues_value: Variant = entry.get("dialogues", null)
	if dialogues_value is Dictionary:
		var dialogues: Dictionary = dialogues_value
		if dialogues.has(s):
			return str(dialogues[s])
		if dialogues.has("normal"):
			return str(dialogues["normal"])
		if dialogues.size() > 0:
			return str(dialogues[dialogues.keys()[0]])
	return str(entry.get("dialogue", ""))


func _npc_display_name(npc_id: String) -> String:
	var entry: Dictionary = _npc_entry(npc_id)
	return str(entry.get("name", npc_id))


# ---------------------------------------------------------------- player

func _build_player() -> void:
	var spawn_value: Variant = data.get("spawn", null)
	var px := 11.0
	var pz := 3.5
	var facing := "up"
	if spawn_value is Dictionary:
		var spawn: Dictionary = spawn_value
		px = float(spawn.get("x", px))
		pz = float(spawn.get("z", pz))
		facing = str(spawn.get("facing", facing))
	var character := CharacterSprite.new()
	character.name = "Player"
	character.setup("ren_xiaoyao")
	character.position = Vector3(px, 0.0, pz)
	character.set_facing(facing)
	add_child(character)
	player = character
	player_pos = Vector2(px, pz)
	follow_target = player


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
	var weight: float = 1.0 - exp(-14.0 * delta)
	var next_y: float = lerpf(player.position.y, 0.0, weight)
	player.position = Vector3(player_pos.x, next_y, player_pos.y)
	var facing: String = PlayerMotion.facing_from_input(input, str(player.get("facing")))
	player.call("set_facing", facing)
	player.call("set_moving", input.length() > 0.01)


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
	var dist: float = CAMERA_OFFSET.length()
	attributes.dof_blur_far_distance = dist + 14.0
	attributes.dof_blur_far_transition = 22.0
	attributes.dof_blur_near_enabled = true
	attributes.dof_blur_near_distance = dist - 9.0
	attributes.dof_blur_near_transition = 8.0
	attributes.dof_blur_amount = 0.08
	return attributes


func _follow_position() -> Vector3:
	if follow_target == null:
		return Vector3(11.0, 0.0, 3.5)
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
	camera.look_at_from_position(camera.position, _focus + LOOK_AHEAD, Vector3.UP)


func snap_camera() -> void:
	if camera == null:
		return
	var target_pos := _follow_position()
	_focus = target_pos
	camera.position = target_pos + CAMERA_OFFSET
	camera.look_at_from_position(camera.position, _focus + LOOK_AHEAD, Vector3.UP)


# ---------------------------------------------------------------- lighting

func _build_lighting() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "FillLight"
	sun.rotation_degrees = Vector3(-52.0, -25.0, 0.0)
	sun.light_color = Color("#ffd2a0")
	sun.light_energy = 0.35
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	sun.shadow_bias = 0.05
	add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#17100c")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#3a3038")
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 0.9
	world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)

	# Small warm pool above the bar counter.
	_add_omni_light(
		self, Vector3(5.5, 3.2, -9.8), Color(1.0, 0.7, 0.45), 5.0, 1.0
	)

	var lights: Array = data.get("lights", [])
	for i in range(lights.size()):
		var light_value: Variant = lights[i]
		if not (light_value is Dictionary):
			continue
		var light_data: Dictionary = light_value
		var pos_value: Variant = light_data.get("pos", [])
		if not (pos_value is Array) or (pos_value as Array).size() < 3:
			continue
		var pos: Array = pos_value
		var color := Color(str(light_data.get("color", "#ffb066")))
		var range_m := float(light_data.get("range", 9.0))
		var energy := float(light_data.get("energy", 1.2))
		_add_omni_light(
			self, Vector3(float(pos[0]), float(pos[1]), float(pos[2])), color, range_m, energy
		)

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


# ---------------------------------------------------------------- stairs

func _build_stairs() -> void:
	var root := Node3D.new()
	root.name = "Stairs"
	add_child(root)
	var stairs_value: Variant = data.get("stairs", null)
	var depth := 0.5
	if stairs_value is Dictionary:
		var stairs: Dictionary = stairs_value
		var sx0 := float(stairs.get("x0", 19.0))
		var sx1 := float(stairs.get("x1", 22.0))
		var z_top := float(stairs.get("z_top", -8.0))
		var z_bottom := float(stairs.get("z_bottom", -5.0))
		var steps: int = int(stairs.get("steps", 6))
		var height := float(stairs.get("height", 3.0))
		var step_mat: StandardMaterial3D = _wood_material(Vector2(1.0, 1.0))
		if steps > 0:
			depth = (z_bottom - z_top) / float(steps)
			for i in range(steps):
				var step_h := height - (height / float(steps)) * float(i)
				var z_center := z_top + depth * (float(i) + 0.5)
				_add_box(
					root,
					Vector3(sx1 - sx0, step_h, depth),
					step_mat,
					Vector3((sx0 + sx1) * 0.5, step_h * 0.5, z_center)
				)

	var platform_value: Variant = data.get("platform", null)
	if platform_value is Dictionary:
		var platform: Dictionary = platform_value
		var px0 := float(platform.get("x0", 16.5))
		var px1 := float(platform.get("x1", 22.0))
		var pz0 := float(platform.get("z0", -12.0))
		var pz1 := float(platform.get("z1", -8.0))
		var py := float(platform.get("y", 3.0))
		var deck_mat: StandardMaterial3D = _wood_material(Vector2(1.0, 1.0))
		_add_box(
			root,
			Vector3(px1 - px0, 0.3, pz1 - pz0),
			deck_mat,
			Vector3((px0 + px1) * 0.5, py - 0.15, (pz0 + pz1) * 0.5),
			"CorridorDeck"
		)
		# Railing along the front edge of the corridor.
		var rail_mat: StandardMaterial3D = _solid_material(Color("#3e2a1a"))
		var rail_x := px0 + 0.3
		while rail_x <= px1 - 0.2:
			_add_box(
				root,
				Vector3(0.1, 0.95, 0.1),
				rail_mat,
				Vector3(rail_x, py + 0.475, pz1 - 0.1)
			)
			rail_x += 1.1
		_add_box(
			root,
			Vector3(px1 - px0, 0.08, 0.1),
			rail_mat,
			Vector3((px0 + px1) * 0.5, py + 0.95, pz1 - 0.1)
		)
		# A heavier handrail along the top, plus two post lamps (no light source).
		_add_box(
			root,
			Vector3(px1 - px0, 0.12, 0.18),
			rail_mat,
			Vector3((px0 + px1) * 0.5, py + 1.04, pz1 - 0.1),
			"Handrail"
		)
		var lamp_mat: StandardMaterial3D = _emissive_material(Color(1.0, 0.55, 0.28), 1.6)
		for lamp_x in [px0 + 1.1, px1 - 1.1]:
			_add_box(
				root,
				Vector3(0.12, 1.9, 0.12),
				rail_mat,
				Vector3(float(lamp_x), py + 0.95, pz1 - 0.1)
			)
			_add_box(
				root,
				Vector3(0.26, 0.3, 0.26),
				lamp_mat,
				Vector3(float(lamp_x), py + 2.05, pz1 - 0.1)
			)


# ---------------------------------------------------------------- hud / interaction

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


func is_in_exit() -> bool:
	if exit_rect.size != Vector2.ZERO and exit_rect.has_point(player_pos):
		return true
	var z_front := _room_float("z_front", 6.0)
	return player_pos.y >= z_front - 1.0


func try_interact() -> bool:
	if is_dialogue_active():
		return false
	var npc_id: String = nearby_npc()
	if npc_id != "" and not _npc_entry(npc_id).is_empty():
		var path := _npc_dialogue_path(npc_id, state)
		if path != "":
			return _start_npc_dialogue(npc_id, path)
	if is_in_exit():
		emit_signal("exit_requested")
		return true
	return false


func _start_npc_dialogue(npc_id: String, path: String) -> bool:
	current_npc_id = npc_id
	_face_player(npc_id)

	var speakers: Dictionary = Dialogue.load_speakers(SPEAKERS_PATH).get("defs", {})
	var loaded: Dictionary = Dialogue.load_file(path, speakers)
	var errors: Array = loaded.get("errors", [])
	if not errors.is_empty():
		for error_text in errors:
			push_warning("tavern dialogue: %s" % str(error_text))
		current_npc_id = ""
		return false

	pending_encounter = {}
	var entry: Dictionary = _npc_entry(npc_id)
	var encounter_value: Variant = entry.get("encounter", null)
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
	if npc_id != "":
		prompt_label.text = "按 E 与 %s 交谈" % _npc_display_name(npc_id)
		prompt_label.visible = true
		return
	if is_in_exit():
		prompt_label.text = exit_prompt
		prompt_label.visible = true
		return
	prompt_label.visible = false


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

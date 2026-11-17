extends Node3D

signal exit_requested(place: String)
signal encounter_requested(enemy_id: String, count: int, first_strike: bool)

const FOREST_PATH := "res://data/forest.json"
const CAMERA_OFFSET := Vector3(0.0, 16.7, 37.5)
# Look slightly north of the player so the characters sit in the lower half of the frame.
const LOOK_AHEAD := Vector3(0.0, 1.0, -4.0)

const INTERACT_RANGE := 1.8
const CHEST_OPEN_DURATION := 0.6
const CHEST_SPRITE_DURATION := 0.5
const CHEST_SWAP_TIME := 0.25
const CHEST_LID_ANGLE := 70.0
const CAMP_LIGHT_ENERGY := 1.2
const CAMP_LIGHT_FLICKER := 0.08
const CAMP_LIGHT_FLICKER_SPEED := 0.9

const PATROL_SPEED := 1.6
const PATROL_WAIT := 1.2
const PATROL_GAP := 1.2
const PATROL_TURN_TIME := 0.6
const PATROL_TURN_ANGLE := PI * 35.0 / 180.0
const SCOUT_VIEW_DISTANCE := 5.0
const SCOUT_HALF_ANGLE := PI * 30.0 / 180.0
const ALERT_DELAY := 0.6
const ALERT_MARK_HEIGHT := 2.6
const VIEW_CONE_SHOW_DISTANCE := 12.0
const VIEW_CONE_COLOR := Color(1.0, 0.3, 0.2, 0.18)
const CROUCH_SPEED_MULT := 0.5
const CROUCH_SCALE_Y := 0.8
const CROUCH_TINT := Color(0.8, 0.8, 0.8, 1.0)

const TREE_TARGET := 90
const TREE_SEED := 20261117
const TREE_GAP := 1.6
const ROAD_CLEARANCE := 2.5
const ARENA_CLEARANCE := 9.0
const SPAWN_CLEARANCE := 3.0
const CHEST_CLEARANCE := 2.5
const HERB_CLEARANCE := 1.5
const EXIT_CLEARANCE := 1.0
const ROCK_ROAD_CLEARANCE := 2.4
const ROCK_MAX_ROAD_DISTANCE := 4.5
const BOUNDS_INSET := 0.8
const CAMP_CLEAR_RADIUS := 2.5

const TREE_SPECIES := [
	{"file": "prop_willow.png", "weight": 20.0, "min_height": 4.2, "max_height": 6.0},
	{"file": "tree_camphor.png", "weight": 22.0, "min_height": 4.5, "max_height": 6.0},
	{"file": "tree_oak.png", "weight": 18.0, "min_height": 4.5, "max_height": 6.2},
	{"file": "tree_pine.png", "weight": 18.0, "min_height": 5.0, "max_height": 7.0},
	{"file": "tree_poplar.png", "weight": 10.0, "min_height": 6.0, "max_height": 8.0},
	{"file": "tree_maple.png", "weight": 8.0, "min_height": 4.0, "max_height": 5.5},
	{"file": "tree_dead.png", "weight": 4.0, "min_height": 3.6, "max_height": 5.0},
]

const Texgen = preload("res://world/texgen.gd")
const AiAssets = preload("res://world/ai_assets.gd")
const CharacterSprite = preload("res://world/character_sprite.gd")
const PlayerMotion = preload("res://world/player_motion.gd")
const Stealth = preload("res://world/stealth.gd")
const GameState = preload("res://core/game_state.gd")
const Progression = preload("res://core/progression.gd")

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
var bounds_rect: Rect2 = Rect2()
var camera: Camera3D = null
var follow_target: Node3D = null
var sun: DirectionalLight3D = null
var world_env: WorldEnvironment = null
var player: Node3D = null
var player_pos: Vector2 = Vector2.ZERO
var dialogue_view: Control = null
var prompt_label: Label = null
var current_npc_id: String = ""
var skip_actors: bool = false
var input_blocked: bool = false
var arena_origin: Vector3 = Vector3.ZERO
var tree_positions: Array[Vector2] = []
var rock_positions: Array[Vector2] = []
var hide_spots: Array = []
var exits: Dictionary = {}
var pickups: Array = []
var chest_node: Node3D = null
var chest_pivot: Node3D = null
var chest_sprite: Sprite3D = null
var chest_opened: bool = false
var patrol_groups: Array = []
var scout: Dictionary = {}
var crouch_hint: Label = null

var _input_override: Variant = null
var _crouch_override: Variant = null
var _built: bool = false
var _textures: Dictionary = {}
var _road_points: Array[Vector2] = []
var _spawn: Dictionary = {}
var _chest_anim_t: float = -1.0
var _chest_swapped: bool = false
var _tree_style_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _camp_light: OmniLight3D = null
var _time: float = 0.0
var _focus: Vector3 = Vector3.ZERO
var _hud_layer: CanvasLayer = null
var _patrol_root: Node3D = null
var _alerted: bool = false
var _alert_timer: float = 0.0
var _encounter_sent: bool = false
var _pending_encounter: Dictionary = {}


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
	_add_action("crouch", KEY_SHIFT, KEY_NONE)


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
	blockers.clear()
	tree_positions.clear()
	rock_positions.clear()
	_build_ground()
	_build_vegetation()
	_build_backdrop()
	_build_lighting()
	_build_camera()
	if not skip_actors:
		_build_patrols()
		_build_pickups()
		_build_chest()
		_build_player()
		snap_camera()


func _process(delta: float) -> void:
	tick_player(delta)
	advance_patrols(delta)
	advance_chest(delta)
	update_prompt()
	if not is_dialogue_active() and InputMap.has_action("interact") \
			and Input.is_action_just_pressed("interact"):
		try_interact()
	_time += delta
	_update_camp_light()
	update_camera(delta)


# ---------------------------------------------------------------- data

func _load_data() -> void:
	data = {}
	exits.clear()
	pickups.clear()
	hide_spots.clear()
	_road_points.clear()
	if not FileAccess.file_exists(FOREST_PATH):
		push_warning("forest: %s not found" % FOREST_PATH)
		return
	var text: String = FileAccess.get_file_as_string(FOREST_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("forest: invalid JSON in %s" % FOREST_PATH)
		return
	data = parsed
	bounds_rect = _read_bounds()
	_spawn = _read_spawn()
	arena_origin = _read_arena_origin()
	_road_points = _read_road()
	_read_exits()
	_read_pickups()
	_read_hide_spots()


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


func _read_spawn() -> Dictionary:
	var spawn_value: Variant = data.get("spawn", null)
	if spawn_value is Dictionary:
		return spawn_value
	return {}


func _read_arena_origin() -> Vector3:
	var arena_value: Variant = data.get("arena", null)
	if not (arena_value is Dictionary):
		return Vector3.ZERO
	var arena: Dictionary = arena_value
	var origin_value: Variant = arena.get("origin", null)
	if origin_value is Array:
		var origin: Array = origin_value
		if origin.size() >= 3:
			return Vector3(float(origin[0]), float(origin[1]), float(origin[2]))
	return Vector3.ZERO


func _read_road() -> Array[Vector2]:
	var result: Array[Vector2] = []
	var road_value: Variant = data.get("road", [])
	if not (road_value is Array):
		return result
	var road: Array = road_value
	for point_value in road:
		if not (point_value is Array):
			continue
		var point: Array = point_value
		if point.size() < 2:
			continue
		result.append(Vector2(float(point[0]), float(point[1])))
	return result


func _read_exits() -> void:
	var exits_value: Variant = data.get("exits", {})
	if not (exits_value is Dictionary):
		return
	var exit_entries: Dictionary = exits_value
	for key in exit_entries.keys():
		var entry_value: Variant = exit_entries[key]
		if not (entry_value is Dictionary):
			continue
		var entry: Dictionary = entry_value
		var rect: Rect2 = _rect_from_array(entry.get("rect", []))
		if rect.size == Vector2.ZERO:
			continue
		exits[str(key)] = {"rect": rect, "prompt": str(entry.get("prompt", ""))}


func _read_pickups() -> void:
	var pickup_data: Array = data.get("pickups", [])
	for i in range(pickup_data.size()):
		var pickup_value: Variant = pickup_data[i]
		if not (pickup_value is Dictionary):
			continue
		var pickup: Dictionary = pickup_value
		pickups.append({
			"id": int(pickup.get("id", i + 1)),
			"kind": str(pickup.get("kind", "herb")),
			"item": str(pickup.get("item", "")),
			"flag": str(pickup.get("flag", "")),
			"pos": Vector2(float(pickup.get("x", 0.0)), float(pickup.get("z", 0.0))),
			"node": null,
		})


func _read_hide_spots() -> void:
	var hide_data: Array = data.get("hide_spots", [])
	for hide_value in hide_data:
		if not (hide_value is Dictionary):
			continue
		var hide: Dictionary = hide_value
		hide_spots.append({
			"pos": Vector2(float(hide.get("x", 0.0)), float(hide.get("z", 0.0))),
			"radius": float(hide.get("radius", 1.8)),
			"road": bool(hide.get("road", false)),
		})


func _rect_from_array(value: Variant) -> Rect2:
	if not (value is Array):
		return Rect2()
	var rect: Array = value
	if rect.size() < 4:
		return Rect2()
	var x0 := float(rect[0])
	var z0 := float(rect[1])
	var x1 := float(rect[2])
	var z1 := float(rect[3])
	if x1 <= x0 or z1 <= z0:
		return Rect2()
	return Rect2(x0, z0, x1 - x0, z1 - z0)


# ---------------------------------------------------------------- helpers

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


func _grass_material(uv_scale: Vector2) -> StandardMaterial3D:
	var tex: ImageTexture = AiAssets.load_texture("tex_forest_floor.png")
	if tex == null:
		tex = AiAssets.load_texture("tex_grass.png")
	if tex == null:
		tex = Texgen.make_texture(Texgen.grass(), true)
	return Texgen.make_material(tex, uv_scale)


func _path_material(uv_scale: Vector2) -> StandardMaterial3D:
	var tex: ImageTexture = AiAssets.load_texture("tex_forest_path.png")
	if tex == null:
		return _dirt_material(uv_scale)
	return Texgen.make_material(tex, uv_scale)


func _dirt_material(uv_scale: Vector2) -> StandardMaterial3D:
	var tex: ImageTexture = AiAssets.load_texture("tex_dirt.png")
	if tex == null:
		tex = Texgen.make_texture(Texgen.stone_street(), true)
	return Texgen.make_material(tex, uv_scale)


func _dark_wood_material() -> StandardMaterial3D:
	var tex: ImageTexture = AiAssets.load_texture("tex_dark_wood.png")
	if tex != null:
		return Texgen.make_material(tex, Vector2(1.0, 1.0))
	return _solid_material(Color("#4a3020"))


func _in_bounds(point: Vector2) -> bool:
	if bounds_rect.size == Vector2.ZERO:
		return true
	return point.x >= bounds_rect.position.x + BOUNDS_INSET \
		and point.x <= bounds_rect.end.x - BOUNDS_INSET \
		and point.y >= bounds_rect.position.y + BOUNDS_INSET \
		and point.y <= bounds_rect.end.y - BOUNDS_INSET


func _spawn_point() -> Vector2:
	return Vector2(
		float(_spawn.get("x", 0.0)),
		float(_spawn.get("z", 21.5))
	)


func _road_distance(point: Vector2) -> float:
	if _road_points.size() < 2:
		return 9999.0
	var best := 9999.0
	for i in range(_road_points.size() - 1):
		var a: Vector2 = _road_points[i]
		var b: Vector2 = _road_points[i + 1]
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(point, a, b)
		best = minf(best, point.distance_to(closest))
	return best


func _point_blocked(point: Vector2, radius: float) -> bool:
	for value in blockers:
		var rect: Rect2 = value
		if rect.grow(radius).has_point(point):
			return true
	return false


func _is_clear(
	point: Vector2, road_clearance: float, arena_clearance: float, tree_gap: float
) -> bool:
	if not _in_bounds(point):
		return false
	if _road_distance(point) < road_clearance:
		return false
	if point.distance_to(_spawn_point()) < SPAWN_CLEARANCE:
		return false
	if point.distance_to(Vector2(arena_origin.x, arena_origin.z)) < arena_clearance:
		return false
	for pickup_value in pickups:
		var pickup: Dictionary = pickup_value
		var pos_value: Variant = pickup.get("pos", Vector2.ZERO)
		if not (pos_value is Vector2):
			continue
		var radius := HERB_CLEARANCE
		if str(pickup.get("kind", "herb")) == "chest":
			radius = CHEST_CLEARANCE
		var pickup_pos: Vector2 = pos_value
		if point.distance_to(pickup_pos) < radius:
			return false
	for key in exits.keys():
		var entry_value: Variant = exits[key]
		if not (entry_value is Dictionary):
			continue
		var entry: Dictionary = entry_value
		var rect_value: Variant = entry.get("rect", Rect2())
		if not (rect_value is Rect2):
			continue
		var exit_rect: Rect2 = rect_value
		if exit_rect.grow(EXIT_CLEARANCE).has_point(point):
			return false
	for other_value in tree_positions:
		var other: Vector2 = other_value
		if point.distance_to(other) < tree_gap:
			return false
	return true


# ---------------------------------------------------------------- ground

func _build_ground() -> void:
	var root := Node3D.new()
	root.name = "Ground"
	add_child(root)
	# A dull meadow plane under everything so the camera never sees the void.
	var fill := MeshInstance3D.new()
	fill.name = "GroundFill"
	var fill_mesh := PlaneMesh.new()
	fill_mesh.size = Vector2(160.0, 160.0)
	fill.mesh = fill_mesh
	var fill_mat: StandardMaterial3D = _solid_material(Color("#4a5a30"))
	var fill_tex: ImageTexture = AiAssets.load_texture("tex_forest_floor.png")
	if fill_tex == null:
		fill_tex = AiAssets.load_texture("tex_grass.png")
	if fill_tex != null:
		fill_mat = Texgen.make_material(fill_tex, Vector2(40.0, 40.0))
		fill_mat.albedo_color = Color(0.8, 0.85, 0.75)
	fill.material_override = fill_mat
	fill.position = Vector3(0.0, -0.05, 0.0)
	root.add_child(fill)

	var grounds: Array = data.get("ground", [])
	var dirt_index := 0
	for i in range(grounds.size()):
		var ground_value: Variant = grounds[i]
		if not (ground_value is Dictionary):
			continue
		var ground: Dictionary = ground_value
		var rect: Rect2 = _rect_from_array(ground.get("rect", []))
		if rect.size == Vector2.ZERO:
			continue
		var kind := str(ground.get("type", "grass"))
		var y := 0.0
		var center: Vector2 = rect.get_center()
		var plane := PlaneMesh.new()
		if kind == "dirt":
			# Nudge overlapping road rectangles apart so their seams do not z-fight.
			y = 0.01 + 0.001 * float(dirt_index)
			dirt_index += 1
			var path_tex: ImageTexture = AiAssets.load_texture("tex_forest_path.png")
			var horizontal := rect.size.x > rect.size.y
			var road_width := rect.size.y if horizontal else rect.size.x
			var road_length := rect.size.x if horizontal else rect.size.y
			if path_tex != null:
				# The path art runs vertically. Horizontal stretches rotate the mesh
				# 90 degrees so the painted path follows the road.
				if horizontal:
					plane.size = Vector2(road_width, road_length)
				else:
					plane.size = rect.size
				var mat := _path_material(Vector2(1.0, road_length / 3.0))
				var path_node := _add_mesh(
					root, plane, mat, Vector3(center.x, y, center.y), "Ground_%d" % i
				)
				if horizontal:
					path_node.rotation.y = PI * 0.5
			else:
				plane.size = rect.size
				var fallback := _dirt_material(
					Vector2(rect.size.x / 3.0, rect.size.y / 3.0)
				)
				_add_mesh(root, plane, fallback, Vector3(center.x, y, center.y), "Ground_%d" % i)
		else:
			plane.size = rect.size
			var mat := _grass_material(Vector2(rect.size.x / 4.0, rect.size.y / 4.0))
			_add_mesh(root, plane, mat, Vector3(center.x, y, center.y), "Ground_%d" % i)


# ---------------------------------------------------------------- vegetation

func _build_vegetation() -> void:
	var root := Node3D.new()
	root.name = "Vegetation"
	add_child(root)
	_generate_trees(root)
	_generate_rocks(root)
	_generate_bamboo(root)
	_generate_shrubs(root)
	_generate_grass(root)
	_build_camp()
	_build_signpost(root)
	_build_path_fences(root)
	_generate_floor_props(root)


func _generate_trees(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = TREE_SEED
	# A separate stream chooses the species and height so the legacy rng keeps
	# producing exactly the same tree positions as before.
	_tree_style_rng = RandomNumberGenerator.new()
	_tree_style_rng.seed = TREE_SEED + 11
	var tree_root := Node3D.new()
	tree_root.name = "Trees"
	root.add_child(tree_root)
	# Dense wall around the edges, spaced roughly three units apart. The south and
	# north gaps line up with the two exits.
	for edge in range(4):
		var t := -23.0
		while t <= 23.0:
			var point := Vector2.ZERO
			match edge:
				0:
					point = Vector2(t, 23.0)
				1:
					point = Vector2(t, -23.0)
				2:
					point = Vector2(-23.0, t)
				_:
					point = Vector2(23.0, t)
			if _is_clear(point, ROAD_CLEARANCE, ARENA_CLEARANCE, TREE_GAP):
				_add_tree(tree_root, point, rng)
			t += 3.0
	# Scattered interior trees fill in the rest of the wall of trees.
	var attempts := 0
	while tree_positions.size() < TREE_TARGET and attempts < 8000:
		attempts += 1
		var point := Vector2(rng.randf_range(-22.0, 22.0), rng.randf_range(-22.0, 22.0))
		if not _is_clear(point, ROAD_CLEARANCE, ARENA_CLEARANCE, TREE_GAP):
			continue
		_add_tree(tree_root, point, rng)
	_generate_outer_trees(tree_root)


# Purely decorative trees beyond the playable bounds so the camera never sees bare ground.
func _generate_outer_trees(tree_root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = TREE_SEED + 7
	var count := 0
	var z := 26.5
	while z <= 31.0:
		var x := -44.0
		while x <= 44.0:
			var point := Vector2(x + rng.randf_range(-1.0, 1.0), z + rng.randf_range(-1.0, 1.0))
			if absf(point.x) > 5.5:
				_add_outer_tree(tree_root, point, rng, count)
			count += 1
			x += 3.4
		z += 3.6
	for side in [-1.0, 1.0]:
		var zz := -22.0
		while zz <= 26.0:
			var xx := 26.5
			while xx <= 40.0:
				var point := Vector2(side * (xx + rng.randf_range(-1.0, 1.0)), zz + rng.randf_range(-1.0, 1.0))
				_add_outer_tree(tree_root, point, rng, count)
				count += 1
				xx += 3.6
			zz += 3.4


func _add_outer_tree(root: Node3D, point: Vector2, rng: RandomNumberGenerator, index: int) -> void:
	# Keep the legacy height roll in the stream even though the species table
	# now decides the visible height.
	var _legacy_height := rng.randf_range(4.2, 6.2)
	var species := _pick_tree_species(_tree_style_rng)
	var height := _tree_style_rng.randf_range(
		float(species["min_height"]), float(species["max_height"])
	)
	var sprite := _make_tree_sprite(str(species["file"]), height, point, "OuterTree_%d" % index)
	if sprite != null:
		root.add_child(sprite)


func _add_tree(root: Node3D, point: Vector2, rng: RandomNumberGenerator) -> void:
	var index := tree_positions.size()
	# Keep the legacy height roll in the stream even though the species table
	# now decides the visible height.
	var _legacy_height := rng.randf_range(4.0, 6.0)
	var species := _pick_tree_species(_tree_style_rng)
	var height := _tree_style_rng.randf_range(
		float(species["min_height"]), float(species["max_height"])
	)
	var sprite := _make_tree_sprite(str(species["file"]), height, point, "Tree_%d" % index)
	if sprite != null:
		root.add_child(sprite)
	tree_positions.append(point)
	blockers.append(Rect2(point.x - 0.5, point.y - 0.5, 1.0, 1.0))


func _pick_tree_species(rng: RandomNumberGenerator) -> Dictionary:
	var roll := rng.randf_range(0.0, 100.0)
	var accumulated := 0.0
	for entry_value in TREE_SPECIES:
		var entry: Dictionary = entry_value
		accumulated += float(entry["weight"])
		if roll < accumulated:
			return entry
	return TREE_SPECIES[0]


func _make_tree_sprite(
	file: String, height: float, point: Vector2, node_name: String
) -> Sprite3D:
	var sprite := AiAssets.make_sprite(
		file, height, Vector3(point.x, 0.0, point.y), node_name
	)
	if sprite == null:
		sprite = AiAssets.make_sprite(
			"prop_willow.png", height, Vector3(point.x, 0.0, point.y), node_name
		)
	return sprite


func _generate_rocks(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = TREE_SEED + 1
	var rock_root := Node3D.new()
	rock_root.name = "Rocks"
	root.add_child(rock_root)
	var added := 0
	var attempts := 0
	while added < 12 and attempts < 5000:
		attempts += 1
		var point := Vector2(rng.randf_range(-22.0, 22.0), rng.randf_range(-22.0, 22.0))
		if not _is_clear(point, ROCK_ROAD_CLEARANCE, ARENA_CLEARANCE, 1.0):
			continue
		var road_distance := _road_distance(point)
		if road_distance > ROCK_MAX_ROAD_DISTANCE:
			continue
		var height := rng.randf_range(0.6, 1.0)
		var sprite := AiAssets.make_sprite(
			"prop_rocks.png", height, Vector3(point.x, 0.0, point.y), "Rock_%d" % added
		)
		if sprite != null:
			rock_root.add_child(sprite)
		rock_positions.append(point)
		blockers.append(Rect2(point.x - 0.5, point.y - 0.5, 1.0, 1.0))
		added += 1


func _generate_bamboo(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = TREE_SEED + 2
	var bamboo_root := Node3D.new()
	bamboo_root.name = "Bamboo"
	root.add_child(bamboo_root)
	var clusters := 0
	var attempts := 0
	while clusters < 12 and attempts < 4000:
		attempts += 1
		var center := Vector2(rng.randf_range(-22.0, 22.0), rng.randf_range(-22.0, 22.0))
		if not _is_clear(center, 2.2, ARENA_CLEARANCE, 2.0):
			continue
		var stems := rng.randi_range(3, 5)
		for stem in range(stems):
			var point := center + Vector2(rng.randf_range(-0.7, 0.7), rng.randf_range(-0.7, 0.7))
			var height := rng.randf_range(3.0, 4.0)
			var sprite := AiAssets.make_sprite(
				"prop_bamboo.png",
				height,
				Vector3(point.x, 0.0, point.y),
				"Bamboo_%d_%d" % [clusters, stem]
			)
			if sprite != null:
				bamboo_root.add_child(sprite)
		clusters += 1


func _generate_shrubs(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = TREE_SEED + 3
	var shrub_root := Node3D.new()
	shrub_root.name = "Shrubs"
	root.add_child(shrub_root)
	var added := 0
	var attempts := 0
	while added < 20 and attempts < 4000:
		attempts += 1
		var point := Vector2(rng.randf_range(-22.0, 22.0), rng.randf_range(-22.0, 22.0))
		if not _is_clear(point, 2.0, ARENA_CLEARANCE, 1.0):
			continue
		var sprite := AiAssets.make_sprite(
			"prop_shrub.png", 1.1, Vector3(point.x, 0.0, point.y), "Shrub_%d" % added
		)
		if sprite != null:
			shrub_root.add_child(sprite)
		added += 1


func _generate_grass(root: Node3D) -> void:
	var grass_root := Node3D.new()
	grass_root.name = "Grass"
	root.add_child(grass_root)
	for i in range(hide_spots.size()):
		var spot: Dictionary = hide_spots[i]
		var pos_value: Variant = spot.get("pos", Vector2.ZERO)
		if not (pos_value is Vector2):
			continue
		var pos: Vector2 = pos_value
		var sprite := AiAssets.make_sprite(
			"prop_grass.png", 1.0, Vector3(pos.x, 0.0, pos.y), "Grass_%d" % i
		)
		if sprite != null:
			grass_root.add_child(sprite)


# ---------------------------------------------------------------- camp and floor props

func _camp_position() -> Vector2:
	var camp_value: Variant = data.get("camp", null)
	if camp_value is Dictionary:
		var camp: Dictionary = camp_value
		var pos_value: Variant = camp.get("pos", null)
		if pos_value is Array:
			var pos: Array = pos_value
			if pos.size() >= 2:
				return Vector2(float(pos[0]), float(pos[1]))
	return Vector2(-12.0, 4.0)


func _build_camp() -> void:
	var center := _camp_position()
	# The camp clearing must not have a tree standing in it. Trees keep their
	# original random stream; a few are nudged outward when the camp overlaps.
	_clear_camp_trees(center)
	var camp := Node3D.new()
	camp.name = "Camp"
	add_child(camp)

	var tent := AiAssets.make_sprite(
		"camp_tent.png", 2.2, Vector3(center.x, 0.0, center.y), "Tent"
	)
	if tent != null:
		camp.add_child(tent)
	blockers.append(Rect2(center.x - 1.5, center.y - 1.0, 3.0, 2.0))

	var fire_pos := center + Vector2(1.8, 0.6)
	var fire := AiAssets.make_sprite(
		"camp_fire.png", 0.5, Vector3(fire_pos.x, 0.0, fire_pos.y), "Campfire"
	)
	if fire != null:
		camp.add_child(fire)
	_camp_light = OmniLight3D.new()
	_camp_light.name = "FireLight"
	_camp_light.light_color = Color("#ff9a4d")
	_camp_light.light_energy = CAMP_LIGHT_ENERGY
	_camp_light.omni_range = 5.0
	_camp_light.position = Vector3(fire_pos.x, 0.9, fire_pos.y)
	camp.add_child(_camp_light)

	for i in range(3):
		var angle := deg_to_rad(-60.0 + 60.0 * float(i))
		var crate_pos := fire_pos + Vector2(cos(angle), sin(angle)) * 1.3
		var crate := AiAssets.make_sprite(
			"camp_crate.png", 0.9, Vector3(crate_pos.x, 0.0, crate_pos.y), "Crate_%d" % i
		)
		if crate != null:
			camp.add_child(crate)
		blockers.append(Rect2(crate_pos.x - 0.45, crate_pos.y - 0.45, 0.9, 0.9))

	var firewood_pos := center + Vector2(-1.9, 1.8)
	var firewood := AiAssets.make_sprite(
		"prop_firewood.png", 0.6, Vector3(firewood_pos.x, 0.0, firewood_pos.y), "Firewood"
	)
	if firewood != null:
		camp.add_child(firewood)

	var scarecrow_pos := center + Vector2(-2.6, -1.4)
	var scarecrow := AiAssets.make_sprite(
		"prop_scarecrow.png", 1.8, Vector3(scarecrow_pos.x, 0.0, scarecrow_pos.y), "Scarecrow"
	)
	if scarecrow != null:
		camp.add_child(scarecrow)


func _update_camp_light() -> void:
	if _camp_light == null or not is_instance_valid(_camp_light):
		return
	_camp_light.light_energy = CAMP_LIGHT_ENERGY \
		+ sin(_time * CAMP_LIGHT_FLICKER_SPEED) * CAMP_LIGHT_FLICKER


func _clear_camp_trees(center: Vector2) -> void:
	var tree_count := tree_positions.size()
	var arena := Vector2(arena_origin.x, arena_origin.z)
	var ring := CAMP_CLEAR_RADIUS + 0.4
	var preferred := (center - arena).angle()
	if (center - arena).length_squared() < 0.0001:
		preferred = (center - _spawn_point()).angle()
	for i in range(tree_count):
		var point: Vector2 = tree_positions[i]
		if point.distance_to(center) >= CAMP_CLEAR_RADIUS:
			continue
		var moved := _find_camp_tree_spot(center, ring, preferred, i)
		if moved == point:
			continue
		tree_positions[i] = moved
		var tree_value: Variant = find_child("Tree_%d" % i, true, false)
		if tree_value is Node3D:
			var tree_node: Node3D = tree_value
			tree_node.position = Vector3(moved.x, 0.0, moved.y)
		if i < blockers.size():
			blockers[i] = Rect2(moved.x - 0.5, moved.y - 0.5, 1.0, 1.0)


func _find_camp_tree_spot(
	center: Vector2, ring: float, preferred: float, skip_index: int
) -> Vector2:
	for step in range(16):
		var offset := PI * 2.0 * float(step) / 16.0
		var angle := preferred + offset
		var candidate: Vector2 = center + Vector2(cos(angle), sin(angle)) * ring
		if _camp_tree_spot_clear(candidate, center, skip_index):
			return candidate
	return tree_positions[skip_index]


func _camp_tree_spot_clear(candidate: Vector2, center: Vector2, skip_index: int) -> bool:
	if not _in_bounds(candidate):
		return false
	if candidate.distance_to(center) < CAMP_CLEAR_RADIUS:
		return false
	if candidate.distance_to(_spawn_point()) < SPAWN_CLEARANCE + 0.2:
		return false
	var arena := Vector2(arena_origin.x, arena_origin.z)
	if candidate.distance_to(arena) < ARENA_CLEARANCE + 0.2:
		return false
	if _road_distance(candidate) < ROAD_CLEARANCE:
		return false
	for pickup_value in pickups:
		var pickup: Dictionary = pickup_value
		var pos_value: Variant = pickup.get("pos", Vector2.ZERO)
		if not (pos_value is Vector2):
			continue
		var radius := HERB_CLEARANCE
		if str(pickup.get("kind", "herb")) == "chest":
			radius = CHEST_CLEARANCE
		var pickup_pos: Vector2 = pos_value
		if candidate.distance_to(pickup_pos) < radius + 0.2:
			return false
	for other_index in range(tree_positions.size()):
		if other_index == skip_index:
			continue
		var other: Vector2 = tree_positions[other_index]
		if candidate.distance_to(other) < TREE_GAP:
			return false
	for rock_value in rock_positions:
		var rock: Vector2 = rock_value
		if candidate.distance_to(rock) < 1.2:
			return false
	return true


func _build_signpost(root: Node3D) -> void:
	var spawn := _spawn_point()
	var sprite := AiAssets.make_sprite(
		"camp_signpost.png",
		1.8,
		Vector3(spawn.x + 1.6, 0.0, spawn.y - 3.0),
		"ForestSignpost"
	)
	if sprite != null:
		root.add_child(sprite)


func _build_path_fences(root: Node3D) -> void:
	var fence_root := Node3D.new()
	fence_root.name = "PathFences"
	root.add_child(fence_root)
	for side in [-1.0, 1.0]:
		for i in range(2):
			var x := 6.0 + float(side) * 2.2
			var z := -19.4 + 1.1 * float(i)
			var sprite := AiAssets.make_sprite(
				"prop_fence.png", 0.9, Vector3(x, 0.0, z), "Fence_%d_%d" % [int(side), i]
			)
			if sprite != null:
				fence_root.add_child(sprite)


func _generate_floor_props(root: Node3D) -> void:
	var props_root := Node3D.new()
	props_root.name = "FloorProps"
	root.add_child(props_root)
	var rng := RandomNumberGenerator.new()
	rng.seed = TREE_SEED + 17
	var placed: Array[Vector2] = []
	_scatter_floor_prop(
		props_root, rng, placed, "prop_log.png", "Log", 4, 0.7, Vector2(1.0, 0.6), true
	)
	_scatter_floor_prop(
		props_root, rng, placed, "prop_stump.png", "Stump", 6, 0.6, Vector2.ZERO, false
	)
	_scatter_floor_prop(
		props_root, rng, placed, "prop_mushroom_red.png", "MushroomRed", 8, 0.4, Vector2.ZERO, false
	)
	_scatter_floor_prop(
		props_root, rng, placed, "prop_mushroom_brown.png", "MushroomBrown", 8, 0.4, Vector2.ZERO, false
	)
	_scatter_floor_prop(
		props_root, rng, placed, "prop_fern.png", "Fern", 16, 0.7, Vector2.ZERO, false
	)
	_scatter_floor_prop(
		props_root, rng, placed, "prop_wildflower.png", "Wildflower", 16, 0.6, Vector2.ZERO, false
	)
	_scatter_floor_prop(
		props_root, rng, placed, "prop_stones.png", "Stones", 6, 0.5, Vector2.ZERO, false
	)


func _scatter_floor_prop(
	parent: Node3D,
	rng: RandomNumberGenerator,
	placed: Array[Vector2],
	file: String,
	prefix: String,
	count: int,
	height: float,
	collision_size: Vector2,
	collides: bool
) -> void:
	var added := 0
	var attempts := 0
	var camp := _camp_position()
	while added < count and attempts < 3000:
		attempts += 1
		var point := Vector2(rng.randf_range(-22.0, 22.0), rng.randf_range(-22.0, 22.0))
		var arena_clearance := (ARENA_CLEARANCE + 1.0) if collides else 0.0
		if not _is_clear(point, 2.0, arena_clearance, 1.0):
			continue
		if _point_blocked(point, 0.55):
			continue
		if point.distance_to(camp) < CAMP_CLEAR_RADIUS + 1.0:
			continue
		var too_close := false
		for other_value in placed:
			var other: Vector2 = other_value
			if point.distance_to(other) < 0.8:
				too_close = true
				break
		if too_close:
			continue
		var sprite := AiAssets.make_sprite(
			file, height, Vector3(point.x, 0.0, point.y), "%s_%d" % [prefix, added]
		)
		if sprite == null:
			continue
		parent.add_child(sprite)
		if collides and collision_size != Vector2.ZERO:
			blockers.append(Rect2(
				point.x - collision_size.x * 0.5,
				point.y - collision_size.y * 0.5,
				collision_size.x,
				collision_size.y
			))
		placed.append(point)
		added += 1


# ---------------------------------------------------------------- pickups

func _pickup_root() -> Node3D:
	var existing: Variant = get_node_or_null("Pickups")
	if existing is Node3D:
		return existing
	var root := Node3D.new()
	root.name = "Pickups"
	add_child(root)
	return root


func _build_pickups() -> void:
	var root := _pickup_root()
	for pickup_value in pickups:
		var pickup: Dictionary = pickup_value
		if str(pickup.get("kind", "herb")) == "chest":
			continue
		var flag := str(pickup.get("flag", ""))
		if flag != "" and GameState.has_flag(flag):
			continue
		var pos_value: Variant = pickup.get("pos", Vector2.ZERO)
		if not (pos_value is Vector2):
			continue
		var pos: Vector2 = pos_value
		var node := Node3D.new()
		node.name = "Herb_%d" % int(pickup.get("id", 1))
		node.position = Vector3(pos.x, 0.0, pos.y)
		var sprite := AiAssets.make_sprite(
			"herb_white.png", 0.75, Vector3.ZERO, "HerbSprite"
		)
		if sprite == null:
			sprite = AiAssets.make_sprite("prop_grass.png", 0.5, Vector3.ZERO, "HerbSprite")
		if sprite != null:
			node.add_child(sprite)
		var glow := MeshInstance3D.new()
		glow.name = "HerbGlow"
		var sphere := SphereMesh.new()
		sphere.radius = 0.07
		sphere.height = 0.14
		glow.mesh = sphere
		glow.material_override = _emissive_material(Color("#d8e878"), 1.6)
		glow.position = Vector3(0.0, 0.45, 0.0)
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(glow)
		root.add_child(node)
		pickup["node"] = node
	_generate_deco_herbs(root)


func _generate_deco_herbs(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = TREE_SEED + 13
	var files: Array[String] = ["herb_ginseng.png", "herb_purple.png", "herb_glow.png"]
	var herb_points: Array[Vector2] = []
	for pickup_value in pickups:
		var pickup: Dictionary = pickup_value
		if str(pickup.get("kind", "")) == "chest":
			continue
		var pos_value: Variant = pickup.get("pos", Vector2.ZERO)
		if pos_value is Vector2:
			herb_points.append(pos_value)
	var added := 0
	var attempts := 0
	while added < 14 and attempts < 800:
		attempts += 1
		var point := Vector2.ZERO
		if not herb_points.is_empty() and added % 2 == 0:
			var anchor: Vector2 = herb_points[rng.randi_range(0, herb_points.size() - 1)]
			var angle := rng.randf_range(0.0, TAU)
			point = anchor + Vector2(cos(angle), sin(angle)) * rng.randf_range(1.2, 2.4)
		elif _road_points.size() >= 2:
			var index := rng.randi_range(0, _road_points.size() - 2)
			var a: Vector2 = _road_points[index]
			var b: Vector2 = _road_points[index + 1]
			var along := a.lerp(b, rng.randf())
			var normal := (b - a).normalized().orthogonal()
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			point = along + normal * rng.randf_range(1.0, 2.2) * side
		else:
			point = Vector2(rng.randf_range(-22.0, 22.0), rng.randf_range(-22.0, 22.0))
		if not _in_bounds(point):
			continue
		if _road_distance(point) < 1.0:
			continue
		var file: String = files[rng.randi_range(0, files.size() - 1)]
		var height := rng.randf_range(0.6, 0.8)
		var sprite := AiAssets.make_sprite(
			file, height, Vector3(point.x, 0.0, point.y), "DecoHerb_%d" % added
		)
		if sprite == null:
			continue
		root.add_child(sprite)
		added += 1


func _build_chest() -> void:
	var entry: Dictionary = _chest_entry()
	if entry.is_empty():
		return
	var flag := str(entry.get("flag", ""))
	chest_opened = flag != "" and GameState.has_flag(flag)
	var pos_value: Variant = entry.get("pos", Vector2.ZERO)
	if not (pos_value is Vector2):
		return
	var pos: Vector2 = pos_value
	var root := _pickup_root()
	var node := Node3D.new()
	node.name = "Chest"
	node.position = Vector3(pos.x, 0.0, pos.y)
	root.add_child(node)

	var closed_tex: ImageTexture = AiAssets.load_texture("chest_closed.png")
	var open_tex: ImageTexture = AiAssets.load_texture("chest_open.png")
	if closed_tex != null and open_tex != null:
		var sprite := AiAssets.make_sprite("chest_closed.png", 0.9, Vector3.ZERO, "ChestSprite")
		if sprite != null:
			node.add_child(sprite)
			# Kept for backwards compatibility; the sprite chest animates by texture.
			var pivot := Node3D.new()
			pivot.name = "LidPivot"
			node.add_child(pivot)
			chest_node = node
			chest_pivot = pivot
			chest_sprite = sprite
			entry["node"] = node
			_chest_swapped = false
			if chest_opened:
				_set_chest_sprite_open()
			return

	var wood: StandardMaterial3D = _dark_wood_material()
	var gold: StandardMaterial3D = _solid_material(Color("#c9a23f"))
	_add_box(node, Vector3(1.1, 0.62, 0.75), wood, Vector3(0.0, 0.31, 0.0), "Body")
	_add_box(node, Vector3(1.16, 0.08, 0.81), gold, Vector3(0.0, 0.04, 0.0), "BaseBand")
	_add_box(node, Vector3(0.08, 0.66, 0.79), gold, Vector3(-0.44, 0.33, 0.0), "BandLeft")
	_add_box(node, Vector3(0.08, 0.66, 0.79), gold, Vector3(0.44, 0.33, 0.0), "BandRight")
	_add_box(node, Vector3(0.16, 0.2, 0.06), gold, Vector3(0.0, 0.42, 0.39), "Lock")

	var pivot := Node3D.new()
	pivot.name = "LidPivot"
	pivot.position = Vector3(0.0, 0.62, -0.375)
	node.add_child(pivot)
	_add_box(pivot, Vector3(1.1, 0.16, 0.75), wood, Vector3(0.0, 0.08, 0.375), "Lid")
	_add_box(pivot, Vector3(1.16, 0.06, 0.79), gold, Vector3(0.0, 0.17, 0.375), "LidBand")

	chest_node = node
	chest_pivot = pivot
	chest_sprite = null
	entry["node"] = node
	if chest_opened:
		pivot.rotation.x = -deg_to_rad(CHEST_LID_ANGLE)


func _set_chest_sprite_open() -> void:
	if chest_sprite == null or not is_instance_valid(chest_sprite):
		return
	var open_tex: ImageTexture = AiAssets.load_texture("chest_open.png")
	if open_tex == null:
		return
	_apply_sprite_texture(chest_sprite, open_tex, 1.1)


func _apply_sprite_texture(sprite: Sprite3D, texture: Texture2D, world_height: float) -> void:
	if texture == null:
		return
	var size: Vector2 = texture.get_size()
	if size.y <= 0.0:
		return
	sprite.texture = texture
	sprite.pixel_size = world_height / size.y
	sprite.offset = Vector2(0.0, size.y * 0.5)


func _chest_entry() -> Dictionary:
	for pickup_value in pickups:
		var pickup: Dictionary = pickup_value
		if str(pickup.get("kind", "")) == "chest":
			return pickup
	return {}


func _nearest_pickup() -> Dictionary:
	var best: Dictionary = {}
	var best_dist := INTERACT_RANGE
	for pickup_value in pickups:
		var pickup: Dictionary = pickup_value
		if str(pickup.get("kind", "")) == "chest" and chest_opened:
			continue
		var node_value: Variant = pickup.get("node", null)
		if not (node_value is Node3D) or not is_instance_valid(node_value):
			continue
		var pos_value: Variant = pickup.get("pos", Vector2.ZERO)
		if not (pos_value is Vector2):
			continue
		var pickup_pos: Vector2 = pos_value
		var dist: float = player_pos.distance_to(pickup_pos)
		if dist <= best_dist:
			best = pickup
			best_dist = dist
	return best


func _collect(pickup: Dictionary) -> void:
	var kind := str(pickup.get("kind", ""))
	var flag := str(pickup.get("flag", ""))
	if kind == "chest":
		if chest_opened:
			return
		chest_opened = true
		if flag != "":
			GameState.set_flag(flag)
		Progression.give_item(str(pickup.get("item", "")))
		_chest_anim_t = 0.0
		_chest_swapped = false
		return
	if flag != "":
		GameState.set_flag(flag)
	Progression.give_item(str(pickup.get("item", "")))
	_remove_pickup_node(pickup)


func _remove_pickup_node(pickup: Dictionary) -> void:
	var node_value: Variant = pickup.get("node", null)
	pickup["node"] = null
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


func advance_chest(delta: float) -> void:
	if _chest_anim_t < 0.0:
		return
	if chest_sprite != null and is_instance_valid(chest_sprite):
		_chest_anim_t += delta
		var t := clampf(_chest_anim_t / CHEST_SPRITE_DURATION, 0.0, 1.0)
		var pop := 1.0 + 0.08 * sin(t * PI)
		chest_sprite.scale = Vector3(pop, pop, pop)
		if not _chest_swapped and _chest_anim_t >= CHEST_SWAP_TIME:
			_chest_swapped = true
			_set_chest_sprite_open()
		if t >= 1.0:
			_chest_anim_t = -1.0
		return
	if chest_pivot == null or not is_instance_valid(chest_pivot):
		_chest_anim_t = -1.0
		return
	_chest_anim_t += delta
	var t := clampf(_chest_anim_t / CHEST_OPEN_DURATION, 0.0, 1.0)
	chest_pivot.rotation.x = -deg_to_rad(CHEST_LID_ANGLE) * t
	if t >= 1.0:
		_chest_anim_t = -1.0


# ---------------------------------------------------------------- stealth patrols

func _build_patrols() -> void:
	_patrol_root = Node3D.new()
	_patrol_root.name = "Patrols"
	add_child(_patrol_root)
	var slots: Dictionary = {}
	var slots_value: Variant = data.get("patrol_slots", null)
	if slots_value is Dictionary:
		slots = slots_value
	_build_patrol_routes(slots)
	_build_scout(slots)


func _build_patrol_routes(slots: Dictionary) -> void:
	var routes_value: Variant = slots.get("routes", [])
	if not (routes_value is Array):
		return
	var routes: Array = routes_value
	for route_index in range(routes.size()):
		if GameState.has_flag("patrol_defeated_%d" % route_index):
			continue
		var raw_value: Variant = routes[route_index]
		if not (raw_value is Array):
			continue
		var raw_points: Array = raw_value
		var route: Array = Stealth.sanitize_route(raw_points, blockers, bounds_rect, _road_points)
		if route.size() < 2:
			continue
		var start: Vector2 = route[0]
		var second: Vector2 = route[1]
		var angle := Stealth.facing_angle("down")
		if start.distance_to(second) > 0.001:
			angle = Stealth.angle_of(second - start)
		var facing := Stealth.facing_from_vector(Stealth.direction(angle))
		var member_count := 2 if route_index == 0 else 1
		var group := {
			"index": route_index,
			"route": route,
			"target": 1,
			"dir": 1,
			"facing_angle": angle,
			"base_angle": angle,
			"turn_sign": 1.0,
			"wait": 0.0,
			"members": [],
			"alerted": false,
		}
		patrol_groups.append(group)
		for n in range(member_count):
			var pos: Vector2 = start
			if n > 0:
				pos = _follower_start(start, angle)
			var member := _make_patrol_member(
				"Patrol_%d_%d" % [route_index, n],
				pos,
				facing,
				Stealth.BASE_VIEW_DISTANCE,
				Stealth.VIEW_HALF_ANGLE,
				group
			)
			var members: Array = group["members"]
			members.append(member)


func _build_scout(slots: Dictionary) -> void:
	if GameState.has_flag("scout_defeated"):
		return
	var scout_value: Variant = slots.get("scout", null)
	if not (scout_value is Array):
		return
	var raw: Array = scout_value
	if raw.size() < 2:
		return
	var raw_pos := Vector2(float(raw[0]), float(raw[1]))
	var snapped: Array = Stealth.sanitize_route([raw_pos], blockers, bounds_rect, _road_points)
	if snapped.is_empty():
		return
	var pos: Vector2 = snapped[0]
	var facing := "down"
	var member := _make_patrol_member(
		"Scout", pos, facing, SCOUT_VIEW_DISTANCE, SCOUT_HALF_ANGLE, {}
	)
	member["enemy_id"] = "bandit_scout"
	var node: Node3D = member["node"]
	var label := Label3D.new()
	label.name = "NameLabel"
	label.text = "探子"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.012
	label.font_size = 48
	label.outline_size = 10
	label.modulate = Color("#f2e2b0")
	label.outline_modulate = Color(0.0, 0.0, 0.0)
	label.position = Vector3(0.0, 2.3, 0.0)
	node.add_child(label)
	scout = member


func _make_patrol_member(
	node_name: String,
	pos: Vector2,
	facing: String,
	view: float,
	half_angle: float,
	group: Dictionary
) -> Dictionary:
	var character := CharacterSprite.new()
	character.name = node_name
	character.setup("bandit")
	character.position = Vector3(pos.x, 0.0, pos.y)
	character.set_facing(facing)
	_patrol_root.add_child(character)
	var cone := _make_view_cone(character, half_angle)
	var mark := _make_alert_mark(character)
	return {
		"node": character,
		"pos": pos,
		"facing_angle": Stealth.facing_angle(facing),
		"vision": view,
		"half_angle": half_angle,
		"cone": cone,
		"mark": mark,
		"group": group,
		"alerted": false,
	}


func _follower_start(leader_pos: Vector2, angle: float) -> Vector2:
	for gap in [PATROL_GAP, PATROL_GAP * 0.6, PATROL_GAP * 0.3]:
		var point: Vector2 = leader_pos - Stealth.direction(angle) * float(gap)
		if Stealth.is_walkable(point, blockers, bounds_rect):
			return point
	return leader_pos


func _make_view_cone(parent: Node3D, half_angle: float) -> MeshInstance3D:
	var cone := MeshInstance3D.new()
	cone.name = "ViewCone"
	cone.mesh = _cone_mesh(half_angle)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = VIEW_CONE_COLOR
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	cone.material_override = mat
	cone.position = Vector3(0.0, 0.03, 0.0)
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cone.visible = false
	parent.add_child(cone)
	return cone


func _cone_mesh(half_angle: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 18
	for i in range(segments):
		var a0: float = -half_angle + (2.0 * half_angle) * float(i) / float(segments)
		var a1: float = -half_angle + (2.0 * half_angle) * float(i + 1) / float(segments)
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(cos(a0), 0.0, sin(a0)))
		st.add_vertex(Vector3(cos(a1), 0.0, sin(a1)))
	st.generate_normals()
	return st.commit()


func _make_alert_mark(parent: Node3D) -> Label3D:
	var mark := Label3D.new()
	mark.name = "AlertMark"
	mark.text = "！"
	mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mark.no_depth_test = true
	mark.pixel_size = 0.02
	mark.font_size = 96
	mark.outline_size = 20
	mark.modulate = Color(1.0, 0.12, 0.1)
	mark.outline_modulate = Color(0.0, 0.0, 0.0)
	mark.position = Vector3(0.0, ALERT_MARK_HEIGHT, 0.0)
	mark.visible = false
	parent.add_child(mark)
	return mark


func set_crouch_override(value: Variant) -> void:
	_crouch_override = value


func is_crouching() -> bool:
	if _crouch_override != null:
		return bool(_crouch_override)
	if not InputMap.has_action("crouch"):
		return false
	return Input.is_action_pressed("crouch")


func _in_hide_spot(point: Vector2) -> bool:
	for spot_value in hide_spots:
		var spot: Dictionary = spot_value
		var pos_value: Variant = spot.get("pos", Vector2.ZERO)
		if not (pos_value is Vector2):
			continue
		var spot_pos: Vector2 = pos_value
		if point.distance_to(spot_pos) <= float(spot.get("radius", 1.8)):
			return true
	return false


func _player_view_reach(base: float) -> float:
	return Stealth.view_distance(base, is_crouching(), _in_hide_spot(player_pos))


func advance_patrols(delta: float) -> void:
	if patrol_groups.is_empty() and scout.is_empty():
		return
	if _alerted:
		_update_view_cones()
		if not _encounter_sent:
			_alert_timer -= delta
			if _alert_timer <= 0.0:
				_finish_alert()
		return
	_advance_patrol_motion(delta)
	_update_view_cones()
	_check_detection()
	if _alerted and not _encounter_sent:
		# The alert timer starts on the frame the player is spotted. Large test
		# ticks can therefore complete the 0.6s delay immediately.
		_alert_timer -= delta
		if _alert_timer <= 0.0:
			_finish_alert()


func _advance_patrol_motion(delta: float) -> void:
	for group_value in patrol_groups:
		var group: Dictionary = group_value
		if bool(group.get("alerted", false)):
			continue
		var members: Array = group["members"]
		if members.is_empty():
			continue
		var route: Array = group["route"]
		if route.size() < 2:
			continue
		var leader: Dictionary = members[0]
		var wait := float(group.get("wait", 0.0))
		var moving := false
		if wait > 0.0:
			var remaining := maxf(0.0, wait - delta)
			group["wait"] = remaining
			var elapsed := PATROL_WAIT - remaining
			if elapsed <= PATROL_TURN_TIME:
				var t := clampf(elapsed / PATROL_TURN_TIME, 0.0, 1.0)
				var offset: float = sin(t * PI) * PATROL_TURN_ANGLE \
						* float(group.get("turn_sign", 1.0))
				group["facing_angle"] = float(group.get("base_angle", 0.0)) + offset
				_apply_group_facing(group, float(group["facing_angle"]))
			if remaining <= 0.0:
				_advance_route_target(group)
		else:
			var target: Vector2 = route[int(group["target"])]
			var leader_pos: Vector2 = leader["pos"]
			var to_target := target - leader_pos
			var dist := to_target.length()
			var step := PATROL_SPEED * delta
			if dist <= step:
				leader["pos"] = target
				group["wait"] = PATROL_WAIT
				group["base_angle"] = float(group["facing_angle"])
				group["turn_sign"] = -float(group.get("turn_sign", 1.0))
			else:
				leader["pos"] = leader_pos + to_target / dist * step
				var angle := Stealth.angle_of(to_target)
				group["facing_angle"] = angle
				_apply_group_facing(group, angle)
				moving = true
		_apply_group_facing(group, float(group["facing_angle"]))
		for i in range(1, members.size()):
			var follower: Dictionary = members[i]
			var desired := _follower_target(group, leader["pos"])
			var follower_pos: Vector2 = follower["pos"]
			var to_desired := desired - follower_pos
			var follower_step := PATROL_SPEED * delta
			var candidate := follower_pos
			if to_desired.length() <= follower_step:
				candidate = desired
			elif to_desired.length() > 0.0001:
				candidate = follower_pos + to_desired.normalized() * follower_step
			if Stealth.is_walkable(candidate, blockers, bounds_rect):
				follower["pos"] = candidate
		for member_value in members:
			var member: Dictionary = member_value
			_sync_member_node(member)
		_set_group_moving(group, moving)


func _advance_route_target(group: Dictionary) -> void:
	var route: Array = group["route"]
	if route.size() < 2:
		return
	var target_index := int(group["target"])
	var direction := int(group.get("dir", 1))
	var next_index := target_index + direction
	if next_index < 0 or next_index >= route.size():
		direction = -direction
		next_index = target_index + direction
	group["dir"] = direction
	group["target"] = clampi(next_index, 0, route.size() - 1)
	var members: Array = group["members"]
	if members.is_empty():
		return
	var leader: Dictionary = members[0]
	var leader_pos: Vector2 = leader["pos"]
	var next_point: Vector2 = route[int(group["target"])]
	if leader_pos.distance_to(next_point) > 0.001:
		var angle := Stealth.angle_of(next_point - leader_pos)
		group["facing_angle"] = angle
		group["base_angle"] = angle
		_apply_group_facing(group, angle)


func _follower_target(group: Dictionary, leader_pos: Vector2) -> Vector2:
	var angle := float(group["facing_angle"])
	for gap in [PATROL_GAP, PATROL_GAP * 0.6, PATROL_GAP * 0.3]:
		var point: Vector2 = leader_pos - Stealth.direction(angle) * float(gap)
		if Stealth.is_walkable(point, blockers, bounds_rect):
			return point
	return leader_pos


func _apply_group_facing(group: Dictionary, angle: float) -> void:
	group["facing_angle"] = angle
	var members: Array = group["members"]
	for member_value in members:
		var member: Dictionary = member_value
		member["facing_angle"] = angle
		_apply_member_facing(member, angle)


func _apply_member_facing(member: Dictionary, angle: float) -> void:
	var node_value: Variant = member.get("node", null)
	if not (node_value is Node3D):
		return
	var node: Node3D = node_value
	var facing := Stealth.facing_from_vector(
		Stealth.direction(angle), str(node.get("facing"))
	)
	node.call("set_facing", facing)


func _set_group_moving(group: Dictionary, moving: bool) -> void:
	var members: Array = group["members"]
	for member_value in members:
		var member: Dictionary = member_value
		_set_member_moving(member, moving)


func _set_member_moving(member: Dictionary, moving: bool) -> void:
	var node_value: Variant = member.get("node", null)
	if not (node_value is Node3D):
		return
	var node: Node3D = node_value
	node.call("set_moving", moving)


func _sync_member_node(member: Dictionary) -> void:
	var node_value: Variant = member.get("node", null)
	if not (node_value is Node3D):
		return
	var node: Node3D = node_value
	var pos: Vector2 = member["pos"]
	node.position = Vector3(pos.x, 0.0, pos.y)


func _update_view_cones() -> void:
	var crouched := is_crouching()
	var in_hide := _in_hide_spot(player_pos)
	for group_value in patrol_groups:
		var group: Dictionary = group_value
		var members: Array = group["members"]
		for member_value in members:
			var member: Dictionary = member_value
			_update_view_cone(member, crouched, in_hide)
	if not scout.is_empty():
		_update_view_cone(scout, crouched, in_hide)


func _update_view_cone(member: Dictionary, crouched: bool, in_hide: bool) -> void:
	var cone_value: Variant = member.get("cone", null)
	if not (cone_value is MeshInstance3D):
		return
	var cone: MeshInstance3D = cone_value
	var pos: Vector2 = member["pos"]
	var show := player_pos.distance_to(pos) <= VIEW_CONE_SHOW_DISTANCE and not _alerted
	cone.visible = show
	if not show:
		return
	var reach := Stealth.view_distance(float(member["vision"]), crouched, in_hide)
	cone.scale = Vector3(reach, 1.0, reach)
	cone.rotation.y = -float(member["facing_angle"])


func _check_detection() -> void:
	for group_value in patrol_groups:
		var group: Dictionary = group_value
		if bool(group.get("alerted", false)):
			continue
		var members: Array = group["members"]
		for member_value in members:
			var member: Dictionary = member_value
			if _member_sees_player(member):
				_begin_group_alert(group, member)
				return
	if scout.is_empty() or bool(scout.get("alerted", false)):
		return
	if _member_sees_player(scout):
		_begin_scout_alert()


func _member_sees_player(member: Dictionary) -> bool:
	var pos: Vector2 = member["pos"]
	var reach := _player_view_reach(float(member["vision"]))
	return Stealth.sees(
		pos,
		float(member["facing_angle"]),
		player_pos,
		reach,
		float(member["half_angle"]),
		blockers
	)


func _begin_group_alert(group: Dictionary, spotter: Dictionary) -> void:
	if _alerted:
		return
	var members: Array = group["members"]
	var count := int(members.size())
	_begin_alert("bandit", count, "patrol", int(group["index"]))
	group["alerted"] = true
	for member_value in members:
		var member: Dictionary = member_value
		_stop_member(member)
		_face_member_toward(member, player_pos)
	_show_alert_mark(spotter)


func _begin_scout_alert() -> void:
	if _alerted:
		return
	_begin_alert("bandit_scout", 1, "scout", -1)
	scout["alerted"] = true
	_stop_member(scout)
	_face_member_toward(scout, player_pos)
	_show_alert_mark(scout)


func _begin_alert(enemy_id: String, count: int, kind: String, id: int) -> void:
	_alerted = true
	_alert_timer = ALERT_DELAY
	_encounter_sent = false
	_pending_encounter = {"enemy": enemy_id, "count": count}
	GameState.pending_forest_encounter = {"kind": kind, "id": id}


func _finish_alert() -> void:
	if _encounter_sent:
		return
	_encounter_sent = true
	var enemy_id := str(_pending_encounter.get("enemy", "bandit"))
	var count := int(_pending_encounter.get("count", 1))
	emit_signal("encounter_requested", enemy_id, count, false)


func _stop_member(member: Dictionary) -> void:
	_set_member_moving(member, false)


func _show_alert_mark(member: Dictionary) -> void:
	var mark_value: Variant = member.get("mark", null)
	if mark_value is Label3D:
		var mark: Label3D = mark_value
		mark.visible = true


func _face_member_toward(member: Dictionary, point: Vector2) -> void:
	var pos: Vector2 = member["pos"]
	var delta := point - pos
	if delta.length_squared() < 0.000001:
		return
	var angle := Stealth.angle_of(delta)
	member["facing_angle"] = angle
	_apply_member_facing(member, angle)


func _nearest_sneak_target() -> Dictionary:
	if _alerted or player == null:
		return {}
	var best: Dictionary = {}
	var best_dist := 9999.0
	for group_value in patrol_groups:
		var group: Dictionary = group_value
		if bool(group.get("alerted", false)):
			continue
		var members: Array = group["members"]
		for member_value in members:
			var member: Dictionary = member_value
			var target := _sneak_target_for(
				member, "bandit", members.size(), "patrol", int(group["index"]), group
			)
			if target.is_empty():
				continue
			var dist := player_pos.distance_to(Vector2(member["pos"]))
			if dist < best_dist:
				best = target
				best_dist = dist
	if not scout.is_empty() and not bool(scout.get("alerted", false)):
		var scout_target := _sneak_target_for(
			scout, "bandit_scout", 1, "scout", -1, {}
		)
		if not scout_target.is_empty():
			var scout_dist := player_pos.distance_to(Vector2(scout["pos"]))
			if scout_dist < best_dist:
				best = scout_target
				best_dist = scout_dist
	return best


func _sneak_target_for(
	member: Dictionary,
	enemy_id: String,
	count: int,
	kind: String,
	id: int,
	group: Dictionary
) -> Dictionary:
	var pos: Vector2 = member["pos"]
	var facing := float(member["facing_angle"])
	var reach := _player_view_reach(float(member["vision"]))
	var in_view := Stealth.sees(
		pos, facing, player_pos, reach, float(member["half_angle"]), blockers
	)
	if not Stealth.can_sneak(pos, facing, player_pos, in_view):
		return {}
	var target := {
		"member": member,
		"enemy_id": enemy_id,
		"count": count,
		"kind": kind,
		"id": id,
	}
	if not group.is_empty():
		target["group"] = group
	return target


func _trigger_sneak(target: Dictionary) -> void:
	if _alerted:
		return
	_alerted = true
	_encounter_sent = true
	var kind := str(target.get("kind", "patrol"))
	GameState.pending_forest_encounter = {"kind": kind, "id": int(target.get("id", -1))}
	var group_value: Variant = target.get("group", null)
	if group_value is Dictionary:
		var group: Dictionary = group_value
		group["alerted"] = true
		var members: Array = group["members"]
		for member_value in members:
			var member: Dictionary = member_value
			_stop_member(member)
	var member_value: Variant = target.get("member", null)
	if member_value is Dictionary:
		var member: Dictionary = member_value
		_stop_member(member)
	emit_signal(
		"encounter_requested",
		str(target.get("enemy_id", "bandit")),
		int(target.get("count", 1)),
		true
	)


# ---------------------------------------------------------------- backdrop, lights, camera

func _build_backdrop() -> void:
	var root := Node3D.new()
	root.name = "Backdrop"
	add_child(root)
	var mountain_tex: ImageTexture = AiAssets.load_texture("bg_mountains.png")
	if mountain_tex != null:
		var quad := QuadMesh.new()
		quad.size = Vector2(240.0, 60.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = mountain_tex
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		mat.roughness = 1.0
		mat.metallic = 0.0
		mat.metallic_specular = 0.0
		mat.set("disable_fog", true)
		var backdrop := _add_mesh(
			root, quad, mat, Vector3(0.0, 19.0, -27.0), "MountainBackdrop"
		)
		backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return
	var layers: Array[Dictionary] = [
		{"z": -46.0, "seed": 31, "color": Color("#6f7f9a")},
		{"z": -60.0, "seed": 32, "color": Color("#8e9bb2")},
	]
	for i in range(layers.size()):
		var layer: Dictionary = layers[i]
		var img: Image = Texgen.mountain_layer(
			256, 64, int(layer["seed"]), layer["color"]
		)
		var tex: ImageTexture = Texgen.make_texture(img, false)
		var mat: StandardMaterial3D = Texgen.make_material(tex, Vector2.ONE, true, true)
		var quad := QuadMesh.new()
		quad.size = Vector2(220.0, 40.0)
		_add_mesh(root, quad, mat, Vector3(0.0, 17.0, float(layer["z"])))


func _build_lighting() -> void:
	var lights: Dictionary = {}
	var lights_value: Variant = data.get("lights", null)
	if lights_value is Dictionary:
		lights = lights_value

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	var rotation_value: Variant = lights.get("sun_rotation", [-48.0, -38.0, 0.0])
	if rotation_value is Array:
		var rotation: Array = rotation_value
		if rotation.size() >= 3:
			sun.rotation_degrees = Vector3(
				float(rotation[0]), float(rotation[1]), float(rotation[2])
			)
		else:
			sun.rotation_degrees = Vector3(-48.0, -38.0, 0.0)
	else:
		sun.rotation_degrees = Vector3(-48.0, -38.0, 0.0)
	sun.light_color = Color(str(lights.get("sun_color", "#eef0c0")))
	sun.light_energy = float(lights.get("sun_energy", 1.1))
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	sun.shadow_bias = 0.05
	add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(str(lights.get("sky_top", "#7fa6d8")))
	sky_mat.sky_horizon_color = Color(str(lights.get("sky_horizon", "#f2d9b0")))
	sky_mat.ground_horizon_color = Color(str(lights.get("sky_horizon", "#f2d9b0")))
	sky_mat.ground_bottom_color = Color("#c8b898")
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(str(lights.get("ambient_color", "#6b7f66")))
	env.ambient_light_energy = float(lights.get("ambient_energy", 0.7))
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color(str(lights.get("fog_color", "#b8c9a8")))
	env.fog_density = float(lights.get("fog_density", 0.006))
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
		return _spawn_position()
	if not follow_target.is_inside_tree():
		return follow_target.position
	return follow_target.global_position


func _spawn_position() -> Vector3:
	var spawn := _spawn_point()
	return Vector3(spawn.x, 0.0, spawn.y)


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


# ---------------------------------------------------------------- player

func _build_player() -> void:
	var spawn := _spawn_point()
	var px := spawn.x
	var pz := spawn.y
	var return_value: Variant = GameState.forest_return_pos
	if return_value is Vector2:
		var return_pos: Vector2 = return_value
		if _spawn_walkable(return_pos):
			px = return_pos.x
			pz = return_pos.y
	var character := CharacterSprite.new()
	character.name = "Player"
	character.setup("ren_xiaoyao")
	character.position = Vector3(px, 0.0, pz)
	character.set_facing(str(_spawn.get("facing", "up")))
	add_child(character)
	player = character
	player_pos = Vector2(px, pz)
	follow_target = player


func _spawn_walkable(point: Vector2) -> bool:
	if bounds_rect.size != Vector2.ZERO \
			and not bounds_rect.grow(-PlayerMotion.RADIUS).has_point(point):
		return false
	return not PlayerMotion.blocked(point, blockers)


func set_input_override(v: Variant) -> void:
	_input_override = v


func get_move_input() -> Vector2:
	if input_blocked or _alerted:
		return Vector2.ZERO
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
	var crouched := is_crouching()
	_update_crouch_visual(crouched)
	if crouched:
		input *= CROUCH_SPEED_MULT
	player_pos = PlayerMotion.step(player_pos, input, delta, blockers, bounds_rect)
	var weight: float = 1.0 - exp(-14.0 * delta)
	var next_y: float = lerpf(player.position.y, 0.0, weight)
	player.position = Vector3(player_pos.x, next_y, player_pos.y)
	var facing: String = PlayerMotion.facing_from_input(input, str(player.get("facing")))
	player.call("set_facing", facing)
	player.call("set_moving", input.length() > 0.01)


func _update_crouch_visual(crouched: bool) -> void:
	var sprite_value: Variant = player.get("sprite")
	if not (sprite_value is Sprite3D):
		return
	var sprite: Sprite3D = sprite_value
	if crouched:
		sprite.scale = Vector3(1.0, CROUCH_SCALE_Y, 1.0)
		sprite.modulate = CROUCH_TINT
	else:
		sprite.scale = Vector3.ONE
		sprite.modulate = Color.WHITE


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

	crouch_hint = Label.new()
	crouch_hint.name = "CrouchHint"
	crouch_hint.text = "Shift 蹲伏"
	crouch_hint.add_theme_font_size_override("font_size", 14)
	crouch_hint.modulate = Color(1.0, 1.0, 1.0, 0.55)
	crouch_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	crouch_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crouch_hint.anchor_left = 0.0
	crouch_hint.anchor_right = 0.0
	crouch_hint.anchor_top = 1.0
	crouch_hint.anchor_bottom = 1.0
	crouch_hint.offset_left = 16.0
	crouch_hint.offset_right = 160.0
	crouch_hint.offset_top = -40.0
	crouch_hint.offset_bottom = -16.0
	crouch_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(crouch_hint)


func is_dialogue_active() -> bool:
	return dialogue_view != null and bool(dialogue_view.call("is_active"))


func exit_at(point: Vector2) -> String:
	for key in exits.keys():
		var entry_value: Variant = exits[key]
		if not (entry_value is Dictionary):
			continue
		var entry: Dictionary = entry_value
		var rect_value: Variant = entry.get("rect", Rect2())
		if not (rect_value is Rect2):
			continue
		var rect: Rect2 = rect_value
		if rect.has_point(point):
			return str(key)
	return ""


func _exit_prompt(place: String) -> String:
	var entry_value: Variant = exits.get(place, null)
	if entry_value is Dictionary:
		var entry: Dictionary = entry_value
		return str(entry.get("prompt", ""))
	return ""


func update_prompt() -> void:
	if prompt_label == null:
		return
	if is_dialogue_active() or _alerted:
		prompt_label.visible = false
		return
	var sneak_target := _nearest_sneak_target()
	if not sneak_target.is_empty():
		prompt_label.text = "按 E 偷袭"
		prompt_label.visible = true
		return
	var pickup := _nearest_pickup()
	if not pickup.is_empty():
		if str(pickup.get("kind", "")) == "chest":
			prompt_label.text = "按 E 打开 宝箱"
		else:
			prompt_label.text = "按 E 采集 草药"
		prompt_label.visible = true
		return
	var place := exit_at(player_pos)
	if place != "":
		prompt_label.text = _exit_prompt(place)
		prompt_label.visible = true
		return
	prompt_label.visible = false


func try_interact() -> bool:
	if input_blocked or _alerted:
		return false
	if is_dialogue_active():
		return false
	var sneak_target := _nearest_sneak_target()
	if not sneak_target.is_empty():
		_trigger_sneak(sneak_target)
		return true
	var pickup := _nearest_pickup()
	if not pickup.is_empty():
		_collect(pickup)
		return true
	var place := exit_at(player_pos)
	if place != "":
		emit_signal("exit_requested", place)
		return true
	return false


func _on_dialogue_finished() -> void:
	current_npc_id = ""

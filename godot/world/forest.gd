extends Node3D

signal exit_requested(place: String)
signal encounter_requested(enemy_id: String, count: int, first_strike: bool)

const FOREST_PATH := "res://data/forest.json"
const CAMERA_OFFSET := Vector3(0.0, 16.7, 37.5)
# Look slightly north of the player so the characters sit in the lower half of the frame.
const LOOK_AHEAD := Vector3(0.0, 1.0, -4.0)

const INTERACT_RANGE := 1.8
const CHEST_OPEN_DURATION := 0.6
const CHEST_LID_ANGLE := 70.0

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

const Texgen = preload("res://world/texgen.gd")
const AiAssets = preload("res://world/ai_assets.gd")
const CharacterSprite = preload("res://world/character_sprite.gd")
const PlayerMotion = preload("res://world/player_motion.gd")
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
var chest_opened: bool = false

var _input_override: Variant = null
var _built: bool = false
var _textures: Dictionary = {}
var _road_points: Array[Vector2] = []
var _spawn: Dictionary = {}
var _chest_anim_t: float = -1.0
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
		_build_pickups()
		_build_chest()
		_build_player()
		snap_camera()


func _process(delta: float) -> void:
	tick_player(delta)
	advance_chest(delta)
	update_prompt()
	if not is_dialogue_active() and InputMap.has_action("interact") \
			and Input.is_action_just_pressed("interact"):
		try_interact()
	_time += delta
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
	var tex: ImageTexture = AiAssets.load_texture("tex_grass.png")
	if tex == null:
		tex = Texgen.make_texture(Texgen.grass(), true)
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
	var fill_tex: ImageTexture = AiAssets.load_texture("tex_grass.png")
	if fill_tex != null:
		fill_mat = Texgen.make_material(fill_tex, Vector2(40.0, 40.0))
		fill_mat.albedo_color = Color(0.8, 0.85, 0.75)
	fill.material_override = fill_mat
	fill.position = Vector3(0.0, -0.05, 0.0)
	root.add_child(fill)

	var grounds: Array = data.get("ground", [])
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
		var mat: StandardMaterial3D
		if kind == "dirt":
			y = 0.01
			mat = _dirt_material(Vector2(rect.size.x / 3.0, rect.size.y / 3.0))
		else:
			mat = _grass_material(Vector2(rect.size.x / 4.0, rect.size.y / 4.0))
		var plane := PlaneMesh.new()
		plane.size = rect.size
		var center: Vector2 = rect.get_center()
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


func _generate_trees(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = TREE_SEED
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
	var height := rng.randf_range(4.2, 6.2)
	var sprite := AiAssets.make_sprite(
		"prop_willow.png", height, Vector3(point.x, 0.0, point.y), "OuterTree_%d" % index
	)
	if sprite != null:
		root.add_child(sprite)


func _add_tree(root: Node3D, point: Vector2, rng: RandomNumberGenerator) -> void:
	var index := tree_positions.size()
	var height := rng.randf_range(4.0, 6.0)
	var sprite := AiAssets.make_sprite(
		"prop_willow.png", height, Vector3(point.x, 0.0, point.y), "Tree_%d" % index
	)
	if sprite != null:
		root.add_child(sprite)
	tree_positions.append(point)
	blockers.append(Rect2(point.x - 0.5, point.y - 0.5, 1.0, 1.0))


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
			"prop_grass.png", 0.5, Vector3.ZERO, "HerbSprite"
		)
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
	entry["node"] = node
	if chest_opened:
		pivot.rotation.x = -deg_to_rad(CHEST_LID_ANGLE)


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
	if chest_pivot == null or not is_instance_valid(chest_pivot):
		_chest_anim_t = -1.0
		return
	_chest_anim_t += delta
	var t := clampf(_chest_anim_t / CHEST_OPEN_DURATION, 0.0, 1.0)
	chest_pivot.rotation.x = -deg_to_rad(CHEST_LID_ANGLE) * t
	if t >= 1.0:
		_chest_anim_t = -1.0


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


func set_input_override(v: Variant) -> void:
	_input_override = v


func get_move_input() -> Vector2:
	if input_blocked:
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
	player_pos = PlayerMotion.step(player_pos, input, delta, blockers, bounds_rect)
	var weight: float = 1.0 - exp(-14.0 * delta)
	var next_y: float = lerpf(player.position.y, 0.0, weight)
	player.position = Vector3(player_pos.x, next_y, player_pos.y)
	var facing: String = PlayerMotion.facing_from_input(input, str(player.get("facing")))
	player.call("set_facing", facing)
	player.call("set_moving", input.length() > 0.01)


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
	if is_dialogue_active():
		prompt_label.visible = false
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
	if input_blocked:
		return false
	if is_dialogue_active():
		return false
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

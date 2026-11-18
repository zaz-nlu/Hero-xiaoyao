extends RefCounted

# 森林地标：强盗营地（含树清理/重排与篝火光闪动）、路牌、围栏与地面杂物。
# 空间数据来自 ForestLayout，节点挂到 controller 或 Vegetation 根节点。

const AiAssets = preload("res://shared/resources/ai_assets.gd")
const ForestLayout = preload("res://shared/resources/forest_layout.gd")
const ForestArt = preload("res://shared/scenery/forest/forest_art.gd")

const CAMP_LIGHT_ENERGY := 1.2
const CAMP_LIGHT_FLICKER := 0.08
const CAMP_LIGHT_FLICKER_SPEED := 0.9

var camp_light: OmniLight3D = null


func build(
	parent: Node3D,
	layout: ForestLayout,
	vegetation_root: Node3D,
	_art: ForestArt
) -> void:
	var center := layout.camp_position()
	# The camp clearing must not have a tree standing in it. Trees keep their
	# original random stream; a few are nudged outward when the camp overlaps.
	_clear_camp_trees(parent, layout, center)
	var camp := Node3D.new()
	camp.name = "Camp"
	parent.add_child(camp)

	var tent := AiAssets.make_sprite(
		"camp_tent.png", 2.2, Vector3(center.x, 0.0, center.y), "Tent"
	)
	if tent != null:
		camp.add_child(tent)
	layout.add_blocker(Rect2(center.x - 1.5, center.y - 1.0, 3.0, 2.0))

	var fire_pos := center + Vector2(1.8, 0.6)
	var fire := AiAssets.make_sprite(
		"camp_fire.png", 0.5, Vector3(fire_pos.x, 0.0, fire_pos.y), "Campfire"
	)
	if fire != null:
		camp.add_child(fire)
	camp_light = OmniLight3D.new()
	camp_light.name = "FireLight"
	camp_light.light_color = Color("#ff9a4d")
	camp_light.light_energy = CAMP_LIGHT_ENERGY
	camp_light.omni_range = 5.0
	camp_light.position = Vector3(fire_pos.x, 0.9, fire_pos.y)
	camp.add_child(camp_light)

	for i in range(3):
		var angle := deg_to_rad(-60.0 + 60.0 * float(i))
		var crate_pos := fire_pos + Vector2(cos(angle), sin(angle)) * 1.3
		var crate := AiAssets.make_sprite(
			"camp_crate.png", 0.9, Vector3(crate_pos.x, 0.0, crate_pos.y), "Crate_%d" % i
		)
		if crate != null:
			camp.add_child(crate)
		layout.add_blocker(Rect2(crate_pos.x - 0.45, crate_pos.y - 0.45, 0.9, 0.9))

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

	_build_signpost(vegetation_root, layout)
	_build_path_fences(vegetation_root)
	_generate_floor_props(vegetation_root, layout)


func update_camp_light(time: float) -> void:
	if camp_light == null or not is_instance_valid(camp_light):
		return
	camp_light.light_energy = CAMP_LIGHT_ENERGY \
		+ sin(time * CAMP_LIGHT_FLICKER_SPEED) * CAMP_LIGHT_FLICKER


func _clear_camp_trees(parent: Node3D, layout: ForestLayout, center: Vector2) -> void:
	var tree_count := layout.tree_positions.size()
	var arena := Vector2(layout.arena_origin.x, layout.arena_origin.z)
	var ring := ForestLayout.CAMP_CLEAR_RADIUS + 0.4
	var preferred := (center - arena).angle()
	if (center - arena).length_squared() < 0.0001:
		preferred = (center - layout.spawn_point()).angle()
	for i in range(tree_count):
		var point: Vector2 = layout.tree_positions[i]
		if point.distance_to(center) >= ForestLayout.CAMP_CLEAR_RADIUS:
			continue
		var moved := _find_camp_tree_spot(layout, center, ring, preferred, i)
		if moved == point:
			continue
		layout.move_tree(i, moved)
		var tree_value: Variant = parent.find_child("Tree_%d" % i, true, false)
		if tree_value is Node3D:
			var tree_node: Node3D = tree_value
			tree_node.position = Vector3(moved.x, 0.0, moved.y)


func _find_camp_tree_spot(
	layout: ForestLayout, center: Vector2, ring: float, preferred: float, skip_index: int
) -> Vector2:
	for step in range(16):
		var offset := PI * 2.0 * float(step) / 16.0
		var angle := preferred + offset
		var candidate: Vector2 = center + Vector2(cos(angle), sin(angle)) * ring
		if _camp_tree_spot_clear(layout, candidate, center, skip_index):
			return candidate
	return layout.tree_positions[skip_index]


func _camp_tree_spot_clear(
	layout: ForestLayout, candidate: Vector2, center: Vector2, skip_index: int
) -> bool:
	if not layout.in_bounds(candidate):
		return false
	if candidate.distance_to(center) < ForestLayout.CAMP_CLEAR_RADIUS:
		return false
	if candidate.distance_to(layout.spawn_point()) < ForestLayout.SPAWN_CLEARANCE + 0.2:
		return false
	var arena := Vector2(layout.arena_origin.x, layout.arena_origin.z)
	if candidate.distance_to(arena) < ForestLayout.ARENA_CLEARANCE + 0.2:
		return false
	if layout.road_distance(candidate) < ForestLayout.ROAD_CLEARANCE:
		return false
	for pickup_value in layout.pickups:
		var pickup: Dictionary = pickup_value
		var pos_value: Variant = pickup.get("pos", Vector2.ZERO)
		if not (pos_value is Vector2):
			continue
		var radius := ForestLayout.HERB_CLEARANCE
		if str(pickup.get("kind", "herb")) == "chest":
			radius = ForestLayout.CHEST_CLEARANCE
		var pickup_pos: Vector2 = pos_value
		if candidate.distance_to(pickup_pos) < radius + 0.2:
			return false
	for other_index in range(layout.tree_positions.size()):
		if other_index == skip_index:
			continue
		var other: Vector2 = layout.tree_positions[other_index]
		if candidate.distance_to(other) < ForestLayout.TREE_GAP:
			return false
	for rock_value in layout.rock_positions:
		var rock: Vector2 = rock_value
		if candidate.distance_to(rock) < 1.2:
			return false
	return true


func _build_signpost(root: Node3D, layout: ForestLayout) -> void:
	var spawn := layout.spawn_point()
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


func _generate_floor_props(root: Node3D, layout: ForestLayout) -> void:
	var props_root := Node3D.new()
	props_root.name = "FloorProps"
	root.add_child(props_root)
	var rng := RandomNumberGenerator.new()
	rng.seed = ForestLayout.TREE_SEED + 17
	var placed: Array[Vector2] = []
	_scatter_floor_prop(
		layout, props_root, rng, placed, "prop_log.png", "Log", 4, 0.7, Vector2(1.0, 0.6), true
	)
	_scatter_floor_prop(
		layout, props_root, rng, placed, "prop_stump.png", "Stump", 6, 0.6, Vector2.ZERO, false
	)
	_scatter_floor_prop(
		layout, props_root, rng, placed, "prop_mushroom_red.png", "MushroomRed", 8, 0.4, Vector2.ZERO, false
	)
	_scatter_floor_prop(
		layout, props_root, rng, placed, "prop_mushroom_brown.png", "MushroomBrown", 8, 0.4, Vector2.ZERO, false
	)
	_scatter_floor_prop(
		layout, props_root, rng, placed, "prop_fern.png", "Fern", 16, 0.7, Vector2.ZERO, false
	)
	_scatter_floor_prop(
		layout, props_root, rng, placed, "prop_wildflower.png", "Wildflower", 16, 0.6, Vector2.ZERO, false
	)
	_scatter_floor_prop(
		layout, props_root, rng, placed, "prop_stones.png", "Stones", 6, 0.5, Vector2.ZERO, false
	)


func _scatter_floor_prop(
	layout: ForestLayout,
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
	var camp := layout.camp_position()
	while added < count and attempts < 3000:
		attempts += 1
		var point := Vector2(rng.randf_range(-22.0, 22.0), rng.randf_range(-22.0, 22.0))
		var arena_clearance := (ForestLayout.ARENA_CLEARANCE + 1.0) if collides else 0.0
		if not layout.is_clear(point, 2.0, arena_clearance, 1.0):
			continue
		if layout.point_blocked(point, 0.55):
			continue
		if point.distance_to(camp) < ForestLayout.CAMP_CLEAR_RADIUS + 1.0:
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
			layout.add_blocker(Rect2(
				point.x - collision_size.x * 0.5,
				point.y - collision_size.y * 0.5,
				collision_size.x,
				collision_size.y
			))
		placed.append(point)
		added += 1

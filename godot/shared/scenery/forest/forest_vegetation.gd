extends RefCounted

# 森林植被：内圈树、外圈装饰树、岩石、竹林、灌木与藏身草丛。
# 树/岩石的生成位置写入 ForestLayout，由其维护与碰撞矩形的显式对应。

const AiAssets = preload("res://shared/resources/ai_assets.gd")
const ForestLayout = preload("res://shared/resources/forest_layout.gd")
const ForestArt = preload("res://shared/scenery/forest/forest_art.gd")

const TREE_TARGET := 90
const ROCK_ROAD_CLEARANCE := 2.4
const ROCK_MAX_ROAD_DISTANCE := 4.5

const TREE_SPECIES := [
	{"file": "prop_willow.png", "weight": 20.0, "min_height": 4.2, "max_height": 6.0},
	{"file": "tree_camphor.png", "weight": 22.0, "min_height": 4.5, "max_height": 6.0},
	{"file": "tree_oak.png", "weight": 18.0, "min_height": 4.5, "max_height": 6.2},
	{"file": "tree_pine.png", "weight": 18.0, "min_height": 5.0, "max_height": 7.0},
	{"file": "tree_poplar.png", "weight": 10.0, "min_height": 6.0, "max_height": 8.0},
	{"file": "tree_maple.png", "weight": 8.0, "min_height": 4.0, "max_height": 5.5},
	{"file": "tree_dead.png", "weight": 4.0, "min_height": 3.6, "max_height": 5.0},
]


func build(parent: Node3D, layout: ForestLayout, _art: ForestArt) -> Node3D:
	var root := Node3D.new()
	root.name = "Vegetation"
	parent.add_child(root)
	_generate_trees(root, layout)
	_generate_rocks(root, layout)
	_generate_bamboo(root, layout)
	_generate_shrubs(root, layout)
	_generate_grass(root, layout)
	return root


func _generate_trees(root: Node3D, layout: ForestLayout) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = ForestLayout.TREE_SEED
	# A separate stream chooses the species and height so the legacy rng keeps
	# producing exactly the same tree positions as before.
	var style_rng := RandomNumberGenerator.new()
	style_rng.seed = ForestLayout.TREE_SEED + 11
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
			if layout.is_clear(
				point,
				ForestLayout.ROAD_CLEARANCE,
				ForestLayout.ARENA_CLEARANCE,
				ForestLayout.TREE_GAP
			):
				_add_tree(tree_root, point, rng, style_rng, layout)
			t += 3.0
	# Scattered interior trees fill in the rest of the wall of trees.
	var attempts := 0
	while layout.tree_positions.size() < TREE_TARGET and attempts < 8000:
		attempts += 1
		var point := Vector2(rng.randf_range(-22.0, 22.0), rng.randf_range(-22.0, 22.0))
		if not layout.is_clear(
			point,
			ForestLayout.ROAD_CLEARANCE,
			ForestLayout.ARENA_CLEARANCE,
			ForestLayout.TREE_GAP
		):
			continue
		_add_tree(tree_root, point, rng, style_rng, layout)
	_generate_outer_trees(tree_root, style_rng)


# Purely decorative trees beyond the playable bounds so the camera never sees bare ground.
func _generate_outer_trees(
	tree_root: Node3D, style_rng: RandomNumberGenerator
) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = ForestLayout.TREE_SEED + 7
	var count := 0
	var z := 26.5
	while z <= 31.0:
		var x := -44.0
		while x <= 44.0:
			var point := Vector2(x + rng.randf_range(-1.0, 1.0), z + rng.randf_range(-1.0, 1.0))
			if absf(point.x) > 5.5:
				_add_outer_tree(tree_root, point, rng, style_rng, count)
			count += 1
			x += 3.4
		z += 3.6
	for side in [-1.0, 1.0]:
		var zz := -22.0
		while zz <= 26.0:
			var xx := 26.5
			while xx <= 40.0:
				var point := Vector2(side * (xx + rng.randf_range(-1.0, 1.0)), zz + rng.randf_range(-1.0, 1.0))
				_add_outer_tree(tree_root, point, rng, style_rng, count)
				count += 1
				xx += 3.6
			zz += 3.4


func _add_outer_tree(
	root: Node3D,
	point: Vector2,
	rng: RandomNumberGenerator,
	style_rng: RandomNumberGenerator,
	index: int
) -> void:
	# Keep the legacy height roll in the stream even though the species table
	# now decides the visible height.
	var _legacy_height := rng.randf_range(4.2, 6.2)
	var species := _pick_tree_species(style_rng)
	var height := style_rng.randf_range(
		float(species["min_height"]), float(species["max_height"])
	)
	var sprite := _make_tree_sprite(str(species["file"]), height, point, "OuterTree_%d" % index)
	if sprite != null:
		root.add_child(sprite)


func _add_tree(
	root: Node3D,
	point: Vector2,
	rng: RandomNumberGenerator,
	style_rng: RandomNumberGenerator,
	layout: ForestLayout
) -> void:
	var index := layout.tree_positions.size()
	# Keep the legacy height roll in the stream even though the species table
	# now decides the visible height.
	var _legacy_height := rng.randf_range(4.0, 6.0)
	var species := _pick_tree_species(style_rng)
	var height := style_rng.randf_range(
		float(species["min_height"]), float(species["max_height"])
	)
	var sprite := _make_tree_sprite(str(species["file"]), height, point, "Tree_%d" % index)
	if sprite != null:
		root.add_child(sprite)
	layout.add_tree(point)


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


func _generate_rocks(root: Node3D, layout: ForestLayout) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = ForestLayout.TREE_SEED + 1
	var rock_root := Node3D.new()
	rock_root.name = "Rocks"
	root.add_child(rock_root)
	var added := 0
	var attempts := 0
	while added < 12 and attempts < 5000:
		attempts += 1
		var point := Vector2(rng.randf_range(-22.0, 22.0), rng.randf_range(-22.0, 22.0))
		if not layout.is_clear(
			point, ROCK_ROAD_CLEARANCE, ForestLayout.ARENA_CLEARANCE, 1.0
		):
			continue
		var road_distance := layout.road_distance(point)
		if road_distance > ROCK_MAX_ROAD_DISTANCE:
			continue
		var height := rng.randf_range(0.6, 1.0)
		var sprite := AiAssets.make_sprite(
			"prop_rocks.png", height, Vector3(point.x, 0.0, point.y), "Rock_%d" % added
		)
		if sprite != null:
			rock_root.add_child(sprite)
		layout.add_rock(point)
		added += 1


func _generate_bamboo(root: Node3D, layout: ForestLayout) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = ForestLayout.TREE_SEED + 2
	var bamboo_root := Node3D.new()
	bamboo_root.name = "Bamboo"
	root.add_child(bamboo_root)
	var clusters := 0
	var attempts := 0
	while clusters < 12 and attempts < 4000:
		attempts += 1
		var center := Vector2(rng.randf_range(-22.0, 22.0), rng.randf_range(-22.0, 22.0))
		if not layout.is_clear(center, 2.2, ForestLayout.ARENA_CLEARANCE, 2.0):
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


func _generate_shrubs(root: Node3D, layout: ForestLayout) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = ForestLayout.TREE_SEED + 3
	var shrub_root := Node3D.new()
	shrub_root.name = "Shrubs"
	root.add_child(shrub_root)
	var added := 0
	var attempts := 0
	while added < 20 and attempts < 4000:
		attempts += 1
		var point := Vector2(rng.randf_range(-22.0, 22.0), rng.randf_range(-22.0, 22.0))
		if not layout.is_clear(point, 2.0, ForestLayout.ARENA_CLEARANCE, 1.0):
			continue
		var sprite := AiAssets.make_sprite(
			"prop_shrub.png", 1.1, Vector3(point.x, 0.0, point.y), "Shrub_%d" % added
		)
		if sprite != null:
			shrub_root.add_child(sprite)
		added += 1


func _generate_grass(root: Node3D, layout: ForestLayout) -> void:
	var grass_root := Node3D.new()
	grass_root.name = "Grass"
	root.add_child(grass_root)
	for i in range(layout.hide_spots.size()):
		var spot: Dictionary = layout.hide_spots[i]
		var pos_value: Variant = spot.get("pos", Vector2.ZERO)
		if not (pos_value is Vector2):
			continue
		var pos: Vector2 = pos_value
		var sprite := AiAssets.make_sprite(
			"prop_grass.png", 1.0, Vector3(pos.x, 0.0, pos.y), "Grass_%d" % i
		)
		if sprite != null:
			grass_root.add_child(sprite)

extends RefCounted

# 小镇外围环带：在 bounds 的西、东、南三侧铺一圈树，遮住地图边缘的空地。
# 数据：顶层可选 "border": {"depth", "spacing", "seed", "files", "height", "sides"}；
# 没有 "border" 键则什么都不建。默认北侧留给远山背景，只补两角；
# 显式把 "north" 加入 sides 时补满北侧，并让东西两带延伸覆盖两角。
# height_at 是可选高度回调 (Vector2 -> float)，用于让树根贴住地形边缘高度；
# 不传时与旧调用一样全部落在 y=0。

const AiAssets = preload("res://shared/resources/ai_assets.gd")
const TownData = preload("res://shared/resources/town_data.gd")

const DEFAULT_DEPTH := 14.0
const DEFAULT_SPACING := 3.2
const DEFAULT_SEED := 7
const DEFAULT_FILES := [
	"prop_willow.png",
	"town_tree_pine_bonsai.png",
	"town_tree_ginkgo.png",
	"town_tree_maple_red.png",
]
const DEFAULT_HEIGHT := Vector2(5.0, 8.0)
const NORTH_CORNER := 6.0
const EDGE_MARGIN := 0.1


func build(
	parent: Node3D, data: Dictionary, height_at: Callable = Callable()
) -> void:
	var config_value: Variant = data.get("border", null)
	if typeof(config_value) != TYPE_DICTIONARY:
		return
	var config: Dictionary = config_value
	var bounds: Rect2 = TownData._bounds(data)
	if bounds.size == Vector2.ZERO:
		return
	var depth := float(config.get("depth", DEFAULT_DEPTH))
	var spacing := float(config.get("spacing", DEFAULT_SPACING))
	if depth <= 0.0 or spacing <= 0.0:
		return
	var files: Array = DEFAULT_FILES
	var files_value: Variant = config.get("files", null)
	if typeof(files_value) == TYPE_ARRAY:
		files = files_value
	if files.is_empty():
		return
	var min_height := DEFAULT_HEIGHT.x
	var max_height := DEFAULT_HEIGHT.y
	var height_value: Variant = config.get("height", null)
	if typeof(height_value) == TYPE_ARRAY and height_value.size() >= 2:
		min_height = float(height_value[0])
		max_height = float(height_value[1])
	var rng := RandomNumberGenerator.new()
	rng.seed = int(config.get("seed", DEFAULT_SEED))
	var root := Node3D.new()
	root.name = "Border"
	parent.add_child(root)
	var sides: Array = ["west", "east", "south"]
	var sides_value: Variant = config.get("sides", null)
	if typeof(sides_value) == TYPE_ARRAY:
		sides = sides_value
	var south_extra: float = depth if sides.has("south") else 0.0
	# 未选北侧时保持旧行为：东西两带只向北多铺 NORTH_CORNER 覆盖两角。
	var north_top: float = bounds.position.y - (
		depth if sides.has("north") else NORTH_CORNER
	)
	var bands: Array[Dictionary] = [
		{
			"side": "west",
			"x0": bounds.position.x - depth,
			"x1": bounds.position.x,
			"z0": north_top,
			"z1": bounds.end.y + south_extra,
		},
		{
			"side": "east",
			"x0": bounds.end.x,
			"x1": bounds.end.x + depth,
			"z0": north_top,
			"z1": bounds.end.y + south_extra,
		},
		{
			"side": "south",
			"x0": bounds.position.x,
			"x1": bounds.end.x,
			"z0": bounds.end.y,
			"z1": bounds.end.y + depth,
		},
		{
			"side": "north",
			"x0": bounds.position.x,
			"x1": bounds.end.x,
			"z0": bounds.position.y - depth,
			"z1": bounds.position.y,
		},
	]
	for band in bands:
		if not sides.has(str(band["side"])):
			continue
		_fill_band(
			root, band, bounds, spacing, rng, files, min_height, max_height, height_at
		)


func _fill_band(
	root: Node3D,
	band: Dictionary,
	bounds: Rect2,
	spacing: float,
	rng: RandomNumberGenerator,
	files: Array,
	min_height: float,
	max_height: float,
	height_at: Callable
) -> void:
	var side := str(band["side"])
	var x0 := float(band["x0"])
	var x1 := float(band["x1"])
	var z0 := float(band["z0"])
	var z1 := float(band["z1"])
	var index := 0
	var z := z0 + spacing * 0.5
	while z < z1:
		var x := x0 + spacing * 0.5
		while x < x1:
			var px := _clamp_x(x + rng.randf_range(-spacing * 0.3, spacing * 0.3), bounds, side)
			var pz := _clamp_z(z + rng.randf_range(-spacing * 0.3, spacing * 0.3), bounds, side)
			var file := str(files[rng.randi_range(0, files.size() - 1)])
			var height := rng.randf_range(min_height, max_height)
			var ground_y := 0.0
			if height_at.is_valid():
				ground_y = float(height_at.call(Vector2(px, pz)))
			var sprite := AiAssets.make_sprite(
				file,
				height,
				Vector3(px, ground_y, pz),
				"Border_%s_%d" % [side, index]
			)
			if sprite != null:
				root.add_child(sprite)
			index += 1
			x += spacing
		z += spacing


func _clamp_x(x: float, bounds: Rect2, side: String) -> float:
	if side == "west":
		return minf(x, bounds.position.x - EDGE_MARGIN)
	if side == "east":
		return maxf(x, bounds.end.x + EDGE_MARGIN)
	return x


func _clamp_z(z: float, bounds: Rect2, side: String) -> float:
	if side == "south":
		return maxf(z, bounds.end.y + EDGE_MARGIN)
	if side == "north":
		return minf(z, bounds.position.y - EDGE_MARGIN)
	return z

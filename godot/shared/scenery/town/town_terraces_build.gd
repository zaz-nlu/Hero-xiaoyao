extends RefCounted

# 小镇梯田/台地搭建：顶面薄板、苔藓石墙与石板台阶。
# 由 town_ground.build_stairs 调用；缺贴图时回退纯色灰石。

const SceneKit = preload("res://shared/scene/scene_kit.gd")
const Texgen = preload("res://shared/scene/texgen.gd")
const AiAssets = preload("res://shared/resources/ai_assets.gd")
const TownTerraces = preload("res://shared/resources/town_terraces.gd")

const WALL_THICKNESS := 0.4
const STEP_HEIGHT := 0.5
const STEP_DEPTH := 1.0
const SLAB_HEIGHT := 0.06
const FALLBACK_COLOR := Color("#8a8277")
const WALL_TEXTURE := "tex_stone_wall_mossy.png"
const STAIRS_TEXTURE := "tex_flagstone_large.png"
const TOP_TEXTURES := {
	"flagstone": "tex_flagstone_large.png",
	"grass": "tex_grass.png",
	"stone": "tex_cobblestone.png",
}


func build(parent: Node3D, data: Dictionary) -> void:
	var terraces: Array = TownTerraces.list(data)
	if terraces.is_empty():
		return
	var bounds: Rect2 = TownTerraces.bounds_rect(data)
	for i in range(terraces.size()):
		var terrace: Dictionary = terraces[i]
		var root := Node3D.new()
		root.name = "Terrace%d" % i
		parent.add_child(root)
		_build_terrace(root, i, terrace, bounds)


func _build_terrace(root: Node3D, index: int, terrace: Dictionary, bounds: Rect2) -> void:
	var rect: Array = terrace["rect"]
	var x0 := float(rect[0])
	var z0 := float(rect[1])
	var x1 := float(rect[2])
	var z1 := float(rect[3])
	var y := float(terrace["y"])
	var from_y := float(terrace["from_y"])
	var width := x1 - x0
	var depth := z1 - z0
	if width <= 0.0 or depth <= 0.0:
		return
	var top_file := str(
		TOP_TEXTURES.get(str(terrace["top"]), TOP_TEXTURES["flagstone"])
	)
	var top_mat := _material(top_file, Vector2(width / 3.0, depth / 3.0))
	# 顶面比台地高度略高 0.01，避免与墙顶/地面共面闪烁。
	SceneKit.add_box(
		root,
		Vector3(width, SLAB_HEIGHT, depth),
		top_mat,
		Vector3((x0 + x1) * 0.5, y + 0.01 - SLAB_HEIGHT * 0.5, (z0 + z1) * 0.5),
		"Terrace%d_top" % index
	)
	_build_south_wall(root, index, terrace, z1, y, from_y)
	_build_side_wall(root, index, "west", x0, z0, z1, y, from_y, bounds)
	_build_side_wall(root, index, "east", x1, z0, z1, y, from_y, bounds)
	_build_stairs(root, index, terrace, z1, y, from_y)


func _build_south_wall(
	root: Node3D, index: int, terrace: Dictionary, z1: float, y: float, from_y: float
) -> void:
	var height := y - from_y
	if height <= 0.0:
		return
	var rect: Array = terrace["rect"]
	var x0 := float(rect[0])
	var x1 := float(rect[2])
	var segment := 0
	var cursor := x0
	for gap_value in _stair_gaps(terrace, x0, x1):
		var gap: Array = gap_value
		var gap_x0 := float(gap[0])
		if gap_x0 - cursor > 0.001:
			_add_wall_segment(
				root, index, segment, cursor, gap_x0, z1, y, from_y
			)
			segment += 1
		cursor = maxf(cursor, float(gap[1]))
	if x1 - cursor > 0.001:
		_add_wall_segment(root, index, segment, cursor, x1, z1, y, from_y)


func _add_wall_segment(
	root: Node3D, index: int, segment: int, x_start: float, x_end: float,
	z1: float, y: float, from_y: float
) -> void:
	var width := x_end - x_start
	var height := y - from_y
	var node_name := "TerraceWall%d_south" % index
	if segment > 0:
		node_name = "TerraceWall%d_south%d" % [index, segment]
	SceneKit.add_box(
		root,
		Vector3(width, height, WALL_THICKNESS),
		_material(WALL_TEXTURE, Vector2(width / 3.0, height / 3.0)),
		Vector3(x_start + width * 0.5, from_y + height * 0.5, z1),
		node_name
	)


func _build_side_wall(
	root: Node3D, index: int, side: String, x: float, z0: float, z1: float,
	y: float, from_y: float, bounds: Rect2
) -> void:
	var height := y - from_y
	var length := z1 - z0
	if height <= 0.0 or length <= 0.0:
		return
	if bounds.size != Vector2.ZERO:
		if side == "west" and x <= bounds.position.x + 0.001:
			return
		if side == "east" and x >= bounds.end.x - 0.001:
			return
	SceneKit.add_box(
		root,
		Vector3(WALL_THICKNESS, height, length),
		_material(WALL_TEXTURE, Vector2(length / 3.0, height / 3.0)),
		Vector3(x, from_y + height * 0.5, (z0 + z1) * 0.5),
		"TerraceWall%d_%s" % [index, side]
	)


func _build_stairs(
	root: Node3D, index: int, terrace: Dictionary, z1: float, y: float, from_y: float
) -> void:
	var steps := int(round((y - from_y) / STEP_HEIGHT))
	if steps <= 0:
		return
	for stairs_value in terrace["stairs"]:
		var stairs: Dictionary = stairs_value
		var x0 := float(stairs["x0"])
		var x1 := float(stairs["x1"])
		var width := x1 - x0
		if width <= 0.001:
			continue
		var material := _material(STAIRS_TEXTURE, Vector2(width / 3.0, 1.0 / 3.0))
		for k in range(1, steps + 1):
			var height := STEP_HEIGHT * float(k)
			var z_center := z1 + float(steps - k) + STEP_DEPTH * 0.5
			SceneKit.add_box(
				root,
				Vector3(width, height, STEP_DEPTH),
				material,
				Vector3((x0 + x1) * 0.5, from_y + height * 0.5, z_center),
				"TerraceStep%d_%d" % [index, k]
			)


func _stair_gaps(terrace: Dictionary, x0: float, x1: float) -> Array:
	var gaps: Array = []
	for stairs_value in terrace["stairs"]:
		var stairs: Dictionary = stairs_value
		var gap_x0 := maxf(float(stairs["x0"]), x0)
		var gap_x1 := minf(float(stairs["x1"]), x1)
		if gap_x1 > gap_x0:
			gaps.append([gap_x0, gap_x1])
	gaps.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	return gaps


func _material(file: String, uv_scale: Vector2) -> StandardMaterial3D:
	var texture: ImageTexture = AiAssets.load_texture(file)
	if texture == null:
		return SceneKit.solid_material(FALLBACK_COLOR)
	return Texgen.make_material(texture, uv_scale)

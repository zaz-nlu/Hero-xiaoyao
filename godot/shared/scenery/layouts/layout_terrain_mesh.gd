extends RefCounted

# 地图地形可视搭建：台地顶面、挡墙、逐级台阶、真实坡道斜面与水面。
# 由 layout_builder.gd 在编译好 LayoutTerrain 后调用；只读编译结果，
# 与运行阻挡共享同一批矩形和高度查询。

const SceneKit = preload("res://shared/scene/scene_kit.gd")
const Texgen = preload("res://shared/scene/texgen.gd")
const AiAssets = preload("res://shared/resources/ai_assets.gd")
const ImageCache = preload("res://shared/resources/image_cache.gd")

const SLAB_HEIGHT := 0.06
const STEP_HEIGHT := 0.5
const STEP_DEPTH := 1.0
const RAMP_THICKNESS := 0.12
const FALLBACK_GROUND := Color("#6f8f4a")
const FALLBACK_STONE := Color("#8a8277")
const WALL_TEXTURE := "tex_stone_wall_mossy.png"
const STAIRS_TEXTURE := "tex_flagstone_large.png"
const WATER_COLOR := Color(0.22, 0.42, 0.55, 0.68)


static func build(
	parent: Node3D, catalog: Dictionary, compiled: Dictionary
) -> void:
	var platforms_value: Variant = compiled.get("platforms", [])
	if platforms_value is Array:
		for platform_value in platforms_value:
			if platform_value is Dictionary:
				_build_platform(parent, catalog, platform_value as Dictionary)
	var connectors_value: Variant = compiled.get("connectors", [])
	if connectors_value is Array:
		for connector_value in connectors_value:
			if connector_value is Dictionary:
				_build_connector(parent, connector_value as Dictionary)
	var walls_value: Variant = compiled.get("walls", [])
	if walls_value is Array:
		for wall_value in walls_value:
			if not (wall_value is Dictionary):
				continue
			var wall: Dictionary = wall_value as Dictionary
			if str(wall.get("kind", "")) == "terrace":
				_build_wall(parent, wall)
	var water_value: Variant = compiled.get("water", [])
	if water_value is Array:
		for entry_value in water_value:
			if entry_value is Dictionary:
				_build_water(parent, entry_value as Dictionary)


# ---------------------------------------------------------------- platforms

static func _build_platform(
	parent: Node3D, catalog: Dictionary, platform: Dictionary
) -> void:
	var rect_value: Variant = platform["rect"]
	var rect: Rect2 = rect_value
	var depth := rect.size.y
	var width := rect.size.x
	if width <= 0.0 or depth <= 0.0:
		return
	var y := float(platform["y"])
	var texture := _ground_texture(catalog, str(platform.get("top", "")))
	var material := _ground_material(texture, Vector2(width / 3.0, depth / 3.0))
	var index := int(platform.get("index", 0))
	SceneKit.add_box(
		parent,
		Vector3(width, SLAB_HEIGHT, depth),
		material,
		Vector3(rect.get_center().x, y + 0.01 - SLAB_HEIGHT * 0.5, rect.get_center().y),
		"TerraceTop_%d" % index
	)


# ---------------------------------------------------------------- connectors

static func _build_connector(parent: Node3D, connector: Dictionary) -> void:
	var kind := str(connector.get("kind", "stairs"))
	if kind == "ramp":
		_build_ramp(parent, connector)
	else:
		_build_stairs(parent, connector)


static func _build_stairs(parent: Node3D, connector: Dictionary) -> void:
	var rect_value: Variant = connector["rect"]
	var rect: Rect2 = rect_value
	var side := str(connector.get("side", "south"))
	var steps := maxi(1, int(connector.get("steps", 1)))
	var from_y := float(connector.get("from_y", 0.0))
	var width := _opening_width(rect, side)
	var material := _material(STAIRS_TEXTURE, Vector2(width / 3.0, 1.0 / 3.0))
	var index := int(connector.get("index", 0))
	for k in range(1, steps + 1):
		var height := STEP_HEIGHT * float(k)
		var center := _step_center(rect, side, steps, k)
		var size := Vector3(width, height, STEP_DEPTH)
		if side == "east" or side == "west":
			size = Vector3(STEP_DEPTH, height, width)
		SceneKit.add_box(
			parent,
			size,
			material,
			Vector3(center.x, from_y + height * 0.5, center.y),
			"TerraceStep_%d_%d" % [index, k]
		)


static func _build_ramp(parent: Node3D, connector: Dictionary) -> void:
	var rect_value: Variant = connector["rect"]
	var rect: Rect2 = rect_value
	var side := str(connector.get("side", "south"))
	var from_y := float(connector.get("from_y", 0.0))
	var y := float(connector.get("y", 0.0))
	var depth := float(connector.get("depth", 0.0))
	if depth <= 0.0:
		return
	var rise := y - from_y
	var length := sqrt(depth * depth + rise * rise)
	var width := _opening_width(rect, side)
	var angle := atan2(rise, depth)
	var center := rect.get_center()
	var size := Vector3(width, RAMP_THICKNESS, length)
	var position := Vector3(center.x, (y + from_y) * 0.5, center.y)
	if side == "east" or side == "west":
		size = Vector3(length, RAMP_THICKNESS, width)
	var material := _material(STAIRS_TEXTURE, Vector2(length / 3.0, width / 3.0))
	var instance := SceneKit.add_mesh(
		parent,
		_mesh(size),
		material,
		position,
		"TerraceRamp_%d" % int(connector.get("index", 0))
	)
	match side:
		"south":
			instance.rotation.x = angle
		"north":
			instance.rotation.x = -angle
		"east":
			instance.rotation.z = -angle
		"west":
			instance.rotation.z = angle


static func _opening_width(rect: Rect2, side: String) -> float:
	if side == "east" or side == "west":
		return rect.size.y
	return rect.size.x


static func _step_center(rect: Rect2, side: String, steps: int, k: int) -> Vector2:
	var offset := float(steps - k) + STEP_DEPTH * 0.5
	match side:
		"north":
			return Vector2(rect.get_center().x, rect.end.y - offset)
		"east":
			return Vector2(rect.position.x + offset, rect.get_center().y)
		"west":
			return Vector2(rect.end.x - offset, rect.get_center().y)
		_:
			return Vector2(rect.get_center().x, rect.position.y + offset)


# ---------------------------------------------------------------- walls / water

static func _build_wall(parent: Node3D, wall: Dictionary) -> void:
	var rect_value: Variant = wall["rect"]
	var rect: Rect2 = rect_value
	var top := float(wall.get("top", 0.0))
	var bottom := float(wall.get("bottom", 0.0))
	var height := top - bottom
	if height <= 0.001:
		return
	var size := Vector3(rect.size.x, height, rect.size.y)
	var material := _material(
		WALL_TEXTURE, Vector2(maxf(rect.size.x, rect.size.y) / 3.0, height / 3.0)
	)
	var index := str(wall.get("side", ""))
	SceneKit.add_box(
		parent,
		size,
		material,
		Vector3(rect.get_center().x, bottom + height * 0.5, rect.get_center().y),
		"TerraceWall_%s_%.1f_%.1f" % [index, rect.position.x, rect.position.y]
	)


static func _build_water(parent: Node3D, entry: Dictionary) -> void:
	var rect_value: Variant = entry["rect"]
	var rect: Rect2 = rect_value
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var plane := PlaneMesh.new()
	plane.size = rect.size
	var material := StandardMaterial3D.new()
	material.albedo_color = WATER_COLOR
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.15
	material.metallic = 0.0
	SceneKit.add_mesh(
		parent,
		plane,
		material,
		Vector3(rect.get_center().x, float(entry.get("y", 0.0)), rect.get_center().y),
		"Water_%d" % int(entry.get("index", 0))
	)


# ---------------------------------------------------------------- helpers

static func _mesh(size: Vector3) -> BoxMesh:
	var box := BoxMesh.new()
	box.size = size
	return box


static func _ground_texture(catalog: Dictionary, asset: String) -> Texture2D:
	var items_value: Variant = catalog.get("items", {})
	if not (items_value is Dictionary):
		return null
	var item_value: Variant = (items_value as Dictionary).get(asset, null)
	if not (item_value is Dictionary):
		return null
	var item: Dictionary = item_value
	return _load_texture(str(item.get("texture", "")))


static func _material(file: String, uv_scale: Vector2) -> StandardMaterial3D:
	var texture := _load_texture(file)
	if texture == null:
		return SceneKit.solid_material(FALLBACK_STONE)
	return Texgen.make_material(texture, uv_scale)


static func _ground_material(texture: Texture2D, uv_scale: Vector2) -> StandardMaterial3D:
	if texture != null:
		return Texgen.make_material(texture, uv_scale)
	return SceneKit.solid_material(FALLBACK_GROUND)


static func _load_texture(path: String) -> Texture2D:
	if path == "":
		return null
	var file := path.get_file()
	if file.begins_with("tex_"):
		return AiAssets.load_texture(file)
	return ImageCache.texture(path)

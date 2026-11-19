extends RefCounted

# 把 layout document + catalog 构建成运行时 Node3D 场景（正式试玩，不是 @tool）。
# 与 LayoutDocument 共用占地/阻挡规则，视觉、占格和运动阻挡保持一致。
#
# 公开 API：
#   LayoutBuilder.build(parent: Node3D, document: Dictionary, catalog: Dictionary) -> Dictionary
#       {ok: bool, errors: Array[String], node: Node3D,
#        blockers: Array[Rect2], anchors: Array[Dictionary],
#        bounds: Rect2, spawn: Vector2, terrain: Dictionary}
#   anchor: {kind: "npc" | "exit", name: String, pos: Vector2, height: float, radius: float}
#   terrain 是 LayoutTerrain.compile 的结果；blockers 已含台地挡墙与水面。
#
# 说明：
# - 地表按材质+支撑平台高度合并为 MultiMesh，96x96 也不会每格生成一个节点。
# - 平坦地面单层：基础地面一块整面，tiles 在其上方稀疏覆盖；涂装跟随平坦支撑面。
# - box 用盒子几何 + 平铺材质；billboard 用 Sprite3D（可固定朝向或固定 Y 广告牌）。
# - scene 以占格中心为锚点实例化 PackedScene，Y=0 视为落地面；占地阻挡仍来自目录。
# - 不读取 GameState；不含战棋/多层逻辑。

const LayoutDocument = preload("res://core/layouts/layout_document.gd")
const LayoutCatalog = preload("res://core/layouts/layout_catalog.gd")
const LayoutTerrain = preload("res://core/layouts/layout_terrain.gd")
const LayoutTerrainMesh = preload("res://shared/scenery/layouts/layout_terrain_mesh.gd")
const AiAssets = preload("res://shared/resources/ai_assets.gd")
const ImageCache = preload("res://shared/resources/image_cache.gd")
const SceneKit = preload("res://shared/scene/scene_kit.gd")
const Texgen = preload("res://shared/scene/texgen.gd")
const CharacterSprite = preload("res://shared/scene/character_sprite.gd")
const TownFonts = preload("res://shared/scenery/town/town_fonts.gd")

const TILE_SIZE := 2.0
const TILE_OFFSET := 0.012
const SPRITE_LIFT := 0.02
const FALLBACK_GROUND := Color("#6f8f4a")


static func build(
	parent: Node3D, document: Dictionary, catalog: Dictionary
) -> Dictionary:
	var errors := LayoutDocument.validate_document(document, catalog)
	var empty_blockers: Array[Rect2] = []
	var empty_anchors: Array = []
	var result := {
		"ok": false,
		"errors": errors,
		"node": null,
		"blockers": empty_blockers,
		"anchors": empty_anchors,
		"bounds": LayoutDocument.world_bounds(document),
		"spawn": LayoutDocument.spawn_point(document),
	}
	if not errors.is_empty():
		return result

	var root := Node3D.new()
	root.name = "LayoutRoot"
	parent.add_child(root)
	var terrain := LayoutTerrain.compile(document)
	_build_ground(root, document, catalog, terrain)
	LayoutTerrainMesh.build(root, catalog, terrain)
	var anchors: Array = []
	var build_errors: Array[String] = []
	_build_objects(root, document, catalog, terrain, anchors, build_errors)
	if not build_errors.is_empty():
		# 场景资源不可用时整体失败：不返回半成品，也不留下实例。
		root.free()
		result["errors"] = build_errors
		return result

	result["ok"] = true
	result["node"] = root
	var blockers: Array = []
	blockers.append_array(LayoutDocument.blocking_rects(document, catalog))
	var terrain_blockers: Variant = terrain.get("blockers", [])
	if terrain_blockers is Array:
		blockers.append_array(terrain_blockers)
	result["blockers"] = blockers
	result["terrain"] = terrain
	result["anchors"] = anchors
	return result


# ---------------------------------------------------------------- ground

static func _build_ground(
	root: Node3D, document: Dictionary, catalog: Dictionary, terrain: Dictionary
) -> void:
	var width := int(document.get("width", 0))
	var depth := int(document.get("depth", 0))
	var items: Dictionary = catalog.get("items", {})
	var ground_item := _catalog_item(items, str(document.get("ground", "")))
	var base_half := Vector2(float(width) * TILE_SIZE, float(depth) * TILE_SIZE)
	var base := PlaneMesh.new()
	base.size = base_half
	var base_texture := _load_texture(str(ground_item.get("texture", "")))
	var base_scale := Vector2(
		maxf(1.0, base_half.x / 4.0), maxf(1.0, base_half.y / 4.0)
	)
	SceneKit.add_mesh(
		root,
		base,
		_ground_material(base_texture, base_scale),
		Vector3(base_half.x * 0.5, 0.0, base_half.y * 0.5),
		"GroundBase"
	)

	var groups: Dictionary = {}
	var tiles_value: Variant = document.get("tiles", [])
	if tiles_value is Array:
		var tiles: Array = tiles_value
		for tile_value in tiles:
			if not (tile_value is Dictionary):
				continue
			var tile: Dictionary = tile_value
			var asset := str(tile.get("asset", ""))
			var cell := Vector2i(int(tile.get("x", 0)), int(tile.get("z", 0)))
			var center := Vector2(
				float(cell.x) * TILE_SIZE + TILE_SIZE * 0.5,
				float(cell.y) * TILE_SIZE + TILE_SIZE * 0.5
			)
			# 涂装落在平坦支撑面上：楼梯/坡道底下跟随下层台地，不随坡顶悬空。
			var support := LayoutTerrain.platform_height(terrain, center)
			if not groups.has(asset):
				groups[asset] = {}
			var batches: Dictionary = groups[asset]
			if not batches.has(support):
				batches[support] = []
			var cells: Array = batches[support]
			cells.append(cell)

	for asset in groups.keys():
		var batches: Dictionary = groups[asset]
		for support_value in batches.keys():
			var cells: Array = batches[support_value]
			if cells.is_empty():
				continue
			var support := float(support_value)
			var item := _catalog_item(items, str(asset))
			var texture := _load_texture(str(item.get("texture", "")))
			var tile_mesh := PlaneMesh.new()
			tile_mesh.size = Vector2(TILE_SIZE, TILE_SIZE)
			var multimesh := MultiMesh.new()
			multimesh.mesh = tile_mesh
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.instance_count = cells.size()
			for i in range(cells.size()):
				var cell: Vector2i = cells[i]
				var center := Vector2(
					float(cell.x) * TILE_SIZE + TILE_SIZE * 0.5,
					float(cell.y) * TILE_SIZE + TILE_SIZE * 0.5
				)
				var position := Vector3(center.x, 0.0, center.y)
				multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, position))
			var instance := MultiMeshInstance3D.new()
			if batches.size() == 1:
				instance.name = "Tiles_%s" % str(asset)
			else:
				instance.name = "Tiles_%s_%d" % [
					str(asset), int(round(support * 2.0))
				]
			instance.position = Vector3(0.0, support + TILE_OFFSET, 0.0)
			instance.multimesh = multimesh
			instance.material_override = _ground_material(texture, Vector2.ONE)
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(instance)


# ---------------------------------------------------------------- objects

static func _build_objects(
	root: Node3D,
	document: Dictionary,
	catalog: Dictionary,
	terrain: Dictionary,
	anchors: Array,
	errors: Array[String]
) -> void:
	var items: Dictionary = catalog.get("items", {})
	var objects_value: Variant = document.get("objects", [])
	if not (objects_value is Array):
		return
	var objects: Array = objects_value
	for object_value in objects:
		if not (object_value is Dictionary):
			continue
		var object: Dictionary = object_value
		var asset := str(object.get("asset", ""))
		var item := _catalog_item(items, asset)
		if item.is_empty():
			continue
		var x := int(object.get("x", 0))
		var z := int(object.get("z", 0))
		var turn := int(object.get("turn", 0))
		var label := str(object.get("label", ""))
		var cells := LayoutDocument.footprint_cells(item, x, z, turn)
		var center := Vector3(
			(float(cells.position.x) + float(cells.size.x) * 0.5) * TILE_SIZE,
			0.0,
			(float(cells.position.y) + float(cells.size.y) * 0.5) * TILE_SIZE
		)
		center.y = LayoutTerrain.height_at(terrain, Vector2(center.x, center.z))
		match str(item.get("kind", "")):
			"box":
				_add_box(root, item, cells, center, label)
			"billboard":
				_add_sprite_visual(root, item, center, turn, label)
			"npc":
				_add_npc(root, item, center, label, anchors)
			"exit":
				_add_exit(root, item, center, turn, label, anchors)
			"ground":
				_add_ground_tile(root, item, cells, center)
			"scene":
				_add_scene(root, item, cells, center, turn, errors)


static func _add_box(
	root: Node3D,
	item: Dictionary,
	cells: Rect2i,
	center: Vector3,
	label: String
) -> void:
	var world_width := float(cells.size.x) * TILE_SIZE
	var world_depth := float(cells.size.y) * TILE_SIZE
	var height := float(item.get("height", 1.0))
	var texture := _load_texture(str(item.get("texture", "")))
	var material: StandardMaterial3D
	if texture != null:
		material = Texgen.make_material(
			texture,
			Vector2(maxf(1.0, float(cells.size.x)), maxf(1.0, float(cells.size.y)))
		)
	else:
		material = SceneKit.solid_material(Color("#8a8277"))
	SceneKit.add_box(
		root,
		Vector3(world_width, height, world_depth),
		material,
		Vector3(center.x, center.y + height * 0.5, center.z),
		"Box_%s_%d_%d" % [
			str(item.get("id", "box")), cells.position.x, cells.position.y
		]
	)
	if label != "":
		_add_label(root, label, Vector3(center.x, center.y + height + 0.4, center.z), 0.016)


static func _add_sprite_visual(
	root: Node3D,
	item: Dictionary,
	center: Vector3,
	turn: int,
	label: String
) -> void:
	var sprite_path := str(item.get("sprite", ""))
	if sprite_path == "":
		return
	var texture := ImageCache.texture(sprite_path)
	if texture == null:
		return
	var size := texture.get_size()
	if size.y <= 0.0:
		return
	var height := float(item.get("height", 2.0))
	var sprite := Sprite3D.new()
	sprite.name = "Sprite_%s" % str(item.get("id", "sprite"))
	sprite.texture = texture
	sprite.centered = true
	sprite.pixel_size = height / size.y
	sprite.offset = Vector2(0.0, size.y * 0.5)
	var billboard := bool(item.get("billboard", false))
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y if billboard \
		else BaseMaterial3D.BILLBOARD_DISABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.double_sided = true
	sprite.shaded = true
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	sprite.position = Vector3(center.x, center.y + SPRITE_LIFT, center.z)
	if not billboard:
		sprite.rotation_degrees.y = float(posmod(turn, 4)) * 90.0
	root.add_child(sprite)
	if label != "":
		_add_label(root, label, Vector3(center.x, center.y + height + 0.4, center.z), 0.016)


static func _add_npc(
	root: Node3D, item: Dictionary, center: Vector3, label: String, anchors: Array
) -> void:
	var sprite_path := str(item.get("sprite", ""))
	var sprite_id := sprite_path.get_file().get_basename()
	var display := label if label != "" else str(item.get("name", "npc"))
	var character := CharacterSprite.new()
	character.name = "Npc_%s" % str(item.get("id", "npc"))
	character.setup(sprite_id)
	character.position = Vector3(center.x, center.y, center.z)
	character.call("set_facing", "down")
	root.add_child(character)
	_add_label(root, display, Vector3(center.x, center.y + 2.6, center.z), 0.02)
	anchors.append({
		"kind": "npc",
		"name": display,
		"pos": Vector2(center.x, center.z),
		"height": center.y,
		"radius": 2.6,
	})


static func _add_exit(
	root: Node3D,
	item: Dictionary,
	center: Vector3,
	turn: int,
	label: String,
	anchors: Array
) -> void:
	var display := label if label != "" else str(item.get("name", "exit"))
	if str(item.get("sprite", "")) != "":
		_add_sprite_visual(root, item, center, turn, "")
	_add_label(root, display, Vector3(center.x, center.y + 2.6, center.z), 0.02)
	anchors.append({
		"kind": "exit",
		"name": display,
		"pos": Vector2(center.x, center.z),
		"height": center.y,
		"radius": 2.6,
	})


static func _add_ground_tile(
	root: Node3D, item: Dictionary, cells: Rect2i, center: Vector3
) -> void:
	var texture := _load_texture(str(item.get("texture", "")))
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(
		float(cells.size.x) * TILE_SIZE, float(cells.size.y) * TILE_SIZE
	)
	SceneKit.add_mesh(
		root,
		mesh,
		_ground_material(texture, Vector2.ONE),
		Vector3(center.x, center.y + TILE_OFFSET, center.z),
		"Ground_%s" % str(item.get("id", "tile"))
	)


# ---------------------------------------------------------------- scene prefabs

static func _add_scene(
	root: Node3D,
	item: Dictionary,
	cells: Rect2i,
	center: Vector3,
	turn: int,
	errors: Array[String]
) -> void:
	var scene_path := str(item.get("scene", ""))
	if not _scene_path_allowed(scene_path):
		var message := "scene: '%s' must be under " % scene_path
		message += "res://assets/ or res://shared/scenery/layouts/prefabs/"
		errors.append(message)
		return
	var node := _instantiate_layout_scene(scene_path, errors)
	if node == null:
		return
	node.name = "Scene_%s_%d_%d" % [
		str(item.get("id", "scene")), cells.position.x, cells.position.y
	]
	# 预制件约定 Y=0 是落地面；占格中心即锚点，转向按 90 度递增。
	node.position = Vector3(center.x, center.y, center.z)
	node.rotation_degrees.y = float(posmod(turn, 4)) * 90.0
	root.add_child(node)


static func _instantiate_layout_scene(
	scene_path: String, errors: Array[String]
) -> Node3D:
	if scene_path == "":
		errors.append("scene: catalog item is missing a scene path")
		return null
	if not ResourceLoader.exists(scene_path, "PackedScene"):
		errors.append("scene: %s is not a loadable PackedScene" % scene_path)
		return null
	var resource := load(scene_path)
	if not (resource is PackedScene):
		errors.append("scene: %s is not a loadable PackedScene" % scene_path)
		return null
	var instance: Node = (resource as PackedScene).instantiate()
	if instance == null:
		errors.append("scene: cannot instantiate %s" % scene_path)
		return null
	if not (instance is Node3D):
		errors.append(
			"scene: root of %s must be Node3D, got %s" % [
				scene_path, instance.get_class()
			]
		)
		instance.free()
		return null
	return instance as Node3D


static func _scene_path_allowed(path: String) -> bool:
	if not path.begins_with("res://"):
		return false
	for segment in path.split("/"):
		if segment == "..":
			return false
	for root in LayoutCatalog.SCENE_ROOTS:
		if path.begins_with(root):
			return true
	return false


# ---------------------------------------------------------------- helpers

static func _add_label(root: Node3D, text: String, pos: Vector3, pixel_size: float) -> void:
	var label := Label3D.new()
	label.text = text
	var font := TownFonts.brush()
	if font != null:
		label.font = font
	label.pixel_size = pixel_size
	label.font_size = 48
	label.modulate = Color("#f2e2b0")
	label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.position = pos
	root.add_child(label)


static func _catalog_item(items: Dictionary, id: String) -> Dictionary:
	var value: Variant = items.get(id, null)
	if value is Dictionary:
		return value
	return {}


static func _load_texture(path: String) -> Texture2D:
	if path == "":
		return null
	var file := path.get_file()
	if file.begins_with("tex_"):
		return AiAssets.load_texture(file)
	return ImageCache.texture(path)


static func _ground_material(
	texture: Texture2D, uv_scale: Vector2
) -> StandardMaterial3D:
	if texture != null:
		return Texgen.make_material(texture, uv_scale)
	return SceneKit.solid_material(FALLBACK_GROUND)

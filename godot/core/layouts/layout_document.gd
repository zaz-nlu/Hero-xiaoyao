@tool
extends RefCounted

# 探索地图文档（schema version 1，固定 2 游戏单位/格，单层、平坦地面）。
#
# 文档字段：
# {
#   "version": 1,
#   "id": "zixia_sect",              # 小写字母/数字/下划线
#   "name": "紫霞派",
#   "width": 24, "depth": 20,        # 整数格数 4..96
#   "ground": "grass",               # 目录库中的地面 asset id
#   "tiles":   [{"asset": "stone", "x": 8, "z": 6}],
#   "objects": [{"asset": "sect_gate", "x": 10, "z": 15, "turn": 0, "label": "",
#                "trigger": {"kind": "exit", "target": "town", "activation": "interact"}}],
#   "trigger" 可选，见 core/layouts/layout_triggers.gd；没有该字段的旧地图保持原行为。
#   "spawn":   {"x": 24, "z": 36},   # 世界单位坐标
#   "regions": [{"name": "前院", "x": 8, "z": 6, "width": 8, "depth": 8}],
#   "environment": {...}             # 可选环境，见 layout_environment.gd
# }
# - tiles/objects 的 x,z 是左上角格坐标；turn 0..3，奇数转向交换占地宽深。
# - objects 以占地中心为锚点；两个物件不能占同一格（即使不阻挡）。
# - spawn 是世界单位坐标，必须在地图内且不被阻挡。
# - regions 只作编辑标注，不参与运行。
#
# 公开 API（下一阶段编辑器直接调用）：
#   LayoutDocument.load_document(path, catalog_path := LayoutCatalog.CATALOG_PATH) -> Dictionary
#       {ok, errors, document, catalog, source}
#   LayoutDocument.validate_document(document: Variant, catalog: Dictionary,
#       trigger_context: Dictionary = {}) -> Array[String]
#   LayoutDocument.save_document(path, document, catalog := {}) -> Dictionary
#       {ok, errors}
#   LayoutDocument.footprint_cells(item: Dictionary, x: int, z: int, turn: int) -> Rect2i
#   LayoutDocument.world_bounds(document: Dictionary) -> Rect2
#   LayoutDocument.spawn_point(document: Dictionary) -> Vector2
#   LayoutDocument.blocking_rects(document: Dictionary, catalog: Dictionary) -> Array[Rect2]
#
# 读取、校验、保存共用同一份 validate_document；无效草稿不会写盘。
# 保存只允许 res://data/layouts/ 与 user://，先写同目录临时文件再替换。

const LayoutCatalog = preload("res://core/layouts/layout_catalog.gd")
const LayoutEnvironment = preload("res://core/layouts/layout_environment.gd")
const LayoutGrid = preload("res://core/layouts/layout_grid.gd")
const LayoutIds = preload("res://core/layouts/layout_ids.gd")
const LayoutTerrain = preload("res://core/layouts/layout_terrain.gd")
const LayoutTriggers = preload("res://core/layouts/layout_triggers.gd")

const SCHEMA_VERSION := 1
const TILE_SIZE := 2.0
const MIN_SPAN := 4
const MAX_SPAN := 96
const PLAYER_RADIUS := 0.4
const WRITE_ROOTS: Array[String] = ["res://data/layouts/"]
const USER_WRITE_ROOT := "user://"
static func load_document(path: String, catalog_path: String = LayoutCatalog.CATALOG_PATH) -> Dictionary:
	var catalog := LayoutCatalog.load_catalog(catalog_path)
	var errors: Array[String] = []
	if not bool(catalog.get("ok", false)):
		var catalog_errors: Array = catalog.get("errors", [])
		for message in catalog_errors:
			errors.append(str(message))
		if errors.is_empty():
			errors.append("catalog: failed to load %s" % catalog_path)
		return {
			"ok": false,
			"errors": errors,
			"document": {},
			"catalog": catalog,
			"source": path,
		}

	if not FileAccess.file_exists(path):
		errors.append("document: cannot read %s" % path)
		return {
			"ok": false,
			"errors": errors,
			"document": {},
			"catalog": catalog,
			"source": path,
		}
	var json := JSON.new()
	var parse_error := json.parse(FileAccess.get_file_as_string(path))
	if parse_error != OK:
		errors.append(
			"document: %s line %d: %s" % [
				path, json.get_error_line(), json.get_error_message()
			]
		)
		return {
			"ok": false,
			"errors": errors,
			"document": {},
			"catalog": catalog,
			"source": path,
		}
	var document: Variant = json.data
	errors = validate_document(document, catalog)
	var doc: Dictionary = document if document is Dictionary else {}
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"document": doc,
		"catalog": catalog,
		"source": path,
	}

static func validate_document(
	document: Variant, catalog: Dictionary, trigger_context: Dictionary = {}
) -> Array[String]:
	var errors: Array[String] = []
	if not (document is Dictionary):
		errors.append("document: top-level JSON must be an object")
		return errors
	var doc: Dictionary = document

	if not _is_int(doc.get("version")) or int(doc.get("version")) != SCHEMA_VERSION:
		errors.append("document: version must be %d" % SCHEMA_VERSION)

	var id := str(doc.get("id", ""))
	if id == "":
		errors.append("document: id is required")
	elif not _valid_id(id):
		errors.append(
			"document: invalid id '%s' (use lowercase letters, digits and _)" % id
		)
	if str(doc.get("name", "")) == "":
		errors.append("document: name is required")

	var width_ok := _check_span(doc, "width", errors)
	var depth_ok := _check_span(doc, "depth", errors)
	var width := int(doc.get("width", 0)) if _is_int(doc.get("width")) else 0
	var depth := int(doc.get("depth", 0)) if _is_int(doc.get("depth")) else 0
	var has_dims := width_ok and depth_ok

	var items: Dictionary = catalog.get("items", {})
	if items.is_empty():
		errors.append("catalog: no items loaded")
		return errors

	var ground := str(doc.get("ground", ""))
	var ground_value: Variant = items.get(ground, null)
	if not (ground_value is Dictionary):
		errors.append("document: ground asset '%s' is not in the catalog" % ground)
	elif str((ground_value as Dictionary).get("kind", "")) != "ground":
		errors.append("document: ground asset '%s' is not a ground item" % ground)

	_validate_tiles(doc, items, width, depth, has_dims, errors)
	_validate_objects(doc, items, width, depth, has_dims, errors)
	_validate_regions(doc, width, depth, has_dims, errors)
	_validate_spawn(doc, items, width, depth, has_dims, errors)
	for message in LayoutEnvironment.validate(doc):
		errors.append(str(message))
	for message in LayoutTriggers.validate(doc, trigger_context):
		errors.append(str(message))
	# 宽或深非法时已经报错，不再把极大的无效矩形送进地形几何扫描。
	if has_dims:
		for message in LayoutTerrain.validate(doc, catalog):
			errors.append(str(message))
	return errors

static func save_document(path: String, document: Dictionary, catalog: Dictionary = {}) -> Dictionary:
	var errors: Array[String] = []
	var catalog_result := catalog
	if catalog_result.is_empty():
		catalog_result = LayoutCatalog.load_catalog()
	if not bool(catalog_result.get("ok", false)):
		errors.append("catalog: not loaded")
		var catalog_errors: Array = catalog_result.get("errors", [])
		for message in catalog_errors:
			errors.append(str(message))
		return {"ok": false, "errors": errors}
	if not _writable_path(path):
		errors.append(
			"save: path must be under res://data/layouts/ or user:// and end with .json: %s"
			% path
		)
		return {"ok": false, "errors": errors}

	var document_errors := validate_document(document, catalog_result)
	for message in document_errors:
		errors.append(str(message))
	if not errors.is_empty():
		return {"ok": false, "errors": errors}

	var text := JSON.stringify(document, "\t", true) + "\n"
	var temp_path := "%s.%d.%d.tmp" % [path, OS.get_process_id(), Time.get_ticks_usec()]
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		errors.append("save: cannot open %s (error %d)" % [temp_path, FileAccess.get_open_error()])
		return {"ok": false, "errors": errors}
	if not file.store_string(text):
		errors.append("save: cannot write %s (error %d)" % [temp_path, file.get_error()])
		file.close()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		return {"ok": false, "errors": errors}
	file.flush()
	file.close()

	var temp_abs := ProjectSettings.globalize_path(temp_path)
	var target_abs := ProjectSettings.globalize_path(path)
	var rename_error := DirAccess.rename_absolute(temp_abs, target_abs)
	if rename_error != OK:
		DirAccess.remove_absolute(temp_abs)
		errors.append("save: cannot replace %s (error %d)" % [path, rename_error])
		return {"ok": false, "errors": errors}
	return {"ok": true, "errors": []}

# ---------------------------------------------------------------- shared geometry

static func footprint_cells(item: Dictionary, x: int, z: int, turn: int) -> Rect2i:
	return LayoutGrid.footprint_cells(item, x, z, turn)


static func footprint_world(item: Dictionary, x: int, z: int, turn: int) -> Rect2:
	return LayoutGrid.footprint_world(item, x, z, turn)


static func world_bounds(document: Dictionary) -> Rect2:
	return LayoutGrid.world_bounds(document)

static func spawn_point(document: Dictionary) -> Vector2:
	var spawn_value: Variant = document.get("spawn", null)
	if not (spawn_value is Dictionary):
		return Vector2.ZERO
	var spawn: Dictionary = spawn_value
	var x: Variant = spawn.get("x", 0.0)
	var z: Variant = spawn.get("z", 0.0)
	return Vector2(float(x) if _is_number(x) else 0.0, float(z) if _is_number(z) else 0.0)

static func blocking_rects(document: Dictionary, catalog: Dictionary) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for entry in blocking_entries(document, catalog):
		result.append(entry["rect"])
	return result

# 公开给校验和运行时共用：每条带 rect / asset / 左上格坐标。
static func blocking_entries(document: Dictionary, catalog: Dictionary) -> Array:
	var entries: Array = []
	var items_value: Variant = catalog.get("items", {})
	if not (items_value is Dictionary):
		return entries
	var items: Dictionary = items_value
	var objects_value: Variant = document.get("objects", [])
	if not (objects_value is Array):
		return entries
	var objects: Array = objects_value
	for i in range(objects.size()):
		var object_value: Variant = objects[i]
		if not (object_value is Dictionary):
			continue
		var object: Dictionary = object_value
		var asset := str(object.get("asset", ""))
		var item_value: Variant = items.get(asset, null)
		if not (item_value is Dictionary):
			continue
		var item: Dictionary = item_value
		if not bool(item.get("blocking", false)):
			continue
		var x := int(object.get("x", 0))
		var z := int(object.get("z", 0))
		var turn := int(object.get("turn", 0))
		entries.append({
			"rect": footprint_world(item, x, z, turn),
			"asset": asset,
			"x": x,
			"z": z,
		})
	return entries

# ---------------------------------------------------------------- validation helpers

static func _validate_tiles(
	document: Dictionary,
	items: Dictionary,
	width: int,
	depth: int,
	has_dims: bool,
	errors: Array[String]
) -> void:
	var raw: Variant = document.get("tiles", [])
	if not (raw is Array):
		errors.append("tiles: must be an array")
		return
	var tiles: Array = raw
	var seen: Dictionary = {}
	for i in range(tiles.size()):
		var tile_value: Variant = tiles[i]
		if not (tile_value is Dictionary):
			errors.append("tiles[%d]: must be an object" % i)
			continue
		var tile: Dictionary = tile_value
		var asset := str(tile.get("asset", ""))
		var where := "tiles[%d] '%s'" % [i, asset]
		var item_value: Variant = items.get(asset, null)
		if not (item_value is Dictionary):
			errors.append("%s: unknown asset id" % where)
		elif str((item_value as Dictionary).get("kind", "")) != "ground":
			errors.append("%s: asset is not a ground item" % where)
		var x := _int_field(tile, "x", where, errors)
		var z := _int_field(tile, "z", where, errors)
		if has_dims and (x < 0 or x >= width or z < 0 or z >= depth):
			errors.append(
				"%s at cell (%d,%d): out of map bounds %dx%d" % [where, x, z, width, depth]
			)
		var key := "%d,%d" % [x, z]
		if seen.has(key):
			errors.append("%s at cell (%d,%d): duplicate ground tile" % [where, x, z])
		else:
			seen[key] = true
static func _validate_objects(
	document: Dictionary,
	items: Dictionary,
	width: int,
	depth: int,
	has_dims: bool,
	errors: Array[String]
) -> void:
	var raw: Variant = document.get("objects", [])
	if not (raw is Array):
		errors.append("objects: must be an array")
		return
	var objects: Array = raw
	var footprints: Array[Rect2i] = []
	var labels: Array[String] = []
	var coords: Array[Vector2i] = []
	for i in range(objects.size()):
		var object_value: Variant = objects[i]
		if not (object_value is Dictionary):
			errors.append("objects[%d]: must be an object" % i)
			continue
		var object: Dictionary = object_value
		var asset := str(object.get("asset", ""))
		var where := "objects[%d] '%s'" % [i, asset]
		if asset == "":
			errors.append("objects[%d]: asset is required" % i)
			continue
		var item_value: Variant = items.get(asset, null)
		if not (item_value is Dictionary):
			errors.append("%s: unknown asset id" % where)
			continue
		var item: Dictionary = item_value
		var kind := str(item.get("kind", ""))
		if not LayoutCatalog.KINDS.has(kind):
			errors.append("%s: catalog item has invalid kind '%s'" % [where, kind])
			continue
		var x := _int_field(object, "x", where, errors)
		var z := _int_field(object, "z", where, errors)
		var turn := _int_field(object, "turn", where, errors)
		if turn < 0 or turn > 3:
			errors.append("%s: turn must be 0..3" % where)
		if object.has("label") and typeof(object["label"]) != TYPE_STRING:
			errors.append("%s: label must be a string" % where)
		var cells := footprint_cells(item, x, z, turn)
		if has_dims and (cells.position.x < 0 or cells.position.y < 0 \
				or cells.position.x + cells.size.x > width \
				or cells.position.y + cells.size.y > depth):
			errors.append(
				"%s at cell (%d,%d) turn %d: footprint %dx%d exceeds map %dx%d" % [
					where, x, z, turn, cells.size.x, cells.size.y, width, depth
				]
			)
		for j in range(footprints.size()):
			if footprints[j].intersects(cells):
				errors.append(
					"%s at cell (%d,%d) overlaps %s at cell (%d,%d)" % [
						where, x, z, labels[j], coords[j].x, coords[j].y
					]
				)
				break
		footprints.append(cells)
		labels.append(where)
		coords.append(Vector2i(x, z))
static func _validate_regions(
	document: Dictionary,
	width: int,
	depth: int,
	has_dims: bool,
	errors: Array[String]
) -> void:
	var raw: Variant = document.get("regions", [])
	if not (raw is Array):
		errors.append("regions: must be an array")
		return
	var regions: Array = raw
	for i in range(regions.size()):
		var region_value: Variant = regions[i]
		if not (region_value is Dictionary):
			errors.append("regions[%d]: must be an object" % i)
			continue
		var region: Dictionary = region_value
		var where := "regions[%d] '%s'" % [i, str(region.get("name", ""))]
		if str(region.get("name", "")) == "":
			errors.append("regions[%d]: name is required" % i)
		var x := _int_field(region, "x", where, errors)
		var z := _int_field(region, "z", where, errors)
		var region_width := _int_field(region, "width", where, errors)
		var region_depth := _int_field(region, "depth", where, errors)
		if region_width < 1 or region_depth < 1:
			errors.append("%s: width and depth must be positive integers" % where)
			continue
		if has_dims and (x < 0 or z < 0 \
				or x + region_width > width or z + region_depth > depth):
			errors.append(
				"%s at cell (%d,%d) size %dx%d: out of map bounds %dx%d" % [
					where, x, z, region_width, region_depth, width, depth
				]
			)
static func _validate_spawn(
	document: Dictionary,
	items: Dictionary,
	width: int,
	depth: int,
	has_dims: bool,
	errors: Array[String]
) -> void:
	var spawn_value: Variant = document.get("spawn", null)
	if not (spawn_value is Dictionary):
		errors.append("spawn: object with x and z is required")
		return
	var spawn: Dictionary = spawn_value
	var x_value: Variant = spawn.get("x", null)
	var z_value: Variant = spawn.get("z", null)
	if not _is_number(x_value) or not _is_number(z_value):
		errors.append("spawn: x and z must be numbers")
		return
	var x := float(x_value)
	var z := float(z_value)
	if has_dims:
		var world_width := float(width) * TILE_SIZE
		var world_depth := float(depth) * TILE_SIZE
		if x < PLAYER_RADIUS or x > world_width - PLAYER_RADIUS \
				or z < PLAYER_RADIUS or z > world_depth - PLAYER_RADIUS:
			errors.append(
				"spawn (%.1f,%.1f): out of map bounds %.1fx%.1f" % [
					x, z, world_width, world_depth
				]
			)
			return
	var catalog := {"items": items}
	var point := Vector2(x, z)
	for entry in blocking_entries(document, catalog):
		var rect: Rect2 = entry["rect"]
		if rect.grow(PLAYER_RADIUS).has_point(point):
			errors.append(
				"spawn (%.1f,%.1f) is blocked by '%s' at cell (%d,%d)" % [
					x, z, entry["asset"], entry["x"], entry["z"]
				]
			)
			return
static func _check_span(document: Dictionary, field: String, errors: Array[String]) -> bool:
	var value: Variant = document.get(field, null)
	if not _is_int(value):
		errors.append("document: %s must be an integer" % field)
		return false
	var span := int(value)
	if span < MIN_SPAN or span > MAX_SPAN:
		errors.append(
			"document: %s must be %d..%d, got %d" % [field, MIN_SPAN, MAX_SPAN, span]
		)
		return false
	return true
static func _int_field(
	entry: Dictionary, field: String, where: String, errors: Array[String]
) -> int:
	var value: Variant = entry.get(field, null)
	if not _is_int(value):
		errors.append("%s: field '%s' must be an integer" % [where, field])
		return 0
	return int(value)
static func _writable_path(path: String) -> bool:
	if not path.ends_with(".json") or path.contains(".."):
		return false
	if path.begins_with(USER_WRITE_ROOT):
		return true
	for root in WRITE_ROOTS:
		if path.begins_with(root):
			return true
	return false
static func _valid_id(id: String) -> bool:
	return LayoutIds.valid_id(id)
static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
static func _is_int(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) == TYPE_FLOAT:
		var number: float = value
		return is_finite(number) and is_equal_approx(number, roundf(number))
	return false

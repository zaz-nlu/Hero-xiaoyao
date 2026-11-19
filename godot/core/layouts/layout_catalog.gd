@tool
extends RefCounted

# 探索地图目录库（layout catalog）。
#
# 数据文件：res://data/layout_catalog.json
# {
#   "version": 1,
#   "items": [
#     {"id", "name", "category", "kind", "size": [w, d],
#      "texture" / "sprite" / "scene", "blocking", "height", "billboard"}
#   ]
# }
# kind: ground | box | billboard | npc | exit | scene
# - size 以格为单位；运行时一格 = 2 游戏单位。
# - texture 用于 ground/box，sprite 用于 billboard/npc/exit。
# - scene 指向本地 PackedScene（.tscn，或导入为 PackedScene 的 .glb/.gltf），
#   只允许 res://assets/ 或 res://shared/scenery/layouts/prefabs/ 下的资源；
#   可选 texture 仅作编辑器缩略图。
# - 图片/场景只接受本地 res:// 完整路径，且必须真实存在。
#
# 公开 API（下一阶段编辑器直接调用）：
#   LayoutCatalog.load_catalog(path := CATALOG_PATH) -> Dictionary
#       {ok: bool, errors: Array[String], version: int,
#        items: Dictionary(id -> item), order: Array[String]}
#   LayoutCatalog.validate_catalog(data: Variant) -> Array[String]
#   LayoutCatalog.item(catalog: Dictionary, id: String) -> Dictionary
#   LayoutCatalog.item_ids(catalog: Dictionary) -> Array[String]
#
# 目录只按稳定 asset id 取数据；不 load()/preload() 目录中的任何路径，
# 也不执行来源内容，只做 JSON 校验、本地文件存在性与 PackedScene 类型检查。

const CATALOG_PATH := "res://data/layout_catalog.json"
const SCHEMA_VERSION := 1
const KINDS: Array[String] = ["ground", "box", "billboard", "npc", "exit", "scene"]
const SCENE_ROOTS: Array[String] = [
	"res://assets/", "res://shared/scenery/layouts/prefabs/",
]
const MAX_ITEM_SIZE := 96


static func load_catalog(path: String = CATALOG_PATH) -> Dictionary:
	var empty_errors: Array[String] = []
	var empty_order: Array[String] = []
	var result := {
		"ok": false,
		"errors": empty_errors,
		"version": 0,
		"items": {},
		"order": empty_order,
	}
	var errors: Array[String] = []
	if not FileAccess.file_exists(path):
		errors.append("catalog: cannot read %s" % path)
		result["errors"] = errors
		return result
	var json := JSON.new()
	var parse_error := json.parse(FileAccess.get_file_as_string(path))
	if parse_error != OK:
		errors.append(
			"catalog: %s line %d: %s" % [
				path, json.get_error_line(), json.get_error_message()
			]
		)
		result["errors"] = errors
		return result
	var data: Variant = json.data
	errors = validate_catalog(data)
	var items: Dictionary = {}
	var order: Array[String] = []
	var version := 0
	if data is Dictionary:
		var root: Dictionary = data
		if _is_int(root.get("version")):
			version = int(root.get("version"))
		var raw_items: Variant = root.get("items", [])
		if raw_items is Array:
			var entries: Array = raw_items
			for entry_value in entries:
				if not (entry_value is Dictionary):
					continue
				var entry: Dictionary = entry_value
				var id := str(entry.get("id", ""))
				if id == "" or items.has(id):
					continue
				items[id] = entry
				order.append(id)
	result["ok"] = errors.is_empty()
	result["errors"] = errors
	result["version"] = version
	result["items"] = items
	result["order"] = order
	return result


static func validate_catalog(data: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not (data is Dictionary):
		errors.append("catalog: top-level JSON must be an object")
		return errors
	var root: Dictionary = data
	if not _is_int(root.get("version")) or int(root.get("version")) != SCHEMA_VERSION:
		errors.append(
			"catalog: version must be %d" % SCHEMA_VERSION
		)
	var raw_items: Variant = root.get("items", null)
	if not (raw_items is Array):
		errors.append("catalog: items must be an array")
		return errors
	var entries: Array = raw_items
	if entries.is_empty():
		errors.append("catalog: items must not be empty")
	var seen: Dictionary = {}
	for i in range(entries.size()):
		var entry_value: Variant = entries[i]
		if not (entry_value is Dictionary):
			errors.append("catalog item %d: must be an object" % i)
			continue
		var entry: Dictionary = entry_value
		_validate_item(entry, i, seen, errors)
	return errors


static func item(catalog: Dictionary, id: String) -> Dictionary:
	var items_value: Variant = catalog.get("items", {})
	if items_value is Dictionary:
		var items: Dictionary = items_value
		var found: Variant = items.get(id, null)
		if found is Dictionary:
			return found
	return {}


static func item_ids(catalog: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var order_value: Variant = catalog.get("order", [])
	if order_value is Array:
		for value in order_value:
			result.append(str(value))
	return result


static func _validate_item(
	entry: Dictionary, index: int, seen: Dictionary, errors: Array[String]
) -> void:
	var id := str(entry.get("id", ""))
	var where := "catalog item %d" % index
	if id == "":
		errors.append("%s: id is required" % where)
	elif not _valid_id(id):
		errors.append(
			"%s: invalid id '%s' (use lowercase letters, digits and _)" % [where, id]
		)
	else:
		where = "catalog item '%s'" % id
		if seen.has(id):
			errors.append("%s: duplicate id" % where)
		seen[id] = true

	if str(entry.get("name", "")) == "":
		errors.append("%s: name is required" % where)
	if str(entry.get("category", "")) == "":
		errors.append("%s: category is required" % where)

	var kind := str(entry.get("kind", ""))
	if not KINDS.has(kind):
		errors.append(
			"%s: invalid kind '%s' (expected %s)" % [
				where, kind, ", ".join(PackedStringArray(KINDS))
			]
		)
		return

	var size_value: Variant = entry.get("size", null)
	if not (size_value is Array) or (size_value as Array).size() != 2:
		errors.append("%s: size must be [w, d]" % where)
	else:
		var size: Array = size_value
		if not _is_int(size[0]) or not _is_int(size[1]) \
				or int(size[0]) < 1 or int(size[1]) < 1:
			errors.append("%s: size values must be positive integers" % where)
		elif int(size[0]) > MAX_ITEM_SIZE or int(size[1]) > MAX_ITEM_SIZE:
			errors.append(
				"%s: size values must not exceed %d" % [where, MAX_ITEM_SIZE]
			)

	if entry.has("blocking") and typeof(entry["blocking"]) != TYPE_BOOL:
		errors.append("%s: blocking must be a bool" % where)
	if entry.has("billboard") and typeof(entry["billboard"]) != TYPE_BOOL:
		errors.append("%s: billboard must be a bool" % where)
	if entry.has("height") \
			and (not _is_number(entry["height"]) or float(entry["height"]) <= 0.0):
		errors.append("%s: height must be a positive number" % where)

	match kind:
		"ground":
			_validate_path(entry, "texture", where, true, errors)
			if bool(entry.get("blocking", false)):
				errors.append("%s: ground items cannot block" % where)
		"box":
			_validate_path(entry, "texture", where, true, errors)
			if not entry.has("height"):
				errors.append("%s: box items need a height" % where)
		"billboard":
			_validate_path(entry, "sprite", where, true, errors)
			if not entry.has("height"):
				errors.append("%s: billboard items need a height" % where)
		"npc":
			_validate_path(entry, "sprite", where, true, errors)
		"exit":
			_validate_path(entry, "sprite", where, false, errors)
		"scene":
			_validate_scene(entry, where, errors)


static func _validate_scene(
	entry: Dictionary, where: String, errors: Array[String]
) -> void:
	var path := str(entry.get("scene", ""))
	if path == "":
		errors.append("%s: scene path is required" % where)
		return
	if not _is_local_resource_path(path):
		errors.append(
			"%s: scene must be a local res:// path without '..' segments" % where
		)
		return
	if not _under_scene_root(path):
		var roots_message := "%s: scene path must be under " % where
		roots_message += "res://assets/ or res://shared/scenery/layouts/prefabs/"
		errors.append(roots_message)
		return
	if not ResourceLoader.exists(path, "PackedScene") \
			or not (ResourceLoader.load(path, "PackedScene") is PackedScene):
		errors.append("%s: scene is not a loadable PackedScene: %s" % [where, path])
	# 可选缩略图：编辑器按 texture/sprite 取图，缺省时退回条目图标。
	if entry.has("texture"):
		_validate_path(entry, "texture", where, false, errors)


static func _is_local_resource_path(path: String) -> bool:
	if not path.begins_with("res://"):
		return false
	for segment in path.split("/"):
		if segment == "..":
			return false
	return true


static func _under_scene_root(path: String) -> bool:
	for root in SCENE_ROOTS:
		if path.begins_with(root):
			return true
	return false


static func _validate_path(
	entry: Dictionary,
	field: String,
	where: String,
	required: bool,
	errors: Array[String]
) -> void:
	if not entry.has(field) or str(entry[field]) == "":
		if required:
			errors.append("%s: %s path is required" % [where, field])
		return
	var path := str(entry[field])
	if not path.begins_with("res://") or path.contains(".."):
		errors.append("%s: %s must be a local res:// path" % [where, field])
		return
	if not FileAccess.file_exists(path):
		errors.append("%s: %s file not found: %s" % [where, field, path])


static func _valid_id(id: String) -> bool:
	if id.is_empty():
		return false
	for i in range(id.length()):
		var code := id.unicode_at(i)
		if i == 0:
			if code < 97 or code > 122:
				return false
		elif not ((code >= 97 and code <= 122) \
				or (code >= 48 and code <= 57) or code == 95):
			return false
	return true


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _is_int(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) == TYPE_FLOAT:
		var number: float = value
		return is_finite(number) and is_equal_approx(number, roundf(number))
	return false

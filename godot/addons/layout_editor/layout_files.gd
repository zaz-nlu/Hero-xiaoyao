@tool
extends RefCounted

# 地图工坊的文件操作辅助：地图列表、新建草稿、保存与试跑快照。
# 只在这里碰磁盘；编辑过程中的所有修改都留在内存里。

const LayoutCatalog = preload("res://core/layouts/layout_catalog.gd")
const LayoutDocument = preload("res://core/layouts/layout_document.gd")

const MAP_DIR := "res://data/layouts"
const PLAYTEST_PATH := "user://map_editor_playtest.json"
const MIN_SPAN := 4
const MAX_SPAN := 96
const TILE_SIZE: float = 2.0


static func map_path(id: String) -> String:
	return "%s/%s.json" % [MAP_DIR, id]


# ID 只允许小写字母/数字/下划线且以字母开头；因此拼出来的路径无法穿越目录。
static func valid_id(id: String) -> bool:
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


static func list_maps() -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(MAP_DIR)
	if dir == null:
		return result
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			result.append("%s/%s" % [MAP_DIR, file_name])
		file_name = dir.get_next()
	dir.list_dir_end()
	result.sort()
	return result


static func default_ground(catalog: Dictionary) -> String:
	for id in LayoutCatalog.item_ids(catalog):
		var item := LayoutCatalog.item(catalog, id)
		if str(item.get("kind", "")) == "ground":
			return id
	return ""


static func build_new_document(
	catalog: Dictionary, id: String, display_name: String, width: int, depth: int
) -> Dictionary:
	if catalog.is_empty():
		return {"ok": false, "errors": ["素材目录尚未加载"], "document": {}}
	var clean_id := id.strip_edges()
	var clean_name := display_name.strip_edges()
	if not valid_id(clean_id):
		return {
			"ok": false,
			"errors": ["地图 ID 只能用小写字母、数字和下划线，且以字母开头"],
			"document": {},
		}
	if clean_name.is_empty():
		return {"ok": false, "errors": ["地图名字不能为空"], "document": {}}
	if width < MIN_SPAN or width > MAX_SPAN or depth < MIN_SPAN or depth > MAX_SPAN:
		return {
			"ok": false,
			"errors": ["地图格数必须在 %d..%d 之间" % [MIN_SPAN, MAX_SPAN]],
			"document": {},
		}
	if FileAccess.file_exists(map_path(clean_id)):
		return {
			"ok": false,
			"errors": ["地图 ID '%s' 已存在，请换一个" % clean_id],
			"document": {},
		}
	var ground := default_ground(catalog)
	if ground.is_empty():
		return {"ok": false, "errors": ["素材目录中没有可用的地面材料"], "document": {}}
	var center := Vector2(
		(float(width / 2) + 0.5) * TILE_SIZE,
		(float(depth / 2) + 0.5) * TILE_SIZE
	)
	var fresh := {
		"version": LayoutDocument.SCHEMA_VERSION,
		"id": clean_id,
		"name": clean_name,
		"width": width,
		"depth": depth,
		"ground": ground,
		"tiles": [],
		"objects": [],
		"spawn": {"x": center.x, "z": center.y},
		"regions": [],
	}
	var errors := LayoutDocument.validate_document(fresh, catalog)
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "document": {}}
	return {"ok": true, "errors": [], "document": fresh}


# 保存允许覆盖当前打开的同 ID 文件；把 ID 改成另一个已存在的文件则拒绝。
static func save(
	current_document: Dictionary, catalog: Dictionary, source_path: String
) -> Dictionary:
	if current_document.is_empty():
		return {"ok": false, "errors": ["没有打开的地图"]}
	var id := str(current_document.get("id", ""))
	if not valid_id(id):
		return {
			"ok": false,
			"errors": ["地图 ID 只能用小写字母、数字和下划线，且以字母开头"],
		}
	var target := map_path(id)
	if target != source_path and FileAccess.file_exists(target):
		return {
			"ok": false,
			"errors": [
				"地图 ID '%s' 已被其他文件使用，保存会覆盖它；请换一个 ID" % id
			],
		}
	var saved := LayoutDocument.save_document(target, current_document, catalog)
	if not bool(saved.get("ok", false)):
		return {"ok": false, "errors": saved.get("errors", [])}
	return {"ok": true, "errors": [], "path": target}


# 无论是否保存过，试跑快照都写到独立的 user:// 路径。
static func export_playtest(
	current_document: Dictionary, catalog: Dictionary, path: String = PLAYTEST_PATH
) -> Dictionary:
	if not path.begins_with("user://"):
		return {"ok": false, "errors": ["试跑快照只能写到 user://"]}
	if current_document.is_empty():
		return {"ok": false, "errors": ["没有打开的地图"]}
	var saved := LayoutDocument.save_document(path, current_document, catalog)
	if not bool(saved.get("ok", false)):
		return {"ok": false, "errors": saved.get("errors", [])}
	return {"ok": true, "errors": [], "path": path}

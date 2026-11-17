extends RefCounted

# 玩家档案（与存档无关）：记录标题页已经可以展示的地点，像相册一样只增不减。
# 纯静态工具，文件为 ConfigFile；读写失败一律静默忽略，方便测试用临时路径。

const PROFILE_PATH := "user://profile.cfg"
const SECTION := "places"
const KEY := "unlocked"

const PLACES := [
	{"id": "town", "name": "紫霞镇", "always": true},
	{"id": "tavern_outside", "name": "紫霞镇·酒馆", "always": true},
	{"id": "west_street", "name": "紫霞镇·西街", "always": false},
	{"id": "tavern_inside", "name": "酒馆内景", "always": false},
	{"id": "forest", "name": "紫霞林", "always": false},
	{"id": "gate", "name": "紫霞派山门", "always": false},
]


static func unlock(id: String, path: String = PROFILE_PATH) -> bool:
	if not _is_known(id):
		return false
	if is_unlocked(id, path):
		return false
	var ids := _read(path)
	if ids.has(id):
		return false
	ids.append(id)
	return _write(ids, path)


static func is_unlocked(id: String, path: String = PROFILE_PATH) -> bool:
	if _is_always(id):
		return true
	if not _is_known(id):
		return false
	return _read(path).has(id)


static func unlocked_ids(path: String = PROFILE_PATH) -> Array:
	var stored := _read(path)
	var result: Array = []
	for place_value in PLACES:
		var place: Dictionary = place_value
		var id := str(place.get("id", ""))
		if bool(place.get("always", false)) or stored.has(id):
			result.append(id)
	return result


static func place_name(id: String) -> String:
	for place_value in PLACES:
		var place: Dictionary = place_value
		if str(place.get("id", "")) == id:
			return str(place.get("name", ""))
	return ""


static func reset(path: String = PROFILE_PATH) -> void:
	if not FileAccess.file_exists(path):
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _is_known(id: String) -> bool:
	return place_name(id) != ""


static func _is_always(id: String) -> bool:
	for place_value in PLACES:
		var place: Dictionary = place_value
		if str(place.get("id", "")) != id:
			continue
		return bool(place.get("always", false))
	return false


static func _read(path: String) -> Array:
	var result: Array = []
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return result
	var value: Variant = config.get_value(SECTION, KEY, [])
	if not (value is Array):
		return result
	var stored: Array = value
	for item in stored:
		result.append(str(item))
	return result


static func _write(ids: Array, path: String) -> bool:
	var config := ConfigFile.new()
	var stored: Array = []
	for item in ids:
		stored.append(str(item))
	config.set_value(SECTION, KEY, stored)
	return config.save(path) == OK

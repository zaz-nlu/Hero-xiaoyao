extends RefCounted

# data/opening.json 的读取与校验（开场序幕）。纯数据层：不依赖场景/UI 类型。
# 返回统一的 {ok, errors, music, slides, storyteller} 结构给 app / features 使用。
# JSON 里的数字统一解析成 float，所以 seed / density 按“整数值的数字”校验。

const DEFAULT_PATH := "res://data/opening.json"
const SPRITES_DIR := "res://assets/sprites/"
const SCENERY_DIR := "res://assets/scenery/"
const BACKDROP_KINDS: Array[String] = ["battlefield", "art", "domain", "black"]
const PALETTES: Array[String] = ["ash", "dawn", "dusk", "gold"]


static func load_opening(path: String = DEFAULT_PATH) -> Dictionary:
	var result := _empty_result()
	if not FileAccess.file_exists(path):
		result["errors"].append("找不到序幕数据文件: %s" % path)
		return result
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		result["errors"].append("序幕数据不是有效的 JSON 对象: %s" % path)
		return result
	var data: Dictionary = parsed
	return validate(data)


static func validate(data: Dictionary) -> Dictionary:
	var result := _empty_result()
	var music_value: Variant = data.get("music", {})
	if music_value is Dictionary:
		var music: Dictionary = music_value
		result["music"] = {
			"intro": str(music.get("intro", "")),
			"town": str(music.get("town", "")),
		}
	else:
		result["errors"].append("music 必须是对象")
	var storyteller_value: Variant = data.get("storyteller", {})
	if storyteller_value is Dictionary:
		result["storyteller"] = storyteller_value
	else:
		result["errors"].append("storyteller 必须是对象")
	_validate_music(result)
	_validate_slides(data, result)
	if data.has("slides_after"):
		_validate_slides(data, result, "slides_after")
	result["duel"] = data.get("duel", {})
	_validate_storyteller(result)
	var errors: Array = result["errors"]
	result["ok"] = errors.is_empty()
	return result


static func _validate_music(result: Dictionary) -> void:
	var music: Dictionary = result["music"]
	for key in ["intro", "town"]:
		if str(music.get(key, "")) == "":
			result["errors"].append("music.%s 必须是非空字符串" % key)


static func _validate_slides(data: Dictionary, result: Dictionary, key: String = "slides") -> void:
	var slides_value: Variant = data.get(key)
	if not (slides_value is Array) or (slides_value as Array).is_empty():
		result["errors"].append("%s 必须是非空数组" % key)
		return
	var slides: Array = slides_value
	result[key] = slides
	for index in range(slides.size()):
		_validate_slide(slides[index], index, result, key)


static func _validate_slide(value: Variant, index: int, result: Dictionary, key: String = "slides") -> void:
	var label := "%s[%d]" % [key, index]
	if not (value is Dictionary):
		result["errors"].append("%s 必须是对象" % label)
		return
	var slide: Dictionary = value
	if str(slide.get("id", "")) == "":
		result["errors"].append("%s.id 必须是非空字符串" % label)
	if _number(slide.get("seconds")) <= 0.0:
		result["errors"].append("%s.seconds 必须大于 0" % label)
	var lines_value: Variant = slide.get("lines")
	if not (lines_value is Array) or (lines_value as Array).is_empty():
		result["errors"].append("%s.lines 必须是非空字符串数组" % label)
	else:
		var lines: Array = lines_value
		for line_index in range(lines.size()):
			var line_value: Variant = lines[line_index]
			if not (line_value is String) or str(line_value).strip_edges() == "":
				result["errors"].append("%s.lines[%d] 必须是非空字符串" % [label, line_index])
	var backdrop_value: Variant = slide.get("backdrop")
	if not (backdrop_value is Dictionary):
		result["errors"].append("%s.backdrop 必须是对象" % label)
		return
	_validate_backdrop(backdrop_value, label, result)


static func _validate_backdrop(
	backdrop: Dictionary, label: String, result: Dictionary
) -> void:
	var kind := str(backdrop.get("kind", ""))
	if not BACKDROP_KINDS.has(kind):
		result["errors"].append(
			"%s.backdrop.kind 必须是 %s 之一"
			% [label, ", ".join(PackedStringArray(BACKDROP_KINDS))]
		)
		return
	if kind == "art":
		_validate_art_backdrop(backdrop, label, result)
		return
	if kind == "domain":
		if not ["recover", "domain"].has(str(backdrop.get("stage", ""))):
			result["errors"].append("%s.backdrop.stage 必须是 recover 或 domain" % label)
		return
	if kind != "battlefield":
		return
	if not _is_integer(backdrop.get("seed")):
		result["errors"].append("%s.backdrop.seed 必须是整数" % label)
	var palette := str(backdrop.get("palette", ""))
	if not PALETTES.has(palette):
		result["errors"].append(
			"%s.backdrop.palette 必须是 %s 之一"
			% [label, ", ".join(PackedStringArray(PALETTES))]
		)
	if not _is_integer(backdrop.get("density")) or _number(backdrop.get("density")) <= 0.0:
		result["errors"].append("%s.backdrop.density 必须是大于 0 的整数" % label)


# art 背景：image 是 scenery/ 下的插画文件名；zoom 可选，必须大于 1（默认 1.1）。
static func _validate_art_backdrop(
	backdrop: Dictionary, label: String, result: Dictionary
) -> void:
	var image := str(backdrop.get("image", ""))
	if image.strip_edges() == "":
		result["errors"].append("%s.backdrop.image 必须是非空字符串" % label)
	elif not FileAccess.file_exists(SCENERY_DIR + image):
		result["errors"].append(
			"%s.backdrop.image 文件不存在: %s" % [label, SCENERY_DIR + image]
		)
	if backdrop.has("zoom"):
		var zoom: Variant = backdrop.get("zoom")
		if not (zoom is int or zoom is float) or float(zoom) <= 1.0:
			result["errors"].append("%s.backdrop.zoom 必须是大于 1 的数字" % label)


# storyteller 段供“书生讲故事”小场景使用：对话文件必须存在，
# scholar 与 crowd 的 id 都要有对应的 sprites/<id>.png 图集。
static func _validate_storyteller(result: Dictionary) -> void:
	var storyteller: Dictionary = result["storyteller"]
	var dialogue := str(storyteller.get("dialogue", ""))
	if dialogue == "":
		result["errors"].append("storyteller.dialogue 必须是非空字符串")
	elif not FileAccess.file_exists(dialogue):
		result["errors"].append("storyteller.dialogue 文件不存在: %s" % dialogue)
	_validate_story_sprite(storyteller.get("scholar"), "storyteller.scholar", result)
	var crowd_value: Variant = storyteller.get("crowd")
	if not (crowd_value is Array) or (crowd_value as Array).is_empty():
		result["errors"].append("storyteller.crowd 必须是非空字符串数组")
		return
	var crowd: Array = crowd_value
	for index in range(crowd.size()):
		_validate_story_sprite(crowd[index], "storyteller.crowd[%d]" % index, result)


static func _validate_story_sprite(value: Variant, label: String, result: Dictionary) -> void:
	if not (value is String) or str(value).strip_edges() == "":
		result["errors"].append("%s 必须是非空字符串" % label)
		return
	var path := SPRITES_DIR + str(value) + ".png"
	if not FileAccess.file_exists(path):
		result["errors"].append("%s 找不到图集: %s" % [label, path])


static func _is_integer(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		var number: float = value
		return is_equal_approx(number, floorf(number))
	return false


static func _number(value: Variant) -> float:
	if value is int or value is float:
		return float(value)
	return 0.0


static func _empty_result() -> Dictionary:
	return {
		"ok": false,
		"errors": [],
		"music": {},
		"slides": [],
		"slides_after": [],
		"duel": {},
		"storyteller": {},
	}

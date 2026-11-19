@tool
extends RefCounted

# 布局可选环境配置（schema version 1）：
#
#   "environment": {
#     "sky": "default",            # default / clear / dusk / night
#     "lighting": "default",       # default / warm / cool / night
#     "camera_clamp": [x0,z0,x1,z1],
#     "border": {"sides": ["north","south"], "depth": 14, "spacing": 3.2, "seed": 7}
#   }
#
# 全部字段可选；缺少 environment 或缺少某一项时沿用 layout_walk 当前默认值。
# camera_clamp 与 border 的语义同 town.json：相机夹取矩形必须在地图内；
# border 只在四边地图外铺背景树，空 sides 等于关闭。
# 校验只读文档，不规范化也不回写原文档。

const LayoutGrid := preload("res://core/layouts/layout_grid.gd")

const SKIES: Array[String] = ["default", "clear", "dusk", "night"]
const LIGHTING: Array[String] = ["default", "warm", "cool", "night"]
const SIDES: Array[String] = ["north", "south", "east", "west"]
const DEFAULT_SKY := "default"
const DEFAULT_LIGHTING := "default"
const DEFAULT_BORDER_SIDES: Array[String] = ["west", "east", "south"]
const DEFAULT_BORDER_DEPTH := 14.0
const DEFAULT_BORDER_SPACING := 3.2
const DEFAULT_BORDER_SEED := 7
const MAX_BORDER_DEPTH := 60.0
const MIN_BORDER_SPACING := 0.5
const MAX_BORDER_SPACING := 40.0
const MAX_BORDER_TREES := 2000
const EPSILON := 0.001


static func validate(document: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not (document is Dictionary):
		return errors
	var doc: Dictionary = document
	var raw_value: Variant = doc.get("environment", null)
	if raw_value == null:
		return errors
	if not (raw_value is Dictionary):
		errors.append("environment: must be an object")
		return errors
	var env: Dictionary = raw_value
	_validate_choice(env, "sky", SKIES, errors)
	_validate_choice(env, "lighting", LIGHTING, errors)
	_validate_camera_clamp(env, doc, errors)
	_validate_border(env, doc, errors)
	return errors


# ---------------------------------------------------------------- accessors

static func settings(document: Dictionary) -> Dictionary:
	var raw_value: Variant = document.get("environment", null)
	return raw_value if raw_value is Dictionary else {}


static func sky_id(document: Dictionary) -> String:
	var value := str(settings(document).get("sky", DEFAULT_SKY))
	return value if SKIES.has(value) else DEFAULT_SKY


static func lighting_id(document: Dictionary) -> String:
	var value := str(settings(document).get("lighting", DEFAULT_LIGHTING))
	return value if LIGHTING.has(value) else DEFAULT_LIGHTING


# 相机夹取矩形；缺省、非法或空面积时返回空矩形（不夹取）。
static func camera_clamp(document: Dictionary) -> Rect2:
	var value: Variant = settings(document).get("camera_clamp", null)
	if not (value is Array) or (value as Array).size() != 4:
		return Rect2()
	var coords: Array = value
	for coord in coords:
		if not _is_number(coord):
			return Rect2()
	var x0 := float(coords[0])
	var z0 := float(coords[1])
	var x1 := float(coords[2])
	var z1 := float(coords[3])
	if x1 <= x0 or z1 <= z0:
		return Rect2()
	return Rect2(x0, z0, x1 - x0, z1 - z0)


# 边界林配置；没有 border 或 sides 为空时返回空字典（不建林）。
# 其余字段沿用 town.json 的缺省值，缺键时补默认值。
static func border_options(document: Dictionary) -> Dictionary:
	var raw_value: Variant = settings(document).get("border", null)
	if not (raw_value is Dictionary):
		return {}
	var raw: Dictionary = raw_value
	var sides: Array = DEFAULT_BORDER_SIDES.duplicate()
	var sides_value: Variant = raw.get("sides", null)
	if sides_value is Array:
		sides = (sides_value as Array).duplicate()
	if sides.is_empty():
		return {}
	var depth := DEFAULT_BORDER_DEPTH
	var depth_value: Variant = raw.get("depth", null)
	if _is_number(depth_value):
		depth = float(depth_value)
	var spacing := DEFAULT_BORDER_SPACING
	var spacing_value: Variant = raw.get("spacing", null)
	if _is_number(spacing_value):
		spacing = float(spacing_value)
	var seed_value := DEFAULT_BORDER_SEED
	var seed_raw: Variant = raw.get("seed", null)
	if _is_int(seed_raw):
		seed_value = int(seed_raw)
	return {
		"sides": sides,
		"depth": depth,
		"spacing": spacing,
		"seed": seed_value,
	}


# ---------------------------------------------------------------- validation

static func _validate_choice(
	env: Dictionary, key: String, allowed: Array[String], errors: Array[String]
) -> void:
	if not env.has(key):
		return
	var value: Variant = env[key]
	if typeof(value) != TYPE_STRING or not allowed.has(str(value)):
		errors.append(
			"environment: %s must be one of %s" % [
				key, ", ".join(PackedStringArray(allowed))
			]
		)


static func _validate_camera_clamp(
	env: Dictionary, doc: Dictionary, errors: Array[String]
) -> void:
	if not env.has("camera_clamp"):
		return
	var value: Variant = env["camera_clamp"]
	if not (value is Array) or (value as Array).size() != 4:
		errors.append("environment.camera_clamp must be [x0,z0,x1,z1]")
		return
	var coords: Array = value
	for coord in coords:
		if not _is_number(coord):
			errors.append("environment.camera_clamp values must be finite numbers")
			return
	var x0 := float(coords[0])
	var z0 := float(coords[1])
	var x1 := float(coords[2])
	var z1 := float(coords[3])
	if x1 <= x0 + EPSILON or z1 <= z0 + EPSILON:
		errors.append("environment.camera_clamp must have positive area")
		return
	var bounds := LayoutGrid.world_bounds(doc)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return
	if x0 < bounds.position.x - EPSILON or z0 < bounds.position.y - EPSILON \
			or x1 > bounds.end.x + EPSILON or z1 > bounds.end.y + EPSILON:
		errors.append("environment.camera_clamp must stay inside the map")


static func _validate_border(
	env: Dictionary, doc: Dictionary, errors: Array[String]
) -> void:
	if not env.has("border"):
		return
	var value: Variant = env["border"]
	if not (value is Dictionary):
		errors.append("environment.border must be an object")
		return
	var border: Dictionary = value
	var sides: Array = DEFAULT_BORDER_SIDES.duplicate()
	if border.has("sides"):
		var sides_value: Variant = border["sides"]
		if not (sides_value is Array):
			errors.append("environment.border.sides must be an array")
			return
		sides = sides_value
		var seen: Dictionary = {}
		for side_value in sides:
			if typeof(side_value) != TYPE_STRING or not SIDES.has(str(side_value)):
				errors.append(
					"environment.border.sides must use north, south, east or west"
				)
				return
			if seen.has(str(side_value)):
				errors.append("environment.border.sides must not repeat %s" % str(side_value))
				return
			seen[str(side_value)] = true
	var depth := DEFAULT_BORDER_DEPTH
	if border.has("depth"):
		var depth_value: Variant = border["depth"]
		if not _is_number(depth_value):
			errors.append("environment.border.depth must be a finite number")
			return
		depth = float(depth_value)
		if depth <= 0.0 or depth > MAX_BORDER_DEPTH:
			errors.append(
				"environment.border.depth must be 0..%.0f" % MAX_BORDER_DEPTH
			)
			return
	var spacing := DEFAULT_BORDER_SPACING
	if border.has("spacing"):
		var spacing_value: Variant = border["spacing"]
		if not _is_number(spacing_value):
			errors.append("environment.border.spacing must be a finite number")
			return
		spacing = float(spacing_value)
		if spacing < MIN_BORDER_SPACING or spacing > MAX_BORDER_SPACING:
			errors.append(
				"environment.border.spacing must be %.1f..%.0f" % [
					MIN_BORDER_SPACING, MAX_BORDER_SPACING
				]
			)
			return
	if border.has("seed") and not _is_int(border["seed"]):
		errors.append("environment.border.seed must be an integer")
		return
	if sides.is_empty():
		return
	var bounds := LayoutGrid.world_bounds(doc)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return
	var estimate := tree_estimate(bounds, sides, depth, spacing)
	if estimate > MAX_BORDER_TREES:
		errors.append(
			"environment.border would place about %d trees; reduce depth or increase spacing (max %d)"
			% [estimate, MAX_BORDER_TREES]
		)


static func tree_estimate(
	bounds: Rect2, sides: Array, depth: float, spacing: float
) -> int:
	if spacing <= 0.0 or depth <= 0.0:
		return 0
	var rows := int(ceil(bounds.size.y / spacing))
	var cols := int(ceil(depth / spacing))
	var count := 0
	if sides.has("west"):
		count += rows * cols
	if sides.has("east"):
		count += rows * cols
	if sides.has("south"):
		count += int(ceil(bounds.size.x / spacing)) * cols
	if sides.has("north"):
		count += int(ceil(bounds.size.x / spacing)) * cols
	return count


static func _is_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) \
		and is_finite(float(value))


static func _is_int(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) == TYPE_FLOAT:
		var number: float = value
		return is_finite(number) and is_equal_approx(number, roundf(number))
	return false

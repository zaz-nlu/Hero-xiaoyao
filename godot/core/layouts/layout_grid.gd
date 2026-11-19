@tool
extends RefCounted

# 格坐标与占地/地图边界的共享纯规则。
# LayoutDocument（运行与校验）和 LayoutTerrainData（地形编译）都转发到这里，
# 避免运行、地形和编辑器出现第二套坐标换算或物件占格规则。

const TILE_SIZE := 2.0


static func footprint_cells(item: Dictionary, x: int, z: int, turn: int) -> Rect2i:
	var width := 1
	var depth := 1
	var size_value: Variant = item.get("size", null)
	if size_value is Array and (size_value as Array).size() == 2:
		width = int((size_value as Array)[0])
		depth = int((size_value as Array)[1])
	if posmod(turn, 4) % 2 == 1:
		var swap := width
		width = depth
		depth = swap
	return Rect2i(x, z, width, depth)


static func footprint_world(item: Dictionary, x: int, z: int, turn: int) -> Rect2:
	var cells := footprint_cells(item, x, z, turn)
	return Rect2(
		float(cells.position.x) * TILE_SIZE,
		float(cells.position.y) * TILE_SIZE,
		float(cells.size.x) * TILE_SIZE,
		float(cells.size.y) * TILE_SIZE
	)


static func item_footprint_world(
	items: Dictionary, asset: String, x: int, z: int, turn: int
) -> Rect2:
	var item_value: Variant = items.get(asset, null)
	if not (item_value is Dictionary):
		return Rect2()
	return footprint_world(item_value, x, z, turn)


static func item_footprint_cells(
	items: Dictionary, asset: String, x: int, z: int, turn: int
) -> Rect2i:
	var world := item_footprint_world(items, asset, x, z, turn)
	return Rect2i(
		int(round(world.position.x / TILE_SIZE)),
		int(round(world.position.y / TILE_SIZE)),
		int(round(world.size.x / TILE_SIZE)),
		int(round(world.size.y / TILE_SIZE))
	)


static func world_bounds(document: Dictionary) -> Rect2:
	var width := int(document.get("width", 0)) if _is_int(document.get("width")) else 0
	var depth := int(document.get("depth", 0)) if _is_int(document.get("depth")) else 0
	return Rect2(0.0, 0.0, float(width) * TILE_SIZE, float(depth) * TILE_SIZE)


static func _is_int(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) == TYPE_FLOAT:
		var number: float = value
		return is_finite(number) and is_equal_approx(number, roundf(number))
	return false

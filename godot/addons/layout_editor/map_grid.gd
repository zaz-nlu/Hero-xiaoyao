@tool
extends Control

# 布局编辑器俯视画布：只读 document / items，自身不改数据；格子像素 12..52，放入 ScrollContainer 可滚动。
# 公开接口：set_map(document, items) / set_zoom(px) / set_selection(cell) / set_preview(asset_id, turn)。
# brush_enabled = true 时按住左键拖动，发 brush_started / brush_moved / brush_finished。

signal cell_clicked(cell: Vector2i, button: int)
signal asset_dropped(asset_id: String, cell: Vector2i)
signal cell_hovered(cell: Vector2i)
signal brush_started(cell: Vector2i)
signal brush_moved(cell: Vector2i)
signal brush_finished()

const MIN_ZOOM: int = 12
const MAX_ZOOM: int = 52
const DEFAULT_ZOOM: int = 22
const MARGIN: float = 12.0
const TERRAIN_TILE: float = 2.0
# 达到这个缩放才在物件块里写名字，避免小格子糊成一团。
const NAME_ZOOM: int = 20
const DEFAULT_WIDTH: int = 24
const DEFAULT_DEPTH: int = 20

const WATER_FILL: Color = Color(0.18, 0.40, 0.62, 0.42)
const WATER_BORDER: Color = Color(0.45, 0.68, 0.92, 0.95)
const STAIRS_FILL: Color = Color(0.92, 0.62, 0.26, 0.34)
const STAIRS_BORDER: Color = Color(0.98, 0.76, 0.38, 0.95)
const RAMP_FILL: Color = Color(0.42, 0.74, 0.56, 0.32)
const RAMP_BORDER: Color = Color(0.60, 0.88, 0.66, 0.95)
const CAMERA_CLAMP_COLOR: Color = Color(0.36, 0.62, 1.0, 0.95)
const CAMERA_PENDING_COLOR: Color = Color(0.72, 0.48, 0.98, 0.95)

const GROUND_COLORS: Dictionary = {
	"stone": Color(0.42, 0.41, 0.39),
	"soil": Color(0.46, 0.36, 0.24),
	"grass": Color(0.27, 0.42, 0.27),
	"sand": Color(0.55, 0.49, 0.35),
	"water": Color(0.24, 0.37, 0.50),
}

# 素材表没给 color 时，按 kind 取色，保证每种材质/类别可辨认。
const KIND_COLORS: Dictionary = {
	"stone": Color(0.55, 0.54, 0.52),
	"soil": Color(0.52, 0.40, 0.27),
	"grass": Color(0.31, 0.50, 0.31),
	"water": Color(0.26, 0.40, 0.56),
	"building": Color(0.64, 0.44, 0.30),
	"prop": Color(0.48, 0.40, 0.62),
	"npc": Color(0.72, 0.52, 0.78),
	"spawn": Color(0.36, 0.78, 0.50),
	"exit": Color(0.92, 0.62, 0.26),
}

const GRID_LINE: Color = Color(1.0, 1.0, 1.0, 0.10)
const BORDER_COLOR: Color = Color(1.0, 1.0, 1.0, 0.20)
const REGION_COLOR: Color = Color(0.96, 0.82, 0.38, 0.85)
const SELECTION_COLOR: Color = Color(1.0, 0.94, 0.55, 1.0)
const HOVER_COLOR: Color = Color(1.0, 1.0, 1.0, 0.55)
const PREVIEW_OK: Color = Color(0.42, 0.92, 0.58, 0.35)
const PREVIEW_BAD: Color = Color(0.95, 0.33, 0.28, 0.42)
const CHIP_BG: Color = Color(0.10, 0.09, 0.07, 0.82)

var brush_enabled: bool = false:
	set(value):
		brush_enabled = value
		if not value:
			_finish_brush()

var _document: Dictionary = {}
var _items: Dictionary = {}
var _terrain: Dictionary = {}
var _terrain_pending_rect: Rect2 = Rect2()
var _terrain_pending_valid: bool = true
var _terrain_pending_label: String = ""
var _camera_rect: Rect2 = Rect2()
var _camera_pending: bool = false
var _camera_label: String = ""
var _width: int = 0
var _depth: int = 0
var _px: int = DEFAULT_ZOOM
var _selection: Vector2i = Vector2i(-1, -1)
var _hover: Vector2i = Vector2i(-1, -1)
var _preview_asset: String = ""
var _preview_turn: int = 0
var _preview_invalid: bool = false
var _brushing: bool = false
var _brush_last: Vector2i = Vector2i(-1, -1)

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	set_process_input(true)
	_update_min_size()

func get_zoom() -> int:
	return _px

func set_map(document: Dictionary, items: Dictionary) -> void:
	_document = document
	_items = items
	_terrain = {}
	_terrain_pending_rect = Rect2()
	_camera_rect = Rect2()
	_camera_pending = false
	_camera_label = ""
	_width = maxi(0, int(_document.get("width", 0)))
	_depth = maxi(0, int(_document.get("depth", 0)))
	_selection = Vector2i(-1, -1)
	_update_min_size()
	queue_redraw()


# 地形叠层只接收已编译结果；hover/重绘不会再触发编译或校验。
func set_terrain(compiled: Dictionary) -> void:
	_terrain = compiled
	queue_redraw()


func set_terrain_pending(rect: Rect2, valid: bool, label: String = "") -> void:
	_terrain_pending_rect = rect
	_terrain_pending_valid = valid
	_terrain_pending_label = label
	queue_redraw()


# 相机夹取范围：已提交用蓝色描边，框选中用紫色描边；rect 是世界单位。
func set_camera_overlay(rect: Rect2, pending: bool = false, label: String = "") -> void:
	_camera_rect = rect
	_camera_pending = pending
	_camera_label = label
	queue_redraw()

func set_zoom(value: int) -> void:
	_px = clampi(value, MIN_ZOOM, MAX_ZOOM)
	_update_min_size()
	queue_redraw()

func set_selection(cell: Vector2i) -> void:
	_selection = cell if _is_cell(cell) else Vector2i(-1, -1)
	queue_redraw()


# invalid 为 true 时预览显示成红色斜纹，供主面板表达碰撞/越界等异常。
func set_preview(asset_id: String, turn: int = 0, invalid: bool = false) -> void:
	_preview_asset = asset_id
	_preview_turn = posmod(turn, 360)
	_preview_invalid = invalid
	queue_redraw()


# 像素 → 地图格；落在边界外返回 (-1, -1)。
func cell_at(local_pos: Vector2) -> Vector2i:
	if _width <= 0 or _depth <= 0: return Vector2i(-1, -1)
	var px: float = _cell_px()
	var rel: Vector2 = local_pos - _origin()
	var x: int = int(floor(rel.x / px))
	var z: int = int(floor(rel.y / px))
	if x < 0 or z < 0 or x >= _width or z >= _depth: return Vector2i(-1, -1)
	return Vector2i(x, z)


# 旋转只交换占地宽深；锚点保持在格子左上，渲染与预览共用。
static func rotated_footprint(size: Vector2i, turn: int) -> Vector2i:
	var t: int = posmod(turn, 360)
	if t == 90 or t == 270:
		return Vector2i(size.y, size.x)
	return size


static func footprint_rect(cell: Vector2i, size: Vector2i, turn: int) -> Rect2i:
	return Rect2i(cell, rotated_footprint(size, turn))

# ---------------------------------------------------------------- 输入
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		_set_hover(cell_at(motion.position))
		if _brushing and brush_enabled and _hover.x >= 0 and _hover != _brush_last:
			_brush_last = _hover
			brush_moved.emit(_hover)
	elif event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_handle_left_press(button.position)
			elif _brushing:
				_finish_brush()
				accept_event()
		elif button.pressed and button.button_index == MOUSE_BUTTON_RIGHT:
			var cell: Vector2i = cell_at(button.position)
			if cell.x >= 0:
				cell_clicked.emit(cell, MOUSE_BUTTON_RIGHT)
				accept_event()

func _handle_left_press(pos: Vector2) -> void:
	var cell: Vector2i = cell_at(pos)
	if cell.x < 0: return
	if brush_enabled:
		# 笔刷模式只发 brush_started / brush_moved / brush_finished，不再发 cell_clicked。
		_finish_brush()
		_brushing = true
		_brush_last = cell
		brush_started.emit(cell)
	else:
		cell_clicked.emit(cell, MOUSE_BUTTON_LEFT)
	accept_event()


# 鼠标在画布外松开时 _gui_input 收不到，这里兜底结束这一笔。
func _input(event: InputEvent) -> void:
	if not _brushing: return
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
		_finish_brush()

func _finish_brush() -> void:
	if not _brushing: return
	_brushing = false
	_brush_last = Vector2i(-1, -1)
	brush_finished.emit()

func _set_hover(cell: Vector2i) -> void:
	if cell == _hover: return
	_hover = cell
	cell_hovered.emit(cell)
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover.x >= 0:
		_set_hover(Vector2i(-1, -1))

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary): return false
	var payload: Dictionary = data
	var asset: Variant = payload.get("layout_asset", null)
	if typeof(asset) != TYPE_STRING or str(asset).is_empty(): return false
	return cell_at(at_position).x >= 0

func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(at_position, data): return
	var asset_id: String = str((data as Dictionary).get("layout_asset", ""))
	asset_dropped.emit(asset_id, cell_at(at_position))

func _get_tooltip(at_position: Vector2) -> String:
	var cell: Vector2i = cell_at(at_position)
	if not _is_cell(cell): return ""
	var lines: String = "坐标 x=%d z=%d" % [cell.x, cell.y]
	var obj: Dictionary = _object_at(cell)
	if not obj.is_empty():
		var obj_asset: String = str(obj.get("asset", ""))
		var obj_name: String = _object_label(obj, _item_for(obj_asset), obj_asset)
		lines += ("\n物件：" + obj_name) if not obj_name.is_empty() else ""
	var tile: Dictionary = _tile_at(cell)
	if not tile.is_empty():
		var tile_asset: String = str(tile.get("asset", ""))
		var tile_name: String = str(_item_for(tile_asset).get("name", tile_asset))
		lines += ("\n地块：" + tile_name) if not tile_name.is_empty() else ""
	var region_name: String = _region_at(cell)
	lines += ("\n区域：" + region_name) if not region_name.is_empty() else ""
	return lines

# ---------------------------------------------------------------- 绘制
func _draw() -> void:
	if _width <= 0 or _depth <= 0: return
	var font: Font = get_theme_default_font()
	var px: float = _cell_px()
	var content := Rect2(_origin(), Vector2(float(_width) * px, float(_depth) * px))
	draw_rect(content, _ground_color())
	_draw_terrain_areas()
	_draw_grid_lines(px, content)
	_draw_tiles()
	_draw_objects(font)
	_draw_regions(font)
	_draw_markers(font)
	_draw_terrain_labels(font)
	_draw_terrain_pending(font)
	_draw_camera_overlay(font)
	_draw_selection(font)
	_draw_hover(font)
	_draw_preview(font)
	draw_rect(content, BORDER_COLOR, false, 1.0)

func _draw_grid_lines(px: float, content: Rect2) -> void:
	for x in range(_width + 1):
		var lx: float = content.position.x + float(x) * px
		draw_line(Vector2(lx, content.position.y), Vector2(lx, content.end.y), GRID_LINE, 1.0)
	for z in range(_depth + 1):
		var lz: float = content.position.y + float(z) * px
		draw_line(Vector2(content.position.x, lz), Vector2(content.end.x, lz), GRID_LINE, 1.0)

func _draw_tiles() -> void:
	for raw in _as_array(_document.get("tiles", [])):
		var tile: Dictionary = _as_dictionary(raw)
		var cell: Vector2i = _cell_from(tile)
		if tile.is_empty() or not _is_cell(cell):
			continue
		var item: Dictionary = _item_for(str(tile.get("asset", "")))
		var rect: Rect2 = _cell_rect(cell).grow(-1.0)
		draw_rect(rect, _item_color(item, Color(0.45, 0.42, 0.36)))
		var texture: Texture2D = _item_texture(item)
		if texture != null:
			draw_texture_rect(texture, rect, false)

func _draw_objects(font: Font) -> void:
	for raw in _as_array(_document.get("objects", [])):
		var obj: Dictionary = _as_dictionary(raw)
		var cell: Vector2i = _cell_from(obj)
		if obj.is_empty() or not _is_cell(cell):
			continue
		var asset: String = str(obj.get("asset", ""))
		var item: Dictionary = _item_for(asset)
		var rect := _map_rect(footprint_rect(cell, _item_size(item), int(obj.get("turn", 0)))).grow(-1.5)
		draw_rect(rect, _item_color(item, Color(0.52, 0.40, 0.62)))
		draw_rect(rect, Color(0.05, 0.04, 0.06, 0.85), false, 1.5)
		var texture: Texture2D = _item_texture(item)
		if texture != null:
			draw_texture_rect(texture, rect, false)
		_draw_turn_arrow(rect.get_center(), minf(rect.size.x, rect.size.y) * 0.30, int(obj.get("turn", 0)), Color(1, 1, 1, 0.85))
		if font == null or _px < NAME_ZOOM or rect.size.x < 34.0 or rect.size.y < 16.0:
			continue
		var fs: int = int(clampf(float(_px) * 0.28, 8.0, 14.0))
		var shown: String = _fit_text(_object_label(obj, item, asset), font, fs, rect.size.x - 4.0)
		if not shown.is_empty():
			draw_string(font, Vector2(rect.position.x + 2.0, rect.position.y + font.get_ascent(fs) + 2.0), shown, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 4.0, fs, Color(1, 1, 1, 0.95))

func _draw_regions(font: Font) -> void:
	for raw in _as_array(_document.get("regions", [])):
		var region: Dictionary = _as_dictionary(raw)
		var origin: Vector2i = _cell_from(region)
		var w: int = maxi(0, int(region.get("width", 0)))
		var d: int = maxi(0, int(region.get("depth", 0)))
		if origin.x < 0 or origin.y < 0 or w <= 0 or d <= 0:
			continue
		var rect := Rect2(_cell_rect(origin).position, Vector2(float(w), float(d)) * _cell_px())
		_draw_dashed_rect(rect, REGION_COLOR, 1.5)
		var region_name: String = str(region.get("name", ""))
		if font != null and not region_name.is_empty():
			var fs: int = int(clampf(float(_px) * 0.30, 9.0, 16.0))
			_draw_text_chip(rect.position + Vector2(3, 3), region_name, font, fs, CHIP_BG, REGION_COLOR, rect.size.x - 6.0)

func _draw_markers(font: Font) -> void:
	var spawn: Dictionary = _as_dictionary(_document.get("spawn", {}))
	if not spawn.is_empty() and _is_cell(_cell_from(spawn)):
		_draw_marker(_cell_from(spawn), Color(0.36, 0.82, 0.52), "出生", font)
	for raw in _as_array(_document.get("objects", [])):
		var obj: Dictionary = _as_dictionary(raw)
		var cell: Vector2i = _cell_from(obj)
		if obj.is_empty() or not _is_cell(cell):
			continue
		var kind: String = str(_item_for(str(obj.get("asset", ""))).get("kind", ""))
		if kind == "npc":
			_draw_marker(cell, Color(0.72, 0.52, 0.78), "NPC", font)
		elif kind == "spawn":
			_draw_marker(cell, Color(0.36, 0.82, 0.52), "出生", font)
		elif kind == "exit":
			_draw_marker(cell, Color(0.95, 0.65, 0.25), "出口", font)

func _draw_marker(cell: Vector2i, color: Color, label: String, font: Font) -> void:
	var rect: Rect2 = _cell_rect(cell)
	var center: Vector2 = rect.get_center()
	var radius: float = _cell_px() * 0.28
	draw_circle(center, radius, color)
	draw_arc(center, radius, 0.0, TAU, 20, Color(0.05, 0.04, 0.06, 0.85), 1.5)
	if font != null and _px >= 14:
		var fs: int = int(clampf(float(_px) * 0.24, 8.0, 12.0))
		_draw_text_chip(Vector2(rect.position.x, rect.end.y + 1.0), label, font, fs, CHIP_BG, color.lightened(0.25), _cell_px() * 2.4)

func _draw_selection(font: Font) -> void:
	if not _is_cell(_selection): return
	var rect: Rect2 = _selection_rect(_selection)
	draw_rect(rect, SELECTION_COLOR, false, 2.0)
	draw_rect(rect.grow(2.0), Color(0.05, 0.04, 0.06, 0.5), false, 1.0)
	if font != null:
		var fs: int = int(clampf(float(_px) * 0.26, 8.0, 12.0))
		_draw_text_chip(Vector2(rect.position.x, rect.end.y + 2.0), "%d, %d" % [_selection.x, _selection.y], font, fs, CHIP_BG, SELECTION_COLOR, -1.0)

func _draw_hover(font: Font) -> void:
	if not _is_cell(_hover) or _hover == _selection: return
	var rect: Rect2 = _cell_rect(_hover)
	draw_rect(rect, HOVER_COLOR, false, 1.5)
	if font != null and _preview_asset.is_empty():
		var fs: int = int(clampf(float(_px) * 0.24, 8.0, 11.0))
		_draw_text_chip(rect.position + Vector2(2, 2), "%d, %d" % [_hover.x, _hover.y], font, fs, Color(0.10, 0.09, 0.07, 0.72), Color(0.92, 0.90, 0.82, 0.95), -1.0)

func _draw_preview(font: Font) -> void:
	if _preview_asset.is_empty(): return
	var cell: Vector2i = _hover if _is_cell(_hover) else _selection
	if not _is_cell(cell): return
	var rect := _map_rect(footprint_rect(cell, _item_size(_item_for(_preview_asset)), _preview_turn)).grow(-1.0)
	var fill: Color = PREVIEW_BAD if _preview_invalid else PREVIEW_OK
	draw_rect(rect, fill)
	draw_rect(rect, fill.lightened(0.25), false, 2.0)
	if _preview_invalid:
		var offset: float = -rect.size.y
		while offset < rect.size.x:
			draw_line(Vector2(rect.position.x + offset, rect.end.y), Vector2(rect.position.x + offset + rect.size.y, rect.position.y), Color(1.0, 0.35, 0.30, 0.30), 1.0)
			offset += 7.0
	_draw_turn_arrow(rect.get_center(), minf(rect.size.x, rect.size.y) * 0.30, _preview_turn, Color(1, 1, 1, 0.9))
	var label: String = _object_label({}, _item_for(_preview_asset), _preview_asset)
	if font == null or label.is_empty():
		return
	var fs: int = int(clampf(float(_px) * 0.26, 8.0, 12.0))
	var chip_y: float = rect.position.y - float(fs) - 8.0
	if chip_y < _origin().y:
		chip_y = rect.end.y + 2.0
	_draw_text_chip(Vector2(rect.position.x, chip_y), label, font, fs, CHIP_BG, fill.lightened(0.4), rect.size.x)

# ---------------------------------------------------------------- 地形叠层
# 台地/水面/连接绘制在网格与物件下面；名称、高度与方向标在物件之后，
# 但仍低于选中/悬停提示，保证可读又不遮挡交互反馈。
func _draw_terrain_areas() -> void:
	for raw in _as_array(_terrain.get("water", [])):
		var entry: Dictionary = _as_dictionary(raw)
		var rect := _terrain_rect(entry.get("rect", null))
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		draw_rect(rect, WATER_FILL)
		draw_rect(rect, WATER_BORDER, false, 1.5)
	for raw in _as_array(_terrain.get("platforms", [])):
		var platform: Dictionary = _as_dictionary(raw)
		var rect := _terrain_rect(platform.get("rect", null))
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		var color := _platform_color(float(platform.get("y", 0.0)))
		draw_rect(rect, Color(color.r, color.g, color.b, 0.30))
		draw_rect(rect, color.lightened(0.30), false, 1.5)
	for raw in _as_array(_terrain.get("connectors", [])):
		var connector: Dictionary = _as_dictionary(raw)
		var rect := _terrain_rect(connector.get("rect", null))
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		var ramp := str(connector.get("kind", "stairs")) == "ramp"
		draw_rect(rect, RAMP_FILL if ramp else STAIRS_FILL)
		draw_rect(rect, RAMP_BORDER if ramp else STAIRS_BORDER, false, 1.2)


func _draw_terrain_labels(font: Font) -> void:
	if font == null:
		return
	var fs: int = int(clampf(float(_px) * 0.26, 8.0, 13.0))
	for raw in _as_array(_terrain.get("platforms", [])):
		var platform: Dictionary = _as_dictionary(raw)
		var rect := _terrain_rect(platform.get("rect", null))
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		var shown := str(platform.get("name", "")).strip_edges()
		if shown.is_empty():
			shown = "台地 %d" % (int(platform.get("index", 0)) + 1)
		var text := "%s · 高 %.1f · 下 %.1f" % [
			shown, float(platform.get("y", 0.0)), float(platform.get("from_y", 0.0)),
		]
		_draw_text_chip(
			rect.position + Vector2(2.0, 2.0), text, font, fs, CHIP_BG,
			_platform_color(float(platform.get("y", 0.0))).lightened(0.35),
			rect.size.x - 4.0
		)
	for raw in _as_array(_terrain.get("connectors", [])):
		var connector: Dictionary = _as_dictionary(raw)
		var rect := _terrain_rect(connector.get("rect", null))
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		var ramp := str(connector.get("kind", "stairs")) == "ramp"
		var color := RAMP_BORDER if ramp else STAIRS_BORDER
		_draw_connector_arrow(rect, str(connector.get("side", "south")), color)
		if _px < 15:
			continue
		var kind_text := "坡道" if ramp else "楼梯 %d 级" % int(connector.get("steps", 0))
		var text := "%s · %s · 深 %.0f" % [
			kind_text, _side_text(str(connector.get("side", ""))),
			float(connector.get("depth", 0.0)),
		]
		_draw_text_chip(
			rect.position + Vector2(2.0, 2.0), text, font, fs, CHIP_BG, color,
			rect.size.x - 4.0
		)
	for raw in _as_array(_terrain.get("water", [])):
		var water_entry: Dictionary = _as_dictionary(raw)
		var water_rect := _terrain_rect(water_entry.get("rect", null))
		if water_rect.size.x <= 0.0 or water_rect.size.y <= 0.0:
			continue
		var shown := str(water_entry.get("name", "")).strip_edges()
		if shown.is_empty():
			shown = "水面 %d" % (int(water_entry.get("index", 0)) + 1)
		_draw_text_chip(
			water_rect.position + Vector2(2.0, 2.0),
			"%s · 水位 %.2f" % [shown, float(water_entry.get("y", 0.0))],
			font, fs, CHIP_BG, WATER_BORDER, water_rect.size.x - 4.0
		)


func _draw_terrain_pending(font: Font) -> void:
	if _terrain_pending_rect.size.x <= 0.0 or _terrain_pending_rect.size.y <= 0.0:
		return
	var rect := _terrain_rect(_terrain_pending_rect)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var fill: Color = PREVIEW_BAD if not _terrain_pending_valid else PREVIEW_OK
	draw_rect(rect, Color(fill.r, fill.g, fill.b, 0.20))
	_draw_dashed_rect(rect, fill.lightened(0.35), 2.0)
	if font != null and not _terrain_pending_label.is_empty():
		var fs: int = int(clampf(float(_px) * 0.26, 8.0, 12.0))
		_draw_text_chip(
			rect.position + Vector2(3.0, 3.0), _terrain_pending_label, font, fs,
			CHIP_BG, fill.lightened(0.45), rect.size.x - 6.0
		)


func _draw_camera_overlay(font: Font) -> void:
	if _camera_rect.size.x <= 0.0 or _camera_rect.size.y <= 0.0:
		return
	var rect := _terrain_rect(_camera_rect)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var color := CAMERA_PENDING_COLOR if _camera_pending else CAMERA_CLAMP_COLOR
	draw_rect(rect, Color(color.r, color.g, color.b, 0.08))
	_draw_dashed_rect(rect, color, 2.0)
	if font == null or _camera_label.is_empty():
		return
	var fs: int = int(clampf(float(_px) * 0.26, 8.0, 12.0))
	_draw_text_chip(
		rect.position + Vector2(3.0, 3.0), _camera_label, font, fs,
		CHIP_BG, color.lightened(0.25), rect.size.x - 6.0
	)


func _draw_connector_arrow(rect: Rect2, side: String, color: Color) -> void:
	var center := rect.get_center()
	var dir := Vector2.ZERO
	match side:
		"north":
			dir = Vector2(0.0, -1.0)
		"east":
			dir = Vector2(1.0, 0.0)
		"west":
			dir = Vector2(-1.0, 0.0)
		_:
			dir = Vector2(0.0, 1.0)
	var reach := minf(rect.size.x, rect.size.y) * 0.32
	if reach <= 1.0:
		return
	var start := center - dir * reach
	var end := center + dir * reach
	draw_line(start, end, color, 2.0)
	var side_dir := Vector2(-dir.y, dir.x)
	var head := clampf(reach * 0.6, 4.0, 8.0)
	draw_colored_polygon(
		PackedVector2Array([
			end,
			end - dir * head + side_dir * head * 0.55,
			end - dir * head - side_dir * head * 0.55,
		]),
		color
	)


func _terrain_rect(value: Variant) -> Rect2:
	if not (value is Rect2):
		return Rect2()
	var rect: Rect2 = value
	var scale := _cell_px() / TERRAIN_TILE
	return Rect2(_origin() + rect.position * scale, rect.size * scale)


func _platform_color(y: float) -> Color:
	var t := clampf(y / 6.0, 0.0, 1.0)
	return Color(0.34, 0.40, 0.46).lerp(Color(0.62, 0.47, 0.28), t)


func _side_text(side: String) -> String:
	match side:
		"north":
			return "北"
		"south":
			return "南"
		"east":
			return "东"
		"west":
			return "西"
	return side


# ---------------------------------------------------------------- 绘制辅助
func _draw_turn_arrow(center: Vector2, radius: float, turn: int, color: Color) -> void:
	if radius <= 1.0: return
	var angle: float = deg_to_rad(float(posmod(turn, 360))) - PI * 0.5
	var dir := Vector2(cos(angle), sin(angle))
	var side := Vector2(-dir.y, dir.x)
	var base: Vector2 = center + dir * radius * 0.15
	draw_colored_polygon(PackedVector2Array([center + dir * radius, base + side * radius * 0.48, base - side * radius * 0.48]), color)

func _draw_dashed_rect(rect: Rect2, color: Color, width: float) -> void:
	_draw_dashed_line(rect.position, Vector2(rect.end.x, rect.position.y), color, width)
	_draw_dashed_line(Vector2(rect.end.x, rect.position.y), rect.end, color, width)
	_draw_dashed_line(rect.end, Vector2(rect.position.x, rect.end.y), color, width)
	_draw_dashed_line(Vector2(rect.position.x, rect.end.y), rect.position, color, width)

func _draw_dashed_line(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var total: float = from.distance_to(to)
	var dir: Vector2 = (to - from) / maxf(total, 0.001)
	var dash: float = 6.0 if _px >= 18 else 4.0
	var pos: float = 0.0
	while pos < total:
		var seg_end: float = minf(pos + dash, total)
		draw_line(from + dir * pos, from + dir * seg_end, color, width)
		pos = seg_end + 4.0

func _draw_text_chip(pos: Vector2, text: String, font: Font, font_size: int, bg: Color, fg: Color, max_width: float) -> void:
	if font == null or text.is_empty(): return
	var shown: String = _fit_text(text, font, font_size, max_width)
	var text_size: Vector2 = font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_rect(Rect2(pos, text_size + Vector2(6.0, 4.0)), bg)
	draw_string(font, pos + Vector2(3.0, font.get_ascent(font_size) + 1.0), shown, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, fg)

func _fit_text(text: String, font: Font, font_size: int, max_width: float) -> String:
	if font == null or text.is_empty() or max_width <= 0.0: return text
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
		return text
	var trimmed: String = text
	while trimmed.length() > 1:
		trimmed = trimmed.substr(0, trimmed.length() - 1)
		if font.get_string_size(trimmed + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
			return trimmed + "…"
	return ""

# ---------------------------------------------------------------- 几何与数据读取
func _cell_px() -> float:
	return float(_px)

func _origin() -> Vector2:
	return Vector2(MARGIN, MARGIN)

func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(_origin() + Vector2(float(cell.x), float(cell.y)) * _cell_px(), Vector2(_cell_px(), _cell_px()))

func _selection_rect(cell: Vector2i) -> Rect2:
	var obj: Dictionary = _object_at(cell)
	if obj.is_empty(): return _cell_rect(cell)
	var item: Dictionary = _item_for(str(obj.get("asset", "")))
	return _map_rect(footprint_rect(cell, _item_size(item), int(obj.get("turn", 0))))

func _map_rect(cells: Rect2i) -> Rect2:
	return Rect2(_cell_rect(cells.position).position, Vector2(cells.size) * _cell_px())

func _update_min_size() -> void:
	var cols: int = _width if _width > 0 else DEFAULT_WIDTH
	var rows: int = _depth if _depth > 0 else DEFAULT_DEPTH
	custom_minimum_size = Vector2(float(cols) * _cell_px() + MARGIN * 2.0, float(rows) * _cell_px() + MARGIN * 2.0)

func _is_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _width and cell.y < _depth

func _cell_from(entry: Dictionary) -> Vector2i:
	return Vector2i(int(entry.get("x", 0)), int(entry.get("z", 0)))

func _as_array(value: Variant) -> Array:
	return value if value is Array else []

func _as_dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _item_for(asset_id: String) -> Dictionary:
	var raw: Variant = _items.get(asset_id, {})
	return raw if raw is Dictionary else {}

func _item_size(item: Dictionary) -> Vector2i:
	var raw: Variant = item.get("size", null)
	if raw is Array and (raw as Array).size() >= 2:
		var arr: Array = raw
		return Vector2i(maxi(1, int(arr[0])), maxi(1, int(arr[1])))
	return Vector2i(1, 1)

func _item_color(item: Dictionary, fallback: Color) -> Color:
	var raw: Variant = item.get("color", null)
	if raw is Color:
		var given: Color = raw
		return given
	if raw is String:
		return Color.from_string(str(raw), fallback)
	var mapped: Variant = KIND_COLORS.get(str(item.get("kind", "")))
	var kind_color: Color = mapped if mapped is Color else fallback
	return kind_color

func _item_texture(item: Dictionary) -> Texture2D:
	var raw: Variant = item.get("texture", item.get("sprite", null))
	return raw as Texture2D

func _ground_color() -> Color:
	var mapped: Variant = GROUND_COLORS.get(str(_document.get("ground", "stone")))
	return mapped if mapped is Color else Color(0.32, 0.31, 0.30)

func _object_label(obj: Dictionary, item: Dictionary, fallback: String) -> String:
	var label: String = str(obj.get("label", ""))
	if not label.is_empty():
		return label
	var item_name: String = str(item.get("name", ""))
	return item_name if not item_name.is_empty() else fallback

func _object_at(cell: Vector2i) -> Dictionary:
	for raw in _as_array(_document.get("objects", [])):
		var obj: Dictionary = _as_dictionary(raw)
		var origin: Vector2i = _cell_from(obj)
		var rect: Rect2i = footprint_rect(origin, _item_size(_item_for(str(obj.get("asset", "")))), int(obj.get("turn", 0)))
		if not obj.is_empty() and rect.has_point(cell):
			return obj
	return {}

func _tile_at(cell: Vector2i) -> Dictionary:
	for raw in _as_array(_document.get("tiles", [])):
		var tile: Dictionary = _as_dictionary(raw)
		if not tile.is_empty() and _cell_from(tile) == cell:
			return tile
	return {}

func _region_at(cell: Vector2i) -> String:
	for raw in _as_array(_document.get("regions", [])):
		var region: Dictionary = _as_dictionary(raw)
		var origin: Vector2i = _cell_from(region)
		var w: int = maxi(0, int(region.get("width", 0)))
		var d: int = maxi(0, int(region.get("depth", 0)))
		if not region.is_empty() and Rect2i(origin, Vector2i(w, d)).has_point(cell):
			return str(region.get("name", ""))
	return ""

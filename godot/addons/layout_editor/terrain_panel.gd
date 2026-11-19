@tool
extends VBoxContainer

# 地图工坊的地形工具区：台地/水面/连接的表单与临时圈选状态。
# 只持有界面和“点到一半”的操作；所有文档修改都经 EditState 的草稿提交入口，
# 校验、撤销与 changed/status 信号由 state 统一负责。

signal status(kind: String, message: String)
signal edit_mode_requested
signal edit_mode_finished

const LayoutCatalog := preload("res://core/layouts/layout_catalog.gd")
const EditQueries := preload("res://addons/layout_editor/edit_queries.gd")
const EditState := preload("res://addons/layout_editor/edit_state.gd")
const TerrainData := preload("res://core/layouts/layout_terrain_data.gd")

const SECTION_COLOR := Color(0.93, 0.79, 0.47)
const MUTED_COLOR := Color(0.68, 0.67, 0.62)
const TILE_SIZE: float = 2.0

enum Pending { NONE, TERRACE, WATER, CONNECT }

var state: EditState = null

var _built := false
var _doc_key := ""

var _terrace_list: ItemList = null
var _name_edit: LineEdit = null
var _y_spin: SpinBox = null
var _from_spin: SpinBox = null
var _top_option: OptionButton = null
var _terrace_note: Label = null
var _water_list: ItemList = null
var _water_name: LineEdit = null
var _water_auto: CheckBox = null
var _water_level: SpinBox = null
var _water_note: Label = null
var _kind_option: OptionButton = null
var _side_option: OptionButton = null
var _connector_list: ItemList = null
var _connector_note: Label = null
var _hover_note: Label = null

var _terrace_index := -1
var _terrace_signature := ""
var _water_index := -1
var _water_signature := ""
var _connector_platform := -1
var _connector_stairs := -1
var _connector_signature := ""
var _pending := Pending.NONE
var _corner_a := Vector2i(-1, -1)
var _connect_a := Vector2i(-1, -1)
var _hover := Vector2i(-1, -1)


func setup(edit_state: EditState) -> void:
	state = edit_state


func _ready() -> void:
	if _built:
		return
	_built = true
	_build_ui()
	refresh()


# ---------------------------------------------------------------- 对外
func is_pending() -> bool:
	return _pending != Pending.NONE


func cancel_pending(notify: bool = true) -> void:
	var had := _pending != Pending.NONE
	_pending = Pending.NONE
	_corner_a = Vector2i(-1, -1)
	_connect_a = Vector2i(-1, -1)
	if had and notify:
		status.emit("info", "已取消进行中的地形操作")


func handle_cell_hovered(cell: Vector2i) -> void:
	_hover = cell
	if _hover_note == null:
		return
	if state != null and state.has_document() and cell.x >= 0:
		var height := state.terrain_height_at_cell(cell)
		_hover_note.text = "光标 (%d, %d) · 地面高度 %.1f" % [cell.x, cell.y, height]
	else:
		_hover_note.text = "光标 —"


# 返回 true 表示仍在等待下一次点击；false 表示完成或已无待办。
func handle_cell_clicked(cell: Vector2i) -> bool:
	if state == null or not state.has_document():
		_pending = Pending.NONE
		return false
	match _pending:
		Pending.TERRACE:
			if _corner_a.x < 0:
				_corner_a = cell
				status.emit("info", "台地角一 (%d, %d)，再点对角完成" % [cell.x, cell.y])
				return true
			var terrace_added := state.add_terrace(
				_name_edit.text, _corner_a, cell,
				float(_y_spin.value), float(_from_spin.value), _selected_top_asset()
			)
			if bool(terrace_added.get("ok", false)):
				_pending = Pending.NONE
				_corner_a = Vector2i(-1, -1)
				_select_terrace(int(terrace_added.get("index", -1)))
				edit_mode_finished.emit()
				return false
			return true
		Pending.WATER:
			if _corner_a.x < 0:
				_corner_a = cell
				status.emit("info", "水面角一 (%d, %d)，再点对角完成" % [cell.x, cell.y])
				return true
			var level: Variant = null
			if not _water_auto.button_pressed:
				level = float(_water_level.value)
			var water_added := state.add_water(_water_name.text, _corner_a, cell, level)
			if bool(water_added.get("ok", false)):
				_pending = Pending.NONE
				_corner_a = Vector2i(-1, -1)
				_select_water(int(water_added.get("index", -1)))
				edit_mode_finished.emit()
				return false
			return true
		Pending.CONNECT:
			if _connect_a.x < 0:
				_connect_a = cell
				status.emit("info", "连接起点 (%d, %d)，再点同一侧边缘的末尾格" % [cell.x, cell.y])
				return true
			var connector_added := state.add_connector(
				_terrace_index, _selected_kind(), _selected_side(), _connect_a, cell
			)
			if bool(connector_added.get("ok", false)):
				_pending = Pending.NONE
				_connect_a = Vector2i(-1, -1)
				_connector_platform = _terrace_index
				_connector_stairs = int(connector_added.get("stairs_index", -1))
				_connector_signature = _stairs_sig(_connector_platform, _connector_stairs)
				refresh()
				edit_mode_finished.emit()
				return false
			return true
	_pending = Pending.NONE
	return false


# 画布悬浮预览：返回 {rect: Rect2(世界), valid: bool, label: String} 或空。
func preview() -> Dictionary:
	if state == null or not state.has_document() or _hover.x < 0:
		return {}
	if _pending == Pending.TERRACE or _pending == Pending.WATER:
		if _corner_a.x < 0:
			return {}
		var rect := EditQueries.cell_rect_world(_corner_a, _hover)
		var cells := EditQueries.cell_rect(_corner_a, _hover)
		var label := "%s %d×%d 格" % [
			"台地" if _pending == Pending.TERRACE else "水面", cells.size.x, cells.size.y,
		]
		return {"rect": rect, "valid": _rect_preview_valid(_pending, rect), "label": label}
	if _pending == Pending.CONNECT and _connect_a.x >= 0:
		return _connector_preview(_connect_a, _hover)
	return {}


# ---------------------------------------------------------------- 刷新
func refresh() -> void:
	if not _built or state == null:
		return
	if not state.has_document():
		_terrace_list.clear()
		_water_list.clear()
		_connector_list.clear()
		return
	var key := "%s|%s" % [state.source_path, state.document_id()]
	if key != _doc_key:
		_doc_key = key
		_terrace_index = -1
		_terrace_signature = ""
		_water_index = -1
		_water_signature = ""
		_connector_platform = -1
		_connector_stairs = -1
		_connector_signature = ""
		if _top_option != null:
			_top_option.select(-1)
		cancel_pending(false)
	_refresh_top_options()
	_refresh_terraces()
	_refresh_water()
	_refresh_connectors()
	_update_note()


func _refresh_top_options() -> void:
	var current := _selected_top_asset()
	if current.is_empty():
		current = str(state.document.get("ground", ""))
	_top_option.clear()
	for id in LayoutCatalog.item_ids(state.catalog):
		var item := LayoutCatalog.item(state.catalog, id)
		if str(item.get("kind", "")) != "ground":
			continue
		_top_option.add_item(str(item.get("name", id)))
		_top_option.set_item_metadata(_top_option.item_count - 1, id)
	_select_top_asset(current)


func _refresh_terraces() -> void:
	var terraces: Array = state.document.get("terraces", [])
	_terrace_index = _find_terrace(terraces)
	_terrace_list.clear()
	for i in range(terraces.size()):
		var entry: Dictionary = terraces[i]
		var shown := str(entry.get("name", "")).strip_edges()
		if shown.is_empty():
			shown = "台地 %d" % (i + 1)
		_terrace_list.add_item("%s · 高 %.1f / 下 %.1f" % [
			shown, float(entry.get("y", 0.0)), float(entry.get("from_y", 0.0)),
		])
	if _terrace_index >= 0:
		_terrace_list.select(_terrace_index)
		_fill_terrace_form(_terrace_index)
	else:
		_terrace_signature = ""


func _refresh_water() -> void:
	var water: Array = state.document.get("water", [])
	_water_index = _find_water(water)
	_water_list.clear()
	for i in range(water.size()):
		var entry: Dictionary = water[i]
		var shown := str(entry.get("name", "")).strip_edges()
		if shown.is_empty():
			shown = "水面 %d" % (i + 1)
		var level := "自动水位"
		if entry.has("y"):
			level = "水位 %.2f" % float(entry.get("y", 0.0))
		_water_list.add_item("%s · %s" % [shown, level])
	if _water_index >= 0:
		_water_list.select(_water_index)
		_fill_water_form(_water_index)
	else:
		_water_signature = ""


func _refresh_connectors() -> void:
	_connector_list.clear()
	var connectors: Array = state.terrain().get("connectors", [])
	var terraces: Array = state.document.get("terraces", [])
	var found := -1
	for i in range(connectors.size()):
		var connector: Dictionary = connectors[i]
		var platform := int(connector.get("platform", -1))
		var stairs_index := int(connector.get("stairs_index", -1))
		var ramp := str(connector.get("kind", "stairs")) == "ramp"
		var width := float(connector.get("open1", 0.0)) - float(connector.get("open0", 0.0))
		_connector_list.add_item("%s · %s · %s · 宽 %.0f" % [
			_terrace_name(terraces, platform),
			_side_text(str(connector.get("side", ""))),
			"坡道" if ramp else "楼梯",
			width,
		])
		_connector_list.set_item_metadata(i, {
			"platform": platform, "stairs_index": stairs_index,
		})
		if _connector_signature.is_empty():
			continue
		if _stairs_sig(platform, stairs_index) == _connector_signature:
			found = i
			_connector_platform = platform
			_connector_stairs = stairs_index
	if found >= 0:
		_connector_list.select(found)
	else:
		_connector_platform = -1
		_connector_stairs = -1
		_connector_signature = ""


func _update_note() -> void:
	if _terrace_note == null:
		return
	var y := float(_y_spin.value)
	var from_y := float(_from_spin.value)
	var rise := y - from_y
	if rise <= 0.0:
		_terrace_note.text = "顶部高度必须高于下层高度。"
	else:
		var stairs_depth := TerrainData.connector_depth("stairs", from_y, y)
		var ramp_depth := TerrainData.connector_depth("ramp", from_y, y)
		_terrace_note.text = "高差 %.1f：楼梯 %d 级、向外 %.0f；坡道向外 %.0f。\n连接从台地边缘向低侧延伸，低侧地面必须等于下层高度。" % [
			rise, TerrainData.stairs_steps(from_y, y), stairs_depth, ramp_depth,
		]
	_refresh_kind_labels(rise, from_y, y)
	if _connector_note != null:
		var entry := _connector_entry(_connector_platform, _connector_stairs)
		if entry.is_empty():
			_connector_note.text = "连接会占用台地外侧空间；上下层接合由 runtime 校验。"
		else:
			_connector_note.text = "当前连接：%s %s · 宽 %.0f；低侧地面必须等于台地下层高度。" % [
				"坡道" if str(entry.get("kind", "stairs")) == "ramp" else "楼梯",
				_side_text(str(entry.get("side", "south"))),
				_opening_width(entry),
			]


func _refresh_kind_labels(rise: float, from_y: float, y: float) -> void:
	if _kind_option == null or _kind_option.item_count < 2:
		return
	if rise <= 0.0:
		_kind_option.set_item_text(0, "楼梯（需要正高差）")
		_kind_option.set_item_text(1, "坡道（需要正高差）")
		return
	_kind_option.set_item_text(
		0, "楼梯（%d 级 / 深 %.0f）" % [TerrainData.stairs_steps(from_y, y), TerrainData.connector_depth("stairs", from_y, y)]
	)
	_kind_option.set_item_text(
		1, "坡道（深 %.0f）" % TerrainData.connector_depth("ramp", from_y, y)
	)


# ---------------------------------------------------------------- 表单填充
func _fill_terrace_form(index: int) -> void:
	var terraces: Array = state.document.get("terraces", [])
	if index < 0 or index >= terraces.size():
		return
	var entry: Dictionary = terraces[index]
	_name_edit.text = str(entry.get("name", ""))
	_y_spin.set_value_no_signal(float(entry.get("y", 1.0)))
	_from_spin.set_value_no_signal(float(entry.get("from_y", 0.0)))
	var top := str(entry.get("top", state.document.get("ground", "")))
	_select_top_asset(top)
	_update_note()


func _fill_water_form(index: int) -> void:
	var water: Array = state.document.get("water", [])
	if index < 0 or index >= water.size():
		return
	var entry: Dictionary = water[index]
	_water_name.text = str(entry.get("name", ""))
	var has_level := entry.has("y")
	_water_auto.set_pressed_no_signal(not has_level)
	_water_level.editable = has_level
	if has_level:
		_water_level.set_value_no_signal(float(entry.get("y", 0.5)))
	_update_water_note()


func _select_top_asset(asset_id: String) -> void:
	for i in range(_top_option.item_count):
		if str(_top_option.get_item_metadata(i)) == asset_id:
			_top_option.select(i)
			return
	if _top_option.item_count > 0:
		_top_option.select(0)
	else:
		_top_option.select(-1)


func _selected_top_asset() -> String:
	if _top_option == null or _top_option.selected < 0:
		return ""
	return str(_top_option.get_item_metadata(_top_option.selected))


func _selected_kind() -> String:
	if _kind_option == null or _kind_option.selected < 0:
		return "stairs"
	return str(_kind_option.get_item_metadata(_kind_option.selected))


func _selected_side() -> String:
	if _side_option == null or _side_option.selected < 0:
		return ""
	return str(_side_option.get_item_metadata(_side_option.selected))


# ---------------------------------------------------------------- 列表选择
func _on_terrace_selected(index: int) -> void:
	var terraces: Array = state.document.get("terraces", [])
	if index < 0 or index >= terraces.size():
		return
	_terrace_index = index
	_terrace_signature = _terrace_sig(terraces[index])
	_fill_terrace_form(index)


func _on_water_selected(index: int) -> void:
	var water: Array = state.document.get("water", [])
	if index < 0 or index >= water.size():
		return
	_water_index = index
	_water_signature = _water_sig(water[index])
	_fill_water_form(index)


func _on_connector_selected(index: int) -> void:
	var meta_value: Variant = _connector_list.get_item_metadata(index)
	if not (meta_value is Dictionary):
		return
	var meta: Dictionary = meta_value
	_connector_platform = int(meta.get("platform", -1))
	_connector_stairs = int(meta.get("stairs_index", -1))
	_connector_signature = _stairs_sig(_connector_platform, _connector_stairs)
	_update_note()


func _select_terrace(index: int) -> void:
	var terraces: Array = state.document.get("terraces", [])
	if index < 0 or index >= terraces.size():
		return
	_terrace_index = index
	_terrace_signature = _terrace_sig(terraces[index])
	refresh()


func _select_water(index: int) -> void:
	var water: Array = state.document.get("water", [])
	if index < 0 or index >= water.size():
		return
	_water_index = index
	_water_signature = _water_sig(water[index])
	refresh()


# ---------------------------------------------------------------- 按钮
func _on_draw_terrace_pressed() -> void:
	_pending = Pending.TERRACE
	_corner_a = Vector2i(-1, -1)
	_connect_a = Vector2i(-1, -1)
	status.emit("info", "圈台地：点画布两个对角（含两端格）")
	edit_mode_requested.emit()


func _on_apply_terrace_pressed() -> void:
	if _terrace_index < 0:
		status.emit("error", "请先在台地列表选中一个台地")
		return
	var index := _terrace_index
	var result := state.update_terrace(
		index, _name_edit.text, float(_y_spin.value),
		float(_from_spin.value), _selected_top_asset()
	)
	if bool(result.get("ok", false)):
		var terraces: Array = state.document.get("terraces", [])
		if index >= 0 and index < terraces.size():
			_terrace_index = index
			_terrace_signature = _terrace_sig(terraces[index])
		refresh()


func _on_delete_terrace_pressed() -> void:
	if _terrace_index < 0:
		status.emit("error", "请先在台地列表选中一个台地")
		return
	var result := state.remove_terrace(_terrace_index)
	if bool(result.get("ok", false)):
		_terrace_index = -1
		_terrace_signature = ""
		refresh()


func _on_draw_water_pressed() -> void:
	_pending = Pending.WATER
	_corner_a = Vector2i(-1, -1)
	_connect_a = Vector2i(-1, -1)
	status.emit("info", "圈水面：点画布两个对角（含两端格）")
	edit_mode_requested.emit()


func _on_delete_water_pressed() -> void:
	if _water_index < 0:
		status.emit("error", "请先在水面列表选中一个水面")
		return
	var result := state.remove_water(_water_index)
	if bool(result.get("ok", false)):
		_water_index = -1
		_water_signature = ""
		refresh()


func _on_add_connector_pressed() -> void:
	if _terrace_index < 0:
		status.emit("error", "请先在台地列表选中一个台地")
		return
	_pending = Pending.CONNECT
	_connect_a = Vector2i(-1, -1)
	_corner_a = Vector2i(-1, -1)
	status.emit("info", "放连接：点台地同侧边缘的起止格；单格宽可点同一格")
	edit_mode_requested.emit()


func _on_delete_connector_pressed() -> void:
	if _connector_platform < 0 or _connector_stairs < 0:
		status.emit("error", "请先在连接列表选中一条连接")
		return
	var result := state.remove_connector(_connector_platform, _connector_stairs)
	if bool(result.get("ok", false)):
		_connector_platform = -1
		_connector_stairs = -1
		_connector_signature = ""
		refresh()


func _on_water_auto_toggled(enabled: bool) -> void:
	_water_level.editable = not enabled
	_update_water_note()


func _on_water_level_changed(_value: float) -> void:
	_update_water_note()


func _update_water_note() -> void:
	if _water_note == null:
		return
	if _water_auto.button_pressed:
		_water_note.text = "默认水位自动取水面底面 + %.2f。" % TerrainData.WATER_LIFT
	else:
		_water_note.text = "显式水位必须高于水面底面；跨高差的水面会被校验拒绝。"


# ---------------------------------------------------------------- 预览
func _rect_preview_valid(kind: int, rect: Rect2) -> bool:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return false
	var width := float(state.document.get("width", 0)) * TILE_SIZE
	var depth := float(state.document.get("depth", 0)) * TILE_SIZE
	if rect.position.x < -TerrainData.EPSILON or rect.position.y < -TerrainData.EPSILON \
			or rect.end.x > width + TerrainData.EPSILON \
			or rect.end.y > depth + TerrainData.EPSILON:
		return false
	var key := "platforms" if kind == Pending.TERRACE else "water"
	var entries: Array = state.terrain().get(key, [])
	for raw in entries:
		if not (raw is Dictionary):
			continue
		var other_value: Variant = (raw as Dictionary).get("rect", null)
		if not (other_value is Rect2):
			continue
		if rect.intersects(other_value as Rect2):
			return false
	return true


func _connector_preview(cell_a: Vector2i, cell_b: Vector2i) -> Dictionary:
	var terraces: Array = state.document.get("terraces", [])
	if _terrace_index < 0 or _terrace_index >= terraces.size():
		return {}
	var entry: Dictionary = terraces[_terrace_index]
	var platform_rect := _entry_rect(entry)
	if platform_rect.size.x <= 0.0 or platform_rect.size.y <= 0.0:
		return {}
	var side := _infer_side(platform_rect, cell_a, cell_b)
	if side.is_empty():
		return {
			"rect": Rect2(), "valid": false,
			"label": "两格须在台地同一条边缘上；角落请先选方向",
		}
	var kind := _selected_kind()
	var depth := TerrainData.connector_depth(
		kind, float(entry.get("from_y", 0.0)), float(entry.get("y", 0.0))
	)
	if depth <= 0.0:
		return {"rect": Rect2(), "valid": false, "label": "连接需要正的高差"}
	var open0 := 0.0
	var open1 := 0.0
	if side == "north" or side == "south":
		open0 = float(mini(cell_a.x, cell_b.x)) * TILE_SIZE
		open1 = float(maxi(cell_a.x, cell_b.x) + 1) * TILE_SIZE
	else:
		open0 = float(mini(cell_a.y, cell_b.y)) * TILE_SIZE
		open1 = float(maxi(cell_a.y, cell_b.y) + 1) * TILE_SIZE
	var rect := TerrainData.connector_rect(platform_rect, side, open0, open1, depth)
	var valid := _rect_preview_valid(Pending.CONNECT, rect)
	return {
		"rect": rect,
		"valid": valid,
		"label": "%s · %s · 深 %.0f" % [
			"坡道" if kind == "ramp" else "楼梯", _side_text(side), depth,
		],
	}


func _infer_side(rect: Rect2, cell_a: Vector2i, cell_b: Vector2i) -> String:
	var x0 := int(round(rect.position.x / TILE_SIZE))
	var z0 := int(round(rect.position.y / TILE_SIZE))
	var x1 := int(round(rect.end.x / TILE_SIZE))
	var z1 := int(round(rect.end.y / TILE_SIZE))
	var span_x := mini(cell_a.x, cell_b.x) >= x0 and maxi(cell_a.x, cell_b.x) < x1
	var span_z := mini(cell_a.y, cell_b.y) >= z0 and maxi(cell_a.y, cell_b.y) < z1
	var candidates: Array[String] = []
	if cell_a.y == cell_b.y and cell_a.y == z1 - 1 and span_x:
		candidates.append("south")
	if cell_a.y == cell_b.y and cell_a.y == z0 and span_x:
		candidates.append("north")
	if cell_a.x == cell_b.x and cell_a.x == x1 - 1 and span_z:
		candidates.append("east")
	if cell_a.x == cell_b.x and cell_a.x == x0 and span_z:
		candidates.append("west")
	var requested := _selected_side()
	if not requested.is_empty():
		return requested if candidates.has(requested) else ""
	if candidates.size() == 1:
		return candidates[0]
	return ""


# ---------------------------------------------------------------- 索引与签名
func _find_terrace(terraces: Array) -> int:
	if _terrace_signature.is_empty():
		return -1
	for i in range(terraces.size()):
		if _terrace_sig(terraces[i]) == _terrace_signature:
			return i
	return -1


func _find_water(water: Array) -> int:
	if _water_signature.is_empty():
		return -1
	for i in range(water.size()):
		if _water_sig(water[i]) == _water_signature:
			return i
	return -1


func _terrace_sig(entry: Dictionary) -> String:
	return JSON.stringify({
		"name": str(entry.get("name", "")),
		"rect": entry.get("rect", []),
		"y": float(entry.get("y", 0.0)),
		"from_y": float(entry.get("from_y", 0.0)),
		"top": str(entry.get("top", "")),
	})


func _water_sig(entry: Dictionary) -> String:
	return JSON.stringify({
		"name": str(entry.get("name", "")),
		"rect": entry.get("rect", []),
		"y": float(entry.get("y", 0.0)) if entry.has("y") else null,
	})


func _stairs_sig(platform: int, stairs_index: int) -> String:
	var entry := _connector_entry(platform, stairs_index)
	if entry.is_empty():
		return ""
	return JSON.stringify({"platform": platform, "stairs": entry})


func _connector_entry(platform: int, stairs_index: int) -> Dictionary:
	if state == null or not state.has_document():
		return {}
	var terraces: Array = state.document.get("terraces", [])
	if platform < 0 or platform >= terraces.size():
		return {}
	var stairs: Array = (terraces[platform] as Dictionary).get("stairs", [])
	if stairs_index < 0 or stairs_index >= stairs.size():
		return {}
	var value: Variant = stairs[stairs_index]
	return value if value is Dictionary else {}


# ---------------------------------------------------------------- UI 构建
func _build_ui() -> void:
	add_theme_constant_override("separation", 6)

	_hover_note = _label("光标 —", 11, MUTED_COLOR)
	add_child(_hover_note)

	add_child(_label("台地", 15, SECTION_COLOR))
	add_child(_label("点“圈台地”后在画布点两个对角；列表项可选中后应用/删除。", 11, MUTED_COLOR))
	_terrace_list = ItemList.new()
	_terrace_list.custom_minimum_size = Vector2(0, 88)
	_terrace_list.item_selected.connect(_on_terrace_selected)
	add_child(_terrace_list)

	var form := GridContainer.new()
	form.columns = 2
	add_child(form)
	_name_edit = _field(form, "名称")
	_y_spin = _spin(form, "顶部高度", 0.5, TerrainData.MAX_HEIGHT, 1.0, 0.5)
	_from_spin = _spin(form, "下层高度", 0.0, TerrainData.MAX_HEIGHT - 0.5, 0.0, 0.5)
	form.add_child(_label("顶面材料", 12, MUTED_COLOR))
	_top_option = OptionButton.new()
	_top_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(_top_option)

	var terrace_row := HBoxContainer.new()
	terrace_row.add_child(_button("圈台地", _on_draw_terrace_pressed))
	terrace_row.add_child(_button("应用", _on_apply_terrace_pressed))
	terrace_row.add_child(_button("删除台地", _on_delete_terrace_pressed))
	add_child(terrace_row)
	_terrace_note = _label("", 11, MUTED_COLOR)
	_terrace_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_terrace_note)

	add_child(_label("水面", 15, SECTION_COLOR))
	_water_list = ItemList.new()
	_water_list.custom_minimum_size = Vector2(0, 70)
	_water_list.item_selected.connect(_on_water_selected)
	add_child(_water_list)
	var water_form := GridContainer.new()
	water_form.columns = 2
	add_child(water_form)
	_water_name = _field(water_form, "名称")
	water_form.add_child(_label("水位", 12, MUTED_COLOR))
	var water_row := HBoxContainer.new()
	_water_auto = CheckBox.new()
	_water_auto.text = "自动（底面 + %.2f）" % TerrainData.WATER_LIFT
	_water_auto.button_pressed = true
	_water_auto.toggled.connect(_on_water_auto_toggled)
	water_row.add_child(_water_auto)
	_water_level = SpinBox.new()
	_water_level.min_value = 0.0
	_water_level.max_value = TerrainData.MAX_HEIGHT
	_water_level.step = 0.25
	_water_level.value = 0.5
	_water_level.editable = false
	_water_level.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_water_level.value_changed.connect(_on_water_level_changed)
	water_row.add_child(_water_level)
	water_form.add_child(water_row)
	var water_buttons := HBoxContainer.new()
	water_buttons.add_child(_button("圈水面", _on_draw_water_pressed))
	water_buttons.add_child(_button("删除水面", _on_delete_water_pressed))
	add_child(water_buttons)
	_water_note = _label("", 11, MUTED_COLOR)
	_water_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_water_note)

	add_child(_label("连接（楼梯 / 坡道）", 15, SECTION_COLOR))
	add_child(_label("先选台地，再选类型与方向，点同侧边缘的起止格。", 11, MUTED_COLOR))
	var conn_row := HBoxContainer.new()
	_kind_option = OptionButton.new()
	_kind_option.add_item("楼梯", 0)
	_kind_option.set_item_metadata(0, "stairs")
	_kind_option.add_item("坡道", 1)
	_kind_option.set_item_metadata(1, "ramp")
	_kind_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	conn_row.add_child(_kind_option)
	_side_option = OptionButton.new()
	_side_option.add_item("自动方向", 0)
	_side_option.set_item_metadata(0, "")
	_side_option.add_item("南", 1)
	_side_option.set_item_metadata(1, "south")
	_side_option.add_item("北", 2)
	_side_option.set_item_metadata(2, "north")
	_side_option.add_item("东", 3)
	_side_option.set_item_metadata(3, "east")
	_side_option.add_item("西", 4)
	_side_option.set_item_metadata(4, "west")
	_side_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	conn_row.add_child(_side_option)
	add_child(conn_row)
	add_child(_button("放连接（点两格）", _on_add_connector_pressed))
	_connector_list = ItemList.new()
	_connector_list.custom_minimum_size = Vector2(0, 78)
	_connector_list.item_selected.connect(_on_connector_selected)
	add_child(_connector_list)
	add_child(_button("删除选中连接", _on_delete_connector_pressed))
	_connector_note = _label("", 11, MUTED_COLOR)
	_connector_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_connector_note)

	_y_spin.value_changed.connect(_on_spin_changed)
	_from_spin.value_changed.connect(_on_spin_changed)
	_kind_option.item_selected.connect(_on_option_selected)
	_side_option.item_selected.connect(_on_option_selected)
	_update_note()
	_update_water_note()


func _on_spin_changed(_value: float) -> void:
	_update_note()


func _on_option_selected(_index: int) -> void:
	_update_note()


func _label(text: String, font_size: int = 13, color: Color = Color(0.88, 0.86, 0.80)) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	return button


func _field(parent: GridContainer, caption: String) -> LineEdit:
	parent.add_child(_label(caption, 12, MUTED_COLOR))
	var field := LineEdit.new()
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(field)
	return field


func _spin(
	parent: GridContainer, caption: String, low: float, high: float,
	value: float, step: float
) -> SpinBox:
	parent.add_child(_label(caption, 12, MUTED_COLOR))
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.value = value
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(spin)
	return spin


func _terrace_name(terraces: Array, index: int) -> String:
	if index < 0 or index >= terraces.size():
		return "台地 ?"
	var shown := str((terraces[index] as Dictionary).get("name", "")).strip_edges()
	return shown if not shown.is_empty() else "台地 %d" % (index + 1)


func _entry_rect(entry: Dictionary) -> Rect2:
	var value: Variant = entry.get("rect", null)
	if not (value is Array) or (value as Array).size() != 4:
		return Rect2()
	var coords: Array = value
	var x0 := float(coords[0])
	var z0 := float(coords[1])
	var x1 := float(coords[2])
	var z1 := float(coords[3])
	if x1 <= x0 or z1 <= z0:
		return Rect2()
	return Rect2(x0, z0, x1 - x0, z1 - z0)


func _opening_width(entry: Dictionary) -> float:
	return absf(float(entry.get("x1", entry.get("z1", 0.0))) - float(entry.get("x0", entry.get("z0", 0.0))))


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

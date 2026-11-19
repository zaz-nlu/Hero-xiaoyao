@tool
extends "res://addons/layout_editor/panel_base.gd"

# 地图工坊主面板：把 EditState 接到三栏界面上，处理画布输入、文件操作与试跑。
# 试跑只发 play_requested；EditorInterface 的调用集中在 plugin.gd。

signal play_requested(scene_path: String)

const EditState := preload("res://addons/layout_editor/edit_state.gd")
const TerrainPanel := preload("res://addons/layout_editor/terrain_panel.gd")
const EnvironmentPanel := preload("res://addons/layout_editor/environment_panel.gd")
const TriggerPanel := preload("res://addons/layout_editor/trigger_panel.gd")

const PLAYTEST_SCENE := "res://tools/layout_playtest.tscn"

enum Mode { SELECT, GROUND, PLACE, MOVE, SPAWN, REGION, TERRAIN, ENVIRONMENT }
const MODE_NAMES := {
	Mode.SELECT: "选择", Mode.GROUND: "刷地面", Mode.PLACE: "放置物件",
	Mode.MOVE: "移动物件", Mode.SPAWN: "放出生点", Mode.REGION: "画区域",
	Mode.TERRAIN: "地形", Mode.ENVIRONMENT: "环境",
}

var state: EditState = null
var _terrain_panel: TerrainPanel = null
var _environment_panel: EnvironmentPanel = null
var _trigger_panel: TriggerPanel = null

var _built := false
var _mode: int = Mode.SELECT
var _asset_id: String = ""
var _hover_cell := Vector2i(-1, -1)
var _region_first := Vector2i(-1, -1)
var _pending_action := Callable()
# 拖动刷地面时暂缓整图刷新，松手后一次刷新，避免打断笔刷与悬停状态。
var _brushing := false


func _ready() -> void:
	if _built:
		return
	_built = true
	set_process_shortcut_input(true)
	_build_ui()
	grid.cell_clicked.connect(_on_cell_clicked)
	grid.asset_dropped.connect(_on_asset_dropped)
	grid.cell_hovered.connect(_on_cell_hovered)
	grid.brush_started.connect(_on_brush_started)
	grid.brush_moved.connect(_on_brush_moved)
	grid.brush_finished.connect(_on_brush_finished)
	_map_select.item_selected.connect(_on_map_selected)
	palette_asset_selected.connect(_on_asset_chosen)
	terrain_tools_toggled.connect(_on_terrain_tools_toggled)
	environment_tools_toggled.connect(_on_environment_tools_toggled)
	state = EditState.new()
	state.changed.connect(_on_state_changed)
	state.status.connect(_on_status)
	_create_terrain_panel()
	_create_environment_panel()
	_create_trigger_panel()
	if not state.setup():
		_on_status("error", "载入默认地图失败，请检查 data/layouts 与素材目录。")
	set_catalog(state.catalog)
	_refresh_map_list()
	_refresh()
	if not Engine.is_editor_hint():
		_on_status("info", "独立运行：可编辑；试跑请在 Godot 编辑器内使用。")


# ---------------------------------------------------------------- 对外
func has_unsaved_changes() -> bool:
	return state != null and state.is_dirty()


func report_status(kind: String, message: String) -> void:
	_on_status(kind, message)


# ---------------------------------------------------------------- 刷新
func _on_state_changed() -> void:
	if _brushing:
		return
	_refresh()


func _refresh() -> void:
	if state == null or grid == null:
		return
	grid.set_map(state.display_document(), _display_items())
	# 地形编译由 state 缓存，只在文档真正变化后重算一次。
	grid.set_terrain(state.terrain())
	if not state.has_document():
		if _terrain_panel != null:
			_terrain_panel.refresh()
		if _environment_panel != null:
			_environment_panel.refresh()
		if _trigger_panel != null:
			_trigger_panel.refresh()
		_sync_environment_preview()
		return
	var cell := Vector2i(-1, -1)
	if str(state.selection.get("kind", "none")) != "none":
		cell = state.selection.get("cell", Vector2i(-1, -1))
	grid.set_selection(cell)
	_refresh_right()
	_undo_btn.disabled = not state.can_undo()
	_redo_btn.disabled = not state.can_redo()
	_refresh_save_state()
	_update_preview()
	if _terrain_panel != null:
		_terrain_panel.refresh()
	if _environment_panel != null:
		_environment_panel.refresh()
	if _trigger_panel != null:
		_trigger_panel.refresh()
	_sync_environment_preview()


func _display_items() -> Dictionary:
	var items: Dictionary = {}
	for id in LayoutCatalog.item_ids(state.catalog):
		var item := LayoutCatalog.item(state.catalog, id).duplicate(true)
		var texture := _texture_for(str(item.get("texture", item.get("sprite", ""))))
		if texture != null:
			item["texture"] = texture
		items[id] = item
	return items


func _refresh_right() -> void:
	if _id_edit == null:
		return
	_id_edit.text = str(state.document.get("id", ""))
	_name_edit.text = str(state.document.get("name", ""))
	_width_spin.value = int(state.document.get("width", 0))
	_depth_spin.value = int(state.document.get("depth", 0))
	var kind := str(state.selection.get("kind", "none"))
	var text := "未选中：点格子查看/选择"
	var label_text := ""
	var has_object := false
	if kind == "object":
		var obj := state.selected_object()
		var item := state.selected_item()
		var origin := Vector2i(int(obj.get("x", 0)), int(obj.get("z", 0)))
		text = "物件：%s\n坐标 (%d, %d) · 朝向 %d°" % [
			str(item.get("name", obj.get("asset", ""))), origin.x, origin.y,
			int(obj.get("turn", 0)) * 90,
		]
		label_text = str(obj.get("label", ""))
		has_object = true
	elif kind == "region":
		var index := int(state.selection.get("index", -1))
		var regions: Array = state.document.get("regions", [])
		if index >= 0 and index < regions.size():
			var region: Dictionary = regions[index]
			text = "区域：%s\n(%d, %d) %d×%d · 不阻挡通行" % [
				str(region.get("name", "")), int(region.get("x", 0)), int(region.get("z", 0)),
				int(region.get("width", 0)), int(region.get("depth", 0)),
			]
	elif kind == "spawn":
		var spawn_cell := state.current_spawn_cell()
		var world := state.document.get("spawn", {})
		text = "出生点 · 格 (%d, %d)\n世界单位 (%.1f, %.1f)" % [
			spawn_cell.x, spawn_cell.y,
			float(world.get("x", 0.0)), float(world.get("z", 0.0)),
		]
	elif kind == "tile":
		var tile_cell: Vector2i = state.selection.get("cell", Vector2i(-1, -1))
		text = "地块 · 格 (%d, %d)" % [tile_cell.x, tile_cell.y]
	_sel_label.text = text
	_label_edit.editable = has_object
	_label_edit.text = label_text
	_delete_region_btn.disabled = kind != "region"
	if trigger_host != null:
		trigger_host.visible = has_object


func _refresh_save_state() -> void:
	if _save_state == null or state == null:
		return
	if state.is_dirty():
		_save_state.text = "● 未保存的修改"
		_save_state.add_theme_color_override("font_color", Color(0.96, 0.70, 0.36))
	else:
		_save_state.text = "已保存"
		_save_state.add_theme_color_override("font_color", MUTED_COLOR)


func _set_mode(mode: int) -> void:
	if _mode == mode:
		_update_preview()
		return
	_mode = mode
	if mode != Mode.REGION:
		_region_first = Vector2i(-1, -1)
	if mode != Mode.TERRAIN and _terrain_panel != null:
		_terrain_panel.cancel_pending(true)
	if mode != Mode.ENVIRONMENT and _environment_panel != null:
		_environment_panel.cancel_pending(false)
	if grid != null:
		grid.brush_enabled = mode == Mode.GROUND
	if _mode_label != null:
		_mode_label.text = "模式：%s" % str(MODE_NAMES.get(mode, "选择"))
	_sync_terrain_preview()
	_sync_environment_preview()
	_update_preview()


func _update_preview() -> void:
	if grid == null or state == null or not state.has_document():
		return
	if _mode == Mode.PLACE and not _asset_id.is_empty() and _hover_cell.x >= 0:
		var check := state.can_place(_asset_id, _hover_cell)
		grid.set_preview(_asset_id, 0, not bool(check.get("ok", false)))
	else:
		grid.set_preview("")


# ---------------------------------------------------------------- 画布输入
func _on_cell_clicked(cell: Vector2i, button: int) -> void:
	if state == null or not state.has_document():
		return
	if button == MOUSE_BUTTON_RIGHT:
		if _mode == Mode.TERRAIN:
			_cancel_terrain_pending()
			return
		if _mode == Mode.ENVIRONMENT:
			_cancel_environment_pending()
			return
		state.erase_cell(cell)
		_update_preview()
		return
	match _mode:
		Mode.SELECT:
			state.select_at(cell)
		Mode.PLACE:
			if not _asset_id.is_empty():
				state.place_asset(_asset_id, cell)
		Mode.MOVE:
			if state.move_selected_object(cell):
				_set_mode(Mode.SELECT)
		Mode.SPAWN:
			if state.set_spawn_cell(cell):
				_set_mode(Mode.SELECT)
		Mode.REGION:
			_on_region_click(cell)
		Mode.TERRAIN:
			if _terrain_panel != null:
				var keep := _terrain_panel.handle_cell_clicked(cell)
				_sync_terrain_preview()
				if not keep:
					_set_mode(Mode.SELECT)
		Mode.ENVIRONMENT:
			if _environment_panel != null:
				var keep_pick := _environment_panel.handle_cell_clicked(cell)
				_sync_environment_preview()
				if not keep_pick:
					_set_mode(Mode.SELECT)
	_update_preview()


func _on_asset_dropped(asset_id: String, cell: Vector2i) -> void:
	if state == null or not state.has_document():
		return
	_asset_id = asset_id
	var result := state.place_asset(asset_id, cell)
	if not bool(result.get("ok", false)):
		return
	var item := LayoutCatalog.item(state.catalog, asset_id)
	_set_mode(Mode.GROUND if str(item.get("kind", "")) == "ground" else Mode.PLACE)


func _on_cell_hovered(cell: Vector2i) -> void:
	_hover_cell = cell
	if _hover_label != null:
		if cell.x >= 0 and state != null and state.has_document():
			_hover_label.text = "坐标 x=%d z=%d · 高 %.1f" % [
				cell.x, cell.y, state.terrain_height_at_cell(cell),
			]
		elif cell.x >= 0:
			_hover_label.text = "坐标 x=%d z=%d" % [cell.x, cell.y]
		else:
			_hover_label.text = "坐标 —"
	if _terrain_panel != null:
		_terrain_panel.handle_cell_hovered(cell)
	if _environment_panel != null:
		_environment_panel.handle_cell_hovered(cell)
	_sync_terrain_preview()
	_sync_environment_preview()
	_update_preview()


func _on_brush_started(cell: Vector2i) -> void:
	if state == null or _asset_id.is_empty():
		return
	_brushing = true
	state.begin_ground_stroke()
	state.stroke_ground(cell, _asset_id)
	grid.set_preview(_asset_id, 0)


func _on_brush_moved(cell: Vector2i) -> void:
	if state == null or _asset_id.is_empty():
		return
	state.stroke_ground(cell, _asset_id)
	grid.set_preview(_asset_id, 0)


func _on_brush_finished() -> void:
	if state == null or not _brushing:
		return
	_brushing = false
	state.end_ground_stroke()
	_update_preview()
	_refresh_save_state()


func _on_region_click(cell: Vector2i) -> void:
	if state == null:
		return
	if _region_first.x < 0:
		_region_first = cell
		_on_status("info", "区域起点 (%d, %d)，再点一个角完成" % [cell.x, cell.y])
		return
	var result := state.add_region(_region_first, cell, _region_name.text)
	_region_first = Vector2i(-1, -1)
	if bool(result.get("ok", false)):
		_set_mode(Mode.SELECT)


func _zoom_in() -> void:
	grid.set_zoom(grid.get_zoom() + 4)
	_refresh_zoom()


func _zoom_out() -> void:
	grid.set_zoom(grid.get_zoom() - 4)
	_refresh_zoom()


# ---------------------------------------------------------------- 素材
func _on_asset_chosen(asset_id: String) -> void:
	_asset_id = asset_id
	var item := LayoutCatalog.item(state.catalog, asset_id)
	_set_mode(Mode.GROUND if str(item.get("kind", "")) == "ground" else Mode.PLACE)
	_on_status("info", "已选择：%s" % str(item.get("name", asset_id)))


# ---------------------------------------------------------------- 文件操作
func _refresh_map_list() -> void:
	if _map_select == null or state == null:
		return
	_map_select.clear()
	for path in state.list_maps():
		_map_select.add_item(path.get_file().get_basename())
		_map_select.set_item_metadata(_map_select.item_count - 1, path)
	_sync_map_select()


func _sync_map_select() -> void:
	if _map_select == null or state == null:
		return
	for index in range(_map_select.item_count):
		if str(_map_select.get_item_metadata(index)) == state.source_path:
			_map_select.select(index)
			return
	_map_select.select(-1)


func _on_map_selected(index: int) -> void:
	var path := str(_map_select.get_item_metadata(index))
	if path.is_empty() or state == null or path == state.source_path:
		return
	_guard_dirty(_do_open_map.bind(path))


func _do_open_map(path: String) -> void:
	var result := state.load_map(path)
	if not bool(result.get("ok", false)):
		_sync_map_select()
		return
	_cancel_terrain_pending()
	_cancel_environment_pending()
	_set_mode(Mode.SELECT)
	set_catalog(state.catalog)
	_refresh_map_list()
	_refresh()


func _open_new_dialog() -> void:
	_guard_dirty(_show_new_dialog)


func _show_new_dialog() -> void:
	_new_id.text = ""
	_new_name.text = ""
	_new_width.value = 24
	_new_depth.value = 20
	_new_error.text = ""
	_new_dialog.popup_centered(Vector2i(380, 240))


func _on_new_confirmed() -> void:
	if state == null:
		return
	var result := state.create_new(
		_new_id.text, _new_name.text, int(_new_width.value), int(_new_depth.value)
	)
	if not bool(result.get("ok", false)):
		_new_error.text = state.last_error
		_new_dialog.popup_centered(Vector2i(380, 240))
		return
	_cancel_terrain_pending()
	_cancel_environment_pending()
	_set_mode(Mode.SELECT)
	_refresh_map_list()
	_refresh()


func _guard_dirty(action: Callable) -> void:
	if state != null and state.is_dirty():
		_pending_action = action
		_confirm_dialog.popup_centered(Vector2i(380, 140))
		return
	action.call()


func _on_discard_confirmed() -> void:
	var action := _pending_action
	_pending_action = Callable()
	if action.is_valid():
		action.call()


func _on_discard_canceled() -> void:
	_pending_action = Callable()
	_sync_map_select()
	_on_status("info", "已取消，当前草稿保持不变")


func _on_save_pressed() -> void:
	if state == null:
		return
	var result := state.save()
	if bool(result.get("ok", false)):
		_refresh_map_list()
		_sync_map_select()


func _on_play_pressed() -> void:
	if state == null:
		return
	var result := state.export_playtest()
	if not bool(result.get("ok", false)):
		return
	if Engine.is_editor_hint():
		play_requested.emit(PLAYTEST_SCENE)
	else:
		_on_status("info", "独立运行无法自动试跑；快照在 user://map_editor_playtest.json")


# ---------------------------------------------------------------- 地形工具
func _create_terrain_panel() -> void:
	if terrain_host == null:
		return
	_terrain_panel = TerrainPanel.new()
	_terrain_panel.name = "TerrainTools"
	_terrain_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_terrain_panel.status.connect(_on_status)
	_terrain_panel.edit_mode_requested.connect(_on_terrain_edit_requested)
	_terrain_panel.edit_mode_finished.connect(_on_terrain_edit_finished)
	terrain_host.add_child(_terrain_panel)
	_terrain_panel.setup(state)


func _on_terrain_edit_requested() -> void:
	_set_mode(Mode.TERRAIN)


func _on_terrain_edit_finished() -> void:
	if _mode == Mode.TERRAIN:
		_set_mode(Mode.SELECT)


func _on_terrain_tools_toggled(open: bool) -> void:
	if open:
		return
	_cancel_terrain_pending()


func _cancel_terrain_pending() -> void:
	if _terrain_panel != null:
		_terrain_panel.cancel_pending(true)
	if _mode == Mode.TERRAIN:
		_set_mode(Mode.SELECT)
	_sync_terrain_preview()


func _sync_terrain_preview() -> void:
	if grid == null:
		return
	if _terrain_panel == null or not _terrain_panel.is_pending():
		grid.set_terrain_pending(Rect2(), true, "")
		return
	var preview: Dictionary = _terrain_panel.preview()
	if preview.is_empty():
		grid.set_terrain_pending(Rect2(), true, "")
		return
	grid.set_terrain_pending(
		preview.get("rect", Rect2()),
		bool(preview.get("valid", true)),
		str(preview.get("label", ""))
	)


# ---------------------------------------------------------------- 环境工具
func _create_environment_panel() -> void:
	if environment_host == null:
		return
	_environment_panel = EnvironmentPanel.new()
	_environment_panel.name = "EnvironmentTools"
	_environment_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_environment_panel.status.connect(_on_status)
	_environment_panel.edit_mode_requested.connect(_on_environment_edit_requested)
	_environment_panel.edit_mode_finished.connect(_on_environment_edit_finished)
	environment_host.add_child(_environment_panel)
	_environment_panel.setup(state)


func _on_environment_edit_requested() -> void:
	_set_mode(Mode.ENVIRONMENT)


func _on_environment_edit_finished() -> void:
	if _mode == Mode.ENVIRONMENT:
		_set_mode(Mode.SELECT)


func _on_environment_tools_toggled(open: bool) -> void:
	if open:
		return
	_cancel_environment_pending()


# ---------------------------------------------------------------- 物件触发器
func _create_trigger_panel() -> void:
	if trigger_host == null:
		return
	_trigger_panel = TriggerPanel.new()
	_trigger_panel.name = "TriggerTools"
	_trigger_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trigger_panel.status.connect(_on_status)
	trigger_host.add_child(_trigger_panel)
	_trigger_panel.setup(state)


func _cancel_environment_pending() -> void:
	if _environment_panel != null:
		_environment_panel.cancel_pending(false)
	if _mode == Mode.ENVIRONMENT:
		_set_mode(Mode.SELECT)
	_sync_environment_preview()


# 已提交的相机范围用蓝色；框选过程中用紫色预览。
func _sync_environment_preview() -> void:
	if grid == null:
		return
	if _environment_panel != null and _environment_panel.is_pending():
		var preview: Dictionary = _environment_panel.preview()
		if preview.is_empty():
			grid.set_camera_overlay(Rect2(), false, "")
		else:
			grid.set_camera_overlay(
				preview.get("rect", Rect2()),
				true,
				str(preview.get("label", ""))
			)
		return
	if _environment_panel != null:
		grid.set_camera_overlay(
			_environment_panel.camera_rect_value(), false, "相机范围"
		)
	else:
		grid.set_camera_overlay(Rect2(), false, "")


# ---------------------------------------------------------------- 右侧操作
func _on_undo() -> void:
	_cancel_terrain_pending()
	_cancel_environment_pending()
	if state != null:
		state.undo()


func _on_redo() -> void:
	_cancel_terrain_pending()
	_cancel_environment_pending()
	if state != null:
		state.redo()


func _on_apply_info() -> void:
	if state == null:
		return
	state.apply_map_info(
		_id_edit.text, _name_edit.text, int(_width_spin.value), int(_depth_spin.value)
	)


func _on_apply_label() -> void:
	if state != null:
		state.set_selected_label(_label_edit.text)


func _on_select_mode() -> void:
	_set_mode(Mode.SELECT)


func _on_move_pressed() -> void:
	if state == null or state.selected_object_index() < 0:
		_on_status("error", "请先选中一个物件")
		return
	_set_mode(Mode.MOVE)
	_on_status("info", "点击目标格完成移动")


func _on_rotate_pressed() -> void:
	if state != null:
		state.rotate_selected_object()


func _on_delete_pressed() -> void:
	if state != null:
		state.delete_selected()


func _on_spawn_pressed() -> void:
	_set_mode(Mode.SPAWN)
	_on_status("info", "点击格子设置出生点")


func _on_add_region_pressed() -> void:
	_set_mode(Mode.REGION)
	_on_status("info", "点两个格子确定区域范围")


func _on_delete_region_pressed() -> void:
	if state != null and str(state.selection.get("kind", "")) == "region":
		state.delete_selected()
	else:
		_on_status("error", "请先选中一个区域")


# ---------------------------------------------------------------- 状态与快捷键
func _on_status(kind: String, message: String) -> void:
	if _status == null:
		return
	_status.text = message
	var color := Color(0.86, 0.84, 0.78)
	match kind:
		"error":
			color = ERROR_COLOR
		"ok":
			color = Color(0.62, 0.85, 0.58)
		"info":
			color = Color(0.70, 0.80, 0.96)
	_status.add_theme_color_override("font_color", color)


func _shortcut_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or state == null:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.ctrl_pressed:
		match key.keycode:
			KEY_S:
				_on_save_pressed()
				accept_event()
			KEY_Z:
				if key.shift_pressed:
					_on_redo()
				else:
					_on_undo()
				accept_event()
			KEY_Y:
				_on_redo()
				accept_event()
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	match key.keycode:
		KEY_ESCAPE:
			_cancel_terrain_pending()
			_cancel_environment_pending()
		KEY_DELETE:
			state.delete_selected()
		KEY_R:
			state.rotate_selected_object()
		KEY_G:
			_set_mode(Mode.SELECT)

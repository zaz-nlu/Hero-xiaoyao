@tool
extends Control

# 地图工坊的界面骨架：三栏容器、素材面板、属性字段与对话框。
# 只搭 UI 并发出 palette_asset_selected；文档操作/输入编排在 main_panel.gd。

signal palette_asset_selected(asset_id: String)
signal terrain_tools_toggled(open: bool)
signal environment_tools_toggled(open: bool)

const MapGrid := preload("res://addons/layout_editor/map_grid.gd")
const PaletteButton := preload("res://addons/layout_editor/palette_button.gd")
const LayoutCatalog := preload("res://core/layouts/layout_catalog.gd")

const SECTION_COLOR := Color(0.93, 0.79, 0.47)
const MUTED_COLOR := Color(0.68, 0.67, 0.62)
const ERROR_COLOR := Color(1.0, 0.45, 0.38)
const CATEGORY_LABELS := {
	"terrain": "地形", "architecture": "建筑", "wall": "墙体", "vegetation": "植被",
	"prop": "物件", "npc": "人物", "exit": "出口", "sign": "标识",
}

var grid: MapGrid = null
var terrain_host: VBoxContainer = null
var environment_host: VBoxContainer = null
var trigger_host: VBoxContainer = null

var _catalog: Dictionary = {}
var _texture_cache: Dictionary = {}
var _map_select: OptionButton = null
var _category: OptionButton = null
var _palette_list: VBoxContainer = null
var _zoom_label: Label = null
var _mode_label: Label = null
var _hover_label: Label = null
var _save_state: Label = null
var _status: Label = null
var _id_edit: LineEdit = null
var _name_edit: LineEdit = null
var _width_spin: SpinBox = null
var _depth_spin: SpinBox = null
var _sel_label: Label = null
var _label_edit: LineEdit = null
var _region_name: LineEdit = null
var _delete_region_btn: Button = null
var _undo_btn: Button = null
var _redo_btn: Button = null
var _confirm_dialog: ConfirmationDialog = null
var _new_dialog: ConfirmationDialog = null
var _new_id: LineEdit = null
var _new_name: LineEdit = null
var _new_width: SpinBox = null
var _new_depth: SpinBox = null
var _new_error: Label = null
var _terrain_button: Button = null
var _environment_button: Button = null
var _right_details: VBoxContainer = null
var _right_scroll: ScrollContainer = null
var _detail_tab: Button = null
var _terrain_tab: Button = null
var _environment_tab: Button = null
var _page := "details"


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pad(margin, 8)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	margin.add_child(root)

	var top := HBoxContainer.new()
	root.add_child(top)
	top.add_child(_make_label("地图", 14))
	_map_select = OptionButton.new()
	_map_select.custom_minimum_size = Vector2(190, 0)
	top.add_child(_map_select)
	top.add_child(_make_button("新建", Callable(self, "_open_new_dialog")))
	top.add_child(_make_button("保存", Callable(self, "_on_save_pressed")))
	_undo_btn = _make_button("撤销", Callable(self, "_on_undo"))
	_redo_btn = _make_button("重做", Callable(self, "_on_redo"))
	top.add_child(_undo_btn)
	top.add_child(_redo_btn)
	top.add_child(_make_button("试跑", Callable(self, "_on_play_pressed")))
	_terrain_button = _make_button("地形", Callable(self, "_toggle_terrain_tools"))
	_terrain_button.toggle_mode = true
	_terrain_button.tooltip_text = "打开右栏的地形工具：台地、楼梯/坡道与水面"
	top.add_child(_terrain_button)
	_environment_button = _make_button("环境", Callable(self, "_toggle_environment_tools"))
	_environment_button.toggle_mode = true
	_environment_button.tooltip_text = "打开右栏的环境工具：天空、光照、相机范围与边界林"
	top.add_child(_environment_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	_save_state = _make_label("已保存", 13, MUTED_COLOR)
	top.add_child(_save_state)

	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	var left_panel := PanelContainer.new()
	left_panel.custom_minimum_size = Vector2(226, 0)
	body.add_child(left_panel)
	var right_split := HSplitContainer.new()
	right_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right_split)
	var center_box := VBoxContainer.new()
	center_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_split.add_child(center_box)
	var right_panel := PanelContainer.new()
	right_panel.custom_minimum_size = Vector2(282, 0)
	right_split.add_child(right_panel)

	_build_left(left_panel)
	_build_center(center_box)
	_build_right(right_panel)

	_status = _make_label("就绪", 13)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 32)
	root.add_child(_status)
	_build_dialogs()


func _build_left(panel: PanelContainer) -> void:
	var margin := _pad(panel)
	var column := VBoxContainer.new()
	margin.add_child(column)
	column.add_child(_make_label("素材", 15, SECTION_COLOR))
	_category = OptionButton.new()
	_category.item_selected.connect(_on_category_selected)
	column.add_child(_category)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_palette_list = VBoxContainer.new()
	_palette_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_palette_list)


func _build_center(column: VBoxContainer) -> void:
	var bar := HBoxContainer.new()
	column.add_child(bar)
	_mode_label = _make_label("模式：选择", 13, SECTION_COLOR)
	bar.add_child(_mode_label)
	_hover_label = _make_label("坐标 —", 13, MUTED_COLOR)
	bar.add_child(_hover_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	bar.add_child(_make_button("缩小", Callable(self, "_zoom_out")))
	_zoom_label = _make_label("22 px/格", 12, MUTED_COLOR)
	bar.add_child(_zoom_label)
	bar.add_child(_make_button("放大", Callable(self, "_zoom_in")))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	grid = MapGrid.new()
	scroll.add_child(grid)
	_refresh_zoom()


func _build_right(panel: PanelContainer) -> void:
	var margin := _pad(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	_right_scroll = scroll
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 6)
	scroll.add_child(column)

	# 右栏顶部切换：默认“详情”，点“地形”或“环境”立即显示对应工具区。
	var tabs := HBoxContainer.new()
	column.add_child(tabs)
	_detail_tab = _make_button("详情", Callable(self, "_show_details"))
	_terrain_tab = _make_button("地形", Callable(self, "_show_terrain"))
	_environment_tab = _make_button("环境", Callable(self, "_show_environment"))
	_detail_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_terrain_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_environment_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(_detail_tab)
	tabs.add_child(_terrain_tab)
	tabs.add_child(_environment_tab)

	_right_details = VBoxContainer.new()
	_right_details.add_theme_constant_override("separation", 6)
	column.add_child(_right_details)

	terrain_host = VBoxContainer.new()
	terrain_host.add_theme_constant_override("separation", 6)
	column.add_child(terrain_host)
	terrain_host.visible = false

	environment_host = VBoxContainer.new()
	environment_host.add_theme_constant_override("separation", 6)
	column.add_child(environment_host)
	environment_host.visible = false
	_apply_page("details")

	_right_details.add_child(_make_label("地图信息", 15, SECTION_COLOR))
	var info := GridContainer.new()
	info.columns = 2
	_right_details.add_child(info)
	_id_edit = _make_field(info, "ID")
	_name_edit = _make_field(info, "名字")
	_width_spin = _make_spin(info, "格数宽", 4, 96, 24)
	_depth_spin = _make_spin(info, "格数深", 4, 96, 20)
	_right_details.add_child(_make_button("应用地图信息", Callable(self, "_on_apply_info")))

	_right_details.add_child(_make_label("当前选择", 15, SECTION_COLOR))
	_sel_label = _make_label("未选中：点格子查看/选择", 13)
	_sel_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sel_label.custom_minimum_size = Vector2(0, 58)
	_right_details.add_child(_sel_label)
	var label_row := HBoxContainer.new()
	_label_edit = LineEdit.new()
	_label_edit.placeholder_text = "对象标签"
	_label_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_row.add_child(_label_edit)
	label_row.add_child(_make_button("应用标签", Callable(self, "_on_apply_label")))
	_right_details.add_child(label_row)

	trigger_host = VBoxContainer.new()
	trigger_host.add_theme_constant_override("separation", 4)
	_right_details.add_child(trigger_host)

	var quick := GridContainer.new()
	quick.columns = 3
	_right_details.add_child(quick)
	quick.add_child(_make_button("选择", Callable(self, "_on_select_mode")))
	quick.add_child(_make_button("移动", Callable(self, "_on_move_pressed")))
	quick.add_child(_make_button("旋转", Callable(self, "_on_rotate_pressed")))
	quick.add_child(_make_button("删除", Callable(self, "_on_delete_pressed")))
	quick.add_child(_make_button("放出生点", Callable(self, "_on_spawn_pressed")))
	_right_details.add_child(_make_label("移动：先选中物件，再点目标格", 11, MUTED_COLOR))

	_right_details.add_child(_make_label("区域标注（不阻挡）", 15, SECTION_COLOR))
	_region_name = LineEdit.new()
	_region_name.placeholder_text = "区域名字"
	_right_details.add_child(_region_name)
	_right_details.add_child(_make_button("添加区域（点两个角）", Callable(self, "_on_add_region_pressed")))
	_delete_region_btn = _make_button("删除选中区域", Callable(self, "_on_delete_region_pressed"))
	_right_details.add_child(_delete_region_btn)


func _build_dialogs() -> void:
	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.title = "放弃未保存的修改？"
	_confirm_dialog.confirmed.connect(Callable(self, "_on_discard_confirmed"))
	_confirm_dialog.canceled.connect(Callable(self, "_on_discard_canceled"))
	add_child(_confirm_dialog)

	_new_dialog = ConfirmationDialog.new()
	_new_dialog.title = "新建地图"
	var box := VBoxContainer.new()
	var fields := GridContainer.new()
	fields.columns = 2
	box.add_child(fields)
	_new_id = _make_field(fields, "ID（小写字母/数字/_）")
	_new_name = _make_field(fields, "名字")
	_new_width = _make_spin(fields, "格数宽", 4, 96, 24)
	_new_depth = _make_spin(fields, "格数深", 4, 96, 20)
	_new_error = _make_label("", 12, ERROR_COLOR)
	_new_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_new_error)
	_new_dialog.add_child(box)
	_new_dialog.confirmed.connect(Callable(self, "_on_new_confirmed"))
	add_child(_new_dialog)


# ---------------------------------------------------------------- 右栏切换
func _toggle_terrain_tools() -> void:
	set_terrain_tools_open(_page != "terrain")


func _toggle_environment_tools() -> void:
	set_environment_tools_open(_page != "environment")


func _show_details() -> void:
	_apply_page("details")


func _show_terrain() -> void:
	_apply_page("terrain")


func _show_environment() -> void:
	_apply_page("environment")


# 详情/地形/环境共用同一套可见性：工具区在右栏滚动内容顶部，切换后立即可见。
func set_terrain_tools_open(open: bool) -> void:
	_apply_page("terrain" if open else "details")


func set_environment_tools_open(open: bool) -> void:
	_apply_page("environment" if open else "details")


func _apply_page(page: String) -> void:
	var previous := _page
	_page = page
	var show_details := page == "details"
	if _right_details != null:
		_right_details.visible = show_details
	if terrain_host != null:
		terrain_host.visible = page == "terrain"
	if environment_host != null:
		environment_host.visible = page == "environment"
	if _terrain_button != null and _terrain_button.button_pressed != (page == "terrain"):
		_terrain_button.set_pressed_no_signal(page == "terrain")
	if _environment_button != null \
			and _environment_button.button_pressed != (page == "environment"):
		_environment_button.set_pressed_no_signal(page == "environment")
	if _detail_tab != null:
		_detail_tab.disabled = not show_details
	if _terrain_tab != null:
		_terrain_tab.disabled = page == "terrain"
	if _environment_tab != null:
		_environment_tab.disabled = page == "environment"
	if page != "details" and _right_scroll != null:
		_right_scroll.scroll_vertical = 0
	if previous == "terrain" and page != "terrain":
		terrain_tools_toggled.emit(false)
	elif page == "terrain" and previous != "terrain":
		terrain_tools_toggled.emit(true)
	if previous == "environment" and page != "environment":
		environment_tools_toggled.emit(false)
	elif page == "environment" and previous != "environment":
		environment_tools_toggled.emit(true)


# ---------------------------------------------------------------- 通用控件
func _pad(panel: Control, amount: int = 6) -> MarginContainer:
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, amount)
	panel.add_child(margin)
	return margin


func _make_label(text: String, font_size: int = 13, color: Color = Color(0.88, 0.86, 0.80)) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _make_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	return button


func _make_field(parent: GridContainer, caption: String) -> LineEdit:
	parent.add_child(_make_label(caption, 12, MUTED_COLOR))
	var field := LineEdit.new()
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(field)
	return field


func _make_spin(parent: GridContainer, caption: String, low: int, high: int, value: int) -> SpinBox:
	parent.add_child(_make_label(caption, 12, MUTED_COLOR))
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = 1
	spin.value = value
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(spin)
	return spin


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _texture_for(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _texture_cache.has(path):
		return _texture_cache[path]
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		var loaded := load(path)
		if loaded is Texture2D:
			texture = loaded
	if texture == null and FileAccess.file_exists(path):
		var image := Image.load_from_file(ProjectSettings.globalize_path(path))
		if image != null and not image.is_empty():
			texture = ImageTexture.create_from_image(image)
	_texture_cache[path] = texture
	return texture


func _refresh_zoom() -> void:
	if _zoom_label != null and grid != null:
		_zoom_label.text = "%d px/格" % grid.get_zoom()


# ---------------------------------------------------------------- 素材面板
func set_catalog(catalog: Dictionary) -> void:
	_catalog = catalog
	if _category == null:
		return
	_category.clear()
	_category.add_item("全部分类")
	_category.set_item_metadata(0, "")
	var seen: Array[String] = []
	for id in LayoutCatalog.item_ids(_catalog):
		var category := str(LayoutCatalog.item(_catalog, id).get("category", ""))
		if category.is_empty() or seen.has(category):
			continue
		seen.append(category)
		_category.add_item(str(CATEGORY_LABELS.get(category, category)))
		_category.set_item_metadata(_category.item_count - 1, category)
	_category.select(0)
	_rebuild_palette()


func _on_category_selected(_index: int) -> void:
	_rebuild_palette()


func _rebuild_palette() -> void:
	if _palette_list == null or _catalog.is_empty():
		return
	_clear_children(_palette_list)
	var category := ""
	if _category.selected >= 0:
		category = str(_category.get_item_metadata(_category.selected))
	var grounds: Array[String] = []
	var objects: Array[String] = []
	for id in LayoutCatalog.item_ids(_catalog):
		var item := LayoutCatalog.item(_catalog, id)
		if category != "" and str(item.get("category", "")) != category:
			continue
		if str(item.get("kind", "")) == "ground":
			grounds.append(id)
		else:
			objects.append(id)
	_palette_list.add_child(_make_label("地面材料 · 拖入或点选后点格子", 12, SECTION_COLOR))
	for id in grounds:
		_add_palette_button(id)
	_palette_list.add_child(_make_label("物件 · 拖入或点选后点格子", 12, SECTION_COLOR))
	for id in objects:
		_add_palette_button(id)


func _add_palette_button(asset_id: String) -> void:
	var item := LayoutCatalog.item(_catalog, asset_id)
	var button := PaletteButton.new()
	button.asset_id = asset_id
	button.text = str(item.get("name", asset_id))
	button.icon = _texture_for(str(item.get("texture", item.get("sprite", ""))))
	button.expand_icon = false
	button.add_theme_constant_override("icon_max_width", 26)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 32)
	button.tooltip_text = "%s · %s\n可拖动到画布，或点选后再点格子" % [
		str(item.get("name", asset_id)), str(item.get("kind", ""))
	]
	button.pressed.connect(_on_palette_pressed.bind(asset_id))
	_palette_list.add_child(button)


func _on_palette_pressed(asset_id: String) -> void:
	palette_asset_selected.emit(asset_id)

@tool
extends VBoxContainer

# 地图工坊的环境工具区：天空/光照预设、相机范围和四边边界林。
# 只持有界面与“框选相机范围”的临时状态；文档修改统一经 EditState 的
# apply_environment / clear_environment 提交，校验、撤销与 changed 信号由 state 负责。

signal status(kind: String, message: String)
signal edit_mode_requested
signal edit_mode_finished

const LayoutEnvironment := preload("res://core/layouts/layout_environment.gd")
const LayoutGrid := preload("res://core/layouts/layout_grid.gd")
const EditState := preload("res://addons/layout_editor/edit_state.gd")

const SECTION_COLOR := Color(0.93, 0.79, 0.47)
const MUTED_COLOR := Color(0.68, 0.67, 0.62)
const TILE_SIZE: float = 2.0
const SKY_LABELS := {
	"default": "默认", "clear": "晴空", "dusk": "黄昏", "night": "夜晚",
}
const LIGHTING_LABELS := {
	"default": "默认", "warm": "暖光", "cool": "冷光", "night": "夜色",
}

var state: EditState = null

var _built := false
var _doc_key := ""
var _form_sig := ""

var _sky_option: OptionButton = null
var _lighting_option: OptionButton = null
var _north_check: CheckBox = null
var _east_check: CheckBox = null
var _south_check: CheckBox = null
var _west_check: CheckBox = null
var _depth_spin: SpinBox = null
var _spacing_spin: SpinBox = null
var _camera_note: Label = null

var _camera_rect: Rect2 = Rect2()
var _pending := false
var _camera_first := Vector2i(-1, -1)
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
	return _pending


func cancel_pending(notify: bool = true) -> void:
	var had := _pending
	_pending = false
	_camera_first = Vector2i(-1, -1)
	if had and notify:
		status.emit("info", "已取消框选相机范围")


# 已提交或已框选的相机范围（世界单位）；空矩形表示不限制。
func camera_rect_value() -> Rect2:
	return _camera_rect


func handle_cell_hovered(cell: Vector2i) -> void:
	_hover = cell


# 返回 true 表示仍在等待下一次点击。
func handle_cell_clicked(cell: Vector2i) -> bool:
	if not _pending:
		return false
	if _camera_first.x < 0:
		_camera_first = cell
		status.emit("info", "相机角一 (%d, %d)，再点对角完成" % [cell.x, cell.y])
		return true
	_camera_rect = _cells_to_world(_camera_first, cell)
	_pending = false
	_camera_first = Vector2i(-1, -1)
	_update_camera_note()
	status.emit("ok", "相机范围已框选，点“应用环境”写入地图")
	edit_mode_finished.emit()
	return false


# 画布预览：返回 {rect: Rect2(世界), valid: bool, label: String} 或空。
func preview() -> Dictionary:
	if not _pending or _camera_first.x < 0 or _hover.x < 0:
		return {}
	var rect := _cells_to_world(_camera_first, _hover)
	return {
		"rect": rect,
		"valid": _rect_inside_map(rect),
		"label": "相机范围 %d×%d 格" % [
			int(rect.size.x / TILE_SIZE), int(rect.size.y / TILE_SIZE),
		],
	}


# ---------------------------------------------------------------- 刷新
func refresh() -> void:
	if not _built or state == null:
		return
	var key := "%s|%s" % [state.source_path, state.document_id()]
	var signature := JSON.stringify(state.document.get("environment", null))
	if key == _doc_key and signature == _form_sig:
		return
	if key != _doc_key:
		cancel_pending(false)
	_doc_key = key
	_form_sig = signature
	_load_form()


func _load_form() -> void:
	if state == null or not state.has_document():
		return
	var env := LayoutEnvironment.settings(state.document)
	_select_option(_sky_option, str(env.get("sky", LayoutEnvironment.DEFAULT_SKY)))
	_select_option(
		_lighting_option, str(env.get("lighting", LayoutEnvironment.DEFAULT_LIGHTING))
	)
	var border_value: Variant = env.get("border", null)
	var border: Dictionary = border_value if border_value is Dictionary else {}
	var sides: Array = []
	if not border.is_empty():
		# 有 border 但没写 sides 时，运行时使用默认三边；界面要显示同样的值。
		sides = LayoutEnvironment.DEFAULT_BORDER_SIDES.duplicate()
		var sides_value: Variant = border.get("sides", null)
		if sides_value is Array:
			sides = sides_value
	_set_side(_north_check, sides.has("north"))
	_set_side(_east_check, sides.has("east"))
	_set_side(_south_check, sides.has("south"))
	_set_side(_west_check, sides.has("west"))
	_depth_spin.set_value_no_signal(
		float(border.get("depth", LayoutEnvironment.DEFAULT_BORDER_DEPTH))
	)
	_spacing_spin.set_value_no_signal(
		float(border.get("spacing", LayoutEnvironment.DEFAULT_BORDER_SPACING))
	)
	_camera_rect = LayoutEnvironment.camera_clamp(state.document)
	_update_camera_note()


func _update_camera_note() -> void:
	if _camera_note == null:
		return
	if _camera_rect.size.x <= 0.0 or _camera_rect.size.y <= 0.0:
		_camera_note.text = "相机范围：默认（跟随人物，不限制取景）"
		return
	_camera_note.text = "相机范围：x %.0f → %.0f · z %.0f → %.0f（世界单位）" % [
		_camera_rect.position.x, _camera_rect.end.x,
		_camera_rect.position.y, _camera_rect.end.y,
	]


# ---------------------------------------------------------------- 按钮
func _on_pick_camera_pressed() -> void:
	_pending = true
	_camera_first = Vector2i(-1, -1)
	status.emit("info", "框选相机范围：在画布点两个对角（含两端格）")
	edit_mode_requested.emit()


func _on_clear_camera_pressed() -> void:
	_camera_rect = Rect2()
	_update_camera_note()
	status.emit("info", "已清空相机范围，点“应用环境”生效")


func _on_apply_pressed() -> void:
	if state == null or not state.has_document():
		return
	var border: Dictionary = {}
	var sides: Array[String] = _selected_sides()
	if not sides.is_empty():
		border = {
			"sides": sides,
			"depth": float(_depth_spin.value),
			"spacing": float(_spacing_spin.value),
			"seed": _existing_seed(),
		}
	var clamp: Array = []
	if _camera_rect.size.x > 0.0 and _camera_rect.size.y > 0.0:
		clamp = [
			_camera_rect.position.x, _camera_rect.position.y,
			_camera_rect.end.x, _camera_rect.end.y,
		]
	var result := state.apply_environment(
		_selected_id(_sky_option), _selected_id(_lighting_option), clamp, border
	)
	if bool(result.get("ok", false)):
		_update_camera_note()


func _on_clear_environment_pressed() -> void:
	if state == null or not state.has_document():
		return
	state.clear_environment()


func _selected_sides() -> Array[String]:
	var sides: Array[String] = []
	if _north_check.button_pressed:
		sides.append("north")
	if _east_check.button_pressed:
		sides.append("east")
	if _south_check.button_pressed:
		sides.append("south")
	if _west_check.button_pressed:
		sides.append("west")
	return sides


func _existing_seed() -> int:
	var env := LayoutEnvironment.settings(state.document)
	var border_value: Variant = env.get("border", null)
	if border_value is Dictionary:
		var seed_value: Variant = (border_value as Dictionary).get("seed", null)
		if typeof(seed_value) == TYPE_INT:
			return int(seed_value)
		if typeof(seed_value) == TYPE_FLOAT and is_equal_approx(
			float(seed_value), roundf(float(seed_value))
		):
			return int(roundf(float(seed_value)))
	return LayoutEnvironment.DEFAULT_BORDER_SEED


# ---------------------------------------------------------------- 坐标
func _cells_to_world(corner_a: Vector2i, corner_b: Vector2i) -> Rect2:
	var x0 := mini(corner_a.x, corner_b.x)
	var z0 := mini(corner_a.y, corner_b.y)
	var x1 := maxi(corner_a.x, corner_b.x) + 1
	var z1 := maxi(corner_a.y, corner_b.y) + 1
	return Rect2(
		float(x0) * TILE_SIZE, float(z0) * TILE_SIZE,
		float(x1 - x0) * TILE_SIZE, float(z1 - z0) * TILE_SIZE
	)


func _rect_inside_map(rect: Rect2) -> bool:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return false
	var bounds := LayoutGrid.world_bounds(state.document)
	return rect.position.x >= bounds.position.x - LayoutEnvironment.EPSILON \
		and rect.position.y >= bounds.position.y - LayoutEnvironment.EPSILON \
		and rect.end.x <= bounds.end.x + LayoutEnvironment.EPSILON \
		and rect.end.y <= bounds.end.y + LayoutEnvironment.EPSILON


# ---------------------------------------------------------------- 选项辅助
func _select_option(option: OptionButton, id: String) -> void:
	if option == null:
		return
	for i in range(option.item_count):
		if str(option.get_item_metadata(i)) == id:
			option.select(i)
			return
	if option.item_count > 0:
		option.select(0)
	else:
		option.select(-1)


func _selected_id(option: OptionButton) -> String:
	if option == null or option.selected < 0:
		return ""
	return str(option.get_item_metadata(option.selected))


func _set_side(check: CheckBox, pressed: bool) -> void:
	if check != null:
		check.set_pressed_no_signal(pressed)


# ---------------------------------------------------------------- UI
func _build_ui() -> void:
	add_theme_constant_override("separation", 6)
	add_child(_label("环境", 15, SECTION_COLOR))
	add_child(_label("天空与光照可分开选择；未配置的地图沿用当前默认环境。", 11, MUTED_COLOR))

	var sky_form := GridContainer.new()
	sky_form.columns = 2
	add_child(sky_form)
	sky_form.add_child(_label("天空", 12, MUTED_COLOR))
	_sky_option = _option(sky_form, LayoutEnvironment.SKIES, SKY_LABELS)
	sky_form.add_child(_label("光照", 12, MUTED_COLOR))
	_lighting_option = _option(sky_form, LayoutEnvironment.LIGHTING, LIGHTING_LABELS)

	add_child(_label("边界林（地图外背景树）", 15, SECTION_COLOR))
	add_child(_label("勾选要铺树的边；全不勾等于关闭。树根会贴合地形边缘高度。", 11, MUTED_COLOR))
	var sides_row := HBoxContainer.new()
	add_child(sides_row)
	_north_check = _side_check(sides_row, "北")
	_east_check = _side_check(sides_row, "东")
	_south_check = _side_check(sides_row, "南")
	_west_check = _side_check(sides_row, "西")

	var border_form := GridContainer.new()
	border_form.columns = 2
	add_child(border_form)
	_depth_spin = _spin(
		border_form, "林带深度", 1.0, LayoutEnvironment.MAX_BORDER_DEPTH,
		LayoutEnvironment.DEFAULT_BORDER_DEPTH, 0.1
	)
	_spacing_spin = _spin(
		border_form, "树木间距", LayoutEnvironment.MIN_BORDER_SPACING, LayoutEnvironment.MAX_BORDER_SPACING,
		LayoutEnvironment.DEFAULT_BORDER_SPACING, 0.1
	)

	add_child(_label("相机范围", 15, SECTION_COLOR))
	_camera_note = _label("", 11, MUTED_COLOR)
	_camera_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_camera_note)
	var camera_row := HBoxContainer.new()
	add_child(camera_row)
	camera_row.add_child(_button("框选相机范围", _on_pick_camera_pressed))
	camera_row.add_child(_button("清空范围", _on_clear_camera_pressed))

	var action_row := HBoxContainer.new()
	add_child(action_row)
	action_row.add_child(_button("应用环境", _on_apply_pressed))
	action_row.add_child(_button("清空环境配置", _on_clear_environment_pressed))
	_update_camera_note()


func _option(
	parent: GridContainer, ids: Array[String], labels: Dictionary
) -> OptionButton:
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for index in range(ids.size()):
		var id: String = ids[index]
		option.add_item(str(labels.get(id, id)))
		option.set_item_metadata(index, id)
	parent.add_child(option)
	return option


func _side_check(parent: HBoxContainer, text: String) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	parent.add_child(check)
	return check


func _label(text: String, font_size: int = 13, color: Color = MUTED_COLOR) -> Label:
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

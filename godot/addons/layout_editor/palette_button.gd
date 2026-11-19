@tool
extends Button

# 布局调色板的素材按钮：普通点击走 Button.pressed，拖拽时返回 {"layout_asset": asset_id}。
# 拖拽预览只使用本控件已有的 icon / text，不读取磁盘，也不依赖插件具体路径。

@export var asset_id: String = ""


func _get_drag_data(_at_position: Vector2) -> Variant:
	var id: String = asset_id.strip_edges()
	if id.is_empty():
		return null
	set_drag_preview(_build_drag_preview())
	return {"layout_asset": id}


func _build_drag_preview() -> Control:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.11, 0.09, 0.96)
	style.border_color = Color(0.78, 0.66, 0.40, 0.95)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6.0)
	panel.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)

	if icon != null:
		var icon_rect := TextureRect.new()
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_rect.texture = icon
		icon_rect.custom_minimum_size = Vector2(24, 24)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon_rect)

	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = text if not text.is_empty() else asset_id
	label.add_theme_color_override("font_color", Color(0.95, 0.91, 0.80))
	row.add_child(label)
	return panel

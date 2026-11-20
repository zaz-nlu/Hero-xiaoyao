extends Control

signal finished

const Dialogue = preload("res://core/dialogue.gd")
const ImageCache = preload("res://shared/resources/image_cache.gd")

const CHARS_PER_SEC := 40.0
const DEFAULT_WIDTH := 1152.0
const DEFAULT_HEIGHT := 648.0
const PORTRAIT_LIFT := 10.0
# 版式按窗口高度缩放（以 648 为基准）。立绘整体下移，只露出上半身，下半身被屏幕底边和对话框挡住。
const BASE_HEIGHT := 648.0
const BOX_HEIGHT := 150.0
const BOX_MARGIN_X := 40.0
const BOX_MARGIN_BOTTOM := 16.0
const PORTRAIT_HEIGHT_RATIO := 0.9
const PORTRAIT_WIDTH_RATIO := 0.7
const PORTRAIT_TOP_RATIO := 0.44
const PORTRAIT_SIDE_MARGIN := 0.03

var runner: Variant = null
var typing: bool = false
var _chars: float = 0.0

var dim: ColorRect = null
var left_portrait: TextureRect = null
var right_portrait: TextureRect = null
var box: ColorRect = null
var name_plate: ColorRect = null
var name_label: Label = null
var text_label: RichTextLabel = null
var hint_label: Label = null
var _active_side: String = "center"


func _ready() -> void:
	if dim == null:
		build_ui()


func build_ui() -> void:
	if dim != null:
		return

	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	dim = ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.0, 0.0, 0.0, 0.45)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	left_portrait = TextureRect.new()
	left_portrait.name = "LeftPortrait"
	_configure_portrait(left_portrait)
	left_portrait.visible = false
	add_child(left_portrait)

	right_portrait = TextureRect.new()
	right_portrait.name = "RightPortrait"
	_configure_portrait(right_portrait)
	right_portrait.visible = false
	add_child(right_portrait)

	box = ColorRect.new()
	box.name = "Box"
	box.color = Color(0.06, 0.05, 0.09, 0.92)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	name_plate = ColorRect.new()
	name_plate.name = "NamePlate"
	name_plate.color = Color(0.35, 0.25, 0.5, 1.0)
	name_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(name_plate)

	name_label = Label.new()
	name_label.name = "NameLabel"
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(name_label)

	text_label = RichTextLabel.new()
	text_label.name = "TextLabel"
	text_label.bbcode_enabled = false
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.scroll_active = false
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(text_label)

	hint_label = Label.new()
	hint_label.name = "HintLabel"
	hint_label.text = "▼"
	hint_label.size = Vector2(40.0, 30.0)
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_label.visible = false
	add_child(hint_label)

	resized.connect(layout)
	layout()
	visible = true


func start(lines: Array) -> void:
	if dim == null:
		build_ui()
	runner = Dialogue.new(lines)
	if lines.is_empty():
		visible = false
		emit_signal("finished")
		return
	visible = true
	show_line()


func show_line() -> void:
	if runner == null:
		return
	var line: Dictionary = runner.current()
	if line.is_empty():
		return

	var speaker: String = str(line.get("speaker", ""))
	var speaker_name: String = str(line.get("name", ""))
	var side: String = str(line.get("side", "center"))
	var portrait_path: String = str(line.get("portrait", ""))

	text_label.text = str(line.get("text", ""))
	text_label.visible_characters = 0
	typing = true
	_chars = 0.0
	hint_label.visible = false

	if speaker == "narrator" or speaker_name == "":
		name_label.text = ""
		name_plate.visible = false
	else:
		name_label.text = speaker_name
		name_plate.visible = true

	if portrait_path != "":
		var portrait_texture: Texture2D = ImageCache.texture(portrait_path)
		if portrait_texture != null:
			if side == "left":
				left_portrait.texture = portrait_texture
				left_portrait.visible = true
			elif side == "right":
				right_portrait.texture = portrait_texture
				right_portrait.visible = true
	elif speaker != "narrator":
		# Speakers such as background villagers have no portrait: show only the
		# name plate and the text, like the narrator, without leaving an old
		# portrait on screen.
		left_portrait.visible = false
		right_portrait.visible = false

	_refresh_portrait_emphasis(side)


func tick(delta: float) -> void:
	if not typing:
		return
	_chars += CHARS_PER_SEC * delta
	text_label.visible_characters = int(_chars)
	var total: int = text_label.get_total_character_count()
	if text_label.visible_characters >= total:
		typing = false
		text_label.visible_characters = -1
		hint_label.visible = true


func advance() -> void:
	if runner == null:
		return
	if typing:
		typing = false
		text_label.visible_characters = -1
		hint_label.visible = true
		return
	runner.advance()
	if runner.is_finished():
		visible = false
		emit_signal("finished")
		return
	show_line()


func is_active() -> bool:
	if runner == null or not visible:
		return false
	return not bool(runner.is_finished())


func _process(delta: float) -> void:
	tick(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if not _is_advance_event(event):
		return
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
	advance()


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if not _is_advance_event(event):
		return
	accept_event()
	advance()


func _is_advance_event(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		return mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT
	return event.is_action_pressed("ui_accept")


# 按实际窗口大小排版（窗口大小变化时会重算），避免暗色遮罩和对话框只铺到一部分。
func layout() -> void:
	if dim == null:
		return
	var w := _view_width()
	var h := _view_height()
	var sc := h / BASE_HEIGHT
	dim.position = Vector2.ZERO
	dim.size = Vector2(w, h)

	var box_h := BOX_HEIGHT * sc
	var mx := BOX_MARGIN_X * sc
	box.position = Vector2(mx, h - box_h - BOX_MARGIN_BOTTOM * sc)
	box.size = Vector2(w - mx * 2.0, box_h)
	name_plate.position = Vector2(box.position.x + 8.0 * sc, box.position.y - 38.0 * sc)
	name_plate.size = Vector2(150.0 * sc, 40.0 * sc)
	name_label.position = name_plate.position + Vector2(12.0 * sc, 6.0 * sc)
	text_label.position = box.position + Vector2(24.0 * sc, 20.0 * sc)
	text_label.size = Vector2(box.size.x - 48.0 * sc, box_h - 40.0 * sc)
	hint_label.position = Vector2(box.position.x + box.size.x - 56.0 * sc, box.position.y + box_h - 40.0 * sc)

	var ph := h * PORTRAIT_HEIGHT_RATIO
	var pw := ph * PORTRAIT_WIDTH_RATIO
	left_portrait.size = Vector2(pw, ph)
	right_portrait.size = Vector2(pw, ph)
	_refresh_portrait_emphasis(_active_side)


func _portrait_base(left: bool) -> Vector2:
	var w := _view_width()
	var h := _view_height()
	var pw := h * PORTRAIT_HEIGHT_RATIO * PORTRAIT_WIDTH_RATIO
	var margin := w * PORTRAIT_SIDE_MARGIN
	var top := h * PORTRAIT_TOP_RATIO
	return Vector2(margin if left else w - margin - pw, top)


func _refresh_portrait_emphasis(side: String) -> void:
	_active_side = side
	_apply_portrait_emphasis(left_portrait, side == "left", _portrait_base(true))
	_apply_portrait_emphasis(right_portrait, side == "right", _portrait_base(false))


func _apply_portrait_emphasis(portrait_rect: TextureRect, active: bool, base_position: Vector2) -> void:
	if portrait_rect == null or not portrait_rect.visible:
		return
	if active:
		portrait_rect.modulate = Color(1.0, 1.0, 1.0, 1.0)
		portrait_rect.position = base_position - Vector2(0.0, PORTRAIT_LIFT * _view_height() / BASE_HEIGHT)
	else:
		portrait_rect.modulate = Color(0.55, 0.55, 0.6, 1.0)
		portrait_rect.position = base_position


func _configure_portrait(portrait_rect: TextureRect) -> void:
	portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	portrait_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _view_width() -> float:
	if size.x > 0.0:
		return size.x
	return DEFAULT_WIDTH


func _view_height() -> float:
	if size.y > 0.0:
		return size.y
	return DEFAULT_HEIGHT

extends Control

signal finished

const Dialogue = preload("res://core/dialogue.gd")
const ImageCache = preload("res://ui/image_cache.gd")

const CHARS_PER_SEC := 40.0
const DEFAULT_WIDTH := 1152.0
const DEFAULT_HEIGHT := 648.0
const PORTRAIT_LIFT := 10.0
const LEFT_POSITION := Vector2(40.0, 70.0)
const RIGHT_POSITION_OFFSET := 460.0
const PORTRAIT_SIZE := Vector2(420.0, 580.0)

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


func _ready() -> void:
	if dim == null:
		build_ui()


func build_ui() -> void:
	if dim != null:
		return

	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var width: float = _view_width()
	var height: float = _view_height()

	dim = ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.0, 0.0, 0.0, 0.45)
	dim.position = Vector2.ZERO
	dim.size = Vector2(width, height)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	left_portrait = TextureRect.new()
	left_portrait.name = "LeftPortrait"
	_configure_portrait(left_portrait)
	left_portrait.position = LEFT_POSITION
	left_portrait.size = PORTRAIT_SIZE
	left_portrait.visible = false
	add_child(left_portrait)

	right_portrait = TextureRect.new()
	right_portrait.name = "RightPortrait"
	_configure_portrait(right_portrait)
	right_portrait.position = _right_position()
	right_portrait.size = PORTRAIT_SIZE
	right_portrait.visible = false
	add_child(right_portrait)

	box = ColorRect.new()
	box.name = "Box"
	box.color = Color(0.06, 0.05, 0.09, 0.92)
	box.position = Vector2(40.0, 470.0)
	box.size = Vector2(width - 80.0, 150.0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	name_plate = ColorRect.new()
	name_plate.name = "NamePlate"
	name_plate.color = Color(0.35, 0.25, 0.5, 1.0)
	name_plate.position = Vector2(48.0, 432.0)
	name_plate.size = Vector2(150.0, 40.0)
	name_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(name_plate)

	name_label = Label.new()
	name_label.name = "NameLabel"
	name_label.position = Vector2(60.0, 438.0)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(name_label)

	text_label = RichTextLabel.new()
	text_label.name = "TextLabel"
	text_label.position = Vector2(64.0, 490.0)
	text_label.size = Vector2(width - 128.0, 110.0)
	text_label.bbcode_enabled = false
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.scroll_active = false
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(text_label)

	hint_label = Label.new()
	hint_label.name = "HintLabel"
	hint_label.text = "▼"
	hint_label.position = Vector2(width - 96.0, 586.0)
	hint_label.size = Vector2(40.0, 30.0)
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_label.visible = false
	add_child(hint_label)

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


func _refresh_portrait_emphasis(side: String) -> void:
	_apply_portrait_emphasis(left_portrait, side == "left", LEFT_POSITION)
	_apply_portrait_emphasis(right_portrait, side == "right", _right_position())


func _apply_portrait_emphasis(portrait_rect: TextureRect, active: bool, base_position: Vector2) -> void:
	if portrait_rect == null or not portrait_rect.visible:
		return
	if active:
		portrait_rect.modulate = Color(1.0, 1.0, 1.0, 1.0)
		portrait_rect.position = base_position - Vector2(0.0, PORTRAIT_LIFT)
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


func _right_position() -> Vector2:
	return Vector2(_view_width() - RIGHT_POSITION_OFFSET, 70.0)

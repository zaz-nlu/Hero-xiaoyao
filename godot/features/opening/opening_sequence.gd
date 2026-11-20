extends Control

# 开场序幕播放器：按 data/opening.json 的 slides 逐页播放字幕。
# 时间完全由 advance(delta) 推进，测试可以无帧循环地手动步进。
#
# 字幕淡入策略：每页把 seconds 平均分给各句；第 i 句在其时间窗起点后 0.6 秒内淡入，
# 之前出现的句子保持显示，直到整页结束（整页由黑场过渡收尾）。
# 页与页之间用约 0.6 秒的黑场交叉淡化：每页开头 0.6 秒从黑淡入、结尾 0.6 秒淡到黑，
# 因此总时长严格等于所有 slides 的 seconds 之和。

signal finished

const OpeningBackdrop = preload("res://features/opening/opening_backdrop.gd")
const TownFonts = preload("res://shared/scenery/town/town_fonts.gd")

const LINE_FADE := 0.6
const PAGE_FADE := 0.6
const FONT_SIZE := 32
const HINT_FONT_SIZE := 16
const HINT_TEXT := "空格/回车 下一句　Esc 跳过"
const TEXT_COLOR := Color(0.96, 0.96, 0.94)
const OUTLINE_COLOR := Color(0.06, 0.05, 0.05)
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.75)
const HINT_COLOR := Color(0.9, 0.88, 0.82, 0.7)

var audio: Variant = null

var _data: Dictionary = {}
var _slides: Array = []
var _page_index: int = 0
var _page_time: float = 0.0
var _built: bool = false
var _finished: bool = false

var _backdrop: OpeningBackdrop = null
var _black: ColorRect = null
var _line_box: VBoxContainer = null
var _labels: Array[Label] = []
var _hint: Label = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	if _built and not _finished:
		advance(delta)


func _unhandled_input(event: InputEvent) -> void:
	if _finished:
		return
	if event is InputEventKey:
		var key_event: InputEventKey = event
		if not key_event.pressed or key_event.echo:
			return
		var key := key_event.keycode
		if key == KEY_NONE:
			key = key_event.physical_keycode
		if key == KEY_ESCAPE:
			skip_all()
		elif key == KEY_SPACE or key == KEY_ENTER or key == KEY_KP_ENTER:
			skip_line()
	elif event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			skip_line()


# ---------------------------------------------------------------- public API

func build(data: Dictionary) -> void:
	if _built:
		return
	_built = true
	_data = data
	var slides_value: Variant = data.get("slides", [])
	if slides_value is Array:
		_slides = slides_value
	_build_layers()
	_play_intro_music()
	if _slides.is_empty():
		_refresh()
	else:
		_enter_page(0)


func advance(delta: float) -> void:
	if not _built:
		build({})
	if _finished:
		return
	if _backdrop != null:
		_backdrop.advance(maxf(delta, 0.0))
	if _slides.is_empty():
		_finish()
		return
	var remaining := maxf(delta, 0.0)
	if remaining <= 0.0:
		_refresh()
		return
	while remaining > 0.0 and not _finished:
		var room := _page_seconds() - _page_time
		if room > remaining:
			_page_time += remaining
			remaining = 0.0
		else:
			remaining -= maxf(room, 0.0)
			_advance_page()
	_refresh()


func skip_line() -> void:
	if not _built:
		build({})
	if _finished:
		return
	if _slides.is_empty():
		_finish()
		return
	var lines := _lines(_slide(_page_index))
	if lines.is_empty():
		_advance_page()
	else:
		var window := _page_seconds() / float(lines.size())
		var revealed := revealed_count()
		if revealed < lines.size():
			_page_time = minf(
				_page_seconds(), float(revealed) * window + minf(LINE_FADE, window)
			)
		else:
			_advance_page()
	_refresh()


func skip_all() -> void:
	if not _built:
		build({})
	if _finished:
		return
	_finish()


func is_finished() -> bool:
	return _finished


func slide_count() -> int:
	return _slides.size()


func page_index() -> int:
	return _page_index


func page_time() -> float:
	return _page_time


func current_slide() -> Dictionary:
	return _slide(_page_index)


func total_duration() -> float:
	var total := 0.0
	for slide_value in _slides:
		if slide_value is Dictionary:
			total += _seconds_of(slide_value)
	return total


# 已经完整淡入的句子数（0 表示第一句还没出现）。
func revealed_count() -> int:
	var lines := _lines(_slide(_page_index))
	var count := 0
	for index in range(lines.size()):
		if _line_alpha(index) >= 0.999:
			count += 1
	return count


func current_line_index() -> int:
	return revealed_count() - 1


func line_alpha(index: int) -> float:
	return _line_alpha(index)


# ---------------------------------------------------------------- timeline

func _advance_page() -> void:
	if _page_index + 1 >= _slides.size():
		_finish()
	else:
		_enter_page(_page_index + 1)


func _enter_page(index: int) -> void:
	_page_index = index
	_page_time = 0.0
	var slide := _slide(index)
	if _backdrop != null:
		_backdrop.apply(slide)
	# text_pos = "top"：字幕移到画面上方，给画面中央的演出让位。
	var at_top := str(slide.get("text_pos", "")) == "top"
	_line_box.offset_top = -600.0 if at_top else -320.0
	_line_box.offset_bottom = -440.0 if at_top else -150.0
	_rebuild_lines(slide)
	_refresh()


func _finish() -> void:
	if _finished:
		return
	_refresh()
	_finished = true
	finished.emit()


func _line_alpha(index: int) -> float:
	var lines := _lines(_slide(_page_index))
	if index < 0 or index >= lines.size():
		return 0.0
	var window := _page_seconds() / float(lines.size())
	if window <= 0.0:
		return 1.0
	var fade := minf(LINE_FADE, window)
	return clampf((_page_time - float(index) * window) / fade, 0.0, 1.0)


func _black_alpha() -> float:
	if _slides.is_empty():
		return 1.0
	var seconds := _page_seconds()
	var fade_in := 1.0 - clampf(_page_time / PAGE_FADE, 0.0, 1.0)
	var fade_out := 0.0
	var remaining := seconds - _page_time
	if remaining < PAGE_FADE:
		fade_out = 1.0 - clampf(remaining / PAGE_FADE, 0.0, 1.0)
	return maxf(fade_in, fade_out)


func _page_seconds() -> float:
	return maxf(_seconds_of(_slide(_page_index)), 0.001)


func _seconds_of(slide: Dictionary) -> float:
	var value: Variant = slide.get("seconds", 0.0)
	if value is int or value is float:
		return float(value)
	return 0.0


func _lines(slide: Dictionary) -> Array:
	var result: Array = []
	var value: Variant = slide.get("lines", [])
	if value is Array:
		for line in value:
			if line is String and str(line) != "":
				result.append(str(line))
	return result


func _slide(index: int) -> Dictionary:
	if index < 0 or index >= _slides.size():
		return {}
	var value: Variant = _slides[index]
	if value is Dictionary:
		return value
	return {}


# ---------------------------------------------------------------- visuals

func _build_layers() -> void:
	_backdrop = OpeningBackdrop.new()
	_backdrop.name = "Backdrop"
	add_child(_backdrop)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_line_box = VBoxContainer.new()
	_line_box.name = "Lines"
	_line_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_line_box.alignment = BoxContainer.ALIGNMENT_END
	_line_box.anchor_left = 0.5
	_line_box.anchor_right = 0.5
	_line_box.anchor_top = 1.0
	_line_box.anchor_bottom = 1.0
	_line_box.offset_left = -640.0
	_line_box.offset_right = 640.0
	_line_box.offset_top = -320.0
	_line_box.offset_bottom = -150.0
	add_child(_line_box)

	_black = ColorRect.new()
	_black.name = "Black"
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.color = Color(0.0, 0.0, 0.0, 1.0)
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_black)

	_hint = Label.new()
	_hint.name = "Hint"
	_hint.text = HINT_TEXT
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint.anchor_left = 1.0
	_hint.anchor_right = 1.0
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_left = -520.0
	_hint.offset_right = -32.0
	_hint.offset_top = -48.0
	_hint.offset_bottom = -20.0
	_hint.add_theme_font_size_override("font_size", HINT_FONT_SIZE)
	_hint.add_theme_color_override("font_color", HINT_COLOR)
	var hint_font := TownFonts.brush()
	if hint_font != null:
		_hint.add_theme_font_override("font", hint_font)
	add_child(_hint)


func _rebuild_lines(slide: Dictionary) -> void:
	for label in _labels:
		if is_instance_valid(label):
			if label.get_parent() != null:
				label.get_parent().remove_child(label)
			label.queue_free()
	_labels.clear()
	if _line_box == null:
		return
	var font := TownFonts.brush()
	for line in _lines(slide):
		var label := Label.new()
		label.text = line
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size", FONT_SIZE)
		label.add_theme_color_override("font_color", TEXT_COLOR)
		label.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
		label.add_theme_constant_override("outline_size", 6)
		label.add_theme_color_override("font_shadow_color", SHADOW_COLOR)
		label.add_theme_constant_override("shadow_offset_x", 2)
		label.add_theme_constant_override("shadow_offset_y", 3)
		label.add_theme_constant_override("shadow_outline_size", 2)
		if font != null:
			label.add_theme_font_override("font", font)
		label.modulate.a = 0.0
		_line_box.add_child(label)
		_labels.append(label)


func _refresh() -> void:
	for index in range(_labels.size()):
		var label := _labels[index]
		if is_instance_valid(label):
			label.modulate.a = _line_alpha(index)
	if _black != null:
		_black.color = Color(0.0, 0.0, 0.0, _black_alpha())


func _play_intro_music() -> void:
	if audio == null or not (audio is Object) or not audio.has_method("play_cue"):
		return
	var music_value: Variant = _data.get("music", {})
	var intro := ""
	if music_value is Dictionary:
		intro = str((music_value as Dictionary).get("intro", ""))
	if intro != "":
		audio.play_cue(intro)

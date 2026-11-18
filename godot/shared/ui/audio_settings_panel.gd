extends Control

# 音频设置页的共用内容：音乐/音效滑块、百分比、静音开关、返回按钮与操作提示。
# 只负责控件与显示。调用方负责音量读写和页面切换：滑块的 value_changed 与
# 静音勾选只转发为信号；sync_values() 回填显示，不会触发这些信号。

const Hud = preload("res://shared/ui/battle_hud_style.gd")

const PANEL_WIDTH := 640.0

signal music_changed(value: float)
signal sfx_changed(value: float)
signal muted_changed(pressed: bool)
signal back_pressed

var music_slider: HSlider = null
var sfx_slider: HSlider = null
var mute_box: CheckBox = null
var back_button: Button = null

var _music_value: Label = null
var _sfx_value: Label = null
var _setting_labels: Array[Label] = []
var _style_back: Callable = Callable()
var _syncing: bool = false


func _init() -> void:
	name = "AudioSettings"
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func build(parent: Node, style_back: Callable = Callable()) -> void:
	_style_back = style_back
	_setting_labels.append(_make_label(
		"MusicLabel", "音乐音量", Vector2(110.0, 96.0), Vector2(180.0, 26.0), 18,
		Hud.TEXT
	))
	music_slider = _make_slider("MusicSlider", Vector2(110.0, 128.0))
	music_slider.value_changed.connect(_on_music_changed)
	_music_value = _make_label(
		"MusicValue", "", Vector2(460.0, 126.0), Vector2(80.0, 26.0), 16, Hud.MUTED
	)

	_setting_labels.append(_make_label(
		"SfxLabel", "音效音量", Vector2(110.0, 180.0), Vector2(180.0, 26.0), 18,
		Hud.TEXT
	))
	sfx_slider = _make_slider("SfxSlider", Vector2(110.0, 212.0))
	sfx_slider.value_changed.connect(_on_sfx_changed)
	_sfx_value = _make_label(
		"SfxValue", "", Vector2(460.0, 210.0), Vector2(80.0, 26.0), 16, Hud.MUTED
	)

	mute_box = CheckBox.new()
	mute_box.name = "MuteCheck"
	mute_box.text = "静音"
	mute_box.position = Vector2(106.0, 264.0)
	mute_box.size = Vector2(160.0, 30.0)
	mute_box.focus_mode = Control.FOCUS_NONE
	mute_box.add_theme_font_size_override("font_size", 17)
	mute_box.add_theme_color_override("font_color", Hud.TEXT)
	mute_box.toggled.connect(_on_mute_toggled)
	add_child(mute_box)

	back_button = Button.new()
	back_button.name = "SettingsBack"
	back_button.text = "返回"
	back_button.position = Vector2(270.0, 512.0)
	back_button.size = Vector2(100.0, 38.0)
	back_button.focus_mode = Control.FOCUS_NONE
	back_button.add_theme_font_size_override("font_size", 18)
	back_button.add_theme_color_override("font_hover_color", Hud.GOLD_BRIGHT)
	back_button.add_theme_color_override("font_pressed_color", Hud.GOLD_BRIGHT)
	back_button.pressed.connect(func() -> void: back_pressed.emit())
	add_child(back_button)
	if _style_back.is_valid():
		_style_back.call(back_button, false)

	var hint := _make_label(
		"SettingsHint", "↑↓ 选择    ←→ 调整    Esc 返回",
		Vector2(0.0, 460.0), Vector2(PANEL_WIDTH, 22.0), 14, Hud.MUTED
	)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(self)


# 回填音频状态。调用方传入已算好的值；这里只改显示，不会发出设置信号。
func sync_values(music: float, sfx: float, muted: bool) -> void:
	_syncing = true
	music_slider.set_value_no_signal(music)
	sfx_slider.set_value_no_signal(sfx)
	mute_box.set_pressed_no_signal(muted)
	_refresh_volume_labels()
	_syncing = false


# 键盘选中态：高亮两个音量标签和静音开关，返回按钮交给调用方注入的样式回调。
func set_selection(index: int) -> void:
	for i in range(_setting_labels.size()):
		_setting_labels[i].add_theme_color_override(
			"font_color", Hud.GOLD_BRIGHT if i == index else Hud.MUTED
		)
	mute_box.modulate = (
		Color(1.0, 1.0, 1.0, 1.0) if index == 2 else Color(0.82, 0.82, 0.82, 1.0)
	)
	if _style_back.is_valid():
		_style_back.call(back_button, index == 3)


func _make_slider(node_name: String, pos: Vector2) -> HSlider:
	var slider := HSlider.new()
	slider.name = node_name
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.position = pos
	slider.size = Vector2(340.0, 24.0)
	slider.focus_mode = Control.FOCUS_NONE
	add_child(slider)
	return slider


func _make_label(
	node_name: String, text: String, pos: Vector2, label_size: Vector2,
	font_size: int, color: Color
) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.position = pos
	label.size = label_size
	Hud.configure_label(label, font_size, color)
	add_child(label)
	return label


func _on_music_changed(value: float) -> void:
	if _syncing:
		return
	_refresh_volume_labels()
	music_changed.emit(value)


func _on_sfx_changed(value: float) -> void:
	if _syncing:
		return
	_refresh_volume_labels()
	sfx_changed.emit(value)


func _on_mute_toggled(pressed: bool) -> void:
	if _syncing:
		return
	muted_changed.emit(pressed)


func _refresh_volume_labels() -> void:
	if _music_value != null:
		_music_value.text = "%d%%" % int(round(music_slider.value * 100.0))
	if _sfx_value != null:
		_sfx_value.text = "%d%%" % int(round(sfx_slider.value * 100.0))

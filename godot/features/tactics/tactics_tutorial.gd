extends RefCounted

# 战旗教学提示：按 data/tactics_tutorial.json 里该遭遇来源的步骤，在对应事件第一次出现时
# 在屏幕上方弹出说明条（每步只弹一次，不挡鼠标）。由 tactics_game_bridge 驱动。

const DATA_PATH := "res://data/tactics_tutorial.json"
const UI = preload("res://features/tactics/tactics_ui_style.gd")

var active: bool = false
var shown: Array = []
var current_id: String = ""

var _view: Control = null
var _steps: Array = []
var _box: PanelContainer = null
var _title: Label = null
var _body: Label = null
var _token: int = 0


func setup(view, origin: String) -> void:
	_view = view
	active = false
	shown.clear()
	_steps = []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if parsed is Dictionary and (parsed as Dictionary).get(origin) is Array:
		_steps = (parsed as Dictionary)[origin]
	active = not _steps.is_empty()
	if active:
		trigger("battle_start")


func on_events(events: Array) -> void:
	if not active:
		return
	for raw in events:
		if not (raw is Dictionary):
			continue
		var event: Dictionary = raw
		match str(event.get("type", "")):
			"hit":
				if bool(event.get("weak", false)):
					trigger("weak_hit")
			"stun":
				trigger("stun")
			"jianyi":
				trigger("jianyi")
			"heal":
				if str(event.get("source", "")) == "regen":
					trigger("regen")


func trigger(kind: String) -> void:
	for raw in _steps:
		var step: Dictionary = raw
		if str(step.get("on", "")) != kind or shown.has(str(step.get("id", ""))):
			continue
		shown.append(str(step.get("id", "")))
		_show(step)
		return


func hide_hint() -> void:
	current_id = ""
	if _box != null and is_instance_valid(_box):
		_box.visible = false


func _show(step: Dictionary) -> void:
	if _view == null or not is_instance_valid(_view):
		return
	_ensure_box()
	current_id = str(step.get("id", ""))
	_title.text = str(step.get("title", ""))
	_body.text = str(step.get("text", ""))
	_box.visible = true
	_token += 1
	var mine := _token
	if _view.is_inside_tree():
		var timer := _view.get_tree().create_timer(float(step.get("seconds", 12)))
		timer.timeout.connect(func() -> void:
			if mine == _token:
				hide_hint())


func _ensure_box() -> void:
	if _box != null and is_instance_valid(_box):
		return
	_box = PanelContainer.new()
	_box.name = "TutorialHint"
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.offset_left = 14.0
	_box.offset_right = 354.0
	_box.offset_top = 196.0
	_box.add_theme_stylebox_override("panel", UI.panel_filled_style())
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 4)
	_box.add_child(column)
	_title = Label.new()
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.configure_label(_title, 17, UI.GOLD_BRIGHT)
	column.add_child(_title)
	_body = Label.new()
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(300.0, 0.0)
	UI.configure_label(_body, 15, UI.TEXT)
	column.add_child(_body)
	_view.add_child(_box)

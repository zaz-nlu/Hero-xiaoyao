@tool
extends VBoxContainer

# 地图工坊的物件触发器小节：选中任意物件实例后设置对话/遭遇/出口/任务。
# 表单只是草稿；应用与清空都通过 EditState 的一次 _commit 提交，因此会进入
# 同一套撤销/重做/保存/试跑流程。应用失败时只显示错误，不清空当前草稿。
# 只持有界面状态，不接管画布点击，因此不会与地形/环境工具抢输入。

signal status(kind: String, message: String)

const LayoutTriggers = preload("res://core/layouts/layout_triggers.gd")
const EditState = preload("res://addons/layout_editor/edit_state.gd")

const SECTION_COLOR := Color(0.93, 0.79, 0.47)
const MUTED_COLOR := Color(0.68, 0.67, 0.62)
const ERROR_COLOR := Color(1.0, 0.45, 0.38)
const KIND_LABELS := {
	"dialogue": "对话",
	"encounter": "遭遇",
	"exit": "出口",
	"quest": "任务",
}
const ACTIVATION_LABELS := {
	"interact": "按键互动（E）",
	"enter": "进入感应圈",
}
const QUEST_ACTION_LABELS := {
	"start": "开始任务",
	"turn_in": "交付任务",
}

var state: EditState = null

var _built := false
var _loading := false
var _signature := ""

var _note: Label = null
var _kind_option: OptionButton = null
var _activation_option: OptionButton = null
var _quest_row: HBoxContainer = null
var _quest_option: OptionButton = null
var _target_option: OptionButton = null
var _target_edit: LineEdit = null
var _count_row: HBoxContainer = null
var _count_spin: SpinBox = null
var _apply_btn: Button = null
var _clear_btn: Button = null


func setup(edit_state: EditState) -> void:
	state = edit_state


func _ready() -> void:
	if _built:
		return
	_built = true
	_build_ui()
	refresh()


# ---------------------------------------------------------------- 对外
func refresh() -> void:
	if not _built or state == null:
		return
	var obj: Dictionary = state.selected_object()
	var has_object := not obj.is_empty()
	_set_enabled(has_object)
	if not has_object:
		_signature = ""
		_note.text = "选中任意地图物件实例后，可在这里设置触发器。"
		return
	var trigger: Dictionary = state.selected_trigger()
	var signature := "%d|%s" % [state.selected_object_index(), JSON.stringify(trigger)]
	if signature == _signature:
		return
	_signature = signature
	_load_trigger(trigger)


func _load_trigger(trigger: Dictionary) -> void:
	var kind := str(trigger.get("kind", "dialogue"))
	if not LayoutTriggers.KINDS.has(kind):
		kind = "dialogue"
	loading_on()
	_select_metadata(_kind_option, kind)
	var activation := str(trigger.get("activation", LayoutTriggers.DEFAULT_ACTIVATION))
	if not LayoutTriggers.ACTIVATIONS.has(activation):
		activation = LayoutTriggers.DEFAULT_ACTIVATION
	_select_metadata(_activation_option, activation)
	var action := str(trigger.get("action", LayoutTriggers.DEFAULT_QUEST_ACTION))
	if not LayoutTriggers.QUEST_ACTIONS.has(action):
		action = LayoutTriggers.DEFAULT_QUEST_ACTION
	_select_metadata(_quest_option, action)
	var target := str(trigger.get("target", ""))
	_target_edit.text = target
	var count := int(trigger.get("count", LayoutTriggers.DEFAULT_ENCOUNTER_COUNT))
	_count_spin.set_value_no_signal(float(maxi(1, count)))
	_update_visibility(kind)
	_rebuild_targets(kind, target)
	loading_off()
	if trigger.is_empty():
		_note.text = "当前未设触发器；填好目标后点“应用触发器”。"
	else:
		_note.text = "当前：%s · %s" % [
			str(KIND_LABELS.get(kind, kind)), str(ACTIVATION_LABELS.get(activation, activation))
		]
	_clear_btn.disabled = trigger.is_empty()


# ---------------------------------------------------------------- 表单行为
func _on_kind_changed(_index: int) -> void:
	if _loading:
		return
	var kind := _selected_metadata(_kind_option)
	_update_visibility(kind)
	_rebuild_targets(kind, _target_edit.text.strip_edges())
	_note.text = _hint_for(kind)


func _on_activation_changed(_index: int) -> void:
	if _loading:
		return
	var activation := _selected_metadata(_activation_option)
	_note.text = _hint_for(_selected_metadata(_kind_option)) + (
		" 进入感应圈只触发一次，离开后可再次进入。"
		if activation == "enter" else ""
	)


func _on_target_selected(index: int) -> void:
	if _loading:
		return
	var id := str(_target_option.get_item_metadata(index))
	if id != "":
		_target_edit.text = id


func _on_apply_pressed() -> void:
	if state == null:
		return
	if state.selected_object_index() < 0:
		status.emit("error", "请先选中一个物件")
		return
	var trigger := _build_trigger()
	if str(trigger.get("target", "")) == "":
		status.emit("error", "请填写或选择一个目标 ID")
		return
	var result: Dictionary = state.set_selected_trigger(trigger)
	if bool(result.get("ok", false)):
		_signature = ""
		refresh()


func _on_clear_pressed() -> void:
	if state == null:
		return
	var result: Dictionary = state.clear_selected_trigger()
	if bool(result.get("ok", false)):
		_signature = ""
		refresh()


func _build_trigger() -> Dictionary:
	var kind := _selected_metadata(_kind_option)
	var trigger := {
		"kind": kind,
		"target": _target_edit.text.strip_edges(),
		"activation": _selected_metadata(_activation_option),
	}
	if kind == "encounter":
		trigger["count"] = int(_count_spin.value)
	elif kind == "quest":
		trigger["action"] = _selected_metadata(_quest_option)
	return trigger


func _update_visibility(kind: String) -> void:
	if _quest_row != null:
		_quest_row.visible = kind == "quest"
	if _count_row != null:
		_count_row.visible = kind == "encounter"


func _rebuild_targets(kind: String, current: String) -> void:
	if _target_option == null or state == null:
		return
	var was_loading := _loading
	_loading = true
	_target_option.clear()
	_target_option.add_item("选择可用目标…")
	_target_option.set_item_metadata(0, "")
	var selected := 0
	var targets: Array[Dictionary] = state.trigger_targets(kind)
	for entry in targets:
		var id := str(entry.get("id", ""))
		if id == "":
			continue
		_target_option.add_item("%s · %s" % [id, str(entry.get("name", id))])
		_target_option.set_item_metadata(_target_option.item_count - 1, id)
		if id == current:
			selected = _target_option.item_count - 1
	_target_option.select(selected)
	_loading = was_loading


func _hint_for(kind: String) -> String:
	match kind:
		"dialogue":
			return "目标填写 data/dialogues/ 下的对话文件 ID。"
		"encounter":
			return "目标填写敌人 ID，可设置 1..%d 个。" % LayoutTriggers.MAX_ENCOUNTER_COUNT
		"exit":
			return "目标可填 town / tavern / forest，或已存在的地图 ID。"
		"quest":
			return "目标填写 data/quests.json 中的任务 ID。"
	return ""


func _set_enabled(enabled: bool) -> void:
	_kind_option.disabled = not enabled
	_activation_option.disabled = not enabled
	_quest_option.disabled = not enabled
	_target_option.disabled = not enabled
	_target_edit.editable = enabled
	_count_spin.editable = enabled
	_apply_btn.disabled = not enabled
	if not enabled:
		_clear_btn.disabled = true


func loading_on() -> void:
	_loading = true


func loading_off() -> void:
	_loading = false


# ---------------------------------------------------------------- 选项辅助
func _select_metadata(option: OptionButton, id: String) -> void:
	if option == null:
		return
	for i in range(option.item_count):
		if str(option.get_item_metadata(i)) == id:
			option.select(i)
			return
	if option.item_count > 0:
		option.select(0)


func _selected_metadata(option: OptionButton) -> String:
	if option == null or option.selected < 0:
		return ""
	return str(option.get_item_metadata(option.selected))


# ---------------------------------------------------------------- UI
func _build_ui() -> void:
	add_theme_constant_override("separation", 4)
	add_child(_label("物件触发器", 15, SECTION_COLOR))
	_note = _label("选中任意地图物件实例后，可在这里设置触发器。", 11, MUTED_COLOR)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_note)

	var kind_row := HBoxContainer.new()
	add_child(kind_row)
	kind_row.add_child(_label("类型", 12, MUTED_COLOR))
	_kind_option = OptionButton.new()
	_kind_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id in LayoutTriggers.KINDS:
		_kind_option.add_item(str(KIND_LABELS.get(id, id)))
		_kind_option.set_item_metadata(_kind_option.item_count - 1, id)
	kind_row.add_child(_kind_option)

	var activation_row := HBoxContainer.new()
	add_child(activation_row)
	activation_row.add_child(_label("触发方式", 12, MUTED_COLOR))
	_activation_option = OptionButton.new()
	_activation_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id in LayoutTriggers.ACTIVATIONS:
		_activation_option.add_item(str(ACTIVATION_LABELS.get(id, id)))
		_activation_option.set_item_metadata(_activation_option.item_count - 1, id)
	activation_row.add_child(_activation_option)

	var target_row := HBoxContainer.new()
	add_child(target_row)
	target_row.add_child(_label("目标", 12, MUTED_COLOR))
	_target_option = OptionButton.new()
	_target_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_target_option.add_item("选择可用目标…")
	_target_option.set_item_metadata(0, "")
	target_row.add_child(_target_option)
	_target_edit = LineEdit.new()
	_target_edit.placeholder_text = "或直接输入内容 ID"
	add_child(_target_edit)

	_quest_row = HBoxContainer.new()
	add_child(_quest_row)
	_quest_row.add_child(_label("任务动作", 12, MUTED_COLOR))
	_quest_option = OptionButton.new()
	_quest_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id in LayoutTriggers.QUEST_ACTIONS:
		_quest_option.add_item(str(QUEST_ACTION_LABELS.get(id, id)))
		_quest_option.set_item_metadata(_quest_option.item_count - 1, id)
	_quest_row.add_child(_quest_option)

	_count_row = HBoxContainer.new()
	add_child(_count_row)
	_count_row.add_child(_label("数量", 12, MUTED_COLOR))
	_count_spin = SpinBox.new()
	_count_spin.min_value = 1
	_count_spin.max_value = LayoutTriggers.MAX_ENCOUNTER_COUNT
	_count_spin.step = 1
	_count_spin.value = LayoutTriggers.DEFAULT_ENCOUNTER_COUNT
	_count_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count_row.add_child(_count_spin)

	add_child(_label(
		"运行时互动半径固定；选中大件物件时也请在可走到的位置附近放触发器。",
		11, MUTED_COLOR
	))

	var action_row := HBoxContainer.new()
	add_child(action_row)
	_apply_btn = _button("应用触发器", _on_apply_pressed)
	_clear_btn = _button("清空触发器", _on_clear_pressed)
	action_row.add_child(_apply_btn)
	action_row.add_child(_clear_btn)

	_kind_option.item_selected.connect(_on_kind_changed)
	_activation_option.item_selected.connect(_on_activation_changed)
	_target_option.item_selected.connect(_on_target_selected)
	_update_visibility("dialogue")


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

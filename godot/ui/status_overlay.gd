extends CanvasLayer

# Map-level status UI: character panel (C), quest panel (J) and the toast strip.
# It lives above the town/tavern HUD and is disabled while the battle view is active.

const Progression = preload("res://core/progression.gd")
const Quests = preload("res://core/quests.gd")
const DataLoader = preload("res://core/data_loader.gd")
const Hud = preload("res://ui/battle_hud_style.gd")
const CharacterPanel = preload("res://ui/character_panel.gd")

const MARTIALS_PATH := "res://data/martials.json"

const STAT_KEYS: Array[String] = ["power", "speed", "defense", "recovery", "skill", "mechanism"]
const STAT_NAMES := {
	"power": "力量",
	"speed": "速度",
	"defense": "防御",
	"recovery": "恢复",
	"skill": "技巧",
	"mechanism": "机关",
}

const PANEL_WIDTH := 640.0
const PANEL_HEIGHT := 420.0
const TOAST_MAX := 3
const TOAST_FADE_IN := 0.15
const TOAST_HOLD := 2.2
const TOAST_FADE_OUT := 0.4

var character_panel: Variant = null
var quest_panel: Control = null
var toast_box: VBoxContainer = null
var enabled: bool = true

var _built: bool = false
var _toasts: Array = []
var _martial_defs: Dictionary = {}

var _quest_list_root: Control = null
var _quest_title: Label = null
var _quest_summary: RichTextLabel = null
var _quest_objectives: Control = null
var _quest_reward: RichTextLabel = null
var _quest_ids: Array[String] = []
var _selected_quest_id: String = ""


func _init() -> void:
	layer = 50


func _ready() -> void:
	_ensure_built()


func _process(delta: float) -> void:
	_ensure_built()
	if toast_box != null:
		toast_box.visible = enabled
	if enabled:
		for text in Progression.take_toasts():
			show_toast(str(text))
	advance(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventKey:
		var key_event: InputEventKey = event
		if not key_event.pressed or key_event.echo:
			if is_panel_open():
				_consume_input()
			return
		var key: int = key_event.keycode
		if key == KEY_NONE:
			key = key_event.physical_keycode
		match key:
			KEY_C:
				toggle_character()
				_consume_input()
				return
			KEY_J:
				toggle_quests()
				_consume_input()
				return
			KEY_ESCAPE:
				close_all()
				_consume_input()
				return
			KEY_UP:
				if quest_panel != null and quest_panel.visible:
					_move_quest_selection(-1)
					_consume_input()
					return
			KEY_DOWN:
				if quest_panel != null and quest_panel.visible:
					_move_quest_selection(1)
					_consume_input()
					return
			_:
				pass
		if character_panel != null and character_panel.visible:
			if character_panel.handle_key(key):
				_consume_input()
				return
	if is_panel_open():
		_consume_input()


# ---------------------------------------------------------------- public API

func toggle_character() -> void:
	if not enabled:
		return
	_ensure_built()
	var opening: bool = not character_panel.visible
	quest_panel.visible = false
	character_panel.visible = opening
	if opening:
		refresh()


func toggle_quests() -> void:
	if not enabled:
		return
	_ensure_built()
	var opening: bool = not quest_panel.visible
	character_panel.visible = false
	quest_panel.visible = opening
	if opening:
		refresh()


func close_all() -> void:
	if character_panel != null:
		character_panel.visible = false
	if quest_panel != null:
		quest_panel.visible = false


func is_panel_open() -> bool:
	if character_panel != null and character_panel.visible:
		return true
	return quest_panel != null and quest_panel.visible


func refresh() -> void:
	_ensure_built()
	if character_panel.visible:
		character_panel.refresh()
	if quest_panel.visible:
		_refresh_quests()


func show_toast(text: String) -> void:
	_ensure_built()
	while _toasts.size() >= TOAST_MAX:
		_remove_toast(0)
	var panel := PanelContainer.new()
	panel.name = "Toast"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var style: StyleBoxFlat = Hud.panel_style(0.9, Hud.GOLD, 6)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Hud.configure_label(label, 18, Hud.TEXT)
	panel.add_child(label)
	panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
	toast_box.add_child(panel)
	_toasts.append({"node": panel, "t": 0.0})


func advance(delta: float) -> void:
	if character_panel != null:
		character_panel.advance(delta)
	var i: int = _toasts.size() - 1
	while i >= 0:
		var record: Dictionary = _toasts[i]
		var t: float = float(record.get("t", 0.0)) + delta
		record["t"] = t
		if t >= TOAST_FADE_IN + TOAST_HOLD + TOAST_FADE_OUT:
			_remove_toast(i)
			i -= 1
			continue
		var alpha := 1.0
		if t < TOAST_FADE_IN:
			alpha = t / TOAST_FADE_IN
		elif t > TOAST_FADE_IN + TOAST_HOLD:
			alpha = 1.0 - (t - TOAST_FADE_IN - TOAST_HOLD) / TOAST_FADE_OUT
		var node_value: Variant = record.get("node", null)
		if node_value is CanvasItem:
			var item: CanvasItem = node_value
			item.modulate = Color(1.0, 1.0, 1.0, clampf(alpha, 0.0, 1.0))
		i -= 1


# ---------------------------------------------------------------- construction

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_build_toast_box()
	_build_character_panel()
	_build_quest_panel()


func _build_toast_box() -> void:
	toast_box = VBoxContainer.new()
	toast_box.name = "ToastBox"
	toast_box.anchor_left = 0.5
	toast_box.anchor_right = 0.5
	toast_box.anchor_top = 0.0
	toast_box.anchor_bottom = 0.0
	toast_box.offset_left = -260.0
	toast_box.offset_right = 260.0
	toast_box.offset_top = 8.0
	toast_box.offset_bottom = 158.0
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_box.add_theme_constant_override("separation", 6)
	add_child(toast_box)


func _build_character_panel() -> void:
	character_panel = CharacterPanel.new()
	character_panel.name = "CharacterPanel"
	character_panel.visible = false
	add_child(character_panel)
	character_panel.refresh()


func _build_quest_panel() -> void:
	quest_panel = Panel.new()
	quest_panel.name = "QuestPanel"
	_center_panel(quest_panel)
	quest_panel.add_theme_stylebox_override("panel", Hud.panel_style(0.94))
	quest_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	quest_panel.visible = false
	add_child(quest_panel)

	_make_label(
		quest_panel, "QuestListHeader", Vector2(24.0, 20.0), Vector2(250.0, 28.0), 20, Hud.GOLD
	).text = "任务"

	_quest_list_root = Control.new()
	_quest_list_root.name = "QuestList"
	_quest_list_root.position = Vector2(24.0, 56.0)
	_quest_list_root.size = Vector2(250.0, 312.0)
	_quest_list_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quest_panel.add_child(_quest_list_root)

	var divider := ColorRect.new()
	divider.name = "QuestDivider"
	divider.position = Vector2(288.0, 20.0)
	divider.size = Vector2(1.0, 354.0)
	divider.color = Color(0.78, 0.65, 0.35, 0.35)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quest_panel.add_child(divider)

	_quest_title = _make_label(
		quest_panel, "QuestTitle", Vector2(306.0, 20.0), Vector2(310.0, 30.0), 22, Hud.GOLD_BRIGHT
	)

	_quest_summary = RichTextLabel.new()
	_quest_summary.name = "QuestSummary"
	_quest_summary.position = Vector2(306.0, 58.0)
	_quest_summary.size = Vector2(310.0, 66.0)
	_quest_summary.bbcode_enabled = true
	_quest_summary.scroll_active = false
	_quest_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quest_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quest_summary.add_theme_font_size_override("normal_font_size", 16)
	_quest_summary.add_theme_color_override("default_color", Hud.TEXT)
	quest_panel.add_child(_quest_summary)

	_quest_objectives = Control.new()
	_quest_objectives.name = "QuestObjectives"
	_quest_objectives.position = Vector2(306.0, 136.0)
	_quest_objectives.size = Vector2(310.0, 140.0)
	_quest_objectives.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quest_panel.add_child(_quest_objectives)

	_quest_reward = RichTextLabel.new()
	_quest_reward.name = "QuestReward"
	_quest_reward.position = Vector2(306.0, 286.0)
	_quest_reward.size = Vector2(310.0, 60.0)
	_quest_reward.bbcode_enabled = true
	_quest_reward.scroll_active = false
	_quest_reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quest_reward.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quest_reward.add_theme_font_size_override("normal_font_size", 16)
	_quest_reward.add_theme_color_override("default_color", Hud.TEXT)
	quest_panel.add_child(_quest_reward)

	var hint := _make_label(
		quest_panel, "CloseHint", Vector2(0.0, 384.0), Vector2(PANEL_WIDTH, 26.0), 16, Hud.MUTED
	)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.text = "按 J 关闭"


# ---------------------------------------------------------------- quest data

func _refresh_quests() -> void:
	_rebuild_quest_list()
	_rebuild_quest_detail()


func _rebuild_quest_list() -> void:
	if _quest_list_root == null:
		return
	_clear_children(_quest_list_root)
	_quest_ids.clear()

	var groups: Array = [
		{"state": "active", "title": "进行中"},
		{"state": "ready", "title": "可交付"},
		{"state": "done", "title": "已完成"},
	]
	var grouped: Array = []
	for group_value in groups:
		var group: Dictionary = group_value
		var ids: Array = Quests.list_by_state(str(group.get("state", "")))
		grouped.append({"group": group, "ids": ids})
		for raw_id in ids:
			_quest_ids.append(str(raw_id))

	if not _quest_ids.has(_selected_quest_id):
		_selected_quest_id = _quest_ids[0] if not _quest_ids.is_empty() else ""

	if _quest_ids.is_empty():
		var empty := _make_label(
			_quest_list_root, "NoQuestsLabel", Vector2(0.0, 8.0), Vector2(250.0, 26.0), 16, Hud.MUTED
		)
		empty.text = "暂无任务"
		return

	var y := 0.0
	for entry_value in grouped:
		var entry: Dictionary = entry_value
		var ids: Array = entry.get("ids", [])
		if ids.is_empty():
			continue
		var group: Dictionary = entry.get("group", {})
		var state := str(group.get("state", ""))
		var header := _make_label(
			_quest_list_root,
			"Group_%s" % state,
			Vector2(0.0, y),
			Vector2(250.0, 24.0),
			16,
			_group_color(state)
		)
		header.text = str(group.get("title", ""))
		y += 26.0
		for raw_id in ids:
			var quest_id := str(raw_id)
			var button := Button.new()
			button.name = "Quest_%s" % quest_id
			button.text = _quest_name(quest_id)
			button.position = Vector2(12.0, y)
			button.size = Vector2(238.0, 26.0)
			button.focus_mode = Control.FOCUS_NONE
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			_style_quest_button(button, quest_id == _selected_quest_id)
			button.pressed.connect(_on_quest_pressed.bind(quest_id))
			_quest_list_root.add_child(button)
			y += 28.0


func _rebuild_quest_detail() -> void:
	_clear_children(_quest_objectives)
	if _selected_quest_id == "":
		_quest_title.text = "暂无任务"
		_quest_summary.text = ""
		_quest_reward.text = ""
		return
	var defs: Dictionary = Quests.load_all()
	var def_value: Variant = defs.get(_selected_quest_id, {})
	var def: Dictionary = {}
	if def_value is Dictionary:
		def = def_value
	_quest_title.text = str(def.get("name", _selected_quest_id))
	_quest_summary.text = str(def.get("summary", ""))

	var progress: Array = Quests.progress(_selected_quest_id)
	for i in range(progress.size()):
		var objective_value: Variant = progress[i]
		if not (objective_value is Dictionary):
			continue
		var objective: Dictionary = objective_value
		var have := int(objective.get("have", 0))
		var need := int(objective.get("need", 0))
		var done := need > 0 and have >= need
		var row := RichTextLabel.new()
		row.name = "ObjectiveRow_%d" % i
		row.position = Vector2(0.0, float(i) * 24.0)
		row.size = Vector2(310.0, 22.0)
		row.bbcode_enabled = true
		row.scroll_active = false
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_font_size_override("normal_font_size", 16)
		row.add_theme_color_override("default_color", Hud.TEXT)
		var text := "%s  %d/%d" % [str(objective.get("text", "")), have, need]
		if done:
			row.text = "[color=#f0c96a]%s ✔[/color]" % text
		else:
			row.text = text
		_quest_objectives.add_child(row)

	_quest_reward.text = _reward_text(def)


func _on_quest_pressed(quest_id: String) -> void:
	_selected_quest_id = quest_id
	_refresh_quests()


func _move_quest_selection(offset: int) -> void:
	if _quest_ids.is_empty():
		return
	var index: int = _quest_ids.find(_selected_quest_id)
	if index < 0:
		index = 0
	index = clampi(index + offset, 0, _quest_ids.size() - 1)
	_selected_quest_id = _quest_ids[index]
	_refresh_quests()


func _quest_name(quest_id: String) -> String:
	var def_value: Variant = Quests.load_all().get(quest_id, {})
	if def_value is Dictionary:
		var def: Dictionary = def_value
		return str(def.get("name", quest_id))
	return quest_id


func _group_color(state: String) -> Color:
	match state:
		"ready":
			return Hud.GOLD_BRIGHT
		"done":
			return Hud.MUTED
		_:
			return Hud.GOLD


func _reward_text(def: Dictionary) -> String:
	var parts: Array = []
	var rewards_value: Variant = def.get("rewards", {})
	if rewards_value is Dictionary:
		var rewards: Dictionary = rewards_value
		var stats_value: Variant = rewards.get("stats", {})
		if stats_value is Dictionary:
			var stats: Dictionary = stats_value
			for key in STAT_KEYS:
				if stats.has(key):
					parts.append("%s %s" % [str(STAT_NAMES.get(key, key)), _signed(int(stats[key]))])
		var items_value: Variant = rewards.get("items", {})
		if items_value is Dictionary:
			var items: Dictionary = items_value
			for item_id in items:
				var item: Dictionary = Progression.item_def(str(item_id))
				parts.append("%s ×%d" % [str(item.get("name", item_id)), int(items[item_id])])
		var exp_value: Variant = rewards.get("mastery_exp", {})
		if exp_value is Dictionary:
			var exp_values: Dictionary = exp_value
			for martial_id in exp_values:
				parts.append("%s 熟练度 +%d" % [
					_martial_name(str(martial_id)), int(exp_values[martial_id])
				])
	if parts.is_empty():
		return "奖励：无"
	return "奖励：" + "、".join(PackedStringArray(parts))


# ---------------------------------------------------------------- helpers

func _martial_def_map() -> Dictionary:
	if _martial_defs.is_empty():
		var loaded: Dictionary = DataLoader.load_martials(MARTIALS_PATH)
		var defs_value: Variant = loaded.get("defs", {})
		if defs_value is Dictionary:
			_martial_defs = defs_value
	return _martial_defs


func _martial_name(martial_id: String) -> String:
	var def_value: Variant = _martial_def_map().get(martial_id, null)
	if def_value != null:
		var name_value: Variant = def_value.get("name")
		if name_value != null:
			return str(name_value)
	return martial_id


func _signed(amount: int) -> String:
	if amount >= 0:
		return "+%d" % amount
	return str(amount)


func _center_panel(panel: Control) -> void:
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -PANEL_WIDTH * 0.5
	panel.offset_right = PANEL_WIDTH * 0.5
	panel.offset_top = -PANEL_HEIGHT * 0.5
	panel.offset_bottom = PANEL_HEIGHT * 0.5


func _make_label(
	parent: Node,
	node_name: String,
	pos: Vector2,
	label_size: Vector2,
	font_size: int,
	color: Color
) -> Label:
	var label := Label.new()
	label.name = node_name
	label.position = pos
	label.size = label_size
	Hud.configure_label(label, font_size, color)
	parent.add_child(label)
	return label


func _style_quest_button(button: Button, selected: bool) -> void:
	if selected:
		button.add_theme_stylebox_override("normal", Hud.card_hover_style())
	else:
		button.add_theme_stylebox_override("normal", Hud.card_style(0.5, Color(0.78, 0.65, 0.35, 0.45)))
	button.add_theme_stylebox_override("hover", Hud.card_hover_style())
	button.add_theme_stylebox_override("pressed", Hud.card_pressed_style())
	button.add_theme_stylebox_override("focus", Hud.card_style(0.5, Color(0.0, 0.0, 0.0, 0.0)))
	button.add_theme_color_override("font_color", Hud.TEXT)
	button.add_theme_color_override("font_hover_color", Hud.GOLD_BRIGHT)
	button.add_theme_color_override("font_pressed_color", Hud.GOLD_BRIGHT)
	button.add_theme_font_size_override("font_size", 16)


func _consume_input() -> void:
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _remove_toast(index: int) -> void:
	if index < 0 or index >= _toasts.size():
		return
	var record: Dictionary = _toasts[index]
	_toasts.remove_at(index)
	var node_value: Variant = record.get("node", null)
	if node_value is Node:
		var node: Node = node_value
		var parent: Node = node.get_parent()
		if parent != null:
			parent.remove_child(node)
		node.queue_free()


func _clear_children(parent: Node) -> void:
	if parent == null:
		return
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

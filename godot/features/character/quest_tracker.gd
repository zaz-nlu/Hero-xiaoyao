extends VBoxContainer

# 屏幕左侧的任务追踪：列出进行中 / 可交付的任务及目标进度，带日期倒计时。
# 每条任务右上角的 × 取消追踪（写入 flag untracked_<id>），底部按钮恢复全部。
# 只读 Quests / Calendar / GameState，数据变化时才重建。

const Calendar = preload("res://core/calendar.gd")
const GameState = preload("res://core/game_state.gd")
const Hud = preload("res://shared/ui/battle_hud_style.gd")
const Quests = preload("res://core/quests.gd")

const WIDTH := 270.0
const MAX_SHOWN := 5
const DONE_COLOR := Color(0.55, 0.85, 0.55)
const FLAG_PREFIX := "untracked_"

var _signature: String = ""


func _init() -> void:
	name = "QuestTracker"
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = 14.0
	offset_right = 14.0 + WIDTH
	offset_top = 64.0
	offset_bottom = 64.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 6)


func _process(_delta: float) -> void:
	var sig := _make_signature()
	if sig == _signature:
		return
	_signature = sig
	rebuild()


func tracked_ids() -> Array:
	var out: Array = []
	for state in ["ready", "active"]:
		for raw_id in Quests.list_by_state(state):
			var id := str(raw_id)
			if not GameState.has_flag(FLAG_PREFIX + id):
				out.append(id)
	return out


func hidden_count() -> int:
	var count := 0
	for state in ["ready", "active"]:
		for raw_id in Quests.list_by_state(state):
			if GameState.has_flag(FLAG_PREFIX + str(raw_id)):
				count += 1
	return count


func set_tracked(id: String, tracked: bool) -> void:
	GameState.set_flag(FLAG_PREFIX + id, not tracked)


func restore_all() -> void:
	for state in ["ready", "active"]:
		for raw_id in Quests.list_by_state(state):
			GameState.set_flag(FLAG_PREFIX + str(raw_id), false)


# 任务的到期提示：未到期返回“还有 N 天”，已到期返回“已到时间”，没有 due 返回空串。
func due_text(def: Dictionary) -> String:
	var due: Variant = def.get("due", null)
	if not (due is Dictionary):
		return ""
	var due_day := int(due.get("day", 0))
	var due_phase := int(due.get("phase", 0))
	var names: Array = Calendar.phase_names()
	var phase_text := str(names[clampi(due_phase, 0, names.size() - 1)])
	var left := Calendar.phases_until(due_day, due_phase)
	var when := "第 %d 天 · %s" % [due_day, phase_text]
	if left <= 0:
		return "%s（已到时间）" % when
	return "%s（还有 %d 个时段）" % [when, left]


func rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var ids := tracked_ids()
	var defs: Dictionary = Quests.load_all()
	var shown := 0
	if not ids.is_empty():
		add_child(_label("任务追踪 [J]", 13, Hud.MUTED))
	for raw_id in ids:
		if shown >= MAX_SHOWN:
			break
		shown += 1
		_add_quest(str(raw_id), defs.get(str(raw_id), {}))
	var hidden := hidden_count()
	if hidden > 0:
		var restore := Button.new()
		restore.name = "RestoreTracking"
		restore.text = "已隐藏 %d 个任务，点击显示" % hidden
		restore.flat = true
		restore.focus_mode = Control.FOCUS_NONE
		restore.alignment = HORIZONTAL_ALIGNMENT_LEFT
		restore.add_theme_font_size_override("font_size", 12)
		restore.add_theme_color_override("font_color", Hud.MUTED)
		restore.add_theme_color_override("font_hover_color", Hud.GOLD_BRIGHT)
		restore.pressed.connect(restore_all)
		add_child(restore)


func _add_quest(id: String, def: Dictionary) -> void:
	var box := PanelContainer.new()
	box.name = "Track_%s" % id
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = Hud.panel_style(0.72, Color(0.78, 0.65, 0.35, 0.4), 4)
	style.content_margin_left = 10.0
	style.content_margin_right = 8.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	box.add_theme_stylebox_override("panel", style)
	add_child(box)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 2)
	box.add_child(column)

	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(head)
	var title := _label(str(def.get("name", id)), 16, Hud.GOLD_BRIGHT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.name = "Untrack_%s" % id
	close.text = "×"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = "取消追踪"
	close.add_theme_color_override("font_color", Hud.MUTED)
	close.add_theme_color_override("font_hover_color", Hud.GOLD_BRIGHT)
	close.pressed.connect(set_tracked.bind(id, false))
	head.add_child(close)

	if Quests.state(id) == "ready":
		column.add_child(_label("✓ 已完成，可去交付", 13, DONE_COLOR))
	else:
		for raw in Quests.progress(id):
			var entry: Dictionary = raw
			var have := int(entry.get("have", 0))
			var need := int(entry.get("need", 0))
			var text := str(entry.get("text", ""))
			if need > 1:
				text += "  %d/%d" % [have, need]
			column.add_child(_label("· " + text, 13, Hud.TEXT))
	var due := due_text(def)
	if due != "":
		column.add_child(_label("⏳ " + due, 13, Hud.GOLD))


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(WIDTH - 40.0, 0.0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Hud.configure_label(label, size, color)
	return label


func _make_signature() -> String:
	var parts := PackedStringArray()
	for id in tracked_ids():
		parts.append("%s:%s:%s" % [id, Quests.state(str(id)), str(GameState.quests.get(id, {}))])
	parts.append("h%d d%d p%d" % [hidden_count(), GameState.day, GameState.phase])
	return "|".join(parts)

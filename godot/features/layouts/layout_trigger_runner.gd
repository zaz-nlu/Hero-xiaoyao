extends RefCounted

# 探索地图的物件触发器运行辅助：把 objects[].trigger 编译成可查询的锚点，
# 负责按键/进入判定、对话播放与正式/试跑的派发方式。
#
# - 按键触发器与 LayoutWalk 原有的最近锚点规则一致：距离 + 地形高度双重门槛。
# - 进入触发器只在“从圈外进入圈内”时触发一次；出生/战斗返回时已在圈内的
#   触发器会被标记为已进入，避免每帧重复或返回立刻重触发。
# - playtest_mode 下对话仍用真实 DialogueView；遭遇/任务/出口只弹确认提示，
#   不调用 Quests、不进入战斗、不切换场景，因此没有存档副作用。
# - 正式模式下退出与遭遇发信号给 app 调度；任务直接调用现有 Quests。

signal message(text: String)
signal encounter_requested(enemy_id: String, count: int)
signal exit_requested(target: String)
signal quest_resolved(quest_id: String, action: String, ok: bool)

const LayoutCatalog = preload("res://core/layouts/layout_catalog.gd")
const LayoutDocument = preload("res://core/layouts/layout_document.gd")
const LayoutTerrain = preload("res://core/layouts/layout_terrain.gd")
const LayoutTriggers = preload("res://core/layouts/layout_triggers.gd")
const Quests = preload("res://core/quests.gd")
const DialogueView = preload("res://shared/ui/dialogue_view.gd")

const TILE_SIZE := 2.0
const CONFIRM_TITLE := "地图试跑"

var playtest_mode: bool = false
var entries: Array = []
var dialogue_view: DialogueView = null

var _ui_parent: Node = null
var _context: Dictionary = {}
var _inside: Dictionary = {}
var _confirm: ConfirmationDialog = null
var _pending_preview := ""


func setup(
	ui_parent: Node,
	document: Dictionary,
	catalog: Dictionary,
	terrain: Dictionary,
	is_playtest: bool,
	trigger_context: Dictionary = {}
) -> void:
	_ui_parent = ui_parent
	playtest_mode = is_playtest
	_context = trigger_context if not trigger_context.is_empty() \
		else LayoutTriggers.new_context()
	entries = _build_entries(document, catalog, terrain)
	_inside.clear()


func entry_count() -> int:
	return entries.size()


# 出生/返回位置已在某个进入圈内时，先记为已进入，等离开再重新武装。
func prime_inside(pos: Vector2, height: float) -> void:
	_inside.clear()
	for entry_value in entries:
		if not (entry_value is Dictionary):
			continue
		var entry: Dictionary = entry_value
		if str(entry.get("activation", "")) != "enter":
			continue
		if _inside_entry(entry, pos, height):
			_inside[str(entry.get("key", ""))] = true


# ---------------------------------------------------------------- 查询

func nearest_interact_trigger(pos: Vector2, height: float) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	for entry_value in entries:
		if not (entry_value is Dictionary):
			continue
		var entry: Dictionary = entry_value
		if str(entry.get("activation", "")) != "interact":
			continue
		if absf(float(entry.get("height", 0.0)) - height) > LayoutTriggers.MAX_HEIGHT_DIFF:
			continue
		var entry_pos: Vector2 = entry.get("pos", Vector2.ZERO)
		var distance := pos.distance_to(entry_pos)
		if distance <= float(entry.get("radius", LayoutTriggers.INTERACT_RADIUS)) \
				and distance < best_distance:
			best = entry
			best_distance = distance
	return best


func prompt_for(pos: Vector2, height: float) -> String:
	var entry := nearest_interact_trigger(pos, height)
	if entry.is_empty():
		return ""
	var display := str(entry.get("name", "?"))
	match str(entry.get("kind", "")):
		"dialogue":
			return "按 E 与 %s 对话" % display
		"encounter":
			return "按 E 迎战：%s" % display
		"exit":
			return "按 E 前往：%s" % display
		"quest":
			return "按 E 处理任务：%s" % display
	return "按 E 互动：%s" % display


func activate_at(pos: Vector2, height: float) -> bool:
	var entry := nearest_interact_trigger(pos, height)
	if entry.is_empty():
		return false
	activate(entry)
	return true


# 每帧在移动后调用；返回本帧触发的条目数量，便于测试与调试。
func update_enter_triggers(pos: Vector2, height: float) -> int:
	var fired := 0
	for entry_value in entries:
		if not (entry_value is Dictionary):
			continue
		var entry: Dictionary = entry_value
		if str(entry.get("activation", "")) != "enter":
			continue
		var key := str(entry.get("key", ""))
		var inside := _inside_entry(entry, pos, height)
		var was_inside := bool(_inside.get(key, false))
		if inside and not was_inside:
			_inside[key] = true
			activate(entry)
			fired += 1
			# 同一帧只派发一个进入触发器：避免重叠感应圈同时开对话/进战斗。
			break
		elif not inside and was_inside:
			_inside.erase(key)
	return fired


func dialogue_active() -> bool:
	return dialogue_view != null and dialogue_view.is_active()


func advance_dialogue() -> void:
	if dialogue_view != null:
		dialogue_view.advance()


# ---------------------------------------------------------------- 派发

func activate(entry: Dictionary) -> void:
	match str(entry.get("kind", "")):
		"dialogue":
			_start_dialogue(str(entry.get("target", "")))
		"encounter":
			_request_encounter(entry)
		"exit":
			_request_exit(str(entry.get("target", "")), entry)
		"quest":
			_run_quest(entry)


func _start_dialogue(target: String) -> void:
	var parsed := LayoutTriggers.dialogue_lines(target, _context)
	var errors_value: Variant = parsed.get("errors", [])
	if errors_value is Array and not (errors_value as Array).is_empty():
		message.emit("对话加载失败：%s" % str((errors_value as Array)[0]))
		return
	var lines_value: Variant = parsed.get("lines", [])
	var lines: Array = lines_value if lines_value is Array else []
	if _ui_parent == null:
		message.emit("[对话] %s" % target)
		return
	if dialogue_view == null:
		dialogue_view = DialogueView.new()
		dialogue_view.name = "DialogueView"
		dialogue_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_ui_parent.add_child(dialogue_view)
		dialogue_view.finished.connect(_on_dialogue_finished)
	dialogue_view.start(lines)


func _request_encounter(entry: Dictionary) -> void:
	var enemy_id := str(entry.get("target", ""))
	var count := int(entry.get("count", LayoutTriggers.DEFAULT_ENCOUNTER_COUNT))
	if playtest_mode:
		_confirm_action(
			"试跑确认：%s进入遭遇 '%s' ×%d？\n（试跑不会进入战斗，也不写存档）" % [
				_activation_label(entry), enemy_id, count,
			],
			"试跑：遭遇 %s ×%d（%s，未进入战斗）" % [
				enemy_id, count, _activation_label(entry),
			]
		)
		return
	encounter_requested.emit(enemy_id, count)


func _request_exit(target: String, entry: Dictionary) -> void:
	var display := str(entry.get("name", target))
	if playtest_mode:
		_confirm_action(
			"试跑确认：%s出口 → '%s'？\n（试跑不会切换场景）" % [
				_activation_label(entry), target,
			],
			"试跑：出口 %s → %s（%s，未切换场景）" % [
				display, target, _activation_label(entry),
			]
		)
		return
	exit_requested.emit(target)


func _run_quest(entry: Dictionary) -> void:
	var quest_id := str(entry.get("target", ""))
	var action := str(entry.get("action", LayoutTriggers.DEFAULT_QUEST_ACTION))
	if playtest_mode:
		var verb := "开始" if action == "start" else "交付"
		_confirm_action(
			"试跑确认：%s%s任务 '%s'？\n（试跑不会修改任务与存档）" % [
				_activation_label(entry), verb, quest_id,
			],
			"试跑：%s任务 %s（%s，未修改状态）" % [
				verb, quest_id, _activation_label(entry),
			]
		)
		return
	var ok := false
	if action == "start":
		ok = Quests.start(quest_id)
	elif action == "turn_in":
		ok = Quests.turn_in(quest_id)
	quest_resolved.emit(quest_id, action, ok)
	var verb := "开始" if action == "start" else "交付"
	if ok:
		message.emit("任务已%s：%s" % [verb, quest_id])
	else:
		message.emit("任务未能%s：%s（当前状态不允许）" % [verb, quest_id])


func _confirm_action(description: String, preview: String) -> void:
	_pending_preview = preview
	if _ui_parent == null or not _ui_parent.is_inside_tree():
		# 无 SceneTree（headless 单测）时直接给出预览，仍不产生副作用。
		message.emit(preview)
		return
	if _confirm == null:
		_confirm = ConfirmationDialog.new()
		_confirm.title = CONFIRM_TITLE
		_confirm.confirmed.connect(_on_confirm_accepted)
		_ui_parent.add_child(_confirm)
	_confirm.dialog_text = description
	_confirm.popup_centered(Vector2i(380, 170))


# ---------------------------------------------------------------- 内部

func _on_confirm_accepted() -> void:
	if _pending_preview != "":
		message.emit(_pending_preview)
	_pending_preview = ""


func _on_dialogue_finished() -> void:
	pass


func _activation_label(entry: Dictionary) -> String:
	return "进入感应圈" if str(entry.get("activation", "")) == "enter" else "按键互动"


func _inside_entry(entry: Dictionary, pos: Vector2, height: float) -> bool:
	if absf(float(entry.get("height", 0.0)) - height) > LayoutTriggers.MAX_HEIGHT_DIFF:
		return false
	var entry_pos: Vector2 = entry.get("pos", Vector2.ZERO)
	var distance := pos.distance_to(entry_pos)
	return distance <= float(entry.get("radius", LayoutTriggers.ENTER_RADIUS))


func _build_entries(
	document: Dictionary, catalog: Dictionary, terrain: Dictionary
) -> Array:
	var result: Array = []
	var objects_value: Variant = document.get("objects", [])
	if not (objects_value is Array):
		return result
	var objects: Array = objects_value
	for i in range(objects.size()):
		var object_value: Variant = objects[i]
		if not (object_value is Dictionary):
			continue
		var object: Dictionary = object_value
		var trigger_value: Variant = object.get("trigger", null)
		if not (trigger_value is Dictionary):
			continue
		var trigger: Dictionary = trigger_value
		var kind := str(trigger.get("kind", ""))
		if not LayoutTriggers.KINDS.has(kind):
			continue
		var target := str(trigger.get("target", ""))
		if target == "":
			continue
		var asset := str(object.get("asset", ""))
		var item := LayoutCatalog.item(catalog, asset)
		if item.is_empty():
			continue
		var cells := LayoutDocument.footprint_cells(
			item, int(object.get("x", 0)), int(object.get("z", 0)), int(object.get("turn", 0))
		)
		var center := Vector2(
			(float(cells.position.x) + float(cells.size.x) * 0.5) * TILE_SIZE,
			(float(cells.position.y) + float(cells.size.y) * 0.5) * TILE_SIZE
		)
		var activation := str(trigger.get("activation", LayoutTriggers.DEFAULT_ACTIVATION))
		if not LayoutTriggers.ACTIVATIONS.has(activation):
			activation = LayoutTriggers.DEFAULT_ACTIVATION
		var display := str(object.get("label", ""))
		if display == "":
			display = str(item.get("name", asset))
		var radius := LayoutTriggers.ENTER_RADIUS if activation == "enter" \
			else LayoutTriggers.INTERACT_RADIUS
		result.append({
			"key": LayoutTriggers.trigger_key(i),
			"index": i,
			"kind": kind,
			"target": target,
			"activation": activation,
			"action": str(trigger.get("action", LayoutTriggers.DEFAULT_QUEST_ACTION)),
			"count": int(trigger.get("count", LayoutTriggers.DEFAULT_ENCOUNTER_COUNT)),
			"pos": center,
			"height": LayoutTerrain.height_at(terrain, center),
			"radius": radius,
			"name": display,
		})
	return result

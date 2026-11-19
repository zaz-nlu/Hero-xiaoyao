extends "res://tests/test_case.gd"

# 物件触发器：结构/枚举/目标校验、旧地图兼容、运行时按键与进入判定、
# 试跑无副作用、正式派发，以及 LayoutWalk 的真实入口。
# 只读写 user:// 临时文件；不修改正式布局与存档。

const LayoutCatalog = preload("res://core/layouts/layout_catalog.gd")
const LayoutDocument = preload("res://core/layouts/layout_document.gd")
const LayoutTriggers = preload("res://core/layouts/layout_triggers.gd")
const LayoutTriggerRunner = preload("res://features/layouts/layout_trigger_runner.gd")
const LayoutWalk = preload("res://features/layouts/layout_walk.gd")
const GameState = preload("res://core/game_state.gd")
const Quests = preload("res://core/quests.gd")

const SAMPLE_PATH := "res://data/layouts/zixia_sect.json"
const FIXTURE_PATH := "res://tests/fixtures/layout_training_yard.json"
const TEMP_PATH := "user://test_layout_triggers.json"
const TEMP_ENTER_PATH := "user://test_layout_triggers_enter.json"

const DISCIPLE_CENTER := Vector2(11.0, 13.0)


func _catalog() -> Dictionary:
	return LayoutCatalog.load_catalog()


func _fixture_document() -> Dictionary:
	var loaded := LayoutDocument.load_document(FIXTURE_PATH)
	var value: Variant = loaded.get("document", {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _doc_with_raw_trigger(raw: Variant) -> Dictionary:
	var doc := _fixture_document()
	for object_value in doc.get("objects", []):
		if not (object_value is Dictionary):
			continue
		var object: Dictionary = object_value
		if str(object.get("asset", "")) == "disciple":
			object["trigger"] = raw
			break
	return doc


func _doc_with_trigger(trigger: Dictionary) -> Dictionary:
	return _doc_with_raw_trigger(trigger.duplicate(true))


func _validate(document: Dictionary) -> Array[String]:
	return LayoutDocument.validate_document(
		document, _catalog(), LayoutTriggers.new_context()
	)


func _has_error(errors: Array, needle: String) -> bool:
	for message in errors:
		if str(message).contains(needle):
			return true
	return false


func _runner(
	document: Dictionary, playtest: bool, parent: Node = null
) -> LayoutTriggerRunner:
	var runner := LayoutTriggerRunner.new()
	runner.setup(parent, document, _catalog(), {}, playtest)
	return runner


func _remove_user_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# ---------------------------------------------------------------- 校验


func test_legacy_layouts_pass_without_triggers() -> void:
	var sample := LayoutDocument.load_document(SAMPLE_PATH)
	assert_true(bool(sample.get("ok", false)), "旧地图应继续通过：%s" % str(sample.get("errors", [])))
	var fixture := LayoutDocument.load_document(FIXTURE_PATH)
	assert_true(bool(fixture.get("ok", false)), "测试布局应继续通过")
	var doc: Dictionary = fixture.get("document", {})
	for object_value in doc.get("objects", []):
		var object: Dictionary = object_value
		assert_true(not object.has("trigger"), "旧对象不应被自动补 trigger")


func test_valid_trigger_kinds_and_defaults() -> void:
	var cases: Array = [
		{"kind": "dialogue", "target": "npc_disciple", "activation": "interact"},
		{"kind": "encounter", "target": "bandit", "count": 2},
		{"kind": "exit", "target": "town"},
		{"kind": "exit", "target": "zixia_sect", "activation": "enter"},
		{"kind": "quest", "target": "herbs", "action": "start"},
		{"kind": "quest", "target": "herbs", "action": "turn_in"},
	]
	for trigger_case in cases:
		var trigger: Dictionary = trigger_case
		var errors := _validate(_doc_with_trigger(trigger))
		assert_eq(errors.size(), 0, "触发器应通过 %s：%s" % [str(trigger), str(errors)])


func test_invalid_triggers_report_errors() -> void:
	var bad_structure := _doc_with_raw_trigger("dialogue")
	assert_true(_has_error(_validate(bad_structure), "must be an object"),
		"非对象 trigger 应拒绝")

	var bad_kind := _doc_with_trigger({"kind": "move", "target": "town"})
	assert_true(_has_error(_validate(bad_kind), "kind must be one of"), "未知类型应拒绝")

	var bad_activation := _doc_with_trigger(
		{"kind": "exit", "target": "town", "activation": "touch"}
	)
	assert_true(_has_error(_validate(bad_activation), "activation must be"), "未知触发方式应拒绝")

	var missing_target := _doc_with_trigger({"kind": "exit"})
	assert_true(_has_error(_validate(missing_target), "target is required"), "缺少目标应拒绝")

	var path_target := _doc_with_trigger(
		{"kind": "exit", "target": "res://data/layouts/zixia_sect.json"}
	)
	assert_true(_has_error(_validate(path_target), "invalid target"), "目标不能是自由路径")

	var unknown_dialogue := _doc_with_trigger(
		{"kind": "dialogue", "target": "no_such_dialogue"}
	)
	assert_true(_has_error(_validate(unknown_dialogue), "dialogue"), "未知对话应拒绝")

	var unknown_enemy := _doc_with_trigger({"kind": "encounter", "target": "no_such_enemy"})
	assert_true(_has_error(_validate(unknown_enemy), "does not exist"), "未知遭遇目标应拒绝")

	var bad_count := _doc_with_trigger(
		{"kind": "encounter", "target": "bandit", "count": 9}
	)
	assert_true(_has_error(_validate(bad_count), "count must be"), "数量越界应拒绝")

	var unknown_exit := _doc_with_trigger({"kind": "exit", "target": "no_such_layout"})
	assert_true(_has_error(_validate(unknown_exit), "exit target"), "未知出口应拒绝")

	var unknown_quest := _doc_with_trigger(
		{"kind": "quest", "target": "no_such_quest", "action": "start"}
	)
	assert_true(_has_error(_validate(unknown_quest), "quest"), "未知任务应拒绝")

	var bad_action := _doc_with_trigger(
		{"kind": "quest", "target": "herbs", "action": "abandon"}
	)
	assert_true(_has_error(_validate(bad_action), "action must be"), "未知任务动作应拒绝")


func test_target_browser_exposes_existing_content() -> void:
	var context := LayoutTriggers.new_context()
	assert_true(_has_id(LayoutTriggers.targets("dialogue", context), "npc_disciple"),
		"对话目标应列出现有对话文件")
	assert_true(_has_id(LayoutTriggers.targets("encounter", context), "bandit"),
		"遭遇目标应列出敌人")
	assert_true(_has_id(LayoutTriggers.targets("exit", context), "town"),
		"出口应列出小镇路由")
	assert_true(_has_id(LayoutTriggers.targets("exit", context), "zixia_sect"),
		"出口应列出已有布局")
	assert_true(_has_id(LayoutTriggers.targets("quest", context), "herbs"),
		"任务目标应列出任务")


func _has_id(entries: Array[Dictionary], wanted: String) -> bool:
	for entry in entries:
		if str(entry.get("id", "")) == wanted:
			return true
	return false


func test_same_asset_instances_keep_independent_triggers() -> void:
	var doc := _fixture_document()
	(doc.get("objects", []) as Array).append({
		"asset": "disciple", "x": 1, "z": 4, "turn": 0, "label": "另一个弟子",
	})
	var objects: Array = doc.get("objects", [])
	var first: Dictionary = objects[4]
	var second: Dictionary = objects[objects.size() - 1]
	first["trigger"] = {"kind": "dialogue", "target": "npc_disciple"}
	var errors := _validate(doc)
	assert_eq(errors.size(), 0, "同素材不同实例应独立：%s" % str(errors))
	assert_true(second.has("trigger") == false, "新实例不能继承另一实例的触发器")


# ---------------------------------------------------------------- 运行时


func test_interact_trigger_respects_radius_and_height() -> void:
	var doc := _doc_with_trigger({"kind": "dialogue", "target": "npc_disciple"})
	var runner = _runner(doc, true)
	assert_eq(int(runner.entry_count()), 1, "应编译出一个触发器")
	assert_eq(str(runner.nearest_interact_trigger(DISCIPLE_CENTER, 0.0).get("kind", "")),
		"dialogue", "圈内应选中对话触发器")
	var inside_edge: Dictionary = runner.nearest_interact_trigger(
		DISCIPLE_CENTER + Vector2(2.5, 0.0), 0.0
	)
	assert_true(not inside_edge.is_empty(), "半径内仍可互动")
	var outside_edge: Dictionary = runner.nearest_interact_trigger(
		DISCIPLE_CENTER + Vector2(2.8, 0.0), 0.0
	)
	assert_true(outside_edge.is_empty(), "越过触发边缘后不能互动")
	var wrong_height: Dictionary = runner.nearest_interact_trigger(DISCIPLE_CENTER, 1.0)
	assert_true(wrong_height.is_empty(), "高差超过门槛时不能互动")


func test_enter_trigger_fires_once_and_rearms() -> void:
	var doc := _doc_with_trigger({
		"kind": "encounter", "target": "bandit", "count": 2, "activation": "enter",
	})
	var runner = _runner(doc, false)
	var events: Array = []
	runner.encounter_requested.connect(
		func(enemy_id: String, count: int) -> void: events.append([enemy_id, count])
	)
	var outside := DISCIPLE_CENTER + Vector2(0.0, 4.0)
	assert_eq(int(runner.update_enter_triggers(outside, 0.0)), 0, "圈外不触发")
	assert_eq(int(runner.update_enter_triggers(DISCIPLE_CENTER, 0.0)), 1, "进入圈内触发一次")
	assert_eq(int(runner.update_enter_triggers(DISCIPLE_CENTER, 0.0)), 0, "每帧不重复触发")
	assert_eq(events.size(), 1)
	assert_eq(events[0], ["bandit", 2])
	runner.update_enter_triggers(outside, 0.0)
	assert_eq(int(runner.update_enter_triggers(DISCIPLE_CENTER, 0.0)), 1, "离开后可重新进入")
	assert_eq(events.size(), 2)


func test_enter_trigger_is_primed_inside_at_spawn() -> void:
	var doc := _doc_with_trigger({
		"kind": "encounter", "target": "bandit", "activation": "enter",
	})
	var runner = _runner(doc, false)
	runner.prime_inside(DISCIPLE_CENTER, 0.0)
	assert_eq(int(runner.update_enter_triggers(DISCIPLE_CENTER, 0.0)), 0,
		"出生/返回已在圈内时不能立即触发")
	assert_eq(int(runner.update_enter_triggers(DISCIPLE_CENTER + Vector2(0.0, 4.0), 0.0)), 0)
	assert_eq(int(runner.update_enter_triggers(DISCIPLE_CENTER, 0.0)), 1,
		"离开后再次进入应触发")


func test_playtest_triggers_have_no_side_effects() -> void:
	GameState.reset()
	Quests.reload()
	var doc := _doc_with_trigger({"kind": "quest", "target": "herbs", "action": "start"})
	var runner = _runner(doc, true)
	var messages: Array = []
	runner.message.connect(func(text: String) -> void: messages.append(text))
	assert_true(bool(runner.activate_at(DISCIPLE_CENTER, 0.0)), "试跑也应响应按键")
	assert_eq(Quests.state("herbs"), "none", "试跑不能启动任务")
	assert_true(not GameState.quests.has("herbs"), "试跑不能写任务状态")
	assert_true(not messages.is_empty(), "试跑应给出确认/预览提示")
	GameState.reset()


func test_formal_trigger_dispatch() -> void:
	GameState.reset()
	Quests.reload()
	var encounter_doc := _doc_with_trigger({"kind": "encounter", "target": "bandit", "count": 2})
	var encounter_runner = _runner(encounter_doc, false)
	var encounters: Array = []
	encounter_runner.encounter_requested.connect(
		func(enemy_id: String, count: int) -> void: encounters.append([enemy_id, count])
	)
	assert_true(bool(encounter_runner.activate_at(DISCIPLE_CENTER, 0.0)))
	assert_eq(encounters, [["bandit", 2]], "正式遭遇应发到 app 处理器")

	var exit_doc := _doc_with_trigger({"kind": "exit", "target": "town"})
	var exit_runner = _runner(exit_doc, false)
	var exits: Array = []
	exit_runner.exit_requested.connect(func(target: String) -> void: exits.append(target))
	assert_true(bool(exit_runner.activate_at(DISCIPLE_CENTER, 0.0)))
	assert_eq(exits, ["town"], "正式出口应发到路由处理器")

	var quest_doc := _doc_with_trigger(
		{"kind": "quest", "target": "herbs", "action": "start"}
	)
	var quest_runner = _runner(quest_doc, false)
	var resolved: Array = []
	quest_runner.quest_resolved.connect(
		func(quest_id: String, action: String, ok: bool) -> void:
			resolved.append([quest_id, action, ok])
	)
	assert_true(bool(quest_runner.activate_at(DISCIPLE_CENTER, 0.0)))
	assert_eq(Quests.state("herbs"), "active", "正式任务调用现有 Quests.start")
	assert_eq(resolved, [["herbs", "start", true]], "任务结果应回传给调用方")
	GameState.reset()


func test_formal_dialogue_uses_real_dialogue_view() -> void:
	var doc := _doc_with_trigger({"kind": "dialogue", "target": "npc_disciple"})
	var parent := Node.new()
	var runner = _runner(doc, false, parent)
	assert_true(bool(runner.activate_at(DISCIPLE_CENTER, 0.0)))
	assert_true(bool(runner.dialogue_active()), "真实对话应开始播放")
	for i in range(80):
		if not bool(runner.dialogue_active()):
			break
		runner.advance_dialogue()
	assert_true(not bool(runner.dialogue_active()), "推进到底后对话应结束")
	parent.free()


# ---------------------------------------------------------------- 场景入口


func test_layout_walk_wires_trigger_runner() -> void:
	_remove_user_file(TEMP_PATH)
	var doc := _doc_with_trigger({"kind": "dialogue", "target": "npc_disciple"})
	var saved := LayoutDocument.save_document(TEMP_PATH, doc, _catalog())
	assert_true(bool(saved.get("ok", false)), "临时布局应能保存：%s" % str(saved.get("errors", [])))

	var walk := LayoutWalk.new()
	walk.map_path = TEMP_PATH
	walk.build()
	assert_true(walk.trigger_runner != null, "LayoutWalk 应建立触发器运行时")
	assert_eq(int(walk.trigger_runner.entry_count()), 1)
	walk.player_pos = DISCIPLE_CENTER
	walk.player_height = 0.0
	assert_true(walk.try_interact(), "E 应优先触发物件触发器")
	assert_true(walk.is_dialogue_active(), "对话应通过现有 DialogueView 播放")
	for i in range(80):
		if not walk.is_dialogue_active():
			break
		walk.trigger_runner.advance_dialogue()
	walk.free()
	_remove_user_file(TEMP_PATH)


func test_layout_walk_return_position_primes_enter_trigger() -> void:
	_remove_user_file(TEMP_ENTER_PATH)
	var doc := _doc_with_trigger({
		"kind": "dialogue", "target": "npc_disciple", "activation": "enter",
	})
	var saved := LayoutDocument.save_document(TEMP_ENTER_PATH, doc, _catalog())
	assert_true(bool(saved.get("ok", false)), "进入圈布局应能保存：%s" % str(saved.get("errors", [])))

	var walk := LayoutWalk.new()
	walk.map_path = TEMP_ENTER_PATH
	var return_pos := Vector2(11.0, 15.5)
	walk.return_position = return_pos
	walk.build()
	assert_eq(walk.player_pos, return_pos, "合法返回位置应保留")
	assert_eq(
		int(walk.trigger_runner.update_enter_triggers(walk.player_pos, walk.player_height)), 0,
		"返回时已在圈内不能立即重触发"
	)
	walk.trigger_runner.update_enter_triggers(Vector2(11.0, 20.0), 0.0)
	assert_eq(
		int(walk.trigger_runner.update_enter_triggers(DISCIPLE_CENTER, 0.0)), 1,
		"离开后再次进入应触发"
	)
	walk.free()
	_remove_user_file(TEMP_ENTER_PATH)

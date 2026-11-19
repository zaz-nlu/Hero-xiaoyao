@tool
extends RefCounted

# 探索地图物件触发器（objects[].trigger）的定义、校验、目标浏览与数据读取。
#
# 数据格式（每个对象实例可选，互不继承）：
#   "trigger": {
#     "kind": "dialogue" | "encounter" | "exit" | "quest",
#     "target": "内容 ID",
#     "activation": "interact" | "enter",   # 缺省 interact
#     "action": "start" | "turn_in",        # 仅 quest，缺省 start
#     "count": 1..5                          # 仅 encounter，缺省 1
#   }
#
# 目标约束（禁止自由路径）：
#   dialogue  res://data/dialogues/<target>.json 的文件 ID，按现有 Dialogue 解析
#   encounter data/enemies.json 中的敌人 ID，数量 1..5
#   exit      town / tavern / forest，或已存在的 data/layouts/<target>.json ID
#   quest     data/quests.json 中的任务 ID
#
# 校验只读数据，不写 GameState，也不回写文档。所有 loader 共用调用方传入的
# context；一次校验内同一份数据只读一次，编辑器可以长期持有这个 context。
#
# 公开 API：
#   LayoutTriggers.new_context() -> Dictionary
#   LayoutTriggers.validate(document: Variant, context: Dictionary = {}) -> Array[String]
#   LayoutTriggers.targets(kind: String, context: Dictionary) -> Array[Dictionary]
#   LayoutTriggers.dialogue_lines(target: String, context: Dictionary) -> Dictionary
#   LayoutTriggers.layout_path(id: String) -> String
#   LayoutTriggers.exit_target_valid(target: String) -> bool
#   LayoutTriggers.trigger_key(object_index: int) -> String

const DataLoader = preload("res://core/data_loader.gd")
const Dialogue = preload("res://core/dialogue.gd")
const Quests = preload("res://core/quests.gd")
const LayoutIds = preload("res://core/layouts/layout_ids.gd")

const KINDS: Array[String] = ["dialogue", "encounter", "exit", "quest"]
const ACTIVATIONS: Array[String] = ["interact", "enter"]
const QUEST_ACTIONS: Array[String] = ["start", "turn_in"]
const ROUTE_TARGETS: Array[String] = ["town", "tavern", "forest"]
const ROUTE_LABELS := {"town": "紫霞镇", "tavern": "酒馆", "forest": "紫霞林"}

const DIALOGUE_DIR := "res://data/dialogues"
const LAYOUT_DIR := "res://data/layouts"
const DIALOGUE_PATH_TEMPLATE := "res://data/dialogues/%s.json"
const LAYOUT_PATH_TEMPLATE := "res://data/layouts/%s.json"

const DEFAULT_ACTIVATION := "interact"
const DEFAULT_QUEST_ACTION := "start"
const DEFAULT_ENCOUNTER_COUNT := 1
const MAX_ENCOUNTER_COUNT := 5

# 运行时固定互动范围与高差门槛；与 LayoutWalk 原有的 2.6 互动半径一致。
const INTERACT_RADIUS := 2.6
const ENTER_RADIUS := 2.6
const MAX_HEIGHT_DIFF := 0.75


static func new_context() -> Dictionary:
	return {
		"loaded": false,
		"speakers": {},
		"enemies": {},
		"quests": {},
		"layout_ids": {},
		"dialogues": {},
	}


# context 为调用方长期持有的缓存；空字典时本次调用自建，不跨调用复用。
static func ensure_loaded(context: Dictionary) -> Dictionary:
	if context.is_empty():
		context = new_context()
	if bool(context.get("loaded", false)):
		return context
	context["loaded"] = true

	var speakers := Dialogue.load_speakers(DataLoader.SPEAKERS_PATH)
	var speaker_defs: Variant = speakers.get("defs", {})
	context["speakers"] = speaker_defs if speaker_defs is Dictionary else {}

	var enemies := DataLoader.load_enemies(DataLoader.ENEMIES_PATH)
	var enemy_defs: Variant = enemies.get("defs", {})
	context["enemies"] = enemy_defs if enemy_defs is Dictionary else {}

	context["quests"] = Quests.load_all()
	context["layout_ids"] = _list_ids(LAYOUT_DIR)
	return context


# ---------------------------------------------------------------- 校验

static func validate(document: Variant, context: Dictionary = {}) -> Array[String]:
	var errors: Array[String] = []
	if not (document is Dictionary):
		return errors
	var doc: Dictionary = document
	var raw_objects: Variant = doc.get("objects", [])
	if not (raw_objects is Array):
		# objects 结构错误由 LayoutDocument 自己报告，这里不重复。
		return errors
	var objects: Array = raw_objects
	var has_trigger := false
	for candidate_object in objects:
		if candidate_object is Dictionary and (candidate_object as Dictionary).has("trigger"):
			has_trigger = true
			break
	# 旧地图完全没有 trigger 时不加载任何目标数据。
	if not has_trigger:
		return errors
	var loaded_context := ensure_loaded(context)
	for i in range(objects.size()):
		var object_value: Variant = objects[i]
		if not (object_value is Dictionary):
			continue
		var object: Dictionary = object_value
		if not object.has("trigger"):
			continue
		var where := "objects[%d] '%s' trigger" % [i, str(object.get("asset", ""))]
		var trigger_errors := _validate_trigger(object["trigger"], where, loaded_context)
		for message in trigger_errors:
			errors.append(str(message))
	return errors


static func _validate_trigger(raw: Variant, where: String, context: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not (raw is Dictionary):
		errors.append("%s: must be an object" % where)
		return errors
	var trigger: Dictionary = raw

	var kind := str(trigger.get("kind", ""))
	if not KINDS.has(kind):
		errors.append(
			"%s: kind must be one of %s" % [where, ", ".join(PackedStringArray(KINDS))]
		)
		return errors

	var activation := str(trigger.get("activation", DEFAULT_ACTIVATION))
	if not ACTIVATIONS.has(activation):
		errors.append(
			"%s: activation must be %s" % [
				where, " or ".join(PackedStringArray(ACTIVATIONS))
			]
		)

	var target := str(trigger.get("target", "")).strip_edges()
	if target == "":
		errors.append("%s: target is required" % where)
		return errors
	if not LayoutIds.valid_id(target):
		errors.append(
			"%s: invalid target '%s' (use lowercase letters, digits and _)" % [where, target]
		)
		return errors

	match kind:
		"dialogue":
			_validate_dialogue(target, where, context, errors)
		"encounter":
			_validate_encounter(trigger, target, where, context, errors)
		"exit":
			if not exit_target_valid(target):
				errors.append(
					"%s: exit target '%s' must be town/tavern/forest or an existing layout id"
					% [where, target]
				)
		"quest":
			_validate_quest(trigger, target, where, context, errors)
	return errors


static func _validate_dialogue(
	target: String, where: String, context: Dictionary, errors: Array[String]
) -> void:
	var path := DIALOGUE_PATH_TEMPLATE % target
	if not FileAccess.file_exists(path):
		errors.append("%s: dialogue '%s' not found in %s" % [where, target, DIALOGUE_DIR])
		return
	var parsed := dialogue_lines(target, context)
	var parse_errors: Variant = parsed.get("errors", [])
	if parse_errors is Array and not (parse_errors as Array).is_empty():
		var parse_list: Array = parse_errors
		for message in parse_list:
			errors.append("%s: %s" % [where, str(message)])


static func _validate_encounter(
	trigger: Dictionary, target: String, where: String, context: Dictionary, errors: Array[String]
) -> void:
	var enemies: Dictionary = context.get("enemies", {})
	if not enemies.has(target):
		errors.append("%s: encounter enemy '%s' does not exist" % [where, target])
	if trigger.has("count"):
		var count_value: Variant = trigger["count"]
		if not _is_int(count_value) or int(count_value) < 1 \
				or int(count_value) > MAX_ENCOUNTER_COUNT:
			errors.append(
				"%s: count must be an integer 1..%d" % [where, MAX_ENCOUNTER_COUNT]
			)


static func _validate_quest(
	trigger: Dictionary, target: String, where: String, context: Dictionary, errors: Array[String]
) -> void:
	var action := str(trigger.get("action", DEFAULT_QUEST_ACTION))
	if not QUEST_ACTIONS.has(action):
		errors.append(
			"%s: action must be %s" % [
				where, " or ".join(PackedStringArray(QUEST_ACTIONS))
			]
		)
	var quests: Dictionary = context.get("quests", {})
	if not quests.has(target):
		errors.append("%s: quest '%s' does not exist" % [where, target])


# ---------------------------------------------------------------- 目标浏览

static func targets(kind: String, context: Dictionary) -> Array[Dictionary]:
	var loaded_context := ensure_loaded(context)
	var result: Array[Dictionary] = []
	match kind:
		"dialogue":
			var dialogue_ids := _list_ids(DIALOGUE_DIR)
			for raw_id in dialogue_ids.keys():
				var dialogue_id := str(raw_id)
				result.append({"id": dialogue_id, "name": dialogue_id})
		"encounter":
			var enemies: Dictionary = loaded_context.get("enemies", {})
			for raw_id in enemies.keys():
				var enemy_id := str(raw_id)
				var def: Variant = enemies[raw_id]
				var label := enemy_id
				if def != null and def is Object:
					var name_value: Variant = (def as Object).get("name")
					if name_value != null and str(name_value) != "":
						label = str(name_value)
				result.append({"id": enemy_id, "name": label})
		"exit":
			for route_id in ROUTE_TARGETS:
				result.append({"id": route_id, "name": str(ROUTE_LABELS.get(route_id, route_id))})
			var layouts: Dictionary = loaded_context.get("layout_ids", {})
			for raw_id in layouts.keys():
				var layout_id := str(raw_id)
				result.append({"id": layout_id, "name": layout_id})
		"quest":
			var quests: Dictionary = loaded_context.get("quests", {})
			for raw_id in quests.keys():
				var quest_id := str(raw_id)
				var quest_def: Variant = quests[raw_id]
				var quest_label := quest_id
				if quest_def is Dictionary:
					quest_label = str((quest_def as Dictionary).get("name", quest_id))
				result.append({"id": quest_id, "name": quest_label})
	# 稳定按 ID 排序，避免下拉列表顺序随字典顺序跳动。
	var sorted: Array[Dictionary] = []
	while not result.is_empty():
		var best_index := 0
		for i in range(1, result.size()):
			if str(result[i].get("id", "")) < str(result[best_index].get("id", "")):
				best_index = i
		sorted.append(result[best_index])
		result.remove_at(best_index)
	return sorted


static func dialogue_lines(target: String, context: Dictionary) -> Dictionary:
	var loaded_context := ensure_loaded(context)
	var cache: Dictionary = loaded_context.get("dialogues", {})
	if cache.has(target):
		return cache[target]
	var result := {"lines": [], "errors": []}
	var path := DIALOGUE_PATH_TEMPLATE % target
	if not LayoutIds.valid_id(target) or not FileAccess.file_exists(path):
		result["errors"] = ["dialogue '%s' not found" % target]
		cache[target] = result
		loaded_context["dialogues"] = cache
		return result
	var speakers: Dictionary = loaded_context.get("speakers", {})
	var parsed := Dialogue.load_file(path, speakers)
	var lines_value: Variant = parsed.get("lines", [])
	var errors_value: Variant = parsed.get("errors", [])
	result["lines"] = lines_value if lines_value is Array else []
	result["errors"] = errors_value if errors_value is Array else []
	cache[target] = result
	loaded_context["dialogues"] = cache
	return result


# ---------------------------------------------------------------- 目标与路由

static func layout_path(id: String) -> String:
	if not LayoutIds.valid_id(id):
		return ""
	var path := LAYOUT_PATH_TEMPLATE % id
	if not FileAccess.file_exists(path):
		return ""
	return path


static func exit_target_valid(target: String) -> bool:
	if ROUTE_TARGETS.has(target):
		return true
	return layout_path(target) != ""


static func trigger_key(object_index: int) -> String:
	return "trigger:%d" % object_index


# ---------------------------------------------------------------- 内部

static func _list_ids(dir_path: String) -> Dictionary:
	var ids: Dictionary = {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return ids
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var id := file_name.get_basename()
			if LayoutIds.valid_id(id):
				ids[id] = true
		file_name = dir.get_next()
	dir.list_dir_end()
	return ids


static func _is_int(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) == TYPE_FLOAT:
		var number: float = value
		return is_finite(number) and is_equal_approx(number, roundf(number))
	return false

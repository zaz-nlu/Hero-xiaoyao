extends RefCounted

const Quests = preload("res://core/quests.gd")


# 该 NPC 是否是任意任务的任务发布者。
static func has_quests(npc_id: String) -> bool:
	var defs: Dictionary = Quests.load_all()
	for raw_id in defs.keys():
		var def_value: Variant = defs[raw_id]
		if not (def_value is Dictionary):
			continue
		var def: Dictionary = def_value
		if str(def.get("giver", "")) == npc_id:
			return true
	return false


# 按 quests.json 的顺序挑出该 NPC 当前该播的对话，并给出对话结束后的动作。
# `after.kind` 为 start / turn_in / encounter / talk / none；start、turn_in、
# encounter、talk 会带 "quest" 字段，encounter 另带 "encounter" 字典，
# talk 另带 "key"（目标 NPC id）。
static func pick(npc_id: String, fallback_file: String) -> Dictionary:
	# 进行中的“捎话”目标优先于普通对话（没有谁同时是 giver 又是 talk 目标）。
	var talk := _pick_talk(npc_id)
	if not talk.is_empty():
		return talk
	var defs: Dictionary = Quests.load_all()
	for raw_id in defs.keys():
		var def_value: Variant = defs[raw_id]
		if not (def_value is Dictionary):
			continue
		var id := str(raw_id)
		var def: Dictionary = def_value
		if str(def.get("giver", "")) != npc_id:
			continue
		if not _requires_met(def):
			continue
		var kind := "none"
		var stage := ""
		match Quests.state(id):
			"none":
				stage = "offer"
				kind = "start"
			"active":
				stage = "active"
				if def.has("active_encounter"):
					kind = "encounter"
			"ready":
				stage = "ready"
				kind = "turn_in"
			_:
				continue
		var path := _dialogue_path(def, stage)
		if path == "" or not FileAccess.file_exists(path):
			push_warning("quest_flow: missing dialogue file '%s' for quest '%s'" % [path, id])
			return {"file": fallback_file, "after": {"kind": "none"}}
		var after := {"kind": kind}
		if kind != "none":
			after["quest"] = id
		if kind == "encounter":
			after["encounter"] = _encounter_of(def)
		return {"file": path, "after": after}
	return {"file": fallback_file, "after": {"kind": "none"}}


# 头顶标记："!" 可接、"?" 可交付、"…" 进行中、"" 无事可做。
static func marker(npc_id: String) -> String:
	var defs: Dictionary = Quests.load_all()
	var available := false
	var ready := false
	var active := false
	for raw_id in defs.keys():
		var def_value: Variant = defs[raw_id]
		if not (def_value is Dictionary):
			continue
		var def: Dictionary = def_value
		if str(def.get("giver", "")) != npc_id:
			continue
		if not _requires_met(def):
			continue
		match Quests.state(str(raw_id)):
			"none":
				available = true
			"ready":
				ready = true
			"active":
				active = true
	if available:
		return "!"
	if ready:
		return "?"
	if active:
		return "…"
	return ""


static func _requires_met(def: Dictionary) -> bool:
	var required := str(def.get("requires", ""))
	if required == "":
		return true
	return Quests.state(required) == "done"


# 进行中的 talk 目标：当前交互对象就是目标 NPC 时，播放 quest 的捎话对话。
static func _pick_talk(npc_id: String) -> Dictionary:
	var defs: Dictionary = Quests.load_all()
	for raw_id in defs.keys():
		var id := str(raw_id)
		if Quests.state(id) != "active":
			continue
		var def_value: Variant = defs[raw_id]
		if not (def_value is Dictionary):
			continue
		var def: Dictionary = def_value
		if not _requires_met(def):
			continue
		var objectives_value: Variant = def.get("objectives", [])
		if not (objectives_value is Array):
			continue
		var objectives: Array = objectives_value
		var matched := false
		for objective_value in objectives:
			if not (objective_value is Dictionary):
				continue
			var objective: Dictionary = objective_value
			if str(objective.get("kind", "")) != "talk":
				continue
			if str(objective.get("key", "")) != npc_id:
				continue
			matched = true
			break
		if not matched:
			continue
		var path := ""
		var talk_value: Variant = def.get("talk_dialogues", {})
		if talk_value is Dictionary:
			var talk: Dictionary = talk_value
			path = str(talk.get(npc_id, ""))
		if path == "" or not FileAccess.file_exists(path):
			push_warning(
				"quest_flow: missing talk dialogue '%s' for quest '%s'" % [path, id]
			)
			return {}
		return {"file": path, "after": {"kind": "talk", "quest": id, "key": npc_id}}
	return {}


static func _dialogue_path(def: Dictionary, stage: String) -> String:
	var dialogue_value: Variant = def.get("dialogue", {})
	if not (dialogue_value is Dictionary):
		return ""
	var dialogue: Dictionary = dialogue_value
	return str(dialogue.get(stage, ""))


static func _encounter_of(def: Dictionary) -> Dictionary:
	var encounter_value: Variant = def.get("active_encounter", {})
	if not (encounter_value is Dictionary):
		return {"enemy": "", "count": 1, "first_strike": false}
	var encounter: Dictionary = encounter_value
	return {
		"enemy": str(encounter.get("enemy", "")),
		"count": int(encounter.get("count", 1)),
		"first_strike": bool(encounter.get("first_strike", false)),
	}

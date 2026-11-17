extends RefCounted

const MoveTypes = preload("res://core/move_types.gd")
const Realms = preload("res://core/realms.gd")
const Stats = preload("res://core/stats.gd")
const MartialDef = preload("res://core/martial_def.gd")
const EnemyDef = preload("res://core/enemy_def.gd")

const MARTIAL_GRADES: Array[String] = ["common", "fine", "rare", "epic", "legendary"]


static func parse_martials(json_text: String) -> Dictionary:
	var defs := {}
	var errors: Array[String] = []
	var parsed = JSON.parse_string(json_text)
	if parsed == null:
		errors.append("martials: invalid JSON")
		return {"defs": defs, "errors": errors}
	if not (parsed is Array):
		errors.append("martials: top-level JSON must be an array")
		return {"defs": defs, "errors": errors}

	for i in range(parsed.size()):
		var item = parsed[i]
		if not (item is Dictionary):
			errors.append("martials[%d]: entry must be an object" % i)
			continue
		var def: Variant = MartialDef.from_dict(item)
		var def_id: String = def.id
		if def_id == "":
			errors.append("martials[%d]: missing id" % i)
			continue
		var item_errors := _validate_martial(def)
		if item_errors.is_empty():
			defs[def_id] = def
		else:
			errors.append_array(item_errors)
	return {"defs": defs, "errors": errors}


static func parse_enemies(json_text: String) -> Dictionary:
	var defs := {}
	var errors: Array[String] = []
	var parsed = JSON.parse_string(json_text)
	if parsed == null:
		errors.append("enemies: invalid JSON")
		return {"defs": defs, "errors": errors}
	if not (parsed is Array):
		errors.append("enemies: top-level JSON must be an array")
		return {"defs": defs, "errors": errors}

	for i in range(parsed.size()):
		var item = parsed[i]
		if not (item is Dictionary):
			errors.append("enemies[%d]: entry must be an object" % i)
			continue
		var def: Variant = EnemyDef.from_dict(item)
		var def_id: String = def.id
		if def_id == "":
			errors.append("enemies[%d]: missing id" % i)
			continue
		var item_errors := _validate_enemy(def)
		if item_errors.is_empty():
			defs[def_id] = def
		else:
			errors.append_array(item_errors)
	return {"defs": defs, "errors": errors}


static func load_martials(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		return {"defs": {}, "errors": ["cannot read %s" % path]}
	return parse_martials(text)


static func load_enemies(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		return {"defs": {}, "errors": ["cannot read %s" % path]}
	return parse_enemies(text)


static func load_player(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		return {}
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {}
	var data: Dictionary = parsed
	data["foresight_max"] = int(data.get("foresight_max", 0))
	return data


static func load_items(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		return {}
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {}
	var data: Dictionary = parsed
	return data


static func _validate_martial(def) -> Array[String]:
	var errors: Array[String] = []
	var def_id: String = def.id
	if def.counters.size() < 1 or def.counters.size() > 3:
		errors.append("martial '%s': counters must have 1 to 3 entries, got %d" % [def_id, def.counters.size()])
	for counter_type in def.counters:
		if not MoveTypes.ALL.has(counter_type):
			errors.append("martial '%s': unknown counter type '%s'" % [def_id, str(counter_type)])
	if not Stats.KEYS.has(def.advantage_stat):
		errors.append("martial '%s': unknown advantage_stat '%s'" % [def_id, def.advantage_stat])
	if not MARTIAL_GRADES.has(str(def.grade)):
		errors.append("martial '%s': unknown grade '%s'" % [def_id, str(def.grade)])
	return errors


static func _validate_enemy(def) -> Array[String]:
	var errors: Array[String] = []
	var def_id: String = def.id
	var realm_id := str(def.realm)
	if str(Realms.get_realm(realm_id).get("id", "")) != realm_id:
		errors.append("enemy '%s': unknown realm '%s'" % [def_id, realm_id])

	var move_ids := {}
	var seen_types := {}
	for move in def.moves:
		var move_id: String = move["id"]
		var move_type: String = move["type"]
		move_ids[move_id] = true
		seen_types[move_type] = true
		if not MoveTypes.ALL.has(move_type):
			errors.append("enemy '%s': move '%s' has unknown type '%s'" % [def_id, move_id, move_type])

	var min_types := 0
	var max_types := 0
	if def.tier == "minion":
		min_types = 1
		max_types = 2
	elif def.tier == "elite" or def.tier == "boss":
		min_types = 3
		max_types = 4
	else:
		errors.append("enemy '%s': unknown tier '%s'" % [def_id, def.tier])

	if max_types > 0:
		var type_count := seen_types.size()
		if type_count < min_types or type_count > max_types:
			errors.append("enemy '%s': tier '%s' requires %d to %d distinct move types, got %d" % [def_id, def.tier, min_types, max_types, type_count])

	for weak_move in def.weak_moves:
		if not move_ids.has(weak_move):
			errors.append("enemy '%s': weak move '%s' does not exist" % [def_id, str(weak_move)])
	return errors

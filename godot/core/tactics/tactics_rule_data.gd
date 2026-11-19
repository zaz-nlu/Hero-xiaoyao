extends RefCounted

# data/tactics_rules.json 的读取、校验与缓存。战旗层的破招数值都从这里来，
# 不写在脚本里；缺文件或字段时返回清晰错误。

const RULES_PATH := "res://data/tactics_rules.json"
const OUTCOMES: Array[String] = ["perfect", "counter", "scrape", "none"]

static var _cache: Dictionary = {}


static func load_rules(path := RULES_PATH) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		return _failed(["tactics_rules: cannot read %s" % path])
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return _failed(["tactics_rules: %s: top-level JSON must be an object" % path])
	return parse_rules(parsed, path)


static func parse_rules(d: Dictionary, source := RULES_PATH) -> Dictionary:
	var errors: Array[String] = []
	var forms: Dictionary = _section(d, "forms", source, errors)
	if forms.is_empty() and (d.get("forms", null) is Dictionary):
		errors.append("tactics_rules: %s: forms must not be empty" % source)
	for key in forms.keys():
		if str(key) == "" or str(forms[key]) == "":
			errors.append("tactics_rules: %s: forms entries must be id-to-name strings" % source)
			break
	var legacy: Dictionary = _section(d, "legacy_type_to_form", source, errors)
	for key in legacy.keys():
		var form := str(legacy[key])
		if not forms.has(form):
			errors.append(
				"tactics_rules: %s: legacy_type_to_form '%s' points to unknown form '%s'"
				% [source, str(key), form])
	var table: Dictionary = _section(d, "result_table", source, errors)
	var result_table := {}
	for outcome in OUTCOMES:
		var raw = table.get(outcome, null)
		if not (raw is Dictionary):
			errors.append("tactics_rules: %s: result_table missing '%s'" % [source, outcome])
			continue
		var entry: Dictionary = raw
		for field in ["damage_pct", "counter_pct", "jianyi"]:
			if not _is_number(entry.get(field, null)):
				errors.append(
					"tactics_rules: %s: result_table '%s'.%s must be a number"
					% [source, outcome, field])
		result_table[outcome] = {
			"damage_pct": int(entry.get("damage_pct", 0)),
			"counter_pct": int(entry.get("counter_pct", 0)),
			"jianyi": int(entry.get("jianyi", 0)),
		}
	var block: Dictionary = _section(d, "basic_block", source, errors)
	for field in ["id", "name", "outcome"]:
		if str(block.get(field, "")) == "":
			errors.append("tactics_rules: %s: basic_block.%s is required" % [source, field])
	var block_outcome := str(block.get("outcome", ""))
	if block_outcome != "" and not OUTCOMES.has(block_outcome):
		errors.append(
			"tactics_rules: %s: basic_block.outcome '%s' is unknown" % [source, block_outcome])
	var weakness: Dictionary = _section(d, "weakness", source, errors)
	var parsed_weakness := _parse_weakness(weakness, source, errors)
	var energy: Dictionary = _section(d, "energy", source, errors)
	var parsed_energy := _parse_energy(energy, source, errors)
	var release: Dictionary = _section(d, "ziqi_release", source, errors)
	var parsed_release := _parse_ziqi_release(release, source, errors)
	if not errors.is_empty():
		return _failed(errors)
	return {
		"ok": true,
		"errors": [],
		"rules": {
			"forms": forms,
			"legacy_type_to_form": legacy,
			"result_table": result_table,
			"basic_block": block,
			"weakness": parsed_weakness,
			"energy": parsed_energy,
			"ziqi_release": parsed_release,
		},
	}


static func rules() -> Dictionary:
	if _cache.is_empty():
		var loaded := load_rules()
		if bool(loaded.get("ok", false)):
			var loaded_rules: Dictionary = loaded.get("rules", {})
			_cache = loaded_rules
	return _cache


static func form_names() -> Dictionary:
	var current := rules()
	var forms = current.get("forms", {})
	if forms is Dictionary:
		var typed_forms: Dictionary = forms
		return typed_forms
	return {}


static func form_name(form: String) -> String:
	return str(form_names().get(form, ""))


static func legacy_form(move_type: String) -> String:
	var current := rules()
	var mapping = current.get("legacy_type_to_form", {})
	if mapping is Dictionary:
		return str(mapping.get(move_type, ""))
	return ""


static func result(outcome: String) -> Dictionary:
	var current := rules()
	var table = current.get("result_table", {})
	if not (table is Dictionary):
		return {}
	var entry = table.get(outcome, {})
	if entry is Dictionary:
		var typed_entry: Dictionary = entry
		return typed_entry
	return {}


static func basic_block() -> Dictionary:
	var current := rules()
	var block = current.get("basic_block", {})
	if block is Dictionary:
		var typed_block: Dictionary = block
		return typed_block
	return {}


static func weakness() -> Dictionary:
	var current := rules()
	var block = current.get("weakness", {})
	if block is Dictionary:
		var typed_block: Dictionary = block
		return typed_block
	return {}


static func energy() -> Dictionary:
	var current := rules()
	var block = current.get("energy", {})
	if block is Dictionary:
		var typed_block: Dictionary = block
		return typed_block
	return {}


static func ziqi_release() -> Dictionary:
	var current := rules()
	var block = current.get("ziqi_release", {})
	if block is Dictionary:
		var typed_block: Dictionary = block
		return typed_block
	return {}


static func _parse_ziqi_release(block: Dictionary, source: String,
		errors: Array[String]) -> Dictionary:
	var out: Dictionary = {}
	for field in ["cost", "heal_pct"]:
		if not _is_number(block.get(field, null)):
			errors.append(
				"tactics_rules: %s: ziqi_release.%s must be a number" % [source, field])
			out[field] = 0
		else:
			out[field] = int(block[field])
	if int(out.get("cost", 0)) < 0:
		errors.append("tactics_rules: %s: ziqi_release.cost must not be negative" % source)
	if int(out.get("heal_pct", 0)) <= 0:
		errors.append("tactics_rules: %s: ziqi_release.heal_pct must be positive" % source)
	return out


static func _parse_weakness(block: Dictionary, source: String,
		errors: Array[String]) -> Dictionary:
	var colors: Array = []
	var raw_colors = block.get("colors", null)
	if not (raw_colors is Array) or (raw_colors as Array).is_empty():
		errors.append(
			"tactics_rules: %s: weakness.colors must be a non-empty array" % source)
	elif raw_colors is Array:
		for raw_color in raw_colors:
			var color := str(raw_color)
			if color == "":
				errors.append(
					"tactics_rules: %s: weakness.colors must be non-empty strings" % source)
				continue
			colors.append(color)
	var out: Dictionary = {"colors": colors}
	for field in ["weak_damage_pct", "toughness_hit", "toughness_weak",
			"empower_after_turns", "empower_pct"]:
		if not _is_number(block.get(field, null)):
			errors.append(
				"tactics_rules: %s: weakness.%s must be a number" % [source, field])
			out[field] = 0
		else:
			out[field] = int(block[field])
	var slots: Dictionary = {}
	var raw_slots = block.get("slots_by_tier", null)
	if not (raw_slots is Dictionary):
		errors.append(
			"tactics_rules: %s: weakness.slots_by_tier must be an object" % source)
	else:
		for tier in ["minion", "elite", "boss"]:
			var value = (raw_slots as Dictionary).get(tier, null)
			if not _is_number(value):
				errors.append(
					"tactics_rules: %s: weakness.slots_by_tier.%s must be a number"
					% [source, tier])
			else:
				slots[tier] = int(value)
	out["slots_by_tier"] = slots
	return out


const _ENERGY_GRADES: Array[String] = ["common", "fine", "rare", "epic", "legendary"]


static func _parse_energy(block: Dictionary, source: String,
		errors: Array[String]) -> Dictionary:
	var colors: Array = []
	var raw_colors = block.get("colors", null)
	if not (raw_colors is Array) or (raw_colors as Array).is_empty():
		errors.append("tactics_rules: %s: energy.colors must be a non-empty array" % source)
	elif raw_colors is Array:
		for raw_color in raw_colors:
			colors.append(str(raw_color))
	var out: Dictionary = {"colors": colors}
	var names := {}
	var raw_names = block.get("names", null)
	if not (raw_names is Dictionary):
		errors.append("tactics_rules: %s: energy.names must be an object" % source)
	else:
		for color in colors:
			names[str(color)] = str((raw_names as Dictionary).get(str(color), str(color)))
	out["names"] = names
	out["initial"] = _number_map(block.get("initial", null), "energy.initial", source, errors)
	out["grade_cost"] = _number_map(
		block.get("grade_cost", null), "energy.grade_cost", source, errors)
	out["damage_pct"] = _number_map(
		block.get("damage_pct", null), "energy.damage_pct", source, errors)
	for color in colors:
		if not (out["initial"] as Dictionary).has(str(color)):
			errors.append("tactics_rules: %s: energy.initial.%s is required" % [source, str(color)])
		if not (out["damage_pct"] as Dictionary).has(str(color)):
			errors.append("tactics_rules: %s: energy.damage_pct.%s is required" % [source, str(color)])
	for grade in _ENERGY_GRADES:
		if not (out["grade_cost"] as Dictionary).has(grade):
			errors.append("tactics_rules: %s: energy.grade_cost.%s is required" % [source, grade])
	out["locked"] = _string_list(block.get("locked", []), "energy.locked", source, errors)
	out["free_martials"] = _string_list(
		block.get("free_martials", []), "energy.free_martials", source, errors)
	for field in ["ziqi_heal_ratio", "ziqi_heal_scale"]:
		if not _is_number(block.get(field, null)):
			errors.append("tactics_rules: %s: energy.%s must be a number" % [source, field])
			out[field] = 1 if field == "ziqi_heal_ratio" else 100
		else:
			out[field] = int(block[field]) if field == "ziqi_heal_scale" else float(block[field])
	var xianqi := {"effects": []}
	var raw_xianqi = block.get("xianqi", null)
	if raw_xianqi is Dictionary:
		var raw_effects = (raw_xianqi as Dictionary).get("effects", [])
		if raw_effects is Array:
			xianqi["effects"] = raw_effects
	elif raw_xianqi != null:
		errors.append("tactics_rules: %s: energy.xianqi must be an object" % source)
	out["xianqi"] = xianqi
	var raw_floor = block.get("defeat_neili_floor_pct", 50)
	if not _is_number(raw_floor):
		errors.append(
			"tactics_rules: %s: energy.defeat_neili_floor_pct must be a number" % source)
		out["defeat_neili_floor_pct"] = 50
	else:
		out["defeat_neili_floor_pct"] = int(raw_floor)
	return out


static func _number_map(raw, label: String, source: String,
		errors: Array[String]) -> Dictionary:
	var out := {}
	if not (raw is Dictionary):
		errors.append("tactics_rules: %s: %s must be an object" % [source, label])
		return out
	for key in (raw as Dictionary).keys():
		var value = (raw as Dictionary)[key]
		if not _is_number(value):
			errors.append("tactics_rules: %s: %s.%s must be a number" % [source, label, str(key)])
			continue
		out[str(key)] = int(value)
	return out


static func _string_list(raw, label: String, source: String,
		errors: Array[String]) -> Array:
	var out: Array = []
	if not (raw is Array):
		errors.append("tactics_rules: %s: %s must be an array" % [source, label])
		return out
	for value in raw:
		out.append(str(value))
	return out


static func _section(d: Dictionary, key: String, source: String,
		errors: Array[String]) -> Dictionary:
	var raw = d.get(key, null)
	if not (raw is Dictionary):
		errors.append("tactics_rules: %s: %s must be an object" % [source, key])
		return {}
	var section: Dictionary = raw
	return section


static func _is_number(value) -> bool:
	return value is int or value is float


static func _failed(errors: Array) -> Dictionary:
	return {"ok": false, "errors": errors, "rules": {}}

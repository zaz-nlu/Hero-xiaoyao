extends RefCounted

# 招式形态映射：招式（move_def）与武学（martial）都归一到刺 / 劈 / 扫 / 点。
# 规则表在 data/tactics_rules.json；这里只做纯映射，不碰战斗状态。

const TacticsRuleData = preload("res://core/tactics/tactics_rule_data.gd")


# 招式优先读显式 form；没有时按旧 type 映射到形态，未知 type 返回 ""。
static func move_form(move_def) -> String:
	var declared = _field(move_def, "form")
	if declared != null:
		var form := str(declared)
		if form != "":
			return form
	var move_type = _field(move_def, "type")
	if move_type == null:
		return ""
	return legacy_form(str(move_type))


static func legacy_form(move_type: String) -> String:
	return TacticsRuleData.legacy_form(move_type)


# 武学可破的形态集合：显式 forms 优先，否则把旧 counters（type 列表）映射成形态。
static func martial_forms(martial) -> Array:
	var out: Array = []
	if martial == null:
		return out
	var declared = _field(martial, "forms")
	if declared is Array:
		for raw_form in declared:
			var form := str(raw_form)
			if form != "" and not out.has(form):
				out.append(form)
		if not out.is_empty():
			return out
	var counters = _field(martial, "counters")
	if counters is Array:
		for raw_type in counters:
			var form := legacy_form(str(raw_type))
			if form != "" and not out.has(form):
				out.append(form)
	return out


static func form_name(form: String) -> String:
	return TacticsRuleData.form_name(form)


static func _field(value, key: String) -> Variant:
	if value == null:
		return null
	if value is Dictionary:
		return value.get(key, null)
	if value is Object:
		for property in value.get_property_list():
			if str(property.get("name", "")) == key:
				return value.get(key)
	return null

extends RefCounted

# 战旗层破招判定：只按“形态 + 几何”判定，不读技艺/威胁数值差，
# 也不再使用武学的 weak_moves / advantage_stat。规则数值在
# data/tactics_rules.json，由 tactics_reaction 折算。

const Counter = preload("res://core/counter.gd")
const Pattern = preload("res://core/tactics/pattern.gd")
const TacticsForms = preload("res://core/tactics/tactics_forms.gd")

const OUTCOME_PERFECT := "perfect"
const OUTCOME_COUNTER := "counter"
const OUTCOME_SCRAPE := "scrape"
const OUTCOME_NONE := "none"


# attacker / defender 是 TacticsUnit；move_def 是招式定义（Dictionary 或带字段的对象）；
# martial_or_null 为 null 表示基础格挡；battle_ctx 目前只使用 {"grid": Grid}。
static func evaluate(
	attacker,
	defender,
	move_def,
	martial_or_null,
	relation: String,
	battle_ctx: Dictionary = {}
) -> Dictionary:
	if _field(move_def, "unblockable") == true:
		return _result(OUTCOME_NONE)
	if martial_or_null == null:
		return _result(OUTCOME_SCRAPE)
	var move_form := TacticsForms.move_form(move_def)
	if move_form == "":
		return _result(OUTCOME_NONE)
	var forms: Array = TacticsForms.martial_forms(martial_or_null)
	if not forms.has(move_form):
		return _result(OUTCOME_NONE)
	if relation == "front" and attacker_in_range(defender, attacker, martial_or_null, battle_ctx):
		return _result(OUTCOME_PERFECT)
	return _result(OUTCOME_COUNTER)


# 复用战棋现有的射程/Pattern 计算：防守者朝向攻击者由 relation == "front" 保证，
# 这里只检查攻击者是否落在防守武学的有效射程内。
static func attacker_in_range(defender, attacker, martial, battle_ctx: Dictionary) -> bool:
	if defender == null or attacker == null:
		return false
	var grid = battle_ctx.get("grid", null)
	if grid == null:
		return false
	var range_def = _field(martial, "range")
	if not (range_def is Dictionary) or range_def.is_empty():
		return false
	var pattern: Dictionary = range_def
	var cells: Array[Vector2i] = Pattern.target_cells(
		pattern, defender.pos, defender.facing, grid)
	return cells.has(attacker.pos)


static func _result(outcome: String) -> Dictionary:
	var verdict := int(Counter.Verdict.IMPOSSIBLE)
	if outcome == OUTCOME_PERFECT or outcome == OUTCOME_COUNTER:
		verdict = int(Counter.Verdict.ADVANTAGE)
	elif outcome == OUTCOME_SCRAPE:
		verdict = int(Counter.Verdict.BARELY)
	return {"outcome": outcome, "verdict": verdict, "perfect": outcome == OUTCOME_PERFECT}


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

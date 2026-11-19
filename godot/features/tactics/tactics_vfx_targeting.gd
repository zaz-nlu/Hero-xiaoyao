extends RefCounted

# 特效落点计算：把 core 事件与 view 传入的 context 翻译成格子或世界坐标。
# 只读战斗状态与地块，不创建节点。

var battle: Variant = null
var tiles: Variant = null


func setup(p_battle, p_tiles) -> void:
	battle = p_battle
	tiles = p_tiles


func unit_cell(unit_id: String) -> Vector2i:
	if battle == null or unit_id == "":
		return Vector2i(-1, -1)
	var unit = battle.get_unit(unit_id)
	if unit == null:
		return Vector2i(-1, -1)
	return unit.pos


func cell_center(cell: Vector2i) -> Vector3:
	if cell.x < 0 or tiles == null:
		return Vector3.ZERO
	return tiles.cell_center(cell)


func attacker_cell(event: Dictionary, context: Dictionary) -> Vector2i:
	var raw: Variant = context.get("attacker_pos", null)
	if raw is Vector2i and raw.x >= 0:
		return raw
	var uid := str(event.get("attacker", event.get("unit", "")))
	return unit_cell(uid)


func target_cell(event: Dictionary, context: Dictionary, fallback: Vector2i) -> Vector2i:
	var raw: Variant = event.get("target", null)
	if raw is Vector2i and raw.x >= 0:
		return raw
	raw = context.get("target_cell", null)
	if raw is Vector2i and raw.x >= 0:
		return raw
	var defender_id := str(event.get("defender", ""))
	if defender_id != "":
		var cell := unit_cell(defender_id)
		if cell.x >= 0:
			return cell
	return fallback


func cell_for_step(step: Dictionary, event: Dictionary, context: Dictionary,
		fallback: Vector2i) -> Vector2i:
	match str(step.get("at", "target")):
		"attacker":
			return attacker_cell(event, context)
		"defender", "target":
			return target_cell(event, context, fallback)
		"unit":
			return unit_cell(str(event.get("unit", "")))
		"to":
			var raw: Variant = event.get("to", null)
			if raw is Vector2i:
				return raw
			return fallback
		_:
			return fallback


# 沿攻击方向铺满射程内格子，用于直线剑法。
func line_cells(event: Dictionary, context: Dictionary, fallback: Vector2i) -> Array:
	var cells: Array = []
	var start := attacker_cell(event, context)
	var target := target_cell(event, context, fallback)
	if start.x < 0 or target.x < 0:
		return cells
	var delta := target - start
	var direction := Vector2i.ZERO
	if absi(delta.x) >= absi(delta.y) and delta.x != 0:
		direction = Vector2i(signi(delta.x), 0)
	elif delta.y != 0:
		direction = Vector2i(0, signi(delta.y))
	if direction == Vector2i.ZERO:
		return cells
	var reach := move_max_range(
		str(event.get("unit", "")), str(event.get("martial_id", "")))
	if reach <= 0:
		reach = maxi(1, absi(delta.x) + absi(delta.y))
	reach = mini(reach, 8)
	for i in range(1, reach + 1):
		var cell := start + direction * i
		if battle != null and battle.grid != null and not battle.grid.in_bounds(cell):
			break
		cells.append(cell)
	return cells


func move_max_range(attacker_id: String, martial_id: String) -> int:
	if battle == null or martial_id == "":
		return 0
	if battle.martials.has(martial_id):
		var martial = battle.martials[martial_id]
		var range_table: Variant = martial.range
		if range_table is Dictionary:
			return int(range_table.get("max", 0))
		return 0
	var move_def := enemy_move_def(attacker_id, martial_id)
	var move_range: Variant = move_def.get("range", {})
	if move_range is Dictionary:
		return int(move_range.get("max", 0))
	return 0


func enemy_move_type(attacker_id: String, martial_id: String) -> String:
	return str(enemy_move_def(attacker_id, martial_id).get("type", ""))


func enemy_move_def(attacker_id: String, martial_id: String) -> Dictionary:
	if battle == null or martial_id == "":
		return {}
	var unit = battle.get_unit(attacker_id)
	if unit == null or unit.unit == null or unit.unit.def == null:
		return {}
	for raw_move in unit.unit.def.moves:
		if raw_move is Dictionary and str(raw_move.get("id", "")) == martial_id:
			return raw_move
	return {}

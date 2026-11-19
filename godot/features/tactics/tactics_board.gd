extends Control

# 战棋灰盒棋盘：只读取 TacticsBattle 的状态并画方块/色格，不修改任何规则。
# 格子边长按控件大小自适应并居中；点击与悬停通过 cell_clicked / cell_hovered 发出。

signal cell_clicked(cell: Vector2i)
signal cell_hovered(cell: Vector2i)
signal cell_inspected(cell: Vector2i)

const TERRAIN_COLORS := {
	"floor": Color(0.30, 0.30, 0.34),
	"wall": Color(0.12, 0.12, 0.14),
	"obstacle": Color(0.47, 0.32, 0.18),
	"water": Color(0.16, 0.34, 0.56),
	"bush": Color(0.20, 0.42, 0.24),
	"furniture": Color(0.44, 0.31, 0.20),
}

const MOVE_TINT := Color(0.32, 0.56, 1.0, 0.30)
const ATTACK_TINT := Color(1.0, 0.30, 0.30, 0.30)
const AFFECTED_TINT := Color(1.0, 0.60, 0.20, 0.48)
const ACTOR_OUTLINE := Color(1.0, 0.86, 0.32)
const SELECTED_OUTLINE := Color(0.96, 0.96, 0.96)
const PLAYER_BODY := Color(0.27, 0.48, 0.92)
const ENEMY_BODY := Color(0.82, 0.26, 0.24)
const HP_BACK := Color(0.05, 0.04, 0.06, 0.85)
const HP_FILL := Color(0.86, 0.24, 0.24)
const TOUGH_ON := Color(0.95, 0.80, 0.35)
const TOUGH_OFF := Color(0.30, 0.28, 0.24)

var battle: Variant = null
var _move_cells: Array = []
var _attack_cells: Array = []
var _affected_cells: Array = []
var _selected_cell: Vector2i = Vector2i(-1, -1)
var _hover_cell: Vector2i = Vector2i(-1, -1)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func set_state(p_battle, p_overlays: Dictionary = {}) -> void:
	battle = p_battle
	var raw_move = p_overlays.get("move", [])
	_move_cells = raw_move if raw_move is Array else []
	var raw_attack = p_overlays.get("attack", [])
	_attack_cells = raw_attack if raw_attack is Array else []
	var raw_affected = p_overlays.get("affected", [])
	_affected_cells = raw_affected if raw_affected is Array else []
	_selected_cell = Vector2i(-1, -1)
	var raw_selected = p_overlays.get("selected", null)
	if raw_selected is Vector2i:
		_selected_cell = raw_selected
	queue_redraw()


func cell_at(local_pos: Vector2) -> Vector2i:
	if battle == null or battle.grid == null:
		return Vector2i(-1, -1)
	var grid = battle.grid
	var side := _cell_size()
	if side <= 0.0:
		return Vector2i(-1, -1)
	var origin := _origin()
	var x := int(floor((local_pos.x - origin.x) / side))
	var y := int(floor((local_pos.y - origin.y) / side))
	if x < 0 or y < 0 or x >= int(grid.width) or y >= int(grid.height):
		return Vector2i(-1, -1)
	return Vector2i(x, y)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var cell := cell_at(event.position)
		if cell != _hover_cell:
			_hover_cell = cell
			cell_hovered.emit(cell)
			queue_redraw()
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if not button.pressed:
			return
		var cell := cell_at(button.position)
		if cell.x < 0 or cell.y < 0:
			return
		if button.button_index == MOUSE_BUTTON_LEFT:
			cell_clicked.emit(cell)
		elif button.button_index == MOUSE_BUTTON_RIGHT:
			cell_inspected.emit(cell)


func _draw() -> void:
	if battle == null or battle.grid == null:
		return
	var grid = battle.grid
	var side := _cell_size()
	if side <= 0.0:
		return
	var font: Font = get_theme_default_font()
	for y in range(int(grid.height)):
		for x in range(int(grid.width)):
			var cell := Vector2i(x, y)
			var rect := _cell_rect(cell)
			draw_rect(rect, _terrain_color(str(grid.terrain_at(cell))))
			draw_rect(rect, Color(0.0, 0.0, 0.0, 0.35), false, 1.0)
			var height := int(grid.height_at(cell))
			if height > 0 and font != null:
				var size := int(maxf(9.0, side * 0.20))
				draw_string(font, rect.position + Vector2(2.0, float(size)),
					str(height), HORIZONTAL_ALIGNMENT_LEFT, -1.0, size,
					Color(0.92, 0.90, 0.82, 0.85))

	for cell in _move_cells:
		draw_rect(_cell_rect(cell), MOVE_TINT)
	for cell in _attack_cells:
		draw_rect(_cell_rect(cell), ATTACK_TINT)
	for cell in _affected_cells:
		draw_rect(_cell_rect(cell), AFFECTED_TINT)

	var actor_id := str(battle.current_actor)
	if actor_id != "":
		var actor = battle.get_unit(actor_id)
		if actor != null and actor.is_alive():
			_draw_outline(actor.pos, ACTOR_OUTLINE, 3.0)
	if _selected_cell.x >= 0:
		_draw_outline(_selected_cell, SELECTED_OUTLINE, 2.0)

	for unit in battle.units:
		if unit == null or not unit.is_alive():
			continue
		_draw_unit(unit, side, font)


func _cell_size() -> float:
	if battle == null or battle.grid == null:
		return 0.0
	var grid = battle.grid
	if int(grid.width) <= 0 or int(grid.height) <= 0:
		return 0.0
	return maxf(0.0, minf(size.x / float(grid.width), size.y / float(grid.height)))


func _origin() -> Vector2:
	var grid = battle.grid
	var side := _cell_size()
	return Vector2(
		(size.x - side * float(grid.width)) * 0.5,
		(size.y - side * float(grid.height)) * 0.5)


func _cell_rect(cell: Vector2i) -> Rect2:
	var side := _cell_size()
	return Rect2(_origin() + Vector2(cell) * side, Vector2(side, side))


func _terrain_color(terrain: String) -> Color:
	var color: Color = TERRAIN_COLORS.get(terrain, Color(0.30, 0.30, 0.34))
	return color


func _draw_outline(cell: Vector2i, color: Color, width: float) -> void:
	var rect := _cell_rect(cell)
	draw_rect(rect.grow(-width * 0.5), color, false, width)


func _draw_unit(unit, side: float, font: Font) -> void:
	var rect := _cell_rect(unit.pos).grow(-side * 0.14)
	var body := PLAYER_BODY if unit.side == "player" else ENEMY_BODY
	draw_rect(rect, body)
	draw_rect(rect, Color(0.05, 0.04, 0.06, 0.9), false, 2.0)

	if font != null:
		var badge := str(unit.unit.name).substr(0, 1)
		if badge != "":
			draw_string(font, rect.position + Vector2(0.0, rect.size.y * 0.5 + side * 0.12),
				badge, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x,
				int(maxf(10.0, side * 0.34)), Color(1.0, 1.0, 1.0, 0.95))

	var center := rect.get_center()
	var direction := Vector2(unit.facing)
	var tip := center + direction * side * 0.34
	var wing := Vector2(-direction.y, direction.x) * side * 0.10
	draw_colored_polygon(PackedVector2Array([
		tip,
		center + direction * side * 0.18 + wing,
		center + direction * side * 0.18 - wing,
	]), Color(1.0, 1.0, 1.0, 0.9))

	var bar_width := side * 0.72
	var bar_height := maxf(2.0, side * 0.06)
	var bar_pos := Vector2(
		rect.position.x + (rect.size.x - bar_width) * 0.5,
		rect.position.y - bar_height - 3.0)
	draw_rect(Rect2(bar_pos, Vector2(bar_width, bar_height)), HP_BACK)
	var max_hp := maxf(1.0, float(unit.unit.max_hp))
	var ratio := clampf(float(unit.unit.hp) / max_hp, 0.0, 1.0)
	draw_rect(Rect2(bar_pos, Vector2(bar_width * ratio, bar_height)), HP_FILL)

	var toughness_max := int(unit.unit.toughness_max)
	if toughness_max > 0:
		var pip := maxf(2.0, side * 0.08)
		var left := int(ceil(float(unit.unit.toughness_left)))
		for i in range(toughness_max):
			var pip_color := TOUGH_ON if i < left else TOUGH_OFF
			draw_rect(Rect2(
				Vector2(bar_pos.x + float(i) * (pip + 1.0), rect.end.y + 2.0),
				Vector2(pip, pip)), pip_color)

	if unit.side != "player" and str(battle.leader_id) != "" and unit.id == battle.leader_id:
		_draw_star(Vector2(rect.position.x + side * 0.14, rect.position.y + side * 0.16),
			side * 0.10, Color(1.0, 0.86, 0.32))

	if unit.unit.is_stunned():
		draw_arc(rect.get_center(), rect.size.x * 0.55, 0.0, TAU, 24,
			Color(0.55, 0.70, 1.0, 0.9), 2.0)
		if font != null:
			draw_string(font, Vector2(rect.end.x - side * 0.24, rect.position.y + side * 0.20),
				"晕", HORIZONTAL_ALIGNMENT_LEFT, -1.0,
				int(maxf(8.0, side * 0.15)), Color(0.65, 0.80, 1.0))


func _draw_star(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(8):
		var angle := -PI * 0.5 + float(i) * PI * 0.25
		var r := radius if i % 2 == 0 else radius * 0.45
		points.append(center + Vector2(cos(angle), sin(angle)) * r)
	draw_colored_polygon(points, color)

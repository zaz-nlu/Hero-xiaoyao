extends RefCounted

# 敌人头顶信息层：意图/预判/弱点/目标按钮/血条等并行数组，以及屏幕投影与重叠处理。
# 只发 enemy_selected(index)，不持有控制器。

signal enemy_selected(index: int)

const BattleText = preload("res://features/battle/battle_text.gd")
const Hud = preload("res://shared/ui/battle_hud_style.gd")
const HudBar = preload("res://shared/ui/hud_bar.gd")
const MoveTypes = preload("res://core/move_types.gd")
const OrnatePanel = preload("res://shared/ui/ornate_panel.gd")

const HEAD_WIDTH := 138.0
const COMPACT_HEAD_WIDTH := 104.0
const HEAD_HEIGHT := 56.0
const HEAD_WORLD_OFFSET := 2.6
const HEAD_SCREEN_GAP := 10.0

var enemies_container: Control = null
var intent_labels: Array = []
var foresight_labels: Array = []
var weak_labels: Array = []
var enemy_info_labels: Array = []
var target_buttons: Array = []
var enemy_head_labels: Array = []
var enemy_hp_bars: Array = []
var enemy_hp_labels: Array = []
var enemy_tough_labels: Array = []
var enemy_stun_labels: Array = []
var enemy_markers: Array = []

var _compact_heads: bool = false


func build(parent: Control) -> void:
	enemies_container = Control.new()
	enemies_container.name = "Enemies"
	enemies_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	enemies_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(enemies_container)


func set_compact(value: bool) -> void:
	_compact_heads = value


func rebuild(battle: Variant) -> void:
	for child in enemies_container.get_children():
		child.free()
	intent_labels.clear()
	foresight_labels.clear()
	weak_labels.clear()
	enemy_info_labels.clear()
	target_buttons.clear()
	enemy_head_labels.clear()
	enemy_hp_bars.clear()
	enemy_hp_labels.clear()
	enemy_tough_labels.clear()
	enemy_stun_labels.clear()
	enemy_markers.clear()
	if battle == null:
		return
	for i in range(battle.enemies.size()):
		_build_enemy_head(i)


func refresh(battle: Variant, selected_target: int) -> void:
	if battle == null:
		return
	for i in range(battle.enemies.size()):
		_refresh_enemy_group(battle, i, selected_target)


func update_positions(actor_nodes: Array, camera: Camera3D, view_size: Vector2) -> void:
	if camera == null or not is_instance_valid(camera) or not camera.is_inside_tree():
		return
	var placements: Array = []
	for i in range(enemy_head_labels.size()):
		var head: Control = enemy_head_labels[i]
		if i >= actor_nodes.size():
			head.visible = false
			continue
		var actor: Variant = actor_nodes[i]
		if actor == null or not is_instance_valid(actor):
			head.visible = false
			continue
		var world: Vector3 = actor.position + Vector3(0.0, HEAD_WORLD_OFFSET, 0.0)
		if camera.is_position_behind(world):
			head.visible = false
			continue
		head.visible = true
		var screen: Vector2 = camera.unproject_position(world)
		var head_size: Vector2 = head.size
		if head_size.x <= 0.0 or head_size.y <= 0.0:
			head_size = head.custom_minimum_size
		var x: float = screen.x - head_size.x * 0.5
		var y: float = screen.y - head_size.y - HEAD_SCREEN_GAP
		x = clampf(x, 0.0, maxf(0.0, view_size.x - head_size.x))
		y = maxf(0.0, y)
		if _compact_heads:
			y = minf(y, maxf(0.0, view_size.y - head_size.y))
		placements.append({"index": i, "pos": Vector2(x, y), "size": head_size})
	if _compact_heads:
		_resolve_head_overlaps(placements, view_size)
	for raw_entry in placements:
		var entry: Dictionary = raw_entry
		var head: Control = enemy_head_labels[int(entry["index"])]
		head.position = entry["pos"]


# 4 个以上敌人时标签更宽地铺开，容易在屏幕上叠在一起：按 x 排序后，
# 把与已放置标签相交的后一个标签往上错开 36 像素，并保持夹在屏幕内。
func _resolve_head_overlaps(placements: Array, view_size: Vector2) -> void:
	placements.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pos_a: Vector2 = a["pos"]
		var pos_b: Vector2 = b["pos"]
		return pos_a.x < pos_b.x
	)
	var placed: Array = []
	for raw_entry in placements:
		var entry: Dictionary = raw_entry
		var pos: Vector2 = entry["pos"]
		var head_size: Vector2 = entry["size"]
		var rect := Rect2(pos, head_size)
		var guard := 0
		while guard < 48:
			guard += 1
			var moved := false
			for raw_prev in placed:
				var prev: Rect2 = raw_prev
				if rect.intersects(prev):
					pos.y = maxf(0.0, pos.y - 36.0)
					rect = Rect2(pos, head_size)
					moved = true
					break
			if not moved:
				break
		pos.y = clampf(pos.y, 0.0, maxf(0.0, view_size.y - head_size.y))
		rect = Rect2(pos, head_size)
		entry["pos"] = pos
		placed.append(rect)


# ---------------------------------------------------------------- build

func _build_enemy_head(index: int) -> void:
	var head := OrnatePanel.new()
	head.name = "EnemyHead%d" % index
	var head_width: float = _head_width()
	head.custom_minimum_size = Vector2(head_width, HEAD_HEIGHT)
	head.size = Vector2(head_width, HEAD_HEIGHT)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_stylebox_override("panel", Hud.head_style(false, false))
	enemies_container.add_child(head)

	var marker := Label.new()
	marker.name = "TargetMarker"
	marker.text = "▼"
	marker.set_anchors_preset(Control.PRESET_CENTER_TOP)
	marker.offset_left = -24.0
	marker.offset_top = -20.0
	marker.offset_right = 24.0
	marker.offset_bottom = 0.0
	marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Hud.configure_label(marker, 18, Hud.GOLD_BRIGHT)
	marker.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	marker.add_theme_constant_override("outline_size", 5)
	marker.visible = false
	marker.z_index = 1
	head.add_child(marker)

	var margin := MarginContainer.new()
	margin.name = "HeadMargin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin_x: int = 4 if _compact_heads else 6
	margin.add_theme_constant_override("margin_left", margin_x)
	margin.add_theme_constant_override("margin_top", 3 if _compact_heads else 4)
	margin.add_theme_constant_override("margin_right", margin_x)
	margin.add_theme_constant_override("margin_bottom", 5 if _compact_heads else 6)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1 if _compact_heads else 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)

	var info_label := Label.new()
	info_label.name = "InfoLabel"
	info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Hud.configure_label(info_label, _head_font(15), Hud.TEXT)
	info_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	info_label.add_theme_constant_override("outline_size", 4)
	box.add_child(info_label)

	var hp_stack := Control.new()
	hp_stack.name = "HpStack"
	hp_stack.custom_minimum_size = Vector2(0.0, 16.0)
	hp_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(hp_stack)

	var hp_bar := HudBar.new()
	hp_bar.name = "HpBar"
	hp_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hp_bar.max_value = 1.0
	hp_bar.value = 0.0
	hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_stack.add_child(hp_bar)

	var hp_label := Label.new()
	hp_label.name = "HpLabel"
	hp_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Hud.configure_label(hp_label, _head_font(10), Color.WHITE)
	hp_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	hp_label.add_theme_constant_override("outline_size", 3)
	hp_stack.add_child(hp_label)

	var stat_row := HBoxContainer.new()
	stat_row.add_theme_constant_override("separation", 8)
	stat_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(stat_row)

	var tough_label := Label.new()
	tough_label.name = "ToughnessLabel"
	tough_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tough_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	Hud.configure_label(tough_label, _head_font(11), Hud.TOUGH_GOLD)
	stat_row.add_child(tough_label)

	var stun_label := Label.new()
	stun_label.name = "StunLabel"
	stun_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	Hud.configure_label(stun_label, _head_font(11), Hud.STUN_BLUE)
	stun_label.visible = false
	stat_row.add_child(stun_label)

	var intent_label := Label.new()
	intent_label.name = "IntentLabel"
	intent_label.add_theme_stylebox_override("normal", Hud.bubble_style())
	intent_label.clip_text = true
	intent_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	intent_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Hud.configure_label(intent_label, _head_font(11), Hud.TEXT)
	box.add_child(intent_label)

	var foresight_label_node := Label.new()
	foresight_label_node.name = "ForesightLabel"
	foresight_label_node.add_theme_stylebox_override("normal", Hud.bubble_style())
	foresight_label_node.clip_text = true
	foresight_label_node.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	foresight_label_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Hud.configure_label(foresight_label_node, _head_font(11), Hud.GOLD)
	foresight_label_node.visible = false
	box.add_child(foresight_label_node)

	var weak_label := Label.new()
	weak_label.name = "WeakLabel"
	weak_label.clip_text = true
	weak_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	weak_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Hud.configure_label(weak_label, _head_font(11), Hud.MUTED)
	weak_label.visible = false
	box.add_child(weak_label)

	var target_button := Button.new()
	target_button.name = "TargetButton"
	target_button.text = ""
	target_button.flat = true
	target_button.focus_mode = Control.FOCUS_NONE
	target_button.mouse_filter = Control.MOUSE_FILTER_STOP
	target_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	target_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	target_button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	target_button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	target_button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	target_button.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	target_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	target_button.pressed.connect(_on_target_pressed.bind(index))
	head.add_child(target_button)

	enemy_head_labels.append(head)
	enemy_info_labels.append(info_label)
	enemy_hp_bars.append(hp_bar)
	enemy_hp_labels.append(hp_label)
	enemy_tough_labels.append(tough_label)
	enemy_stun_labels.append(stun_label)
	enemy_markers.append(marker)
	intent_labels.append(intent_label)
	foresight_labels.append(foresight_label_node)
	weak_labels.append(weak_label)
	target_buttons.append(target_button)
	_fit_enemy_head(head)


func _refresh_enemy_group(battle: Variant, index: int, selected_target: int) -> void:
	if index < 0 or index >= battle.enemies.size():
		return
	var enemy: Variant = battle.enemies[index]
	var dead: bool = enemy.is_dead()
	if index < enemy_info_labels.size():
		var info_label: Label = enemy_info_labels[index]
		info_label.text = str(enemy.name)
	if index < enemy_hp_labels.size():
		var hp_label: Label = enemy_hp_labels[index]
		BattleText.fit_hp_label(hp_label, int(enemy.hp), int(enemy.max_hp), 10)
	if index < enemy_hp_bars.size():
		var hp_bar: ProgressBar = enemy_hp_bars[index]
		hp_bar.max_value = maxf(1.0, float(enemy.max_hp))
		hp_bar.value = float(maxi(0, int(enemy.hp)))
	if index < enemy_tough_labels.size():
		var tough_label: Label = enemy_tough_labels[index]
		tough_label.text = _toughness_text(enemy)
	if index < enemy_stun_labels.size():
		var stun_label: Label = enemy_stun_labels[index]
		stun_label.visible = enemy.is_stunned()
		if stun_label.visible:
			stun_label.text = "晕眩"
	if index < intent_labels.size():
		var intent_label: Label = intent_labels[index]
		intent_label.text = _intent_text(battle, index)
	if index < foresight_labels.size():
		var foresight_label_node: Label = foresight_labels[index]
		var foresight_text: String = _foresight_text(battle, index)
		foresight_label_node.text = foresight_text
		foresight_label_node.visible = foresight_text != ""
	if index < weak_labels.size():
		var weak_label: Label = weak_labels[index]
		weak_label.text = _weak_text(enemy)
		weak_label.visible = enemy.weak_revealed and not enemy.weak_moves.is_empty()
	if index < target_buttons.size():
		var target_button: Button = target_buttons[index]
		target_button.disabled = dead
		if dead:
			target_button.tooltip_text = ""
		elif index == selected_target:
			target_button.tooltip_text = "当前目标"
		else:
			target_button.tooltip_text = "点击选为目标"
	if index < enemy_markers.size():
		var marker: Label = enemy_markers[index]
		marker.visible = index == selected_target and not dead
	if index < enemy_head_labels.size():
		var head: Panel = enemy_head_labels[index]
		head.add_theme_stylebox_override(
			"panel", Hud.head_style(index == selected_target, dead)
		)
		if head.has_method("set_frame"):
			head.call(
				"set_frame",
				Hud.GOLD_BRIGHT if index == selected_target and not dead else Hud.GOLD
			)
		head.modulate = Color(0.62, 0.62, 0.66, 0.72) if dead else Color.WHITE
		head.z_index = 10 if index == selected_target else 0
		_fit_enemy_head(head)


func _head_width() -> float:
	return COMPACT_HEAD_WIDTH if _compact_heads else HEAD_WIDTH


func _head_font(base_size: int) -> int:
	return maxi(8, base_size - 1) if _compact_heads else base_size


func _fit_enemy_head(head: Panel) -> void:
	if head == null:
		return
	var margin: MarginContainer = (
		head.get_node_or_null("HeadMargin") as MarginContainer
	)
	if margin == null:
		return
	var needed: float = margin.get_combined_minimum_size().y
	head.size = Vector2(_head_width(), maxf(HEAD_HEIGHT, needed))


func _toughness_text(enemy: Variant) -> String:
	var left: float = maxf(0.0, float(enemy.toughness_left))
	var shown: int = int(ceilf(left))
	var text := "◆".repeat(shown)
	if text == "":
		text = "—"
	return "耐性 %s" % text


func _intent_text(battle: Variant, index: int) -> String:
	var enemy: Variant = battle.enemies[index]
	if enemy.is_dead():
		return "（已倒下）"
	if enemy.is_stunned():
		return "（晕眩，不出招）"
	var intent: Dictionary = {}
	if index < battle.intents.size():
		intent = battle.intents[index]
	if intent.is_empty():
		return "（无意图）"
	if not battle.is_move_known(index):
		return "下一招：？？？"
	var type_id: String = str(intent.get("type", ""))
	var type_name: String = str(MoveTypes.NAMES.get(type_id, type_id))
	return "下一招：%s（%s）" % [str(intent.get("name", "")), type_name]


func _foresight_text(battle: Variant, index: int) -> String:
	if index < 0 or index >= battle.enemies.size():
		return ""
	var moves: Array = battle.foreseen(index)
	if moves.is_empty():
		return ""
	var names := PackedStringArray()
	for raw_move in moves:
		var move: Dictionary = raw_move
		names.append(str(move.get("name", move.get("id", ""))))
	return "预判：%s" % " → ".join(names)


func _weak_text(enemy: Variant) -> String:
	if not enemy.weak_revealed or enemy.weak_moves.is_empty():
		return "弱点：？"
	var names := PackedStringArray()
	for raw_move_id in enemy.weak_moves:
		names.append(_move_name(enemy, str(raw_move_id)))
	return "弱点：%s" % ", ".join(names)


func _move_name(enemy: Variant, move_id: String) -> String:
	if enemy.def == null:
		return move_id
	for raw_move in enemy.def.moves:
		var move: Dictionary = raw_move
		if str(move.get("id", "")) == move_id:
			return str(move.get("name", move_id))
	return move_id


func _on_target_pressed(index: int) -> void:
	enemy_selected.emit(index)

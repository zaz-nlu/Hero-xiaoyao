extends Panel

# 背包面板（K）：左侧格子网格，右侧物品详情与操作（服用 / 装备 / 卸下）。
# 由 status_overlay.gd 持有；数据只读写 GameState / Progression。

const CharacterPanelStyle = preload("res://features/character/character_panel_style.gd")
const GameState = preload("res://core/game_state.gd")
const Hud = preload("res://shared/ui/battle_hud_style.gd")
const IconLib = preload("res://shared/ui/icon_lib.gd")
const Progression = preload("res://core/progression.gd")

const PANEL_WIDTH := 640.0
const PANEL_HEIGHT := 420.0
const COLUMNS := 5
const CELL := 76.0
const KIND_NAMES := {
	"weapon": "武器", "armor": "防具", "accessory": "饰品",
	"material": "材料", "consumable": "丹药",
}

var selected_id: String = ""

var _grid: Control = null
var _detail: Control = null


func _init() -> void:
	name = "InventoryPanel"
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -PANEL_WIDTH * 0.5
	offset_right = PANEL_WIDTH * 0.5
	offset_top = -PANEL_HEIGHT * 0.5
	offset_bottom = PANEL_HEIGHT * 0.5
	add_theme_stylebox_override("panel", Hud.panel_style(0.94))
	mouse_filter = Control.MOUSE_FILTER_STOP
	CharacterPanelStyle.make_label(
		self, "Header", Vector2(24.0, 20.0), Vector2(250.0, 28.0), 20, Hud.GOLD).text = "背包"
	_grid = _make_area("Grid", Vector2(24.0, 60.0), Vector2(CELL * COLUMNS, 310.0))
	var divider := ColorRect.new()
	divider.position = Vector2(420.0, 20.0)
	divider.size = Vector2(1.0, 354.0)
	divider.color = Color(0.78, 0.65, 0.35, 0.35)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(divider)
	_detail = _make_area("Detail", Vector2(436.0, 20.0), Vector2(190.0, 354.0))
	var hint := CharacterPanelStyle.make_label(
		self, "CloseHint", Vector2(0.0, 384.0), Vector2(PANEL_WIDTH, 26.0), 16, Hud.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.text = "按 K 关闭"


func item_ids() -> Array:
	var ids: Array = []
	for raw_id in GameState.inventory.keys():
		if int(GameState.inventory[raw_id]) > 0:
			ids.append(str(raw_id))
	ids.sort()
	return ids


func refresh() -> void:
	var ids := item_ids()
	if not ids.has(selected_id):
		selected_id = "" if ids.is_empty() else str(ids[0])
	_clear(_grid)
	for index in range(ids.size()):
		_build_cell(str(ids[index]), index)
	if ids.is_empty():
		CharacterPanelStyle.make_label(
			_grid, "Empty", Vector2(0.0, 8.0), Vector2(380.0, 22.0), 16, Hud.MUTED
		).text = "行囊空空如也"
	_rebuild_detail()


func select(item_id: String) -> void:
	selected_id = item_id
	refresh()


func _make_area(node_name: String, pos: Vector2, area_size: Vector2) -> Control:
	var area := Control.new()
	area.name = node_name
	area.position = pos
	area.size = area_size
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(area)
	return area


func _build_cell(item_id: String, index: int) -> void:
	var cell := Button.new()
	cell.name = "Cell_%s" % item_id
	cell.position = Vector2(float(index % COLUMNS) * CELL, float(index / COLUMNS) * CELL)
	cell.size = Vector2(CELL - 6.0, CELL - 6.0)
	cell.focus_mode = Control.FOCUS_NONE
	var border: Color = Hud.GOLD_BRIGHT if item_id == selected_id else Color(0.78, 0.65, 0.35, 0.3)
	cell.add_theme_stylebox_override("normal", Hud.card_style(0.9, border))
	cell.add_theme_stylebox_override("hover", Hud.card_hover_style())
	cell.add_theme_stylebox_override("pressed", Hud.card_pressed_style())
	cell.pressed.connect(select.bind(item_id))
	_grid.add_child(cell)
	var icon: Texture2D = IconLib.item_icon(item_id)
	if icon != null:
		var rect := TextureRect.new()
		rect.position = Vector2(12.0, 6.0)
		rect.size = Vector2(46.0, 46.0)
		rect.texture = icon
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(rect)
	else:
		var name_label := CharacterPanelStyle.make_label(
			cell, "Name", Vector2(4.0, 10.0), Vector2(60.0, 40.0), 13, Hud.TEXT)
		name_label.text = str(Progression.item_def(item_id).get("name", item_id))
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var count := CharacterPanelStyle.make_label(
		cell, "Count", Vector2(30.0, 50.0), Vector2(36.0, 16.0), 12, Hud.GOLD_BRIGHT)
	count.text = "×%d" % int(GameState.inventory.get(item_id, 0))
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _rebuild_detail() -> void:
	_clear(_detail)
	if selected_id == "":
		return
	var item: Dictionary = Progression.item_def(selected_id)
	CharacterPanelStyle.make_label(
		_detail, "ItemName", Vector2(0.0, 0.0), Vector2(190.0, 30.0), 20, Hud.GOLD_BRIGHT
	).text = str(item.get("name", selected_id))
	var kind := str(item.get("kind", ""))
	CharacterPanelStyle.make_label(
		_detail, "ItemKind", Vector2(0.0, 34.0), Vector2(190.0, 20.0), 14, Hud.GOLD
	).text = "%s  ×%d" % [str(KIND_NAMES.get(kind, kind)), int(GameState.inventory.get(selected_id, 0))]
	var desc := RichTextLabel.new()
	desc.name = "ItemDesc"
	desc.position = Vector2(0.0, 62.0)
	desc.size = Vector2(190.0, 150.0)
	desc.scroll_active = false
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc.add_theme_font_size_override("normal_font_size", 15)
	desc.add_theme_color_override("default_color", Hud.TEXT)
	desc.text = str(item.get("desc", ""))
	_detail.add_child(desc)
	_build_action(item, kind)


func _build_action(item: Dictionary, kind: String) -> void:
	var pos := Vector2(0.0, 300.0)
	var button_size := Vector2(110.0, 32.0)
	if _is_usable(item):
		CharacterPanelStyle.make_small_button(
			_detail, "Use", "服用", pos, button_size).pressed.connect(_on_use)
		return
	if not Progression.EQUIP_SLOTS.has(kind):
		return
	var slot := str(item.get("slot", kind))
	if str(GameState.equipment.get(slot, "")) == selected_id:
		CharacterPanelStyle.make_small_button(
			_detail, "Unequip", "卸下", pos, button_size).pressed.connect(_on_unequip.bind(slot))
	else:
		CharacterPanelStyle.make_small_button(
			_detail, "Equip", "装备", pos, button_size).pressed.connect(_on_equip)


func _is_usable(item: Dictionary) -> bool:
	for key in ["perm", "restore"]:
		var raw: Variant = item.get(key, {})
		if raw is Dictionary and not (raw as Dictionary).is_empty():
			return true
	return false


func _on_use() -> void:
	if not Progression.use_restore_item(selected_id):
		Progression.use_permanent_item(selected_id)
	refresh()


func _on_equip() -> void:
	Progression.equip(selected_id)
	refresh()


func _on_unequip(slot: String) -> void:
	Progression.unequip(slot)
	refresh()


func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

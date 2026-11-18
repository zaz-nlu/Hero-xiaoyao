extends RefCounted

# 装备页签：武器/防具/饰品槽、行囊列表与装备、卸下、服用操作。

signal refresh_requested

const CharacterData = preload("res://features/character/character_panel_data.gd")
const CharacterPanelStyle = preload("res://features/character/character_panel_style.gd")
const GameState = preload("res://core/game_state.gd")
const Hud = preload("res://shared/ui/battle_hud_style.gd")
const IconLib = preload("res://shared/ui/icon_lib.gd")
const Progression = preload("res://core/progression.gd")

const SLOT_KEYS: Array[String] = ["weapon", "armor", "accessory"]
const SLOT_NAMES := {
	"weapon": "武器",
	"armor": "防具",
	"accessory": "饰品",
}
const KIND_NAMES := {
	"weapon": "武器",
	"armor": "防具",
	"accessory": "饰品",
	"material": "材料",
	"consumable": "丹药",
}
const SLOT_COLORS := {
	"weapon": Color(0.72, 0.6, 0.38),
	"armor": Color(0.42, 0.58, 0.72),
	"accessory": Color(0.62, 0.46, 0.72),
}

var _content: Control = null
var _data: Variant = null


func _init(content: Control, data: Variant) -> void:
	_content = content
	_data = data


func build() -> void:
	for i in range(SLOT_KEYS.size()):
		var slot := SLOT_KEYS[i]
		var card := Panel.new()
		card.name = "EquipSlotCard_%s" % slot
		card.position = Vector2(float(i) * 198.0, 0.0)
		card.size = Vector2(182.0, 104.0)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_theme_stylebox_override("panel", Hud.card_style(0.9))
		_content.add_child(card)

		var icon := Panel.new()
		icon.name = "SlotIcon_%s" % slot
		icon.position = Vector2(12.0, 12.0)
		icon.size = Vector2(38.0, 38.0)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.add_theme_stylebox_override("panel", Hud.circle_style(SLOT_COLORS[slot], 19))
		card.add_child(icon)
		var glyph := CharacterPanelStyle.make_label(
			icon, "SlotGlyph_%s" % slot, Vector2.ZERO, Vector2(38.0, 38.0), 16, Hud.TEXT
		)
		glyph.text = str(SLOT_NAMES[slot]).substr(0, 1)
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

		var equipped_id := str(GameState.equipment.get(slot, ""))
		var equipped_icon: Texture2D = null
		if equipped_id != "":
			equipped_icon = IconLib.item_icon(equipped_id)
		if equipped_icon != null:
			var item_icon_rect := TextureRect.new()
			item_icon_rect.name = "SlotItemIcon_%s" % slot
			item_icon_rect.position = Vector2(13.0, 13.0)
			item_icon_rect.size = Vector2(36.0, 36.0)
			item_icon_rect.texture = equipped_icon
			item_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			item_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			item_icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			item_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(item_icon_rect)
			glyph.visible = false

		CharacterPanelStyle.make_label(
			card, "SlotLabel_%s" % slot, Vector2(58.0, 10.0), Vector2(112.0, 20.0), 15, Hud.GOLD
		).text = str(SLOT_NAMES[slot])

		var item_id := str(GameState.equipment.get(slot, ""))
		var item_label := CharacterPanelStyle.make_label(
			card, "SlotItem_%s" % slot, Vector2(58.0, 32.0), Vector2(116.0, 20.0), 14,
			Hud.MUTED if item_id == "" else Hud.TEXT
		)
		var bonus_label := CharacterPanelStyle.make_label(
			card, "SlotBonus_%s" % slot, Vector2(12.0, 68.0), Vector2(160.0, 20.0), 12,
			CharacterPanelStyle.BONUS_COLOR
		)
		if item_id == "":
			item_label.text = "未装备"
			bonus_label.text = ""
		else:
			var item: Dictionary = Progression.item_def(item_id)
			item_label.text = str(item.get("name", item_id))
			bonus_label.text = _item_bonus_text(item)

	CharacterPanelStyle.make_label(
		_content, "BagHeader", Vector2(0.0, 116.0), Vector2(300.0, 22.0), 16, Hud.GOLD
	).text = "行囊"

	var ids: Array = GameState.inventory.keys()
	ids.sort()
	var shown := 0
	for raw_id in ids:
		var item_id := str(raw_id)
		var count := int(GameState.inventory[item_id])
		if count <= 0:
			continue
		_build_bag_row(item_id, count, 142.0 + float(shown) * 60.0)
		shown += 1

	if shown == 0:
		CharacterPanelStyle.make_label(
			_content, "BagEmpty", Vector2(0.0, 142.0), Vector2(400.0, 22.0), 15, Hud.MUTED
		).text = "行囊空空如也"


func _build_bag_row(item_id: String, count: int, y: float) -> void:
	var item: Dictionary = Progression.item_def(item_id)
	var row := Panel.new()
	row.name = "BagItem_%s" % item_id
	row.position = Vector2(0.0, y)
	row.size = Vector2(592.0, 54.0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_stylebox_override(
		"panel", Hud.card_style(0.55, Color(0.78, 0.65, 0.35, 0.25))
	)
	_content.add_child(row)

	var bag_icon: Texture2D = IconLib.item_icon(item_id)
	var text_x := 10.0
	if bag_icon != null:
		var icon_rect := TextureRect.new()
		icon_rect.name = "BagIcon_%s" % item_id
		icon_rect.position = Vector2(8.0, 9.0)
		icon_rect.size = Vector2(36.0, 36.0)
		icon_rect.texture = bag_icon
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon_rect)
		text_x = 50.0

	var name_label := CharacterPanelStyle.make_label(
		row, "BagName_%s" % item_id, Vector2(text_x, 4.0), Vector2(140.0, 20.0), 15, Hud.TEXT
	)
	name_label.text = str(item.get("name", item_id))
	var count_label := CharacterPanelStyle.make_label(
		row, "BagCount_%s" % item_id, Vector2(text_x + 140.0, 6.0), Vector2(44.0, 18.0), 12, Hud.MUTED
	)
	count_label.text = "×%d" % count
	var kind := str(item.get("kind", ""))
	var kind_label := CharacterPanelStyle.make_label(
		row, "BagKind_%s" % item_id, Vector2(text_x + 190.0, 6.0), Vector2(60.0, 18.0), 12, Hud.GOLD
	)
	kind_label.text = str(KIND_NAMES.get(kind, kind))
	var desc := CharacterPanelStyle.make_label(
		row, "BagDesc_%s" % item_id, Vector2(text_x, 27.0), Vector2(440.0, 18.0), 12, Hud.MUTED
	)
	desc.text = str(item.get("desc", ""))

	var raw_perm: Variant = item.get("perm", {})
	if raw_perm is Dictionary:
		var perm: Dictionary = raw_perm
		if not perm.is_empty():
			var use_button := CharacterPanelStyle.make_small_button(
				row, "Use_%s" % item_id, "服用", Vector2(506.0, 12.0), Vector2(76.0, 28.0)
			)
			use_button.pressed.connect(_on_use_pressed.bind(item_id))
			return

	if not Progression.EQUIP_SLOTS.has(kind):
		return
	var slot := str(item.get("slot", kind))
	if slot == "" or not Progression.EQUIP_SLOTS.has(slot):
		slot = kind
	var equipped_here := str(GameState.equipment.get(slot, "")) == item_id
	if equipped_here:
		var unequip_button := CharacterPanelStyle.make_small_button(
			row, "Unequip_%s" % item_id, "卸下", Vector2(506.0, 12.0), Vector2(76.0, 28.0)
		)
		unequip_button.pressed.connect(_on_unequip_pressed.bind(slot))
	else:
		var equip_button := CharacterPanelStyle.make_small_button(
			row, "Equip_%s" % item_id, "装备", Vector2(506.0, 12.0), Vector2(76.0, 28.0)
		)
		equip_button.pressed.connect(_on_equip_pressed.bind(item_id))


func _on_equip_pressed(item_id: String) -> void:
	Progression.equip(item_id)
	refresh_requested.emit()


func _on_use_pressed(item_id: String) -> void:
	Progression.use_permanent_item(item_id)
	refresh_requested.emit()


func _on_unequip_pressed(slot: String) -> void:
	Progression.unequip(slot)
	refresh_requested.emit()


func _item_bonus_text(item: Dictionary) -> String:
	var parts := PackedStringArray()
	var bonus_value: Variant = item.get("bonus", {})
	if bonus_value is Dictionary:
		var bonus: Dictionary = bonus_value
		for key in bonus.keys():
			var stat_key := str(key)
			if not CharacterData.STAT_NAMES.has(stat_key):
				continue
			var amount := int(bonus[key])
			if amount == 0:
				continue
			parts.append("%s%s" % [str(CharacterData.STAT_NAMES[stat_key]), _data.signed(amount)])
	return " ".join(parts)

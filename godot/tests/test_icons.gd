extends "res://tests/test_case.gd"

const IconLib = preload("res://shared/ui/icon_lib.gd")
const GameState = preload("res://core/game_state.gd")
const Progression = preload("res://core/progression.gd")

const MARTIAL_IDS: Array[String] = [
	"basic_sword", "parry", "sidestep", "taiji", "qingyun",
	"huifeng", "lianhuan", "duanshi", "liuxing", "jueshi"
]
const STAT_IDS: Array[String] = [
	"power", "speed", "defense", "recovery", "skill", "mechanism"
]
const ITEM_IDS: Array[String] = [
	"plain_sword", "herb", "cloth_robe", "jade_pendant", "iron_ore",
	"old_box", "jade_hairpin", "ginseng", "healing_pills"
]


func test_martial_icons_load() -> void:
	for id in MARTIAL_IDS:
		assert_true(IconLib.martial_icon(id) != null, "%s has a martial icon" % id)
	assert_true(
		IconLib.martial_icon("does_not_exist") == null,
		"an unknown martial returns null"
	)


func test_stat_icons_load() -> void:
	for stat in STAT_IDS:
		assert_true(IconLib.stat_icon(stat) != null, "%s has a stat icon" % stat)
	assert_true(
		IconLib.stat_icon("does_not_exist") == null,
		"an unknown stat returns null"
	)


func test_item_icons_load() -> void:
	for id in ITEM_IDS:
		assert_true(IconLib.item_icon(id) != null, "%s has an item icon" % id)
	assert_true(
		IconLib.item_icon("does_not_exist") == null,
		"an unknown item returns null"
	)


func test_martial_cards_show_texture_rect_icons() -> void:
	GameState.reset()
	var view: Variant = load("res://features/battle/battle_view.gd").new()
	view.build_ui()
	view.start("bandit", 1, true)
	assert_eq(
		view.martial_buttons.size(), view.battle.loadout.size(),
		"one card per martial"
	)
	for i in range(view.martial_buttons.size()):
		var card: Button = view.martial_buttons[i]
		var icon: Node = card.get_node_or_null("Icon")
		assert_true(icon is TextureRect, "martial card %d has an icon rect" % i)
		if icon is TextureRect:
			var icon_rect: TextureRect = icon
			assert_true(icon_rect.texture != null, "martial card %d has an icon texture" % i)
	var round_before: int = int(view.battle.round)
	view.martial_buttons[0].emit_signal("pressed")
	assert_eq(
		int(view.battle.round), round_before + 1,
		"the card still submits its martial when clicked"
	)
	view.free()
	GameState.reset()


func test_character_panel_shows_martial_and_item_icons() -> void:
	GameState.reset()
	Progression.reload_items()
	var panel: Variant = load("res://features/character/character_panel.gd").new()
	panel.refresh()
	panel.select_tab(1)
	for i in range(4):
		var icon: Node = panel.find_child("SlotIcon_%d" % i, true, false)
		assert_true(icon is TextureRect, "loadout slot %d shows a texture icon" % i)
		if icon is TextureRect:
			var icon_rect: TextureRect = icon
			assert_true(icon_rect.texture != null, "loadout slot %d has a texture" % i)
	var learned_icon: Node = panel.find_child("MartialIcon_basic_sword", true, false)
	assert_true(learned_icon is TextureRect, "the learned row shows its martial icon")

	Progression.give_item("plain_sword")
	Progression.equip("plain_sword")
	panel.select_tab(2)
	var weapon_icon: Node = panel.find_child("SlotItemIcon_weapon", true, false)
	assert_true(weapon_icon is TextureRect, "the weapon slot shows the equipped item icon")
	if weapon_icon is TextureRect:
		var weapon_rect: TextureRect = weapon_icon
		assert_true(
			weapon_rect.texture == IconLib.item_icon("plain_sword"),
			"the weapon slot uses the iron sword icon for the plain sword"
		)
	var bag_icon: Node = panel.find_child("BagIcon_plain_sword", true, false)
	assert_true(bag_icon is TextureRect, "the bag row shows the item icon")

	panel.select_tab(0)
	for stat in ["power", "speed", "defense", "recovery", "skill"]:
		var attr_icon: Node = panel.find_child("AttrIcon_%s" % stat, true, false)
		assert_true(attr_icon is TextureRect, "%s row shows a stat icon" % stat)
	panel.free()
	GameState.reset()


func test_tavern_furniture_uses_ai_sprites() -> void:
	GameState.reset()
	var tavern: Variant = load("res://features/tavern/tavern.gd").new()
	tavern.build()
	var table_ids: Array[String] = ["table_1", "table_2", "table_3", "table_4"]
	for id in table_ids:
		var node: Node3D = tavern.furniture_nodes[id]
		var sprite: Node = node.get_node_or_null("TableSprite")
		assert_true(sprite is Sprite3D, "%s uses a table sprite" % id)
		if sprite is Sprite3D:
			var table_sprite: Sprite3D = sprite
			assert_true(table_sprite.texture != null, "%s has a table texture" % id)

	var debris: Node3D = tavern.find_child("WreckedDebris", true, false) as Node3D
	assert_true(debris != null, "wrecked debris exist")
	if debris != null:
		assert_true(not debris.visible, "wrecked debris are hidden in the normal state")

	tavern.set_state("brawl", true)
	var table_1: Node3D = tavern.furniture_nodes["table_1"]
	var wrecked_value: Node = table_1.get_node_or_null("TableWreckedSprite")
	assert_true(wrecked_value is Sprite3D, "the fallen table has a wrecked sprite")
	if wrecked_value is Sprite3D:
		var wrecked_sprite: Sprite3D = wrecked_value
		assert_true(wrecked_sprite.modulate.a < 0.5, "the wrecked art fades in, not a hard cut")
	tavern.advance(1.5)
	var downed := 0
	for id in table_ids:
		var node: Node3D = tavern.furniture_nodes[id]
		var sprite_value: Node = node.get_node_or_null("TableWreckedSprite")
		if sprite_value is Sprite3D:
			var sprite: Sprite3D = sprite_value
			if sprite.visible:
				downed += 1
	assert_true(downed >= 2, "at least two overturned tables are visible in the wrecked state")
	if debris != null:
		assert_true(debris.visible, "wrecked debris are visible in the wrecked state")

	tavern.set_state("normal", false)
	var hidden_debris: Node3D = tavern.find_child("WreckedDebris", true, false) as Node3D
	assert_true(hidden_debris != null and not hidden_debris.visible,
			"wrecked debris disappear in the normal state")
	tavern.free()
	GameState.reset()

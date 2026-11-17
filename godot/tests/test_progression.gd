extends "res://tests/test_case.gd"

const GameState = preload("res://core/game_state.gd")
const Progression = preload("res://core/progression.gd")


func _base() -> Dictionary:
	return {
		"power": 10,
		"speed": 15,
		"defense": 5,
		"recovery": 5,
		"skill": 20,
		"constitution": 5,
	}


func test_final_stats_without_growth_equals_base() -> void:
	GameState.reset()
	Progression.reload_items()
	var base := _base()
	assert_eq(Progression.final_stats(base), base, "no growth leaves the base stats unchanged")
	GameState.reset()


func test_final_stats_adds_stat_bonus_and_equipment() -> void:
	GameState.reset()
	Progression.reload_items()
	GameState.stat_bonus["power"] = 2
	GameState.equipment["weapon"] = "plain_sword"
	var result: Dictionary = Progression.final_stats(_base())
	assert_eq(int(result["power"]), 13, "base 10 + 2 permanent + 1 sword")
	assert_eq(int(result["speed"]), 16, "base 15 + 1 sword")
	assert_eq(int(result["defense"]), 5, "untouched stat stays at base")
	assert_eq(int(result["skill"]), 20, "untouched stat stays at base")
	GameState.reset()


func test_unknown_stat_is_ignored() -> void:
	GameState.reset()
	Progression.reload_items()
	GameState.stat_bonus["luck"] = 99
	var result: Dictionary = Progression.final_stats(_base())
	assert_eq(result, _base(), "unknown stat keys are ignored")
	assert_true(not result.has("luck"), "unknown stat is not added to the result")
	GameState.reset()


func test_add_stat_accumulates_and_pushes_toast() -> void:
	GameState.reset()
	Progression.add_stat("power", 2)
	Progression.add_stat("power", 1)
	assert_eq(int(GameState.stat_bonus["power"]), 3, "stat bonus accumulates")
	assert_eq(
		Progression.take_toasts(),
		["力量 +2", "力量 +1"],
		"each add_stat pushes a Chinese stat toast"
	)
	assert_eq(Progression.take_toasts(), [], "take_toasts clears the queue")
	GameState.reset()


func test_add_stat_ignores_unknown_stat() -> void:
	GameState.reset()
	Progression.add_stat("luck", 5)
	assert_eq(GameState.stat_bonus, {}, "unknown stat is not stored")
	assert_eq(Progression.take_toasts(), [], "unknown stat pushes no toast")
	GameState.reset()


func test_give_item_auto_equips_weapon() -> void:
	GameState.reset()
	Progression.reload_items()
	Progression.give_item("plain_sword")
	assert_eq(Progression.item_count("plain_sword"), 1, "the sword is in the inventory")
	assert_eq(Progression.equipped("weapon"), "plain_sword", "an empty weapon slot auto-equips")
	assert_eq(
		Progression.take_toasts(),
		["获得 普通的剑", "已装备 普通的剑"],
		"pickup and auto-equip both toast"
	)
	var result: Dictionary = Progression.final_stats(_base())
	assert_eq(int(result["speed"]), 16, "equipped sword adds speed")
	assert_eq(int(result["power"]), 11, "equipped sword adds power")
	GameState.reset()


func test_give_material_does_not_equip() -> void:
	GameState.reset()
	Progression.reload_items()
	Progression.give_item("herb", 2)
	assert_eq(Progression.item_count("herb"), 2, "materials stack in the inventory")
	assert_eq(Progression.equipped("weapon"), "", "a material does not fill a weapon slot")
	assert_eq(Progression.take_toasts(), ["获得 草药"], "only the pickup toast fires")
	GameState.reset()


func test_use_permanent_item_consumes_and_applies_bonus() -> void:
	GameState.reset()
	Progression.reload_items()
	Progression.give_item("yangyuan_pill", 2)
	Progression.take_toasts()
	assert_true(Progression.use_permanent_item("yangyuan_pill"), "the pill can be used")
	assert_eq(Progression.item_count("yangyuan_pill"), 1, "one pill is consumed")
	assert_eq(int(GameState.stat_bonus.get("constitution", 0)), 1, "the pill adds constitution")
	assert_eq(
		Progression.take_toasts(),
		["体质 +1", "气血上限 +15"],
		"using the pill toasts the stat and the hp gain"
	)
	assert_true(Progression.use_permanent_item("yangyuan_pill"), "the second pill can be used")
	assert_eq(Progression.item_count("yangyuan_pill"), 0, "the second pill is consumed")
	assert_true(not Progression.use_permanent_item("yangyuan_pill"), "an empty stack cannot be used")
	assert_true(not Progression.use_permanent_item("herb"), "items without perm cannot be used")
	GameState.reset()


func test_reset_clears_growth_state() -> void:
	GameState.reset()
	GameState.stat_bonus["power"] = 1
	GameState.equipment["weapon"] = "plain_sword"
	GameState.inventory["herb"] = 3
	GameState.quests["herbs"] = {"state": "active", "progress": {"herb": 3}}
	GameState.mastery_exp["basic_sword"] = 5
	GameState.toasts.append("提示")
	GameState.reset()
	assert_eq(GameState.stat_bonus, {}, "stat bonus is cleared")
	assert_eq(GameState.equipment, {}, "equipment is cleared")
	assert_eq(GameState.inventory, {}, "inventory is cleared")
	assert_eq(GameState.quests, {}, "quests are cleared")
	assert_eq(GameState.mastery_exp, {}, "mastery exp is cleared")
	assert_eq(GameState.toasts, [], "toasts are cleared")


func test_reset_restores_initial_points_and_clears_mastery_total() -> void:
	GameState.reset()
	assert_eq(GameState.unspent_points, 3, "a new game starts with the tutorial points")
	assert_eq(GameState.mastery_total, {}, "the mastery total starts empty")
	GameState.unspent_points = 7
	GameState.mastery_total["basic_sword"] = 20
	GameState.reset()
	assert_eq(GameState.unspent_points, 3, "reset restores the tutorial points")
	assert_eq(GameState.mastery_total, {}, "reset clears the mastery total")


func test_add_points_accumulates_and_toasts() -> void:
	GameState.reset()
	Progression.add_points(2)
	Progression.add_points(1)
	assert_eq(GameState.unspent_points, 6, "awarded points accumulate")
	assert_eq(
		Progression.take_toasts(),
		["获得 2 点属性点", "获得 1 点属性点"],
		"each award pushes a Chinese toast"
	)
	GameState.reset()


func test_spend_point_applies_bonus_without_toast() -> void:
	GameState.reset()
	Progression.reload_items()
	assert_true(Progression.can_spend("power"), "power can be raised")
	assert_true(Progression.spend_point("power"), "the first point is spent")
	assert_true(Progression.spend_point("power"), "the second point is spent")
	assert_eq(int(GameState.stat_bonus.get("power", 0)), 2, "each point adds one bonus")
	assert_eq(GameState.unspent_points, 1, "each point is deducted")
	assert_eq(Progression.take_toasts(), [], "spending points is silent")
	GameState.reset()


func test_can_spend_checks_points_names_and_cap() -> void:
	GameState.reset()
	Progression.reload_items()
	assert_true(not Progression.can_spend("luck"), "unknown stats are rejected")
	GameState.unspent_points = 0
	assert_true(not Progression.can_spend("power"), "no points means no spending")
	GameState.unspent_points = 3
	GameState.stat_bonus["speed"] = 42
	assert_true(not Progression.can_spend("speed"), "a stat at the cap cannot be raised")
	assert_true(Progression.can_spend("power"), "other stats remain available")
	assert_true(not Progression.spend_point("speed"), "spend_point honours the cap")
	GameState.reset()


func test_equip_and_unequip_keep_the_item_in_the_bag() -> void:
	GameState.reset()
	Progression.reload_items()
	Progression.give_item("cloth_robe")
	assert_eq(Progression.equipped("armor"), "", "armor does not auto-equip")
	assert_true(Progression.equip("cloth_robe"), "the robe can be equipped")
	assert_eq(Progression.equipped("armor"), "cloth_robe", "the robe fills the armor slot")
	assert_eq(Progression.item_count("cloth_robe"), 1, "the robe stays in the bag")
	assert_eq(
		Progression.take_toasts(),
		["获得 粗布衣", "已装备 粗布衣"],
		"pickup and equip both toast"
	)
	Progression.unequip("armor")
	assert_eq(Progression.equipped("armor"), "", "unequip empties the slot")
	assert_eq(Progression.item_count("cloth_robe"), 1, "unequip keeps the item in the bag")
	GameState.reset()


func test_equip_rejects_materials_and_missing_items() -> void:
	GameState.reset()
	Progression.reload_items()
	assert_true(not Progression.equip("jade_pendant"), "an unowned item cannot be equipped")
	Progression.give_item("herb")
	assert_true(not Progression.equip("herb"), "materials cannot be equipped")
	assert_eq(GameState.equipment, {}, "no slot was filled")
	GameState.reset()

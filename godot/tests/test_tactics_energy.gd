extends "res://tests/test_case.gd"

# 能量模型：内力 / 紫气 / 仙气池、品质消耗、紫气回复、锁定、反制与 bot 选能量。

const EnemyDef = preload("res://core/enemy_def.gd")
const Facing = preload("res://core/tactics/facing.gd")
const GameState = preload("res://core/game_state.gd")
const Grid = preload("res://core/tactics/grid.gd")
const MartialDef = preload("res://core/martial_def.gd")
const Mastery = preload("res://core/mastery.gd")
const TacticsBattle = preload("res://core/tactics/tactics_battle.gd")
const TacticsBot = preload("res://core/tactics/tactics_bot.gd")
const TacticsDamage = preload("res://core/tactics/tactics_damage.gd")
const TacticsEnergy = preload("res://core/tactics/tactics_energy.gd")
const TacticsReaction = preload("res://core/tactics/tactics_reaction.gd")
const TacticsRuleData = preload("res://core/tactics/tactics_rule_data.gd")
const TacticsUnit = preload("res://core/tactics/tactics_unit.gd")
const Unit = preload("res://core/unit.gd")

const MELEE := {"shape": "melee", "min": 1, "max": 1, "width": 1, "pierce": false}


func _stats(power := 10, speed := 15, defense := 0, recovery := 0, skill := 20,
		constitution := 0) -> Dictionary:
	return {"power": power, "speed": speed, "defense": defense,
			"recovery": recovery, "skill": skill, "constitution": constitution}


func _grid(tiles: Array = ["......"]) -> Variant:
	var size_x := 0
	if not tiles.is_empty():
		size_x = str(tiles[0]).length()
	return Grid.from_dict({"width": size_x, "height": tiles.size(), "tiles": tiles})


func _martial(martial_id: String, grade := "common", power := 10) -> Variant:
	return MartialDef.from_dict({
		"id": martial_id, "name": martial_id, "power": power, "counters": ["heavy"],
		"initiative": 0, "counter_level": 5, "grade": grade,
		"advantage_stat": "skill", "range": MELEE, "effects": [],
	})


func _martials() -> Dictionary:
	return {
		"basic_sword": _martial("basic_sword", "common", 10),
		"taiji": _martial("taiji", "rare", 5),
		"jueshi": _martial("jueshi", "legendary", 18),
	}


func _player(energy: Dictionary = {}, loadout: Array = ["basic_sword", "taiji"],
		speed := 15, hp := 500) -> Variant:
	var core = Unit.make_player("测试", _stats(10, speed), hp, 0, 0, "lianti")
	return TacticsUnit.create("player", core, "player", Vector2i(0, 0), Facing.RIGHT,
		loadout, energy)


func _enemy(speed := 10, hp := 500, tier := "minion") -> Variant:
	var def = EnemyDef.from_dict({
		"id": "enemy", "name": "enemy", "tier": tier,
		"stats": _stats(10, speed, 0, 0, 0), "max_hp": hp,
		"toughness": 0, "stun_turns": 1,
		"moves": [{"id": "swing", "name": "swing", "type": "heavy", "threat": 0,
				"power": 10, "range": MELEE}],
		"weak_moves": [],
	})
	return TacticsUnit.create("enemy", Unit.from_enemy(def), "enemy", Vector2i(1, 0),
		Facing.LEFT, [], {})


func _battle(units: Array, martials: Dictionary = {}, seed_value := 1) -> Variant:
	var use_martials := _martials() if martials.is_empty() else martials
	return TacticsBattle.create(
		_grid(), units, use_martials, Mastery.new(), "defeat_all", "", seed_value)


func _first_event(events: Array, event_type: String) -> Dictionary:
	for event in events:
		if str(event.get("type", "")) == event_type:
			return event
	return {}


func test_energy_rules_load() -> void:
	var pools: Dictionary = TacticsEnergy.initial_pools()
	assert_eq(int(pools.get("neili", 0)), 14)
	assert_eq(int(pools.get("ziqi", 0)), 4)
	assert_eq(int(pools.get("xianqi", -1)), 0)
	assert_eq(TacticsEnergy.grade_cost("common"), 1)
	assert_eq(TacticsEnergy.grade_cost("fine"), 1)
	assert_eq(TacticsEnergy.grade_cost("rare"), 2)
	assert_eq(TacticsEnergy.grade_cost("epic"), 3)
	assert_eq(TacticsEnergy.grade_cost("legendary"), 4)
	assert_eq(TacticsEnergy.damage_pct("neili"), 100)
	assert_eq(TacticsEnergy.damage_pct("ziqi"), 60)
	assert_eq(TacticsEnergy.damage_pct("xianqi"), 100)
	assert_true(TacticsEnergy.is_locked("xianqi"), "xianqi is locked for now")
	assert_true(not TacticsEnergy.is_locked("ziqi"))
	var martials := _martials()
	assert_eq(TacticsEnergy.cost_for(martials["basic_sword"]), 0, "basic_sword is free")
	assert_eq(TacticsEnergy.cost_for(martials["taiji"]), 2)
	assert_eq(TacticsEnergy.cost_for(martials["jueshi"]), 4)


func test_pools_start_from_data_and_spend_by_cost() -> void:
	var player = _player()
	assert_eq(int(player.energy_left["neili"]), 14)
	assert_eq(int(player.energy_left["ziqi"]), 4)
	assert_true(player.can_pay("neili", 14))
	assert_true(not player.can_pay("neili", 15))
	player.spend_energy("neili", 2)
	assert_eq(int(player.energy_left["neili"]), 12)
	assert_eq(int(player.energy_max["neili"]), 14, "spending never lowers the maximum")


func test_player_data_can_override_pools() -> void:
	var player = _player({"neili": 7, "ziqi": 1})
	assert_eq(int(player.energy_left["neili"]), 7)
	assert_eq(int(player.energy_max["neili"]), 7)
	assert_eq(int(player.energy_left["ziqi"]), 1)


func test_insufficient_pool_rejects_the_attack() -> void:
	var player = _player({"neili": 0})
	var enemy = _enemy()
	var b = _battle([player, enemy])
	assert_eq(b.begin_turn(), "player")
	var result: Dictionary = b.attack("player", "taiji", Vector2i(1, 0))
	assert_true(not bool(result["ok"]))
	assert_eq(str(result["reason"]), "no_energy")
	assert_true(player.has_acted == false, "a rejected attack does not spend the action")


func test_any_martial_can_use_any_energy() -> void:
	var player = _player({"ziqi": 4})
	var enemy = _enemy()
	var b = _battle([player, enemy])
	assert_eq(b.begin_turn(), "player")
	var result: Dictionary = b.attack("player", "taiji", Vector2i(1, 0), {}, "ziqi")
	assert_true(bool(result["ok"]), "a counter martial can attack with ziqi")
	assert_eq(int(player.energy_left["ziqi"]), 2)
	assert_eq(str(_first_event(result["events"], "attack").get("energy", "")), "ziqi")


func test_ziqi_trades_damage_for_healing() -> void:
	var player = _player()
	player.unit.hp = 300
	var enemy = _enemy()
	var martials := _martials()
	var b = _battle([player, enemy], martials)
	assert_eq(b.begin_turn(), "player")
	var base := TacticsDamage.martial_damage(
		player.unit.stats, player.unit.realm, 5, 1.0, enemy.unit, "front", 0.0)
	var result: Dictionary = b.attack("player", "taiji", Vector2i(1, 0), {}, "ziqi")
	assert_true(bool(result["ok"]))
	var hit := _first_event(result["events"], "hit")
	var expected_damage := maxi(1, floori(float(base) * 0.6))
	assert_eq(int(hit.get("damage", -1)), expected_damage, "ziqi deals 60% damage")
	var expected_heal := floori(float(expected_damage) * 1.5 * (1.0 + 20.0 / 100.0))
	assert_eq(int(player.unit.hp), 300 + expected_heal, "the heal follows the formula")
	var heal := _first_event(result["events"], "heal")
	assert_eq(str(heal.get("unit", "")), "player")
	assert_eq(int(heal.get("amount", -1)), expected_heal)
	assert_eq(int(player.energy_left["ziqi"]), 2, "a rare martial costs two ziqi")


func test_heal_is_capped_by_max_hp() -> void:
	var player = _player()
	player.unit.hp = 499
	var enemy = _enemy()
	var b = _battle([player, enemy])
	assert_eq(b.begin_turn(), "player")
	b.attack("player", "taiji", Vector2i(1, 0), {}, "ziqi")
	assert_eq(int(player.unit.hp), 500, "healing never exceeds the maximum")


func test_neili_keeps_full_damage_without_healing() -> void:
	var player = _player()
	player.unit.hp = 300
	var enemy = _enemy()
	var martials := _martials()
	var b = _battle([player, enemy], martials)
	assert_eq(b.begin_turn(), "player")
	var base := TacticsDamage.martial_damage(
		player.unit.stats, player.unit.realm, 5, 1.0, enemy.unit, "front", 0.0)
	var result: Dictionary = b.attack("player", "taiji", Vector2i(1, 0), {}, "neili")
	var hit := _first_event(result["events"], "hit")
	assert_eq(int(hit.get("damage", -1)), base, "neili keeps 100% damage")
	assert_true(_first_event(result["events"], "heal").is_empty(), "neili never heals")
	assert_eq(int(player.unit.hp), 300)
	assert_eq(int(player.energy_left["neili"]), 12)


func test_xianqi_is_locked() -> void:
	var player = _player()
	assert_true(not player.has_energy("xianqi"))
	assert_true(not player.can_pay("xianqi", 0), "a locked pool cannot be chosen")
	var enemy = _enemy()
	var b = _battle([player, enemy])
	assert_eq(b.begin_turn(), "player")
	var result: Dictionary = b.attack("player", "basic_sword", Vector2i(1, 0), {}, "xianqi")
	assert_true(not bool(result["ok"]))
	assert_eq(str(result["reason"]), "no_energy")


func test_basic_sword_is_free_for_any_energy() -> void:
	var player = _player({"neili": 0})
	var enemy = _enemy()
	var b = _battle([player, enemy])
	assert_eq(b.begin_turn(), "player")
	var result: Dictionary = b.attack("player", "basic_sword", Vector2i(1, 0), {}, "neili")
	assert_true(bool(result["ok"]), "basic_sword works even at zero neili")
	assert_eq(int(player.energy_left["neili"]), 0, "basic_sword spends no pool")


func test_counter_spends_neili_and_block_is_free() -> void:
	var player = _player({"neili": 2}, ["taiji"])
	player.reactions_left = 1
	var enemy = _enemy()
	var b = _battle([player, enemy])
	assert_eq(b.begin_turn(), "player")
	b.end_turn("player")
	assert_eq(b.begin_turn(), "enemy")
	var result: Dictionary = b.attack(
		"enemy", "swing", Vector2i(0, 0), {"player": "taiji"})
	assert_true(bool(result["ok"]))
	assert_eq(str(_first_event(result["events"], "hit").get("outcome", "")), "perfect")
	assert_eq(int(player.energy_left["neili"]), 0, "a rare counter costs two neili")

	var blocker = _player({"neili": 2}, ["taiji"])
	blocker.reactions_left = 1
	var blocked = _battle([blocker, _enemy()])
	assert_eq(blocked.begin_turn(), "player")
	blocked.end_turn("player")
	assert_eq(blocked.begin_turn(), "enemy")
	blocked.attack("enemy", "swing", Vector2i(0, 0), {"player": "_block"})
	assert_eq(int(blocker.energy_left["neili"]), 2, "basic block spends no neili")


func test_reaction_options_need_neili_but_keep_block() -> void:
	var player = _player({"neili": 0}, ["taiji"])
	player.reactions_left = 1
	var enemy = _enemy()
	var move_def := {"id": "swing", "name": "swing", "type": "heavy", "power": 10}
	var options: Array = TacticsReaction.options(
		player, enemy, move_def, _martials(), Mastery.new(), "front", {"grid": _grid()})
	var ids: Array = []
	for option in options:
		ids.append(str(option.get("id", "")))
	var block_id := str(TacticsRuleData.basic_block().get("id", ""))
	assert_eq(ids, [block_id], "no neili leaves only the basic block")


func test_bot_prefers_the_weakness_color() -> void:
	var player = _player({}, ["basic_sword", "taiji"], 15)
	var boss = _enemy(1)
	var b = _battle([player, boss])
	# battle assembly draws the weaknesses, so pin them afterwards
	boss.weaknesses = ["ziqi", "none"]
	assert_eq(b.begin_turn(), "player")
	var events: Array = TacticsBot.take_turn(b, "player", _rng(1), "best")
	var attack := _first_event(events, "attack")
	assert_eq(str(attack.get("energy", "")), "ziqi", "the bot matches the weakness color")


func test_bot_uses_ziqi_when_hurt() -> void:
	var player = _player({}, ["basic_sword", "taiji"], 15, 500)
	# 45%：低于紫气回复偏好的 50%，但高于主动运功的 40% 阈值，仍走紫气出招。
	player.unit.hp = 225
	var boss = _enemy(1)
	var b = _battle([player, boss])
	boss.weaknesses = ["none", "none"]
	assert_eq(b.begin_turn(), "player")
	var events: Array = TacticsBot.take_turn(b, "player", _rng(1), "best")
	var attack := _first_event(events, "attack")
	assert_eq(str(attack.get("energy", "")), "ziqi", "low hp prefers ziqi healing")


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _make_view() -> Dictionary:
	GameState.reset()
	var tree: Variant = Engine.get_meta("test_tree", null)
	var holder := Control.new()
	holder.size = Vector2(1152.0, 720.0)
	if tree != null:
		tree.root.add_child(holder)
	var view: Variant = load("res://features/tactics/tactics_view.gd").new()
	view.use_3d = false
	holder.add_child(view)
	view.size = Vector2(1152.0, 720.0)
	return {"holder": holder, "view": view}


func _finish(holder: Control) -> void:
	holder.free()
	GameState.reset()


func test_panel_energy_buttons_show_pools_and_switch() -> void:
	var built := _make_view()
	var view: Variant = built["view"]
	view.start()
	assert_eq(view.panel.energy_buttons.size(), 3, "neili / ziqi / xianqi buttons")
	assert_true(str(view.panel.energy_buttons["neili"].text).contains("14/14"),
		"the neili button shows left/max")
	assert_true(view.panel.energy_buttons["xianqi"].disabled, "xianqi starts greyed out")
	view.panel.select_energy("ziqi")
	assert_eq(str(view.panel.energy), "ziqi")
	assert_true(bool(view.panel.energy_buttons["ziqi"].get_meta("selected", false)))
	view.panel.select_energy("xianqi")
	assert_eq(str(view.panel.energy), "ziqi", "a locked energy cannot be selected")
	_finish(built["holder"])


func test_tab_cycles_energy_and_skips_locked() -> void:
	var built := _make_view()
	var view: Variant = built["view"]
	view.start()
	view.panel.select_energy("neili")
	view._player_input.handle_key(KEY_TAB)
	assert_eq(str(view.panel.energy), "ziqi")
	view._player_input.handle_key(KEY_TAB)
	assert_eq(str(view.panel.energy), "neili", "Tab skips the locked xianqi")
	_finish(built["holder"])


func test_unit_card_shows_the_three_pools() -> void:
	var built := _make_view()
	var view: Variant = built["view"]
	view.start()
	var labels: Variant = view.unit_card.get("_energy_labels")
	assert_true(labels is Dictionary and labels.size() == 3,
		"the unit card maps each pool to a label")
	if labels is Dictionary:
		assert_eq(str(labels["neili"].text), "14/14")
		assert_eq(str(labels["ziqi"].text), "4/4")
		assert_eq(str(labels["xianqi"].text), "0/0")
	var row: Variant = view.unit_card.get("_energy_row")
	assert_true(row != null and row.get_child_count() == 3,
		"each pool renders as one icon + number cell")
	_finish(built["holder"])

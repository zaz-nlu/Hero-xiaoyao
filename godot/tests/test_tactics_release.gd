extends "res://tests/test_case.gd"

# 紫气主动释放：数值、资格、事件、bot 决策与界面按钮/快捷键/单位卡布局。

const EnemyDef = preload("res://core/enemy_def.gd")
const Facing = preload("res://core/tactics/facing.gd")
const GameState = preload("res://core/game_state.gd")
const Grid = preload("res://core/tactics/grid.gd")
const MartialDef = preload("res://core/martial_def.gd")
const Mastery = preload("res://core/mastery.gd")
const TacticsBattle = preload("res://core/tactics/tactics_battle.gd")
const TacticsBot = preload("res://core/tactics/tactics_bot.gd")
const TacticsRelease = preload("res://core/tactics/tactics_release.gd")
const TacticsRuleData = preload("res://core/tactics/tactics_rule_data.gd")
const TacticsSfx = preload("res://features/tactics/tactics_sfx.gd")
const TacticsUnit = preload("res://core/tactics/tactics_unit.gd")
const Unit = preload("res://core/unit.gd")

const MELEE := {"shape": "melee", "min": 1, "max": 1, "width": 1, "pierce": false}


func _stats(power := 10, speed := 15, defense := 0, recovery := 0, skill := 20,
		constitution := 0) -> Dictionary:
	return {"power": power, "speed": speed, "defense": defense,
			"recovery": recovery, "skill": skill, "constitution": constitution}


func _grid(tiles: Array = ["......"]) -> Variant:
	return Grid.from_dict({"width": str(tiles[0]).length(), "height": tiles.size(),
			"tiles": tiles})


func _martials() -> Dictionary:
	return {
		"basic_sword": MartialDef.from_dict({
			"id": "basic_sword", "name": "basic_sword", "power": 10,
			"counters": ["heavy"], "initiative": 0, "counter_level": 5,
			"grade": "common", "advantage_stat": "skill", "range": MELEE,
			"effects": [],
		}),
	}


func _player(max_hp := 500, hp := -1, ziqi := 4, speed := 15) -> Variant:
	var core = Unit.make_player("测试", _stats(10, speed), max_hp, 0, 0, "lianti")
	if hp >= 0:
		core.hp = hp
	return TacticsUnit.create("player", core, "player", Vector2i(0, 0), Facing.RIGHT,
		["basic_sword"], {"ziqi": ziqi})


func _enemy(speed := 10) -> Variant:
	var def = EnemyDef.from_dict({
		"id": "enemy", "name": "enemy", "tier": "minion",
		"stats": _stats(10, speed, 0, 0, 0), "max_hp": 500,
		"toughness": 0, "stun_turns": 1,
		"moves": [{"id": "swing", "name": "swing", "type": "heavy", "threat": 0,
				"power": 10, "range": MELEE}],
		"weak_moves": [],
	})
	return TacticsUnit.create("enemy", Unit.from_enemy(def), "enemy", Vector2i(1, 0),
		Facing.LEFT, [], {})


func _battle(units: Array) -> Variant:
	return TacticsBattle.create(
		_grid(), units, _martials(), Mastery.new(), "defeat_all", "", 1)


func _first_event(events: Array, event_type: String) -> Dictionary:
	for event in events:
		if str(event.get("type", "")) == event_type:
			return event
	return {}


func _release_count(battle: Variant) -> int:
	var count := 0
	for event in battle.log:
		if str(event.get("type", "")) == "heal" \
				and str(event.get("source", "")) == "ziqi_release":
			count += 1
	return count


func test_rule_data_reads_release_numbers() -> void:
	var block: Dictionary = TacticsRuleData.ziqi_release()
	assert_eq(int(block.get("cost", -1)), 1)
	assert_eq(int(block.get("heal_pct", -1)), 20)
	assert_eq(TacticsRelease.cost(), 1)
	assert_eq(TacticsRelease.heal_pct(), 20)
	assert_eq(TacticsRelease.heal_amount(507), 101, "20% of 507 floors to 101")
	assert_eq(TacticsRelease.heal_amount(1), 1, "the heal is at least one point")


func test_rule_data_reports_a_missing_release_section() -> void:
	var text := FileAccess.get_file_as_string("res://data/tactics_rules.json")
	var parsed: Variant = JSON.parse_string(text)
	assert_true(parsed is Dictionary, "the shipped rules file parses")
	if not (parsed is Dictionary):
		return
	var broken: Dictionary = (parsed as Dictionary).duplicate(true)
	broken.erase("ziqi_release")
	var result: Dictionary = TacticsRuleData.parse_rules(broken)
	assert_true(not bool(result.get("ok", false)), "a missing section is rejected")
	var errors: Array = result.get("errors", [])
	assert_true(_errors_contain(errors, "ziqi_release"),
		"the error names the missing section")


func test_release_heals_twenty_percent_and_spends_one_ziqi() -> void:
	var player = _player(507, 300)
	var b = _battle([player, _enemy()])
	assert_eq(b.begin_turn(), "player")
	var result: Dictionary = b.release_ziqi("player")
	assert_true(bool(result["ok"]))
	var heal := _first_event(result["events"], "heal")
	assert_eq(str(heal.get("unit", "")), "player")
	assert_eq(str(heal.get("source", "")), "ziqi_release")
	assert_eq(int(heal.get("amount", -1)), 101)
	assert_eq(int(player.unit.hp), 401)
	assert_eq(int(player.energy_left["ziqi"]), 3)
	assert_true(player.has_acted, "release spends the turn action")


func test_release_heal_is_capped_by_max_hp() -> void:
	var player = _player(500, 480)
	var b = _battle([player, _enemy()])
	assert_eq(b.begin_turn(), "player")
	var result: Dictionary = b.release_ziqi("player")
	assert_true(bool(result["ok"]))
	assert_eq(int(player.unit.hp), 500)
	assert_eq(int(_first_event(result["events"], "heal").get("amount", -1)), 20)


func test_release_rejects_full_hp_without_spending_ziqi() -> void:
	var player = _player(500)
	var b = _battle([player, _enemy()])
	assert_eq(b.begin_turn(), "player")
	var result: Dictionary = b.release_ziqi("player")
	assert_true(not bool(result["ok"]))
	assert_eq(str(result["reason"]), "full_hp")
	assert_eq(int(player.energy_left["ziqi"]), 4, "a rejected release spends nothing")
	assert_true(not player.has_acted)


func test_release_rejects_without_ziqi() -> void:
	var player = _player(500, 300, 0)
	var b = _battle([player, _enemy()])
	assert_eq(b.begin_turn(), "player")
	var result: Dictionary = b.release_ziqi("player")
	assert_true(not bool(result["ok"]))
	assert_eq(str(result["reason"]), "no_energy")
	assert_eq(int(player.unit.hp), 300)


func test_release_rejects_when_already_acted() -> void:
	var player = _player(500, 300)
	var b = _battle([player, _enemy()])
	assert_eq(b.begin_turn(), "player")
	player.has_acted = true
	var result: Dictionary = b.release_ziqi("player")
	assert_true(not bool(result["ok"]))
	assert_eq(str(result["reason"]), "already_acted")
	assert_eq(int(player.energy_left["ziqi"]), 4)


func test_release_cannot_target_the_enemy_side() -> void:
	var player = _player(500, 300, 4, 1)
	var enemy = _enemy(20)
	var b = _battle([player, enemy])
	assert_eq(b.begin_turn(), "enemy")
	var result: Dictionary = b.release_ziqi("enemy")
	assert_true(not bool(result["ok"]))
	assert_eq(str(result["reason"]), "player_only")


func test_release_blocks_a_later_attack_this_turn() -> void:
	var player = _player(500, 300)
	var b = _battle([player, _enemy()])
	assert_eq(b.begin_turn(), "player")
	assert_true(bool(b.release_ziqi("player")["ok"]))
	var attack: Dictionary = b.attack("player", "basic_sword", Vector2i(1, 0))
	assert_true(not bool(attack["ok"]))
	assert_eq(str(attack["reason"]), "already_acted")


func test_release_heal_uses_the_heal_sfx_mapping() -> void:
	var event := {"type": "heal", "unit": "player", "amount": 100,
			"source": "ziqi_release"}
	assert_eq(TacticsSfx.key_for(event), "heal")
	assert_eq(str(TacticsSfx.entry_for("heal").get("sfx", "")), "sfx_heal")


func test_bot_releases_when_hp_is_low_and_only_once_per_turn() -> void:
	var player = _player(500, 100)
	var b = _battle([player, _enemy()])
	assert_eq(b.begin_turn(), "player")
	var events: Array = TacticsBot.take_turn(b, "player", _rng(1), "best")
	var heal := _first_event(events, "heal")
	assert_eq(str(heal.get("source", "")), "ziqi_release", "low hp releases first")
	assert_eq(int(player.unit.hp), 200)
	assert_true(player.has_acted)
	TacticsBot.take_turn(b, "player", _rng(1), "best")
	assert_eq(_release_count(b), 1, "the bot releases at most once per turn")


func test_bot_does_not_release_above_forty_percent() -> void:
	var player = _player(500, 300)
	var b = _battle([player, _enemy()])
	assert_eq(b.begin_turn(), "player")
	var events: Array = TacticsBot.take_turn(b, "player", _rng(1), "best")
	assert_true(_first_event(events, "heal").is_empty())
	assert_eq(_release_count(b), 0)


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _errors_contain(errors: Array, needle: String) -> bool:
	for message in errors:
		if str(message).contains(needle):
			return true
	return false


func _make_view(width := 1152.0, height := 720.0) -> Dictionary:
	GameState.reset()
	var tree: Variant = Engine.get_meta("test_tree", null)
	var holder := Control.new()
	holder.size = Vector2(width, height)
	if tree != null:
		tree.root.add_child(holder)
	var view: Variant = load("res://features/tactics/tactics_view.gd").new()
	view.use_3d = false
	holder.add_child(view)
	view.size = Vector2(width, height)
	return {"holder": holder, "view": view}


func _finish(holder: Control) -> void:
	holder.free()
	GameState.reset()


func test_release_button_greys_out_and_h_key_releases() -> void:
	var built := _make_view()
	var view: Variant = built["view"]
	view.start()
	var player = view.battle.get_unit("player")
	var button: Button = view.panel.release_button
	assert_true(button != null, "the skill bar owns a release button")
	if button == null or player == null:
		_finish(built["holder"])
		return
	assert_true(button.disabled, "full hp greys out the release button")
	var hp_before := int(player.unit.max_hp) / 2
	player.unit.hp = hp_before
	view._refresh_all()
	assert_true(not button.disabled, "a wounded unit can release")
	var ziqi_before := int(player.energy_left["ziqi"])
	view._player_input.handle_key(KEY_H)
	assert_true(player.has_acted, "H performs the release")
	assert_eq(int(player.energy_left["ziqi"]), ziqi_before - TacticsRelease.cost())
	assert_true(int(player.unit.hp) > hp_before, "the release heals")
	assert_true(button.disabled, "acting greys out the release button")
	_finish(built["holder"])


func test_release_button_greys_out_without_ziqi() -> void:
	var built := _make_view()
	var view: Variant = built["view"]
	view.start()
	var player = view.battle.get_unit("player")
	if player == null:
		_finish(built["holder"])
		return
	player.unit.hp = int(player.unit.max_hp) / 2
	player.energy_left["ziqi"] = 0
	view._refresh_all()
	assert_true(view.panel.release_button.disabled, "no ziqi greys out the release button")
	_finish(built["holder"])


func test_unit_card_text_fits_a_1152x648_window() -> void:
	var built := _make_view(1152.0, 648.0)
	var view: Variant = built["view"]
	view.start()
	var card = view.unit_card
	assert_true(card != null)
	if card == null:
		_finish(built["holder"])
		return
	assert_true(float(card.custom_minimum_size.y) >= float(card.get_combined_minimum_size().y),
		"the card is tall enough for every text row")
	var info: Control = card.get("_name_label").get_parent()
	assert_true(float(info.get_combined_minimum_size().y) + 16.0
		<= float(card.custom_minimum_size.y),
		"the info rows plus the card margins fit the card height")
	assert_true(648.0 + float(card.offset_top) >= 0.0, "the card top stays inside the window")
	assert_true(648.0 + float(card.offset_bottom) <= 648.0, "the card bottom stays inside")
	var labels: Variant = card.get("_energy_labels")
	assert_true(labels is Dictionary and labels.size() == 3,
		"the energy row shows all three pools")
	if labels is Dictionary:
		assert_eq(str(labels["neili"].text), "14/14", "the neili pool is filled in")
	_finish(built["holder"])

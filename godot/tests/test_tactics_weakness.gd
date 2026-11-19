extends "res://tests/test_case.gd"

# 弱点按“出招所用能量”命中；韧性、击破、蓄势、刷新与音效映射。

const EnemyDef = preload("res://core/enemy_def.gd")
const Facing = preload("res://core/tactics/facing.gd")
const Grid = preload("res://core/tactics/grid.gd")
const MartialDef = preload("res://core/martial_def.gd")
const Mastery = preload("res://core/mastery.gd")
const TacticsBattle = preload("res://core/tactics/tactics_battle.gd")
const TacticsDamage = preload("res://core/tactics/tactics_damage.gd")
const TacticsRuleData = preload("res://core/tactics/tactics_rule_data.gd")
const TacticsSfx = preload("res://features/tactics/tactics_sfx.gd")
const TacticsUnit = preload("res://core/tactics/tactics_unit.gd")
const TacticsWeakness = preload("res://core/tactics/tactics_weakness.gd")
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


func _move(move_id := "swing", move_type := "heavy", power := 10) -> Dictionary:
	return {"id": move_id, "name": move_id, "type": move_type, "threat": 0, "power": power}


func _martial(martial_id: String, power := 10) -> Variant:
	return MartialDef.from_dict({
		"id": martial_id, "name": martial_id, "power": power,
		"counters": ["heavy"], "initiative": 0, "counter_level": 5, "grade": "common",
		"advantage_stat": "skill", "range": MELEE, "effects": [],
	})


func _martials() -> Dictionary:
	return {
		"basic_sword": _martial("basic_sword", 10),
		"taiji": _martial("taiji", 5),
	}


func _player(energy: Dictionary = {}, loadout: Array = ["basic_sword", "taiji"],
		speed := 15, jianyi_max := 0) -> Variant:
	var core = Unit.make_player("测试", _stats(10, speed), 500, jianyi_max, 0, "lianti")
	return TacticsUnit.create("player", core, "player", Vector2i(0, 0), Facing.RIGHT,
		loadout, energy)


func _enemy(tier := "boss", speed := 10, toughness := 5, stun_turns := 1,
		slots := -1) -> Variant:
	var def = EnemyDef.from_dict({
		"id": "enemy", "name": "enemy", "tier": tier,
		"stats": _stats(10, speed, 0, 0, 0), "max_hp": 500,
		"toughness": toughness, "stun_turns": stun_turns,
		"weakness_slots": slots, "moves": [_move()], "weak_moves": [],
	})
	return TacticsUnit.create("enemy", Unit.from_enemy(def), "enemy", Vector2i(1, 0),
		Facing.LEFT, [], {})


func _battle(units: Array, seed_value := 1) -> Variant:
	return TacticsBattle.create(
		_grid(), units, _martials(), Mastery.new(), "defeat_all", "", seed_value)


func _first_event(events: Array, event_type: String) -> Dictionary:
	for event in events:
		if str(event.get("type", "")) == event_type:
			return event
	return {}


func _expected_martial(player, enemy, martial) -> int:
	return TacticsDamage.martial_damage(
		player.unit.stats, player.unit.realm, int(martial.power), 1.0,
		enemy.unit, "front", 0.0)


func test_weakness_rules_load() -> void:
	var block: Dictionary = TacticsRuleData.weakness()
	assert_eq(int(block.get("weak_damage_pct", 0)), 125)
	assert_eq(int(block.get("toughness_hit", 0)), 1)
	assert_eq(int(block.get("toughness_weak", 0)), 2)
	assert_eq(int(block.get("empower_after_turns", 0)), 3)
	assert_eq(int(block.get("empower_pct", 0)), 125)
	var slots: Dictionary = block.get("slots_by_tier", {})
	assert_eq(int(slots.get("minion", -1)), 0)
	assert_eq(int(slots.get("elite", -1)), 1)
	assert_eq(int(slots.get("boss", -1)), 2)


func test_slots_follow_tier_and_override() -> void:
	assert_eq(TacticsWeakness.slot_count(_enemy("minion")), 0, "minions have no weakness")
	assert_eq(TacticsWeakness.slot_count(_enemy("elite")), 1)
	assert_eq(TacticsWeakness.slot_count(_enemy("boss")), 2)
	assert_eq(TacticsWeakness.slot_count(_enemy("boss", 10, 5, 1, 1)), 1,
		"an explicit weakness_slots overrides the tier")
	assert_eq(TacticsWeakness.slot_count(_enemy("minion", 10, 5, 1, 2)), 2)


func test_initial_weaknesses_are_distinct_and_available() -> void:
	var player = _player()
	var boss = _enemy("boss")
	var b: Variant = _battle([player, boss], 5)
	assert_eq(boss.weaknesses.size(), 2)
	assert_true(["neili", "ziqi"].has(str(boss.weaknesses[0])), "only available pools")
	assert_true(["neili", "ziqi"].has(str(boss.weaknesses[1])), "only available pools")
	assert_true(str(boss.weaknesses[0]) != str(boss.weaknesses[1]), "slots are distinct")
	assert_true(b != null)


func test_locked_and_empty_pools_are_not_drawn() -> void:
	var player = _player({"ziqi": 0})
	var boss = _enemy("boss")
	_battle([player, boss], 7)
	assert_eq(str(boss.weaknesses[0]), "neili", "the only available color fills one slot")
	assert_eq(str(boss.weaknesses[1]), "none", "exhausted colors leave a neutral slot")


func test_same_seed_reproduces_weaknesses() -> void:
	var first: Array = []
	var second: Array = []
	for _i in range(2):
		var player = _player()
		var boss = _enemy("boss")
		_battle([player, boss], 42)
		if first.is_empty():
			first = boss.weaknesses.duplicate()
		else:
			second = boss.weaknesses.duplicate()
	assert_eq(first, second, "the same seed draws the same weakness slots")


func test_weak_hit_boosts_damage_chips_two_and_refreshes() -> void:
	var player = _player()
	var boss = _enemy("boss")
	var martials := _martials()
	var b: Variant = _battle([player, boss], 3)
	boss.weaknesses = ["neili", "none"]
	assert_eq(b.begin_turn(), "player")
	var base := _expected_martial(player, boss, martials["basic_sword"])
	var result: Dictionary = b.attack("player", "basic_sword", Vector2i(1, 0))
	assert_true(bool(result["ok"]))
	var hit := _first_event(result["events"], "hit")
	assert_true(bool(hit.get("weak", false)), "the energy matches the weakness slot")
	assert_eq(str(hit.get("weak_color", "")), "neili")
	assert_eq(str(hit.get("energy", "")), "neili")
	assert_eq(int(hit.get("damage", -1)),
		maxi(1, floori(float(base) * 1.25)), "weak hits deal 125% damage")
	assert_near(float(boss.unit.toughness_left), 3.0, 0.0001, "a weak hit chips two")
	assert_near(float(hit.get("toughness_left", -1)), 3.0, 0.0001)
	assert_eq(str(boss.weaknesses[0]), "ziqi", "the hit slot refreshes to another color")
	assert_eq(str(boss.weaknesses[1]), "none", "other slots are unchanged")


func test_non_weak_hit_chips_one() -> void:
	var player = _player()
	var boss = _enemy("boss")
	var martials := _martials()
	var b: Variant = _battle([player, boss], 3)
	boss.weaknesses = ["ziqi", "none"]
	assert_eq(b.begin_turn(), "player")
	var base := _expected_martial(player, boss, martials["basic_sword"])
	var result: Dictionary = b.attack("player", "basic_sword", Vector2i(1, 0))
	var hit := _first_event(result["events"], "hit")
	assert_true(not bool(hit.get("weak", false)))
	assert_eq(int(hit.get("damage", -1)), base, "normal hits keep their damage")
	assert_near(float(boss.unit.toughness_left), 4.0, 0.0001, "a normal hit chips one")
	assert_eq(boss.weaknesses, ["ziqi", "none"], "normal hits do not refresh weaknesses")


func test_jianyi_does_not_trigger_weakness() -> void:
	var player = _player({}, ["basic_sword"], 15, 1)
	var boss = _enemy("boss")
	var martials := _martials()
	var b: Variant = _battle([player, boss], 3)
	boss.weaknesses = ["neili", "none"]
	assert_eq(b.begin_turn(), "player")
	var expected := TacticsDamage.jianyi_damage(
		player.unit.stats, player.unit.realm, int(martials["basic_sword"].power), 1.0)
	assert_true(bool(b.jianyi("player", "basic_sword", Vector2i(1, 0))["ok"]))
	assert_eq(int(boss.unit.hp), 500 - expected, "jianyi true damage is not boosted")
	assert_near(float(boss.unit.toughness_left), 4.0, 0.0001,
		"jianyi is not an energy color: it only chips like a normal hit")
	assert_eq(boss.weaknesses, ["neili", "none"], "jianyi does not refresh a weakness")


func test_counter_and_block_do_not_chip_or_trigger_weakness() -> void:
	var player = _player({}, ["basic_sword"], 15, 2)
	player.reactions_left = 1
	var boss = _enemy("boss", 10, 5, 1, -1)
	var b: Variant = _battle([player, boss])
	boss.weaknesses = ["neili", "ziqi"]
	assert_eq(b.begin_turn(), "player")
	b.end_turn("player")
	assert_eq(b.begin_turn(), "enemy")
	var counter: Dictionary = b.attack(
		"enemy", "swing", Vector2i(0, 0), {"player": "basic_sword"})
	var hit := _first_event(counter["events"], "hit")
	assert_eq(str(hit.get("outcome", "")), "perfect", "the counter negates the hit")
	assert_near(float(boss.unit.toughness_left), 5.0, 0.0001, "counters do not chip toughness")
	assert_eq(boss.weaknesses, ["neili", "ziqi"], "counters never trigger weaknesses")

	var blocker = _player({}, ["basic_sword"], 15, 2)
	blocker.reactions_left = 1
	var blocked_boss = _enemy("boss", 10, 5, 1, -1)
	var blocked: Variant = _battle([blocker, blocked_boss])
	blocked_boss.weaknesses = ["neili", "ziqi"]
	assert_eq(blocked.begin_turn(), "player")
	blocked.end_turn("player")
	assert_eq(blocked.begin_turn(), "enemy")
	var scrape: Dictionary = blocked.attack(
		"enemy", "swing", Vector2i(0, 0), {"player": "_block"})
	assert_eq(str(_first_event(scrape["events"], "hit").get("outcome", "")), "scrape")
	assert_near(float(blocked_boss.unit.toughness_left), 5.0, 0.0001,
		"basic block does not chip toughness")
	assert_eq(blocked_boss.weaknesses, ["neili", "ziqi"],
		"basic block never triggers weaknesses")


func test_break_stuns_clears_weakness_and_grants_jianyi() -> void:
	var player = _player({}, ["basic_sword"], 15, 2)
	player.unit.jianyi_points = 1
	var boss = _enemy("boss", 10, 2, 2)
	var b: Variant = _battle([player, boss], 3)
	boss.weaknesses = ["neili", "ziqi"]
	assert_eq(b.begin_turn(), "player")
	var result: Dictionary = b.attack("player", "basic_sword", Vector2i(1, 0))
	assert_true(bool(result["ok"]))
	assert_true(not _first_event(result["events"], "stun").is_empty(), "breaking emits a stun event")
	assert_eq(int(boss.unit.stun_left), 2, "the boss is stunned for its full duration")
	assert_eq(boss.weaknesses, ["none", "none"], "breaking clears every weakness slot")
	assert_eq(int(player.unit.jianyi_points), 2, "the breaker gains one jianyi point")


func test_stun_end_refills_toughness_and_redraws_weaknesses() -> void:
	var player = _player({}, ["basic_sword"], 15, 1)
	var boss = _enemy("boss", 10, 2, 1)
	var b: Variant = _battle([player, boss], 3)
	boss.weaknesses = ["neili", "ziqi"]
	assert_eq(b.begin_turn(), "player")
	assert_true(bool(b.attack("player", "basic_sword", Vector2i(1, 0))["ok"]))
	assert_eq(int(boss.unit.stun_left), 1)
	b.end_turn("player")
	assert_eq(b.begin_turn(), "player", "the stunned boss skips its turn")
	assert_true(not boss.unit.is_stunned(), "the stun ends after the skipped turn")
	assert_near(float(boss.unit.toughness_left), 2.0, 0.0001, "toughness refills after stun")
	assert_eq(boss.weaknesses.size(), 2, "weakness slots are drawn again")
	assert_true(str(boss.weaknesses[0]) != "none", "the refreshed slots are usable again")
	assert_true(str(boss.weaknesses[0]) != str(boss.weaknesses[1]))


func test_empower_triggers_after_three_quiet_turns() -> void:
	var player = _player({}, ["basic_sword"], 1, 1)
	var boss = _enemy("boss", 20)
	var b: Variant = _battle([player, boss])
	boss.weaknesses = ["neili", "none"]
	b.end_turn("enemy")
	b.end_turn("enemy")
	assert_true(not boss.empowered, "two quiet turns are not enough")
	b.end_turn("enemy")
	assert_true(boss.empowered, "three quiet own turns empower the boss")
	assert_true(not _first_event(b.log, "empowered").is_empty(), "empowering emits an event")


func test_empowered_attack_is_boosted_and_then_cleared() -> void:
	var player = _player({}, ["basic_sword"], 1, 1)
	var boss = _enemy("boss", 20)
	var b: Variant = _battle([player, boss])
	boss.weaknesses = ["neili", "none"]
	assert_eq(b.begin_turn(), "enemy", "the fast boss acts first")
	boss.empowered = true
	var base := TacticsDamage.move_damage(10, boss.unit.realm, player.unit, "front", 0.0)
	var result: Dictionary = b.attack("enemy", "swing", Vector2i(0, 0))
	var hit := _first_event(result["events"], "hit")
	assert_eq(int(hit.get("damage", -1)), maxi(1, floori(float(base) * 1.25)),
		"the empowered attack deals 125%")
	assert_true(not boss.empowered, "the bonus is cleared after the attack")


func test_weak_hit_resets_empower() -> void:
	var player = _player()
	var boss = _enemy("boss", 5, 5)
	var b: Variant = _battle([player, boss], 3)
	boss.weaknesses = ["neili", "none"]
	boss.no_weak_turns = 2
	boss.empowered = true
	assert_eq(b.begin_turn(), "player")
	assert_true(bool(b.attack("player", "basic_sword", Vector2i(1, 0))["ok"]))
	assert_true(not boss.empowered, "a weak hit removes the empower state")
	assert_eq(int(boss.no_weak_turns), 0, "a weak hit resets the quiet counter")
	assert_eq(str(boss.last_weak_color), "neili")


func test_sfx_key_prefers_perfect_then_weak() -> void:
	assert_eq(TacticsSfx.key_for({"type": "hit", "weak": true, "weak_color": "neili"}),
		"weak_hit", "a weak hit uses the weak sound")
	assert_eq(TacticsSfx.key_for({"type": "hit", "outcome": "perfect", "weak": true}),
		"hit_perfect", "a perfect counter still wins over a weak flag")
	assert_eq(TacticsSfx.key_for({"type": "hit", "outcome": "none", "weak": false}),
		"hit_plain")
	assert_eq(TacticsSfx.key_for({"type": "heal"}), "heal", "healing has its own sound")

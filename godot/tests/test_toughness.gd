extends "res://tests/test_case.gd"

const Unit = preload("res://core/unit.gd")
const EnemyDef = preload("res://core/enemy_def.gd")


func _make_enemy(toughness := 2, stun_turns := 1) -> Variant:
	var d: Variant = EnemyDef.from_dict({
		"id": "minion",
		"name": "马匪",
		"tier": "minion",
		"stats": {"power": 5, "speed": 8, "defense": 3, "recovery": 1, "skill": 5, "constitution": 5},
		"max_hp": 40,
		"toughness": toughness,
		"stun_turns": stun_turns,
		"moves": [{"id": "sweep", "name": "横扫", "type": "sweep", "threat": 12, "power": 12}],
		"weak_moves": [],
	})
	return Unit.from_enemy(d)


func test_two_normal_counters_stun_minion() -> void:
	var u: Variant = _make_enemy()
	assert_true(not u.apply_toughness(1.0), "first normal counter does not stun")
	assert_true(u.apply_toughness(1.0), "second normal counter stuns")
	assert_true(u.is_stunned(), "minion is stunned")


func test_barely_counters_need_four() -> void:
	var u: Variant = _make_enemy()
	assert_true(not u.apply_toughness(0.5), "first barely counter")
	assert_true(not u.apply_toughness(0.5), "second barely counter")
	assert_true(not u.apply_toughness(0.5), "third barely counter")
	assert_true(u.apply_toughness(0.5), "fourth barely counter stuns")


func test_perfect_stuns_minion_at_once() -> void:
	var u: Variant = _make_enemy()
	assert_true(u.apply_toughness(2.0), "perfect counter stuns at once")
	assert_true(u.is_stunned(), "minion is stunned")


func test_overflow_not_carried() -> void:
	var u: Variant = _make_enemy()
	assert_true(u.apply_toughness(5.0), "overflowing cost still stuns")
	u.tick_stun()
	assert_true(not u.is_stunned(), "stun ends after one tick")
	assert_near(u.toughness_left, 2.0, 0.0001, "toughness resets to max, overflow discarded")


func test_toughness_ignored_while_stunned() -> void:
	var u: Variant = _make_enemy()
	u.apply_toughness(2.0)
	var before: float = u.toughness_left
	assert_true(not u.apply_toughness(1.0), "toughness is ignored while stunned")
	assert_near(u.toughness_left, before, 0.0001, "toughness_left is unchanged")


func test_boss_stun_lasts_two_turns() -> void:
	var u: Variant = _make_enemy(2, 2)
	assert_true(u.apply_toughness(2.0), "boss is stunned")
	u.tick_stun()
	assert_true(u.is_stunned(), "boss still stunned after one tick")
	u.tick_stun()
	assert_true(not u.is_stunned(), "boss stun ends after two ticks")
	assert_near(u.toughness_left, float(u.toughness_max), 0.0001, "toughness reset after stun")


func test_tick_stun_when_not_stunned_is_noop() -> void:
	var u: Variant = _make_enemy()
	u.tick_stun()
	assert_true(not u.is_stunned(), "still not stunned")
	assert_near(u.toughness_left, 2.0, 0.0001, "toughness_left untouched")


func test_probe_reveals_weak_moves() -> void:
	var u: Variant = _make_enemy()
	assert_true(not u.weak_revealed, "weak moves hidden at first")
	u.probe()
	assert_true(u.weak_revealed, "probe reveals weak moves")

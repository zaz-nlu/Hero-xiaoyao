extends "res://tests/test_case.gd"

const Counter = preload("res://core/counter.gd")
const MartialDef = preload("res://core/martial_def.gd")


func _make_martial(overrides := {}) -> Variant:
	var data := {
		"id": "m",
		"name": "测试武学",
		"power": 10,
		"counters": ["heavy"],
		"initiative": 0,
		"counter_level": 5,
		"advantage_stat": "skill",
		"effects": [],
	}
	for key in overrides:
		data[key] = overrides[key]
	return MartialDef.from_dict(data)


func _stats() -> Dictionary:
	return {"power": 10, "speed": 15, "defense": 5, "recovery": 5, "skill": 20, "constitution": 5}


func _move(type := "heavy", threat := 20) -> Dictionary:
	return {"id": "m1", "type": type, "threat": threat}


func test_type_mismatch_is_impossible() -> void:
	var verdict := Counter.evaluate(_make_martial(), _stats(), 10, _move("sweep"), false)
	assert_eq(verdict, Counter.Verdict.IMPOSSIBLE, "uncovered move type is impossible")


func test_fast_and_strong_enough_is_advantage() -> void:
	var verdict := Counter.evaluate(_make_martial(), _stats(), 10, _move(), false)
	assert_eq(verdict, Counter.Verdict.ADVANTAGE, "faster and gap >= 0")


func test_slower_than_enemy_is_barely() -> void:
	var verdict := Counter.evaluate(_make_martial(), _stats(), 30, _move(), false)
	assert_eq(verdict, Counter.Verdict.BARELY, "slower than enemy")


func test_first_strike_makes_slow_fast() -> void:
	var verdict := Counter.evaluate(_make_martial(), _stats(), 30, _move(), true)
	assert_eq(verdict, Counter.Verdict.ADVANTAGE, "first strike compensates speed")


func test_threat_far_above_power_is_impossible() -> void:
	var verdict := Counter.evaluate(_make_martial(), _stats(), 10, _move("heavy", 40), false)
	assert_eq(verdict, Counter.Verdict.IMPOSSIBLE, "gap below -5")


func test_gap_boundary() -> void:
	var martial: Variant = _make_martial()
	var stats := _stats()
	var at_minus_five := Counter.evaluate(martial, stats, 10, _move("heavy", 31), false)
	assert_eq(at_minus_five, Counter.Verdict.BARELY, "gap -5 is not impossible")
	var at_minus_six := Counter.evaluate(martial, stats, 10, _move("heavy", 32), false)
	assert_eq(at_minus_six, Counter.Verdict.IMPOSSIBLE, "gap -6 is impossible")


func test_perfect_needs_weak_move_and_top_stat() -> void:
	var martial: Variant = _make_martial()
	var stats := _stats()
	assert_true(
		Counter.is_perfect(Counter.Verdict.ADVANTAGE, martial, stats, ["m1"], "m1"),
		"advantage on weak move with top stat"
	)
	var power_martial: Variant = _make_martial({"advantage_stat": "power"})
	assert_true(
		not Counter.is_perfect(Counter.Verdict.ADVANTAGE, power_martial, stats, ["m1"], "m1"),
		"non-top advantage stat is not perfect"
	)
	assert_true(
		not Counter.is_perfect(Counter.Verdict.ADVANTAGE, martial, stats, [], "m1"),
		"move not in weak moves is not perfect"
	)
	assert_true(
		not Counter.is_perfect(Counter.Verdict.BARELY, martial, stats, ["m1"], "m1"),
		"non-advantage verdict is not perfect"
	)


func test_perfect_counts_ties() -> void:
	var tied := {
		"power": 10, "speed": 10, "defense": 10,
		"recovery": 10, "skill": 10, "constitution": 10,
	}
	var martial: Variant = _make_martial({"advantage_stat": "power"})
	assert_true(
		Counter.is_perfect(Counter.Verdict.ADVANTAGE, martial, tied, ["m1"], "m1"),
		"tied top stat counts as top"
	)


func test_toughness_cost_values() -> void:
	assert_near(Counter.toughness_cost(Counter.Verdict.IMPOSSIBLE, false), 0.0, 0.0001, "impossible")
	assert_near(Counter.toughness_cost(Counter.Verdict.BARELY, false), 0.5, 0.0001, "barely")
	assert_near(Counter.toughness_cost(Counter.Verdict.ADVANTAGE, false), 1.0, 0.0001, "advantage")
	assert_near(Counter.toughness_cost(Counter.Verdict.ADVANTAGE, true), 2.0, 0.0001, "perfect")

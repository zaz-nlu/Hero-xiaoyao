extends "res://tests/test_case.gd"

const Mastery = preload("res://core/mastery.gd")


func test_unlearned_is_level_zero() -> void:
	var mastery = Mastery.new()
	assert_eq(mastery.level("a"), 0, "unlearned martial is level zero")


func test_learn_gives_level_one() -> void:
	var mastery = Mastery.new()
	mastery.learn("a")
	assert_eq(mastery.level("a"), 1, "learned martial is level one")


func test_exp_thresholds() -> void:
	var mastery = Mastery.new()
	mastery.add_exp("a", 14)
	assert_eq(mastery.level("a"), 1, "14 exp is still level one")
	mastery.add_exp("a", 1)
	assert_eq(mastery.level("a"), 2, "15 exp reaches level two")


func test_level_caps_at_ten() -> void:
	var mastery = Mastery.new()
	mastery.add_exp("a", 99999)
	assert_eq(mastery.level("a"), 10, "level capped at ten")


func test_multiplier() -> void:
	var mastery = Mastery.new()
	mastery.learn("a")
	assert_near(mastery.damage_multiplier("a"), 1.04, 0.0001, "level one multiplier")
	mastery.add_exp("a", 99999)
	assert_near(mastery.damage_multiplier("a"), 1.4, 0.0001, "level ten multiplier")
	assert_near(mastery.damage_multiplier("b"), 1.0, 0.0001, "unlearned multiplier")


func test_learn_does_not_lower_level() -> void:
	var mastery = Mastery.new()
	mastery.add_exp("a", Mastery.exp_to_reach(3))
	assert_eq(mastery.level("a"), 3, "exp reaches level three")
	mastery.learn("a")
	assert_eq(mastery.level("a"), 3, "learn does not lower level")


func test_exp_to_reach_values() -> void:
	assert_eq(Mastery.exp_to_reach(1), 5)
	assert_eq(Mastery.exp_to_reach(2), 15)
	assert_eq(Mastery.exp_to_reach(10), 275)

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


func test_exp_of_export_and_import() -> void:
	var mastery = Mastery.new()
	mastery.add_exp("a", 7)
	assert_eq(mastery.exp_of("a"), 7, "exp_of returns the accumulated exp")
	assert_eq(mastery.exp_of("b"), 0, "unseen martials have zero exp")
	var exported: Dictionary = mastery.export_exp()
	assert_eq(int(exported["a"]), 7, "export contains the exp")
	exported["a"] = 99
	assert_eq(mastery.exp_of("a"), 7, "export returns a copy, not the live dictionary")

	var other = Mastery.new()
	other.import_exp({"a": 15, "b": 3})
	assert_eq(other.level("a"), 2, "imported exp restores the level")
	assert_eq(other.exp_of("b"), 3, "import keeps every key")
	other.add_exp("a", 1)
	assert_eq(other.exp_of("a"), 16, "imported exp keeps accumulating")


func test_progress_in_level() -> void:
	var zero: Dictionary = Mastery.progress_in_level(0)
	assert_eq(int(zero["level"]), 0, "zero exp is level zero")
	assert_eq(int(zero["into"]), 0, "no progress into level one")
	assert_eq(int(zero["need"]), 5, "level one needs five exp")

	var first: Dictionary = Mastery.progress_in_level(14)
	assert_eq(int(first["level"]), 1, "14 exp is level one")
	assert_eq(int(first["into"]), 9, "nine exp into level one")
	assert_eq(int(first["need"]), 10, "level one spans ten exp")

	var second: Dictionary = Mastery.progress_in_level(15)
	assert_eq(int(second["level"]), 2, "15 exp reaches level two")
	assert_eq(int(second["into"]), 0, "a fresh level starts at zero")
	assert_eq(int(second["need"]), 15, "level two spans fifteen exp")

	var maxed: Dictionary = Mastery.progress_in_level(Mastery.exp_to_reach(10))
	assert_eq(int(maxed["level"]), 10, "the level caps at ten")
	assert_eq(int(maxed["need"]), 0, "a maxed martial needs no more exp")

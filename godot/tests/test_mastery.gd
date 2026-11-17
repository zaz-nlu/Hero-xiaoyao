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
	mastery.add_exp("a", 99)
	assert_eq(mastery.level("a"), 0, "99 exp is still level zero")
	mastery.add_exp("a", 1)
	assert_eq(mastery.level("a"), 1, "100 exp reaches level one")
	mastery.add_exp("a", 199)
	assert_eq(mastery.level("a"), 2, "299 exp reaches level two")


func test_level_caps_at_ten() -> void:
	var mastery = Mastery.new()
	mastery.realm_id = "banshen"
	mastery.add_exp("a", 99999)
	assert_eq(mastery.level("a"), 10, "level capped at ten")


func test_multiplier() -> void:
	var mastery = Mastery.new()
	mastery.realm_id = "banshen"
	mastery.learn("a")
	assert_near(mastery.damage_multiplier("a"), 1.04, 0.0001, "level one multiplier")
	mastery.add_exp("a", 99999)
	assert_near(mastery.damage_multiplier("a"), 1.4, 0.0001, "level ten multiplier")
	assert_near(mastery.damage_multiplier("b"), 1.0, 0.0001, "unlearned multiplier")


func test_learn_does_not_lower_level() -> void:
	var mastery = Mastery.new()
	mastery.add_exp("a", 300)
	assert_eq(mastery.level("a"), 3, "exp reaches level three")
	mastery.learn("a")
	assert_eq(mastery.level("a"), 3, "learn does not lower level")


func test_grade_exp_per_level_values() -> void:
	assert_eq(Mastery.grade_per_level("common"), 100)
	assert_eq(Mastery.grade_per_level("fine"), 150)
	assert_eq(Mastery.grade_per_level("rare"), 200)
	assert_eq(Mastery.grade_per_level("epic"), 250)
	assert_eq(Mastery.grade_per_level("legendary"), 300)
	assert_eq(Mastery.grade_per_level("unknown"), 100, "unknown grades fall back to common")


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
	other.import_exp({"a": 100, "b": 3})
	assert_eq(other.level("a"), 1, "imported exp restores the level")
	assert_eq(other.exp_of("b"), 3, "import keeps every key")
	other.add_exp("a", 100)
	assert_eq(other.exp_of("a"), 200, "imported exp keeps accumulating")
	assert_eq(other.level("a"), 2, "imported exp keeps leveling")


func test_progress_in_level() -> void:
	var zero: Dictionary = Mastery.progress_in_level(0)
	assert_eq(int(zero["level"]), 0, "zero exp is level zero")
	assert_eq(int(zero["into"]), 0, "no progress into level one")
	assert_eq(int(zero["need"]), 100, "level one needs one hundred exp")
	assert_true(not bool(zero.get("capped", true)), "a fresh martial is not capped")

	var first: Dictionary = Mastery.progress_in_level(150)
	assert_eq(int(first["level"]), 1, "150 exp is level one")
	assert_eq(int(first["into"]), 50, "fifty exp into level one")
	assert_eq(int(first["need"]), 100, "every level spans one hundred exp")

	var second: Dictionary = Mastery.progress_in_level(299)
	assert_eq(int(second["level"]), 2, "299 exp is level two")
	assert_eq(int(second["into"]), 99, "ninety-nine exp into level two")

	var capped: Dictionary = Mastery.progress_in_level(700, "common", 5)
	assert_eq(int(capped["level"]), 5, "the realm cap limits the level")
	assert_eq(int(capped["need"]), 0, "a capped martial needs no more exp")
	assert_true(bool(capped.get("capped", false)), "the progress reports the realm cap")

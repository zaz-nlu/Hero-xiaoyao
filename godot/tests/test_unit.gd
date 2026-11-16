extends "res://tests/test_case.gd"

const Unit = preload("res://core/unit.gd")
const Damage = preload("res://core/damage.gd")


func _player(stats := {}) -> Variant:
	return Unit.make_player("测试", stats, 100, 1)


func test_heal_capped_by_wound() -> void:
	var u: Variant = _player()
	u.hp = 50
	u.wound = 30
	assert_eq(u.heal(100), 20, "heal stops at max_hp - wound")
	assert_eq(u.hp, 70, "hp reaches the reduced cap")


func test_wound_lowers_hp_and_cap() -> void:
	var u: Variant = _player()
	u.take_wound(10)
	assert_eq(u.hp, 90, "wound lowers hp")
	assert_eq(u.wound, 10, "wound is recorded")
	assert_eq(u.heal(999), 0, "wound blocks healing back to max hp")


func test_wound_can_kill() -> void:
	var u: Variant = Unit.make_player("测试", {}, 10, 0)
	u.take_wound(10)
	assert_true(u.is_dead(), "wound can reduce hp to zero")


func test_damage_subtracts_defense() -> void:
	var target: Variant = _player({"defense": 3})
	var damage := Damage.hit(10, 1.0, {"power": 5}, target)
	assert_eq(damage, 12, "15 raw minus 3 defense")
	assert_eq(target.hp, 88, "damage is applied to the target")


func test_damage_minimum_one() -> void:
	var target: Variant = _player({"defense": 99})
	var damage := Damage.hit(10, 1.0, {"power": 5}, target)
	assert_eq(damage, 1, "damage never goes below one")


func test_stunned_target_takes_crit_with_zero_defense() -> void:
	var target: Variant = _player({"defense": 3})
	target.stun_left = 1
	var damage := Damage.hit(10, 1.0, {"power": 5}, target)
	assert_eq(damage, 22, "floor(15 * 1.5) with zero defense")

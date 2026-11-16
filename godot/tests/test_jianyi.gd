extends "res://tests/test_case.gd"

const Unit = preload("res://core/unit.gd")
const Jianyi = preload("res://core/jianyi.gd")


func _player() -> Variant:
	return Unit.make_player("剑客", {"skill": 20, "defense": 0, "power": 0}, 100, 1)


func _enemy() -> Variant:
	var e: Variant = Unit.make_player("木桩", {"defense": 50, "skill": 0, "power": 0}, 200, 0)
	e.is_player = false
	e.id = "enemy"
	return e


func test_strike_ignores_defense_and_wounds() -> void:
	var p: Variant = _player()
	var e: Variant = _enemy()
	assert_eq(Jianyi.strike(p, e), 50, "30 base plus 20 skill, defense ignored")
	assert_eq(e.wound, 50, "wound is recorded")
	assert_eq(e.hp, 150, "hp lowered by the full damage")
	assert_eq(p.jianyi_points, 0, "one point is spent")


func test_strike_with_zero_points_is_refused() -> void:
	var p: Variant = _player()
	var e: Variant = _enemy()
	Jianyi.strike(p, e)
	var hp_before: int = e.hp
	var wound_before: int = e.wound
	assert_eq(Jianyi.strike(p, e), -1, "no points left")
	assert_eq(e.hp, hp_before, "target hp unchanged")
	assert_eq(e.wound, wound_before, "target wound unchanged")
	assert_eq(p.jianyi_points, 0, "points unchanged")
	assert_true(not Jianyi.can_strike(p, e), "cannot strike without points")


func test_strike_on_incorporeal_refused_without_cost() -> void:
	var p: Variant = _player()
	var e: Variant = _enemy()
	e.incorporeal = true
	assert_eq(Jianyi.strike(p, e), -1, "incorporeal target is immune")
	assert_eq(p.jianyi_points, 1, "no point is spent")
	assert_eq(e.hp, 200, "target hp unchanged")


func test_strike_on_dead_target_refused() -> void:
	var p: Variant = _player()
	var e: Variant = _enemy()
	e.hp = 0
	assert_eq(Jianyi.strike(p, e), -1, "dead target cannot be struck")
	assert_eq(p.jianyi_points, 1, "no point is spent")


func test_restore_capped_by_max() -> void:
	var p: Variant = _player()
	var e: Variant = _enemy()
	Jianyi.strike(p, e)
	assert_eq(p.jianyi_points, 0, "point spent")
	Jianyi.restore(p)
	assert_eq(p.jianyi_points, 1, "restore brings it back to max")
	Jianyi.restore(p)
	assert_eq(p.jianyi_points, 1, "restore never exceeds max")


func test_wound_blocks_healing() -> void:
	var p: Variant = _player()
	var e: Variant = _enemy()
	Jianyi.strike(p, e)
	assert_eq(e.heal(999), 0, "wound lowers the healing cap")

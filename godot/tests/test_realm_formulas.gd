extends "res://tests/test_case.gd"

const Balance = preload("res://core/balance.gd")
const Battle = preload("res://core/battle.gd")
const Damage = preload("res://core/damage.gd")
const EnemyDef = preload("res://core/enemy_def.gd")
const Jianyi = preload("res://core/jianyi.gd")
const Mastery = preload("res://core/mastery.gd")
const Realms = preload("res://core/realms.gd")
const Unit = preload("res://core/unit.gd")


func _stats(overrides := {}) -> Dictionary:
	var stats := {
		"power": 0,
		"speed": 0,
		"defense": 0,
		"recovery": 0,
		"skill": 0,
		"constitution": 0,
	}
	for key in overrides:
		stats[key] = overrides[key]
	return stats


func _target(defense := 0, hp := 1000, realm := "lianti") -> Variant:
	return Unit.make_player("靶子", _stats({"defense": defense}), hp, 0, 0, realm)


func _player(recovery := 0, hp := 100, realm := "lianti") -> Variant:
	return Unit.make_player("测试", _stats({"recovery": recovery}), hp, 0, 0, realm)


func _enemy(recovery := 0, power := 0, max_hp := 1000, realm := "lianti") -> Variant:
	var d: Variant = EnemyDef.from_dict({
		"id": "enemy",
		"name": "木人",
		"tier": "minion",
		"realm": realm,
		"stats": _stats({"recovery": recovery}),
		"max_hp": max_hp,
		"toughness": 2,
		"stun_turns": 1,
		"moves": [{"id": "m1", "name": "轻推", "type": "heavy", "threat": 1, "power": power}],
		"weak_moves": [],
	})
	return Unit.from_enemy(d)


func _find_log(lines: Array[String], marker: String) -> String:
	for line in lines:
		if line.contains(marker):
			return line
	return ""


func test_s1_damage_matches_old_formula() -> void:
	Realms.reload()
	var attacker := {"power": 5}
	assert_eq(Damage.hit(10, 1.0, attacker, _target(3)), 12, "15 raw minus 3 defense")
	assert_eq(Damage.hit(10, 1.3, attacker, _target(7)), 11, "floor(18) minus 7 defense")
	assert_eq(Damage.hit(10, 1.0, attacker, _target(99)), 1, "damage never goes below one")


func test_attacker_realm_scales_raw_damage() -> void:
	Realms.reload()
	assert_eq(
		Damage.hit(10, 1.0, {"power": 5}, _target(3), "renjie"),
		floori((10 + 5) * 2.0) - 3,
		"人杰 s=2 doubles the raw damage"
	)


func test_defender_realm_scales_defense() -> void:
	Realms.reload()
	assert_eq(
		Damage.hit(10, 1.0, {"power": 5}, _target(2, 1000, "diling")),
		15 - floori(2 * 3.5),
		"地灵 s=3.5 multiplies the defense term"
	)


func test_stunned_target_takes_crit_with_zero_defense() -> void:
	Realms.reload()
	var target: Variant = _target(3)
	target.stun_left = 1
	assert_eq(Damage.hit(10, 1.0, {"power": 5}, target), 22, "floor(15 * 1.5), defense ignored")

	var scaled: Variant = _target(3)
	scaled.stun_left = 1
	assert_eq(
		Damage.hit(10, 1.0, {"power": 5}, scaled, "renjie"),
		45,
		"attacker s=2 then crit, defense ignored"
	)


func test_jianyi_scales_with_attacker_realm() -> void:
	Realms.reload()
	var attacker: Variant = Unit.make_player("剑客", _stats({"skill": 20}), 100, 1, 0, "renjie")
	var target: Variant = _target(0)
	assert_eq(Jianyi.strike(attacker, target), 100, "(30 + 20) * 2")
	assert_eq(target.wound, 100, "jianyi wound matches its damage")


func test_enemy_regen_scales_with_realm() -> void:
	Realms.reload()
	var player: Variant = _player(0, 100)
	var enemy: Variant = _enemy(4, 0, 1000, "renjie")
	enemy.hp = 100
	enemy.wound = 500
	var battle: Variant = Battle.new(player, [enemy], [], Mastery.new(), {}, 1, false)
	var result: Dictionary = battle.submit({"kind": "probe", "target": 0})
	assert_true(bool(result["ok"]), "probe accepted")
	assert_eq(enemy.hp, 116, "enemy regen = floor(4 * 2 * 2)")
	assert_true(_find_log(battle.log, "act:e0").contains("heal 16"), "enemy regen is logged")


func test_enemy_regen_capped_by_max_hp_minus_wound() -> void:
	Realms.reload()
	var player: Variant = _player(0, 100)
	var enemy: Variant = _enemy(4, 0, 1000, "renjie")
	enemy.wound = 500
	enemy.hp = 495
	var battle: Variant = Battle.new(player, [enemy], [], Mastery.new(), {}, 1, false)
	battle.submit({"kind": "probe", "target": 0})
	# 上限 1000 - 500 = 500，只回 5。
	assert_eq(enemy.hp, 500, "enemy regen stops at max_hp - wound")
	assert_true(_find_log(battle.log, "act:e0").contains("heal 5"), "capped enemy regen is logged")


func test_player_regen_at_round_end() -> void:
	Realms.reload()
	var player: Variant = _player(5, 100)
	player.hp = 50
	var enemy: Variant = _enemy(0)
	var battle: Variant = Battle.new(player, [enemy], [], Mastery.new(), {}, 1, false)
	battle.submit({"kind": "probe", "target": 0})
	# 敌人威力 0 仍打到最低 1 点，随后恢复 5 × 2 × 1.0 = 10。
	assert_eq(player.hp, 59, "50 - 1 damage + 10 regen")
	assert_eq(_find_log(battle.log, "regen:player"), "R1 regen:player 10", "player regen is logged")


func test_player_regen_capped_by_max_hp_minus_wound() -> void:
	Realms.reload()
	var player: Variant = _player(5, 100)
	player.wound = 10
	player.hp = 85
	var enemy: Variant = _enemy(0)
	var battle: Variant = Battle.new(player, [enemy], [], Mastery.new(), {}, 1, false)
	battle.submit({"kind": "probe", "target": 0})
	# 85 - 1 = 84，上限 100 - 10 = 90，只回 6。
	assert_eq(player.hp, 90, "regen stops at max_hp - wound")
	assert_eq(_find_log(battle.log, "regen:player"), "R1 regen:player 6", "capped regen is logged")


func test_player_regen_scales_with_realm() -> void:
	Realms.reload()
	var player: Variant = _player(5, 1000, "renjie")
	player.hp = 500
	var enemy: Variant = _enemy(0)
	var battle: Variant = Battle.new(player, [enemy], [], Mastery.new(), {}, 1, false)
	battle.submit({"kind": "probe", "target": 0})
	assert_eq(player.hp, 519, "500 - 1 damage + floor(5 * 2 * 2)")


func test_realm_suppression_floors_damage_at_one() -> void:
	Realms.reload()
	var target: Variant = _target(50, 1000, "diling")
	assert_eq(
		Damage.hit(10, 1.0, {"power": 5}, target, "lianti"),
		1,
		"炼体打地灵：伤害下限为 1"
	)


func test_heal_amount_formula() -> void:
	assert_eq(Balance.heal_amount(30, 0, 1.0), 30, "no recovery bonus")
	assert_eq(Balance.heal_amount(30, 25, 2.0), 120, "double realm scale and +100% recovery")

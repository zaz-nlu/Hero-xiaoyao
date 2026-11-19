extends "res://tests/test_case.gd"

# 内力持久化：存档往返、战前恢复与钳制、战后写回（含战败下限）、
# 紫气每场重置、沙盒隔离与突破回满钩子。

const GameState = preload("res://core/game_state.gd")
const Progression = preload("res://core/progression.gd")
const TacticsEnergy = preload("res://core/tactics/tactics_energy.gd")
const TacticsSession = preload("res://features/tactics/tactics_session.gd")
const TacticsSetup = preload("res://core/tactics/tactics_setup.gd")

const UNRECORDED := -1


func _player(battle) -> Variant:
	return battle.get_unit("player")


func _neili_left(battle) -> int:
	return int(_player(battle).energy_left.get("neili", -999))


func _neili_max(battle) -> int:
	return int(_player(battle).energy_max.get("neili", 0))


func _kill_enemies(battle) -> void:
	for entry in battle.units:
		if entry.side == "enemy":
			entry.unit.hp = 0


func test_save_round_trip_keeps_neili_left() -> void:
	GameState.reset()
	GameState.neili_left = 6
	var saved := GameState.to_dict()
	assert_true(saved.has("neili_left"), "neili_left is written to the save")
	GameState.reset()
	GameState.from_dict(saved)
	assert_eq(GameState.neili_left, 6, "neili_left survives the round trip")
	GameState.reset()


func test_old_save_without_neili_defaults_to_full() -> void:
	GameState.reset()
	GameState.neili_left = 4
	GameState.from_dict({"flags": {}})
	assert_eq(GameState.neili_left, UNRECORDED, "a save without neili_left means full")
	GameState.from_dict({"neili_left": "lot"})
	assert_eq(GameState.neili_left, UNRECORDED, "a bad type keeps the full default")
	GameState.from_dict({"neili_left": -5})
	assert_eq(GameState.neili_left, UNRECORDED, "negative values clamp to unrecorded")
	GameState.reset()


func test_reset_restores_neili_default() -> void:
	GameState.reset()
	GameState.neili_left = 2
	GameState.reset()
	assert_eq(GameState.neili_left, UNRECORDED, "reset forgets the carried neili")


func test_unrecorded_neili_starts_full() -> void:
	GameState.reset()
	var built: Dictionary = TacticsSession.build("bandit", 1, false, "tavern")
	assert_true(bool(built.get("ok", false)), "the battle builds")
	if not bool(built.get("ok", false)):
		return
	var battle: Variant = built["battle"]
	assert_eq(_neili_left(battle), _neili_max(battle), "unrecorded neili means a full pool")
	GameState.reset()


func test_build_restores_carried_neili_and_clamps() -> void:
	GameState.reset()
	GameState.neili_left = 3
	var built: Dictionary = TacticsSession.build("bandit", 1, false, "tavern")
	assert_true(bool(built.get("ok", false)), "the battle builds")
	if not bool(built.get("ok", false)):
		return
	var battle: Variant = built["battle"]
	assert_eq(_neili_left(battle), 3, "the player starts with the carried neili")
	assert_eq(
		_neili_max(battle), TacticsEnergy.max_neili_for(GameState.realm_id),
		"the pool cap comes from the energy rules"
	)
	GameState.neili_left = 999
	var high: Dictionary = TacticsSession.build("bandit", 1, false, "tavern")
	assert_true(bool(high.get("ok", false)), "the clamped battle builds")
	if bool(high.get("ok", false)):
		var high_battle: Variant = high["battle"]
		assert_eq(
			_neili_left(high_battle), _neili_max(high_battle),
			"a carried value above the cap is clamped"
		)
		assert_true(_neili_left(high_battle) >= 0, "the pool never goes negative")
	GameState.reset()


func test_victory_writes_back_remaining_neili() -> void:
	GameState.reset()
	var built: Dictionary = TacticsSession.build("bandit", 1, false, "tavern")
	assert_true(bool(built.get("ok", false)), "the battle builds")
	if not bool(built.get("ok", false)):
		return
	var battle: Variant = built["battle"]
	_player(battle).energy_left["neili"] = 5
	_kill_enemies(battle)
	TacticsSession.settle(battle)
	assert_eq(GameState.neili_left, 5, "victory carries the remaining neili")
	GameState.reset()


func test_defeat_keeps_at_least_half_neili() -> void:
	GameState.reset()
	var built: Dictionary = TacticsSession.build("bandit", 1, false, "tavern")
	assert_true(bool(built.get("ok", false)), "the battle builds")
	if not bool(built.get("ok", false)):
		return
	var battle: Variant = built["battle"]
	var cap := _neili_max(battle)
	var floor_value := ceili(
		float(cap) * float(TacticsEnergy.defeat_neili_floor_pct()) / 100.0)
	_player(battle).energy_left["neili"] = 0
	_player(battle).unit.hp = 0
	TacticsSession.settle_defeat(battle)
	assert_eq(GameState.neili_left, floor_value, "a defeat restores the floor share")

	var second: Dictionary = TacticsSession.build("bandit", 1, false, "tavern")
	assert_true(bool(second.get("ok", false)), "the second battle builds")
	if bool(second.get("ok", false)):
		var second_battle: Variant = second["battle"]
		_player(second_battle).energy_left["neili"] = cap
		_player(second_battle).unit.hp = 0
		TacticsSession.settle_defeat(second_battle)
		assert_eq(GameState.neili_left, cap, "a defeat never lowers neili above the floor")
	GameState.reset()


func test_ziqi_refills_every_battle() -> void:
	GameState.reset()
	var built: Dictionary = TacticsSession.build("bandit", 1, false, "tavern")
	assert_true(bool(built.get("ok", false)), "the battle builds")
	if not bool(built.get("ok", false)):
		return
	var battle: Variant = built["battle"]
	var ziqi_max := int(_player(battle).energy_max.get("ziqi", 0))
	assert_true(ziqi_max > 0, "ziqi starts with a positive pool")
	_player(battle).energy_left["ziqi"] = 0
	_player(battle).energy_left["neili"] = 4
	_kill_enemies(battle)
	TacticsSession.settle(battle)

	var again: Dictionary = TacticsSession.build("bandit", 1, false, "tavern")
	assert_true(bool(again.get("ok", false)), "the second battle builds")
	if not bool(again.get("ok", false)):
		return
	var second: Variant = again["battle"]
	assert_eq(
		int(_player(second).energy_left.get("ziqi", -1)), ziqi_max,
		"ziqi is refilled every battle"
	)
	assert_eq(
		int(_player(second).energy_left.get("neili", -1)), 4,
		"neili carries over while ziqi refills"
	)
	GameState.reset()


func test_sandbox_build_ignores_game_state_neili() -> void:
	GameState.reset()
	GameState.neili_left = 2
	var built: Dictionary = TacticsSetup.build(
		"tavern_brawl", [{"id": "bandit", "count": 1}], null, 1)
	assert_true(bool(built.get("ok", false)), "the sandbox battle builds")
	if bool(built.get("ok", false)):
		var battle: Variant = built["battle"]
		assert_eq(
			_neili_left(battle), _neili_max(battle),
			"the sandbox does not read the carried neili"
		)
	assert_eq(GameState.neili_left, 2, "the sandbox does not write the carried neili")
	GameState.reset()


func test_breakthrough_refills_neili_and_sets_realm() -> void:
	GameState.reset()
	GameState.neili_left = 1
	Progression.on_breakthrough("renjie", 2)
	assert_eq(GameState.realm_id, "renjie", "the breakthrough sets the realm")
	assert_eq(GameState.realm_stage, 2, "the breakthrough sets the stage")
	assert_eq(GameState.neili_left, UNRECORDED, "the breakthrough refills neili")
	Progression.restore_neili_full()
	assert_eq(
		GameState.neili_left, UNRECORDED,
		"restoring full keeps the unrecorded marker"
	)
	GameState.reset()


func test_consecutive_battles_carry_the_remaining_neili() -> void:
	GameState.reset()
	var first: Dictionary = TacticsSession.build("bandit", 1, false, "tavern")
	assert_true(bool(first.get("ok", false)), "the first battle builds")
	if not bool(first.get("ok", false)):
		return
	var first_battle: Variant = first["battle"]
	_player(first_battle).energy_left["neili"] = 9
	_kill_enemies(first_battle)
	TacticsSession.settle(first_battle)
	assert_eq(GameState.neili_left, 9, "the first battle writes its remaining neili")

	var second: Dictionary = TacticsSession.build("bandit", 1, false, "tavern")
	assert_true(bool(second.get("ok", false)), "the second battle builds")
	if not bool(second.get("ok", false)):
		return
	assert_eq(
		_neili_left(second["battle"]), 9,
		"the second battle starts where the first ended"
	)
	GameState.reset()

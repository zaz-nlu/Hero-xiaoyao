extends "res://tests/test_case.gd"

const Battle = preload("res://core/battle.gd")
const Balance = preload("res://core/balance.gd")
const EnemyDef = preload("res://core/enemy_def.gd")
const GameState = preload("res://core/game_state.gd")
const Mastery = preload("res://core/mastery.gd")
const Unit = preload("res://core/unit.gd")

const RECOVERY := 10


func _stats(recovery := 0, speed := 5) -> Dictionary:
	return {
		"power": 0,
		"speed": speed,
		"defense": 0,
		"recovery": recovery,
		"skill": 0,
		"constitution": 0,
	}


func _make_player(max_hp: int, recovery: int, speed := 5) -> Variant:
	return Unit.make_player("测试", _stats(recovery, speed), max_hp, 0)


func _make_enemy(power: int, speed: int) -> Variant:
	var d: Variant = EnemyDef.from_dict({
		"id": "enemy",
		"name": "木人",
		"tier": "minion",
		"stats": _stats(0, speed),
		"max_hp": 200,
		"toughness": 4,
		"stun_turns": 1,
		"moves": [
			{"id": "move0", "name": "招式0", "type": "heavy", "threat": power, "power": power},
		],
		"weak_moves": [],
	})
	return Unit.from_enemy(d)


func _make_battle(player: Variant, enemy: Variant) -> Variant:
	return Battle.new(player, [enemy], [], Mastery.new(), {}, 1, false)


func _has_log(battle: Variant, text: String) -> bool:
	for line in battle.log:
		if str(line).contains(text):
			return true
	return false


func test_herb_heals_and_the_enemy_still_acts() -> void:
	var player: Variant = _make_player(200, RECOVERY)
	player.hp = 40
	var enemy: Variant = _make_enemy(10, 20)
	var battle: Variant = _make_battle(player, enemy)
	battle.inventory = {"herb": 2}
	var expected: int = Balance.heal_amount(30, RECOVERY, 1.0)
	assert_eq(expected, 42, "the herb heals 30 x (1 + recovery/25)")
	var result: Dictionary = battle.submit({"kind": "item", "id": "herb"})
	assert_true(bool(result["ok"]), "eating a herb is accepted")
	assert_eq(battle.round, 2, "the round advances")
	assert_eq(int(battle.inventory["herb"]), 1, "one herb is consumed")
	# Enemy (speed 20) acts first, then the heal, then end-of-round regen.
	var regen: int = RECOVERY * Balance.REGEN_PER_RECOVERY
	assert_eq(player.hp, mini(200, 40 - 10 + expected + regen), "heal and enemy action both apply")
	assert_true(_has_log(battle, "act:player item herb heal 42"), "the heal is logged")
	assert_true(_has_log(battle, "act:e0"), "the enemy still takes its turn")


func test_herb_heal_is_capped_by_missing_hp() -> void:
	var player: Variant = _make_player(100, RECOVERY)
	player.hp = 95
	var enemy: Variant = _make_enemy(0, 1)
	var battle: Variant = _make_battle(player, enemy)
	battle.inventory = {"herb": 1}
	var result: Dictionary = battle.submit({"kind": "item", "id": "herb"})
	assert_true(bool(result["ok"]), "eating a herb is accepted")
	assert_true(_has_log(battle, "heal 5"), "the logged heal is capped to the missing hp")
	assert_eq(int(battle.inventory["herb"]), 0, "the herb is consumed")


func test_herb_is_rejected_without_stock() -> void:
	var player: Variant = _make_player(100, RECOVERY)
	player.hp = 40
	var battle: Variant = _make_battle(player, _make_enemy(0, 1))
	battle.inventory = {}
	var result: Dictionary = battle.submit({"kind": "item", "id": "herb"})
	assert_true(not bool(result["ok"]), "an empty bag cannot heal")
	assert_eq(battle.round, 1, "the rejected action does not advance the round")


func test_herb_is_rejected_at_full_hp() -> void:
	var player: Variant = _make_player(100, RECOVERY)
	var battle: Variant = _make_battle(player, _make_enemy(0, 1))
	battle.inventory = {"herb": 1}
	var result: Dictionary = battle.submit({"kind": "item", "id": "herb"})
	assert_true(not bool(result["ok"]), "full hp cannot heal")
	assert_true(str(result.get("error", "")).contains("full"), "the error says the hp is full")
	assert_eq(int(battle.inventory["herb"]), 1, "the herb is not consumed")


func _make_view() -> Variant:
	var view: Variant = load("res://ui/battle_view.gd").new()
	view.build_ui()
	return view


func _press_key(view: Variant, code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	view._unhandled_input(event)


func test_herb_card_disabled_at_zero_and_key_eight_uses_one() -> void:
	GameState.reset()
	var empty: Variant = _make_view()
	empty.start("bandit", 1, false, false)
	assert_true(empty.herb_button != null, "the herb card exists")
	assert_true(empty.herb_button.disabled, "the herb card is disabled with no herbs")
	assert_eq(str(empty.herb_badge.text), "×0", "the badge shows zero herbs")
	empty.free()

	GameState.inventory["herb"] = 1
	var view: Variant = _make_view()
	view.start("bandit", 1, false, false)
	view.battle.player.hp = 50
	view.refresh()
	assert_true(not view.herb_button.disabled, "the herb card is enabled with herbs and missing hp")
	_press_key(view, KEY_8)
	assert_eq(int(view.battle.round), 2, "pressing 8 eats a herb")
	assert_eq(int(GameState.inventory["herb"]), 0, "the herb is consumed from the shared inventory")
	assert_eq(str(view.herb_badge.text), "×0", "the badge refreshes")
	assert_true(view.herb_button.disabled, "the card disables itself once empty")
	var healed_popup := false
	for entry in view.stage.popups:
		var label: Label3D = entry["node"]
		if str(label.text).begins_with("+"):
			healed_popup = true
	assert_true(healed_popup, "a green +N popup appears over the player")
	view.free()
	GameState.reset()

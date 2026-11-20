extends "res://tests/test_case.gd"

# 序幕教学战斗：东方阳（极意）对东方云 + 魔王索尔；无限回复、剑意伤口、教学提示。

const GameState = preload("res://core/game_state.gd")
const TacticsSession = preload("res://features/tactics/tactics_session.gd")
const TacticsTutorial = preload("res://features/tactics/tactics_tutorial.gd")


func _build() -> Dictionary:
	GameState.reset()
	GameState.encounter_group = [
		{"id": "dongfang_yun", "count": 1}, {"id": "sol_demon_king", "count": 1}]
	return TacticsSession.build("dongfang_yun", 1, true, "opening_duel")


func test_duel_uses_its_own_player_and_ignores_saved_progress() -> void:
	GameState.reset()
	GameState.neili_left = 3
	var built := _build()
	assert_true(bool(built.get("ok", false)), "the duel builds: %s" % str(built.get("errors", [])))
	var hero = built["battle"].get_unit("player")
	assert_eq(str(hero.unit.name), "东方阳", "the player is Dongfang Yang")
	assert_eq(str(hero.unit.realm), "jiyi")
	assert_eq(hero.loadout.size(), 4, "four 御神剑术 forms")
	assert_eq(int(hero.energy_left["neili"]), 4000, "saved neili is not carried into the tutorial")
	assert_true(TacticsSession.is_tutorial("opening_duel"))
	assert_true(not TacticsSession.is_tutorial("tavern"))
	GameState.reset()


func test_mana_mode_costs_come_from_the_martial_not_the_grade() -> void:
	var built := _build()
	var battle = built["battle"]
	var Energy = load("res://core/tactics/tactics_energy.gd")
	assert_eq(Energy.cost_for(battle.martials["yushen_chop"]), 400, "御神·劈 costs 400 mana")
	assert_eq(Energy.cost_for(battle.martials["basic_sword"]), 0, "count-mode martials are unchanged")
	assert_eq(Energy.cost_for(battle.martials["parry"]), 1)
	GameState.reset()


func test_bosses_have_two_weaknesses_minions_none() -> void:
	var battle = _build()["battle"]
	for id in ["dongfang_yun", "sol_demon_king"]:
		var boss = battle.get_unit(id)
		assert_eq(boss.weaknesses.size(), 2, "%s has two weakness slots" % id)
		assert_eq(str(boss.weaknesses[0]), "neili", "slots follow the colors the hero owns")
		assert_eq(str(boss.weaknesses[1]), "neili", "with one color both slots use it")
		assert_true(boss.weak_dirs[0] != boss.weak_dirs[1], "in different directions")
	GameState.reset()


func test_regen_heals_after_the_players_turn_but_not_wounds_or_stun() -> void:
	var battle = _build()["battle"]
	var yun = battle.get_unit("dongfang_yun")
	assert_eq(battle.begin_turn(), "player")
	yun.unit.hp -= 400
	battle.end_turn("player")
	var events: Array = battle.take_pending()
	assert_eq(events.size() >= 1, true, "a regen event is queued")
	assert_eq(str(events[0].get("source", "")), "regen")
	assert_eq(yun.unit.hp, yun.unit.max_hp, "the damage is regenerated at once")
	assert_eq(battle.take_pending().size(), 0, "pending events are taken only once")
	# 伤口压低上限，回复不会超过；眩晕期间不回复。
	var regen = load("res://core/tactics/tactics_regen.gd")
	yun.unit.wound = 300
	yun.unit.hp = 100
	yun.unit.stun_left = 1
	regen.on_player_turn_end(battle)
	assert_eq(yun.unit.hp, 100, "a stunned (broken) enemy does not regenerate")
	yun.unit.stun_left = 0
	regen.on_player_turn_end(battle)
	assert_eq(yun.unit.hp, yun.unit.max_hp - 300, "regeneration stops at the wound cap")
	GameState.reset()


func test_tutorial_hints_fire_once_per_event() -> void:
	var tutorial = TacticsTutorial.new()
	var holder := Control.new()
	tutorial.setup(holder, "opening_duel")
	assert_true(tutorial.active, "the duel has tutorial steps")
	assert_true(tutorial.shown.has("start"), "the first hint shows at battle start")
	tutorial.on_events([{"type": "heal", "unit": "x", "amount": 5, "source": "regen"}])
	assert_true(tutorial.shown.has("regen"), "regen shows the jianyi hint")
	var count: int = tutorial.shown.size()
	tutorial.on_events([{"type": "heal", "unit": "x", "amount": 5, "source": "regen"}])
	assert_eq(tutorial.shown.size(), count, "each hint shows only once")
	tutorial.on_events([{"type": "hit", "weak": true}, {"type": "stun"}, {"type": "jianyi"}])
	assert_true(tutorial.shown.has("weak_hit") and tutorial.shown.has("break") and tutorial.shown.has("jianyi"))
	holder.free()

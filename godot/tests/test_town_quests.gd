extends "res://tests/test_case.gd"

const GameState = preload("res://core/game_state.gd")
const Progression = preload("res://core/progression.gd")
const Quests = preload("res://core/quests.gd")

const BUN_VENDOR_PLAYER_POS := Vector2(18.0, 2.4)
const DISCIPLE_PLAYER_POS := Vector2(22.5, 2.8)

var encounter_count: int = 0
var encounter_args: Array = []


func _reset() -> void:
	GameState.reset()
	Quests.reload()
	Progression.reload_items()


func _new_town() -> Variant:
	var town: Variant = load("res://world/town.gd").new()
	town.build()
	town.build_hud()
	return town


func _finish_dialogue(town: Variant) -> void:
	for i in range(200):
		if not bool(town.dialogue_view.is_active()):
			return
		town.dialogue_view.advance()


func _on_encounter(enemy_id: String, count: int, first_strike: bool) -> void:
	encounter_count += 1
	encounter_args = [enemy_id, count, first_strike]


func _marker(town: Variant, npc_id: String) -> Node:
	return town.find_child("QuestMarker_%s" % npc_id, true, false)


func _marker_text(town: Variant, npc_id: String) -> String:
	var node: Node = _marker(town, npc_id)
	if node == null:
		return "<missing>"
	return str(node.get("text"))


func test_bun_vendor_runs_the_herbs_quest() -> void:
	_reset()
	var town: Variant = _new_town()
	town.player_pos = BUN_VENDOR_PLAYER_POS
	var marker: Node = _marker(town, "bun_vendor")
	assert_true(marker != null, "the bun vendor has a quest marker node")
	assert_eq(str(marker.get("text")), "!", "the marker offers the quest")
	assert_true(bool(marker.get("visible")), "the available marker is visible")

	assert_true(town.try_interact(), "the vendor starts the offer dialogue")
	_finish_dialogue(town)
	assert_eq(Quests.state("herbs"), "active", "the offer starts the herbs quest")
	assert_eq(_marker_text(town, "bun_vendor"), "…", "the marker turns into dots")

	Progression.give_item("herb", 3)
	assert_eq(Quests.state("herbs"), "ready", "three herbs complete the quest")
	town._refresh_quest_markers()
	assert_eq(_marker_text(town, "bun_vendor"), "?", "the ready marker asks for turn in")

	assert_true(town.try_interact(), "the vendor starts the ready dialogue")
	_finish_dialogue(town)
	assert_eq(Quests.state("herbs"), "done", "the ready dialogue turns the quest in")
	assert_eq(
		int(GameState.stat_bonus.get("recovery", 0)), 2, "the herbs reward adds recovery"
	)
	town._refresh_quest_markers()
	assert_eq(_marker_text(town, "bun_vendor"), "", "a finished quest has no marker")
	assert_true(not bool(marker.get("visible")), "the marker hides when it is empty")

	assert_true(town.try_interact(), "the vendor falls back to the plain chat")
	_finish_dialogue(town)
	assert_true(not town.is_dialogue_active(), "the plain chat also finishes")
	town.free()
	_reset()


func test_disciple_spar_and_scout_flow() -> void:
	_reset()
	encounter_count = 0
	encounter_args.clear()
	var town: Variant = _new_town()
	town.connect("encounter_requested", Callable(self, "_on_encounter"))
	town.player_pos = DISCIPLE_PLAYER_POS
	assert_eq(_marker_text(town, "disciple"), "!", "the disciple signals an available quest")

	assert_true(town.try_interact(), "the disciple offers the spar")
	_finish_dialogue(town)
	assert_eq(Quests.state("spar"), "active", "the spar offer starts the quest")
	assert_eq(Quests.state("scout"), "none", "the scout is still locked")
	assert_eq(encounter_count, 0, "the offer dialogue does not start the fight")
	assert_eq(_marker_text(town, "disciple"), "…", "the active spar shows dots")

	assert_true(town.try_interact(), "talking again starts the active spar dialogue")
	_finish_dialogue(town)
	assert_eq(encounter_count, 1, "the active spar requests one encounter")
	assert_eq(encounter_args, ["disciple_spar", 1, false], "the spar encounter args")
	assert_eq(Quests.state("spar"), "active", "losing or winning keeps the quest active")

	# Game._on_battle_finished applies this on a win.
	Quests.notify("defeat", "disciple_spar", 1)
	assert_eq(Quests.state("spar"), "ready", "winning makes the spar ready")
	town._refresh_quest_markers()
	assert_eq(_marker_text(town, "disciple"), "?", "the ready marker asks for turn in")

	assert_true(town.try_interact(), "the disciple starts the ready dialogue")
	_finish_dialogue(town)
	assert_eq(Quests.state("spar"), "done", "the spar is turned in")
	assert_eq(int(GameState.stat_bonus.get("skill", 0)), 2, "the spar rewards skill")
	assert_eq(_marker_text(town, "disciple"), "!", "the scout unlocks after the spar")

	assert_true(town.try_interact(), "the disciple offers the scout")
	_finish_dialogue(town)
	assert_eq(Quests.state("scout"), "active", "the scout offer starts the quest")

	Quests.notify("defeat", "bandit_scout", 1)
	assert_eq(Quests.state("scout"), "ready", "beating the scout makes it ready")
	assert_true(town.try_interact(), "the disciple starts the scout ready dialogue")
	_finish_dialogue(town)
	assert_eq(Quests.state("scout"), "done", "the scout is turned in")
	assert_eq(int(GameState.stat_bonus.get("power", 0)), 1, "the scout rewards power")
	assert_eq(int(GameState.stat_bonus.get("defense", 0)), 1, "the scout rewards defense")
	assert_eq(_marker_text(town, "disciple"), "", "the finished chain has no marker")
	town.free()
	_reset()

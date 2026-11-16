extends "res://tests/test_case.gd"

const Interaction = preload("res://world/interaction.gd")
const GameState = preload("res://core/game_state.gd")

const BUN_VENDOR_PLAYER_POS := Vector2(18.0, 2.4)
const BOSS_PLAYER_POS := Vector2(8.5, 2.4)

var encounter_count: int = 0
var encounter_args: Array = []


func _new_town() -> Variant:
	var town: Variant = load("res://world/town.gd").new()
	town.build()
	town.build_hud()
	return town


func _reset_encounter() -> void:
	encounter_count = 0
	encounter_args.clear()


func _on_encounter(enemy_id: String, count: int, first_strike: bool) -> void:
	encounter_count += 1
	encounter_args = [enemy_id, count, first_strike]


func _finish_dialogue(town: Variant) -> void:
	for i in range(60):
		if not bool(town.dialogue_view.is_active()):
			break
		town.dialogue_view.advance()


func test_game_state_flags() -> void:
	GameState.reset()
	assert_true(not GameState.has_flag("boss_defeated"), "a flag starts unset")
	GameState.set_flag("boss_defeated")
	assert_true(GameState.has_flag("boss_defeated"), "a flag can be set")
	GameState.set_flag("boss_defeated", false)
	assert_true(not GameState.has_flag("boss_defeated"), "a flag can be cleared")
	GameState.set_flag("boss_defeated")
	GameState.reset()
	assert_true(not GameState.has_flag("boss_defeated"), "reset clears every flag")


func test_nearest_npc() -> void:
	var positions: Dictionary = {
		"a": Vector2(0.0, 0.0),
		"b": Vector2(10.0, 0.0),
		"c": Vector2(0.0, 10.0),
	}
	assert_eq(
		Interaction.nearest_npc(Vector2(1.0, 0.0), positions), "a",
		"the npc inside the range is returned"
	)
	assert_eq(
		Interaction.nearest_npc(Vector2(5.0, 5.0), positions), "",
		"nothing is returned when every npc is out of range"
	)
	var two: Dictionary = {
		"left": Vector2(0.0, 0.0),
		"right": Vector2(2.0, 0.0),
	}
	assert_eq(
		Interaction.nearest_npc(Vector2(1.2, 0.0), two), "right",
		"the closer of two npcs in range wins"
	)


func test_town_has_all_npcs_initially() -> void:
	GameState.reset()
	var town: Variant = _new_town()
	assert_eq(town.npc_nodes.size(), 5, "all five npcs are built")
	town.free()


func test_defeated_npcs_are_removed() -> void:
	GameState.reset()
	GameState.set_flag("boss_defeated")
	var town: Variant = _new_town()
	assert_eq(town.npc_nodes.size(), 2, "only the two ordinary npcs remain")
	assert_true(town.npc_nodes.has("bun_vendor"), "the bun vendor remains")
	assert_true(town.npc_nodes.has("disciple"), "the disciple remains")
	assert_true(not town.npc_nodes.has("ma_youwei"), "the boss is gone")
	town.free()
	GameState.reset()


func test_try_interact_starts_dialogue() -> void:
	GameState.reset()
	var town: Variant = _new_town()
	town.player_pos = BUN_VENDOR_PLAYER_POS
	assert_true(town.try_interact(), "interaction starts next to the bun vendor")
	assert_true(town.is_dialogue_active(), "the dialogue is active")
	assert_eq(
		str(town.dialogue_view.name_label.text), "包子摊老板",
		"the first line uses the name override"
	)
	town.free()


func test_try_interact_far_away_returns_false() -> void:
	GameState.reset()
	var town: Variant = _new_town()
	assert_true(not town.try_interact(), "no npc is close to the spawn point")
	assert_true(not town.is_dialogue_active(), "no dialogue starts")
	town.free()


func test_dialogue_blocks_movement() -> void:
	GameState.reset()
	var town: Variant = _new_town()
	town.player_pos = BUN_VENDOR_PLAYER_POS
	assert_true(town.try_interact(), "interaction starts")
	assert_true(town.is_dialogue_active(), "the dialogue is active")
	var before: Vector2 = town.player_pos
	town.set_input_override(Vector2(1.0, 0.0))
	town.tick_player(0.5)
	assert_true(town.player_pos.is_equal_approx(before), "the player stands still in a dialogue")
	town.free()


func test_dialogue_finish_resumes_movement() -> void:
	GameState.reset()
	var town: Variant = _new_town()
	town.player_pos = BUN_VENDOR_PLAYER_POS
	assert_true(town.try_interact(), "interaction starts")
	_finish_dialogue(town)
	assert_true(not town.is_dialogue_active(), "the dialogue has finished")
	var before_x: float = float(town.player_pos.x)
	town.set_input_override(Vector2(1.0, 0.0))
	town.tick_player(0.5)
	assert_true(float(town.player_pos.x) > before_x, "the player moves after the dialogue ends")
	town.free()


func test_ordinary_npc_does_not_emit_encounter() -> void:
	GameState.reset()
	_reset_encounter()
	var town: Variant = _new_town()
	town.connect("encounter_requested", Callable(self, "_on_encounter"))
	town.player_pos = BUN_VENDOR_PLAYER_POS
	assert_true(town.try_interact(), "interaction starts")
	_finish_dialogue(town)
	assert_eq(encounter_count, 0, "an ordinary npc never requests an encounter")
	town.free()


func test_boss_dialogue_emits_encounter_after_finish() -> void:
	GameState.reset()
	_reset_encounter()
	var town: Variant = _new_town()
	town.connect("encounter_requested", Callable(self, "_on_encounter"))
	town.player_pos = BOSS_PLAYER_POS
	assert_true(town.try_interact(), "the boss dialogue starts")
	assert_true(town.is_dialogue_active(), "the dialogue is active")
	assert_eq(encounter_count, 0, "no encounter while the dialogue is running")
	for i in range(60):
		if not bool(town.dialogue_view.is_active()):
			break
		assert_eq(encounter_count, 0, "no encounter before the dialogue ends")
		town.dialogue_view.advance()
	assert_eq(encounter_count, 1, "the encounter is requested exactly once")
	assert_eq(encounter_args.size(), 3, "the signal carries three arguments")
	if encounter_args.size() == 3:
		assert_eq(str(encounter_args[0]), "ma_youwei", "the enemy is ma_youwei")
		assert_eq(int(encounter_args[1]), 1, "one enemy")
		assert_eq(bool(encounter_args[2]), false, "the player does not strike first")
	town.free()


func test_npc_turns_to_face_player() -> void:
	GameState.reset()
	var town: Variant = _new_town()
	town.player_pos = Vector2(19.5, 0.6)
	assert_true(town.try_interact(), "interaction starts")
	var npc: Variant = town.npc_nodes["bun_vendor"]
	assert_eq(str(npc.facing), "right", "the npc turns toward the player on its right")
	town.free()


func test_prompt_label_shows_name_when_near() -> void:
	GameState.reset()
	var town: Variant = _new_town()
	town.player_pos = BUN_VENDOR_PLAYER_POS
	town.update_prompt()
	assert_true(bool(town.prompt_label.visible), "the prompt is shown near an npc")
	assert_true(
		str(town.prompt_label.text).contains("包子摊老板"),
		"the prompt names the nearby npc"
	)
	town.player_pos = Vector2(-20.0, 15.0)
	town.update_prompt()
	assert_true(not bool(town.prompt_label.visible), "the prompt hides when far away")
	town.free()

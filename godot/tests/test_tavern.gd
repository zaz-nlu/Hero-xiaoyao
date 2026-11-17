extends "res://tests/test_case.gd"

const GameState = preload("res://core/game_state.gd")

var exit_count: int = 0
var enter_count: int = 0
var enter_places: Array = []
var encounter_count: int = 0
var encounter_args: Array = []


func _new_tavern() -> Variant:
	var tavern: Variant = load("res://world/tavern.gd").new()
	tavern.build()
	return tavern


func _new_town() -> Variant:
	var town: Variant = load("res://world/town.gd").new()
	town.build()
	town.build_hud()
	return town


func _on_exit_requested() -> void:
	exit_count += 1


func _on_enter_requested(place: String) -> void:
	enter_count += 1
	enter_places.append(place)


func _on_encounter(enemy_id: String, count: int, first_strike: bool) -> void:
	encounter_count += 1
	encounter_args = [enemy_id, count, first_strike]


func _finish_dialogue(tavern: Variant) -> void:
	for i in range(80):
		if not bool(tavern.dialogue_view.is_active()):
			return
		tavern.dialogue_view.advance()


func test_normal_state_builds_without_bandits() -> void:
	GameState.reset()
	var tavern: Variant = _new_tavern()
	assert_eq(str(tavern.current_state()), "normal", "a clean game starts in a normal tavern")
	assert_true(tavern.camera != null, "the tavern has a camera")
	assert_true(not bool(tavern.data.is_empty()), "tavern data loaded")
	assert_true(tavern.npc_nodes.has("keeper"), "the keeper is present")
	assert_true(not tavern.npc_nodes.has("ma_youwei"), "no ma_youwei in normal")
	assert_true(not tavern.npc_nodes.has("bandit_1"), "no bandit_1 in normal")
	assert_true(not tavern.npc_nodes.has("bandit_2"), "no bandit_2 in normal")
	assert_eq(tavern.fallen_table_count(), 0, "no table is down in normal")
	tavern.free()


func test_brawl_state_places_enemies_in_the_open_floor() -> void:
	GameState.reset()
	GameState.set_flag("bandits_entered")
	var tavern: Variant = _new_tavern()
	assert_eq(str(tavern.current_state()), "brawl", "bandits_entered starts a brawl")
	assert_true(tavern.npc_nodes.has("ma_youwei"), "ma_youwei is in the brawl")
	assert_true(tavern.npc_nodes.has("bandit_1"), "bandit_1 is in the brawl")
	assert_true(tavern.npc_nodes.has("bandit_2"), "bandit_2 is in the brawl")
	var enemies: Array = ["ma_youwei", "bandit_1", "bandit_2"]
	for id in enemies:
		var node: Node3D = tavern.npc_nodes[id]
		assert_true(
			node.position.x >= 6.5 and node.position.x <= 15.5,
			"%s x %.2f is inside the open floor" % [id, node.position.x]
		)
		assert_true(
			node.position.z >= -8.0 and node.position.z <= 1.0,
			"%s z %.2f is inside the open floor" % [id, node.position.z]
		)
	assert_true(tavern.fallen_table_count() >= 2, "at least two tables are down in a brawl")
	tavern.free()
	GameState.reset()


func test_aftermath_state_has_no_bandits() -> void:
	GameState.reset()
	GameState.set_flag("boss_defeated")
	var tavern: Variant = _new_tavern()
	assert_eq(str(tavern.current_state()), "aftermath", "boss_defeated starts the aftermath")
	assert_true(not tavern.npc_nodes.has("ma_youwei"), "ma_youwei is gone")
	assert_true(not tavern.npc_nodes.has("bandit_1"), "bandit_1 is gone")
	assert_true(not tavern.npc_nodes.has("bandit_2"), "bandit_2 is gone")
	assert_true(tavern.npc_nodes.has("keeper"), "the keeper is back")
	var keeper: Node3D = tavern.npc_nodes["keeper"]
	assert_true(
		keeper.position.distance_to(Vector3(6.0, 0.0, -8.5)) < 0.01,
		"the keeper stands in front of the bar"
	)
	tavern.free()
	GameState.reset()


func test_set_state_animates_furniture_and_npcs() -> void:
	GameState.reset()
	var tavern: Variant = _new_tavern()
	tavern.set_state("brawl", true)
	assert_true(tavern.fallen_table_count() < 2, "tables are still mid-fall before ticking")
	tavern.advance(1.5)
	var table_node: Node3D = tavern.furniture_nodes["table_1"]
	var table_target: Transform3D = tavern.furniture_target("table_1")
	assert_true(
		table_node.position.distance_to(table_target.origin) < 0.05,
		"the fallen table reaches its wrecked position"
	)
	assert_true(
		absf(absf(table_node.rotation.z) - PI / 2.0) < 0.05,
		"the fallen table is on its side"
	)
	var boss: Node3D = tavern.npc_nodes["ma_youwei"]
	var boss_target: Vector3 = tavern.npc_target_position("ma_youwei")
	assert_true(
		boss.position.distance_to(boss_target) < 0.05,
		"ma_youwei finishes walking to the open floor"
	)
	assert_eq(tavern.fallen_table_count(), 2, "exactly two tables end up down")
	tavern.free()


func test_player_cannot_walk_through_the_bar() -> void:
	GameState.reset()
	var tavern: Variant = _new_tavern()
	tavern.player_pos = Vector2(5.5, -8.6)
	tavern.set_input_override(Vector2(0.0, -1.0))
	for i in range(30):
		tavern.tick_player(0.1)
	assert_true(
		tavern.player_pos.y > -8.81,
		"the bar counter blocks the player (z=%.2f)" % tavern.player_pos.y
	)
	tavern.free()


func test_exit_area_emits_exit_requested() -> void:
	GameState.reset()
	exit_count = 0
	var tavern: Variant = _new_tavern()
	tavern.build_hud()
	tavern.connect("exit_requested", Callable(self, "_on_exit_requested"))
	tavern.player_pos = Vector2(11.0, 5.1)
	assert_true(tavern.try_interact(), "pressing E at the front edge leaves the tavern")
	assert_eq(exit_count, 1, "exit_requested fires once")
	tavern.update_prompt()
	assert_true(bool(tavern.prompt_label.visible), "the exit prompt is shown")
	assert_true(
		str(tavern.prompt_label.text).contains("走出酒馆"), "the prompt mentions leaving"
	)
	tavern.free()


func test_ma_youwei_dialogue_then_encounter() -> void:
	GameState.reset()
	GameState.set_flag("bandits_entered")
	encounter_count = 0
	encounter_args.clear()
	var tavern: Variant = _new_tavern()
	tavern.build_hud()
	tavern.connect("encounter_requested", Callable(self, "_on_encounter"))
	tavern.player_pos = Vector2(11.0, -1.8)
	assert_true(tavern.try_interact(), "talking to ma_youwei starts his intro")
	assert_true(tavern.is_dialogue_active(), "the intro dialogue is active")
	assert_eq(encounter_count, 0, "no encounter while the dialogue runs")
	_finish_dialogue(tavern)
	assert_eq(encounter_count, 1, "the encounter is requested after the dialogue")
	assert_eq(encounter_args.size(), 3, "the signal carries three arguments")
	if encounter_args.size() == 3:
		assert_eq(str(encounter_args[0]), "ma_youwei", "the enemy is ma_youwei")
		assert_eq(int(encounter_args[1]), 1, "one enemy")
		assert_eq(bool(encounter_args[2]), false, "the player does not strike first")
	tavern.free()
	GameState.reset()


func test_town_tavern_door_emits_enter_requested() -> void:
	GameState.reset()
	enter_count = 0
	enter_places.clear()
	var town: Variant = _new_town()
	town.connect("enter_requested", Callable(self, "_on_enter_requested"))
	town.player_pos = town.tavern_door()
	town.update_prompt()
	assert_true(bool(town.prompt_label.visible), "the tavern door prompt is shown")
	assert_true(
		str(town.prompt_label.text).contains("进入酒馆"), "the prompt mentions entering"
	)
	assert_true(town.try_interact(), "pressing E at the tavern door works")
	assert_eq(enter_count, 1, "enter_requested fires once")
	if not enter_places.is_empty():
		assert_eq(str(enter_places[0]), "tavern", "the requested place is the tavern")
	town.free()


func _decor_node_count(tavern: Variant) -> int:
	var names: Array[String] = [
		"Beams",
		"Rug",
		"Lantern_1",
		"Lantern_2",
		"Lantern_3",
		"Lantern_4",
		"LightShaft_1",
		"LightShaft_2",
		"LightShaft_3",
		"Dust",
		"WallSign",
	]
	var count := 0
	for node_name in names:
		if tavern.find_child(node_name, true, false) != null:
			count += 1
	return count


func test_tavern_decor_and_rug_states() -> void:
	GameState.reset()
	var tavern: Variant = _new_tavern()
	var beams: Node = tavern.find_child("Beams", true, false)
	assert_true(beams != null, "the tavern has a Beams node")
	if beams != null:
		assert_true(beams.get_child_count() >= 8, "five main beams and three cross beams")
	var rug_value: Variant = tavern.furniture_nodes.get("Rug", null)
	assert_true(rug_value is Node3D, "the rug is a furniture node")
	for i in range(1, 5):
		var lantern: Node = tavern.find_child("Lantern_%d" % i, true, false)
		assert_true(lantern != null, "Lantern_%d exists" % i)
		var has_light := false
		if lantern != null:
			for child in lantern.get_children():
				if child is OmniLight3D:
					has_light = true
		assert_true(has_light, "Lantern_%d carries an omni light" % i)
	for i in range(1, 4):
		assert_true(
			tavern.find_child("LightShaft_%d" % i, true, false) != null,
			"LightShaft_%d exists" % i
		)
	assert_true(tavern.find_child("Dust", true, false) != null, "dust particles exist")
	if FileAccess.file_exists("res://assets/ai/game/prop_tavern_sign.png"):
		assert_true(tavern.find_child("WallSign", true, false) != null, "the wall sign exists")
	var decor_count: int = _decor_node_count(tavern)
	tavern.set_state("brawl", false)
	if rug_value is Node3D:
		var rug: Node3D = rug_value
		assert_near(rug.position.x - 11.0, 0.6, 0.1, "the brawl kicks the rug sideways")
		assert_near(rug.position.z + 2.5, 0.4, 0.1, "the brawl pushes the rug forward")
	tavern.set_state("aftermath", true)
	tavern.advance(1.5)
	tavern.set_state("normal", true)
	tavern.advance(1.5)
	assert_eq(
		_decor_node_count(tavern), decor_count, "state changes do not duplicate decor"
	)
	tavern.free()
	GameState.reset()

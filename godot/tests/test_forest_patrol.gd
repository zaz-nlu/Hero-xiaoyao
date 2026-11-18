extends "res://tests/test_case.gd"

const GameState = preload("res://core/game_state.gd")
const Stealth = preload("res://shared/gameplay/stealth.gd")

var encounters: Array = []


func _new_forest() -> Variant:
	var forest: Variant = load("res://features/forest/forest.gd").new()
	forest.build()
	forest.build_hud()
	return forest


func _on_encounter_requested(enemy_id: String, count: int, first_strike: bool) -> void:
	encounters.append([enemy_id, count, first_strike])


func _new_game() -> Variant:
	Engine.set_meta("skip_title", true)
	var game: Variant = load("res://app/game.gd").new()
	game.show_town()
	return game


func _place_in_cone(forest: Variant, member: Dictionary, distance: float) -> Vector2:
	var pos: Vector2 = member["pos"]
	var facing := float(member["facing_angle"])
	var half := float(member["half_angle"])
	for offset_deg in [0.0, -10.0, 10.0, -20.0, 20.0, -30.0, 30.0]:
		for dist in [distance, distance * 0.8, distance * 1.2, 2.0]:
			var point: Vector2 = pos + Stealth.direction(facing + deg_to_rad(offset_deg)) * float(dist)
			if not Stealth.is_walkable(point, forest.blockers, forest.bounds_rect):
				continue
			if Stealth.sees(pos, facing, point, float(dist) + 0.01, half, forest.blockers):
				return point
	return pos + Stealth.direction(facing) * distance


func _place_behind(forest: Variant, member: Dictionary) -> Vector2:
	var pos: Vector2 = member["pos"]
	var facing := float(member["facing_angle"])
	for dist in [1.2, 1.5, 1.7, 1.0]:
		var point: Vector2 = pos - Stealth.direction(facing) * float(dist)
		if Stealth.is_walkable(point, forest.blockers, forest.bounds_rect):
			return point
	return pos


func _patrol_sees(forest: Variant, point: Vector2) -> bool:
	for group_value in forest.patrol_groups:
		var group: Dictionary = group_value
		var members: Array = group["members"]
		for member_value in members:
			var member: Dictionary = member_value
			var reach := Stealth.view_distance(float(member["vision"]), false, false)
			if Stealth.sees(
				member["pos"],
				float(member["facing_angle"]),
				point,
				reach,
				float(member["half_angle"]),
				forest.blockers
			):
				return true
	return false


# Scout test helper: stay out of every patrol's cone so only the scout reacts.
func _place_in_scout_cone(forest: Variant, distance: float) -> Vector2:
	var scout_pos: Vector2 = forest.scout["pos"]
	var facing := float(forest.scout["facing_angle"])
	var half := float(forest.scout["half_angle"])
	for offset_deg in [0.0, -10.0, 10.0, -20.0, 20.0, -30.0, 30.0]:
		for dist in [distance, distance * 0.8, distance * 1.2, 2.0]:
			var point: Vector2 = scout_pos + Stealth.direction(facing + deg_to_rad(offset_deg)) * float(dist)
			if not Stealth.is_walkable(point, forest.blockers, forest.bounds_rect):
				continue
			if _patrol_sees(forest, point):
				continue
			if Stealth.sees(scout_pos, facing, point, float(dist) + 0.01, half, forest.blockers):
				return point
	return scout_pos + Stealth.direction(facing) * distance


func test_build_creates_two_groups_and_a_scout() -> void:
	GameState.reset()
	var forest: Variant = _new_forest()
	assert_eq(forest.patrol_groups.size(), 2, "two patrol groups exist")
	var patrol_nodes: Array = forest.find_children("Patrol_*", "", true, false)
	assert_eq(patrol_nodes.size(), 3, "three bandit patrol sprites exist")
	assert_true(forest.find_child("Scout", true, false) != null, "the scout exists")
	assert_eq(str(forest.scout.get("enemy_id", "")), "bandit_scout", "the scout uses the scout enemy")
	forest.free()


func test_patrols_move_and_stay_walkable() -> void:
	GameState.reset()
	var forest: Variant = _new_forest()
	var leader: Dictionary = forest.patrol_groups[0]["members"][0]
	var start: Vector2 = leader["pos"]
	forest.advance_patrols(1.0)
	var moved: Vector2 = leader["pos"]
	assert_true(start.distance_to(moved) > 0.5, "the patrol advances along its route")
	for group_value in forest.patrol_groups:
		var group: Dictionary = group_value
		var members: Array = group["members"]
		for member_value in members:
			var member: Dictionary = member_value
			assert_true(
				Stealth.is_walkable(member["pos"], forest.blockers, forest.bounds_rect),
				"patrol waypoints stay on walkable ground"
			)
	assert_true(
		Stealth.is_walkable(forest.scout["pos"], forest.blockers, forest.bounds_rect),
		"the scout stands on walkable ground"
	)
	forest.free()


func test_detection_emits_once() -> void:
	GameState.reset()
	encounters.clear()
	var forest: Variant = _new_forest()
	forest.connect("encounter_requested", Callable(self, "_on_encounter_requested"))
	var leader: Dictionary = forest.patrol_groups[0]["members"][0]
	forest.player_pos = _place_in_cone(forest, leader, 3.0)
	forest.advance_patrols(1.0)
	assert_eq(encounters.size(), 1, "being spotted requests a battle")
	if encounters.size() == 1:
		assert_eq(str(encounters[0][0]), "bandit", "the group is bandits")
		assert_eq(int(encounters[0][1]), 2, "the whole two-man group joins")
		assert_true(not bool(encounters[0][2]), "the player does not get the first strike")
	forest.advance_patrols(1.0)
	assert_eq(encounters.size(), 1, "further ticks do not request a second battle")
	forest.free()


func test_crouching_avoids_detection() -> void:
	GameState.reset()
	encounters.clear()
	var forest: Variant = _new_forest()
	forest.connect("encounter_requested", Callable(self, "_on_encounter_requested"))
	var leader: Dictionary = forest.patrol_groups[0]["members"][0]
	forest.player_pos = _place_in_cone(forest, leader, 4.5)
	forest.set_crouch_override(true)
	forest.advance_patrols(0.1)
	assert_eq(encounters.size(), 0, "crouching halves the viewing distance")
	forest.set_crouch_override(false)
	forest.advance_patrols(1.0)
	assert_eq(encounters.size(), 1, "standing up at the same distance gets spotted")
	forest.free()


func test_sneak_attack_from_behind() -> void:
	GameState.reset()
	encounters.clear()
	var forest: Variant = _new_forest()
	forest.connect("encounter_requested", Callable(self, "_on_encounter_requested"))
	var leader: Dictionary = forest.patrol_groups[0]["members"][0]
	forest.player_pos = _place_behind(forest, leader)
	forest.update_prompt()
	assert_true(
		str(forest.prompt_label.text).contains("偷袭"),
		"the prompt offers a sneak attack from behind"
	)
	assert_true(forest.try_interact(), "pressing E starts the sneak attack")
	assert_eq(encounters.size(), 1, "the sneak attack requests one battle")
	if encounters.size() == 1:
		assert_eq(str(encounters[0][0]), "bandit", "it is still the bandit group")
		assert_eq(int(encounters[0][1]), 2, "the whole group joins")
		assert_true(bool(encounters[0][2]), "a sneak attack grants the first strike")
	forest.free()


func test_scout_detection() -> void:
	GameState.reset()
	encounters.clear()
	var forest: Variant = _new_forest()
	forest.connect("encounter_requested", Callable(self, "_on_encounter_requested"))
	forest.player_pos = _place_in_cone(forest, forest.scout, 2.5)
	forest.advance_patrols(0.01)
	forest.advance_patrols(1.0)
	assert_eq(encounters.size(), 1, "the scout raises the alarm")
	if encounters.size() == 1:
		assert_eq(str(encounters[0][0]), "bandit_scout", "the scout enemy is used")
		assert_eq(int(encounters[0][1]), 1, "the scout fights alone")
		assert_true(not bool(encounters[0][2]), "the scout spots the player first")
	forest.free()


func test_defeated_patrol_is_not_rebuilt() -> void:
	GameState.reset()
	GameState.set_flag("patrol_defeated_0")
	var forest: Variant = _new_forest()
	assert_eq(forest.patrol_groups.size(), 1, "only the surviving group is built")
	assert_true(forest.find_child("Patrol_0_0", true, false) == null, "route 0 is gone")
	var patrol_nodes: Array = forest.find_children("Patrol_*", "", true, false)
	assert_eq(patrol_nodes.size(), 1, "only the one-man group remains")
	forest.free()


func test_defeated_scout_is_not_rebuilt() -> void:
	GameState.reset()
	GameState.set_flag("scout_defeated")
	var forest: Variant = _new_forest()
	assert_true(forest.scout.is_empty(), "the scout is gone")
	assert_true(forest.find_child("Scout", true, false) == null, "no scout node is built")
	forest.free()


func test_forest_win_sets_patrol_flag_and_returns_to_spot() -> void:
	GameState.reset()
	var game: Variant = _new_game()
	var town: Variant = game.current
	town.enter_requested.emit("forest")
	var forest: Variant = game.current
	forest.player_pos = Vector2(0.0, 18.0)
	GameState.pending_forest_encounter = {"kind": "patrol", "id": 0}
	forest.encounter_requested.emit("bandit", 2, false)
	assert_eq(str(game.current_kind), "battle", "the patrol starts a battle")
	var view: Variant = game.current
	for enemy in view.battle.enemies:
		enemy.hp = 0
	view.refresh()
	view.press_return()
	assert_eq(str(game.current_kind), "forest", "the win returns to the forest")
	assert_true(GameState.has_flag("patrol_defeated_0"), "the win sets the patrol flag")
	assert_true(GameState.pending_forest_encounter == null, "the pending encounter is cleared")
	var back: Variant = game.current
	assert_true(
		back.player_pos.distance_to(Vector2(0.0, 18.0)) < 0.01,
		"the player returns to the same spot"
	)
	assert_eq(back.patrol_groups.size(), 1, "the defeated group is not rebuilt")
	game.free()


func test_forest_loss_returns_to_spawn_without_flag() -> void:
	GameState.reset()
	var game: Variant = _new_game()
	var town: Variant = game.current
	town.enter_requested.emit("forest")
	var forest: Variant = game.current
	forest.player_pos = Vector2(0.0, 18.0)
	GameState.pending_forest_encounter = {"kind": "patrol", "id": 0}
	forest.encounter_requested.emit("bandit", 2, false)
	var view: Variant = game.current
	view.battle.player.hp = 0
	view.refresh()
	view.press_return()
	assert_eq(str(game.current_kind), "forest", "a loss returns to the forest")
	assert_true(not GameState.has_flag("patrol_defeated_0"), "a loss sets no patrol flag")
	assert_true(GameState.forest_return_pos == null, "the saved forest position is cleared")
	assert_true(GameState.pending_forest_encounter == null, "the pending encounter is cleared")
	var back: Variant = game.current
	assert_true(
		back.player_pos.distance_to(Vector2(0.0, 21.5)) < 0.01,
		"the player respawns at the forest entrance"
	)
	assert_eq(back.patrol_groups.size(), 2, "both patrols are back")
	game.free()


func test_scout_win_sets_scout_flag() -> void:
	GameState.reset()
	var game: Variant = _new_game()
	var town: Variant = game.current
	town.enter_requested.emit("forest")
	var forest: Variant = game.current
	GameState.pending_forest_encounter = {"kind": "scout", "id": -1}
	forest.encounter_requested.emit("bandit_scout", 1, true)
	var view: Variant = game.current
	view.battle.enemies[0].hp = 0
	view.refresh()
	view.press_return()
	assert_true(GameState.has_flag("scout_defeated"), "the win sets the scout flag")
	var back: Variant = game.current
	assert_true(back.scout.is_empty(), "the scout is not rebuilt")
	game.free()

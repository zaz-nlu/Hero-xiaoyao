extends "res://tests/test_case.gd"

const Battle = preload("res://core/battle.gd")


func _make_view() -> Variant:
	var view: Variant = load("res://features/battle/battle_view.gd").new()
	view.build_ui()
	return view


func _finish_dialogue(view: Variant) -> void:
	for i in range(40):
		if not view.dialogue_view.is_active():
			return
		view.dialogue_view.advance()


func _sprite(actor: Variant) -> Sprite3D:
	return actor.get_node("Sprite") as Sprite3D


func test_sprites_built() -> void:
	var view: Variant = _make_view()
	view.start("bandit", 2, false)
	assert_true(view.stage != null, "the battle stage is built")
	assert_eq(view.stage.enemy_actors.size(), 2, "one actor per enemy")
	assert_eq(str(view.stage.player_actor.facing), "right", "the player faces right")
	assert_true(_sprite(view.stage.player_actor) != null, "the player actor has a sprite")
	for actor in view.stage.enemy_actors:
		assert_eq(str(actor.facing), "left", "enemies face left")
		assert_true(_sprite(actor) != null, "each enemy actor has a sprite")
	view.free()


func test_enemy_actors_have_independent_sprites() -> void:
	var view: Variant = _make_view()
	view.start("bandit", 2, false)
	assert_true(_sprite(view.stage.enemy_actors[0]) != _sprite(view.stage.enemy_actors[1]), "each enemy has its own sprite node")
	var first: Sprite3D = _sprite(view.stage.enemy_actors[0])
	var second: Sprite3D = _sprite(view.stage.enemy_actors[1])
	assert_true(first.texture != null and second.texture != null, "both enemy sprites have a texture")
	view.free()


func test_idle_actors_stand_still() -> void:
	var view: Variant = _make_view()
	view.start("bandit", 1, false)
	view.tick(0.6)
	assert_eq(view.stage.player_actor.current_frame_index(), 10, "the player stands in the right-facing idle frame")
	assert_eq(view.stage.enemy_actors[0].current_frame_index(), 15, "the enemy stands in the left-facing idle frame")
	view.free()


func test_hit_flash_then_recovers() -> void:
	var view: Variant = _make_view()
	view.start("bandit", 1, false)
	view.press_action({"kind": "martial", "id": "basic_sword", "target": 0})
	var sprite: Sprite3D = _sprite(view.stage.enemy_actors[0])
	assert_true(sprite.modulate.g < 0.8, "a damaged enemy flashes red")
	view.tick(0.3)
	assert_true(sprite.modulate.g > 0.95, "the flash recovers to the base tint")
	view.free()


func test_stunned_enemy_tinted_blue() -> void:
	var view: Variant = _make_view()
	view.start("bandit", 1, false)
	view.battle.enemies[0].stun_left = 1
	view.refresh()
	var sprite: Sprite3D = _sprite(view.stage.enemy_actors[0])
	assert_true(sprite.modulate.b > sprite.modulate.r, "a stunned enemy is tinted blue")
	view.free()


func test_dead_enemy_faded() -> void:
	var view: Variant = _make_view()
	view.start("bandit", 1, false)
	view.battle.enemies[0].hp = 0
	view.refresh()
	var sprite: Sprite3D = _sprite(view.stage.enemy_actors[0])
	assert_true(sprite.modulate.a < 0.5, "a fallen enemy fades out")
	view.free()


func test_bandit_has_no_dialogue() -> void:
	var view: Variant = _make_view()
	view.start("bandit", 1, true)
	assert_true(not view.dialogue_view.is_active(), "bandit encounters have no dialogue")
	view.free()


func test_boss_intro_blocks_actions_until_finished() -> void:
	var view: Variant = _make_view()
	view.start("ma_youwei", 1, false)
	assert_true(view.dialogue_view.is_active(), "the boss intro dialogue plays before the fight")
	view.press_action({"kind": "martial", "id": "basic_sword", "target": 0})
	assert_eq(int(view.battle.round), 1, "actions are blocked while the dialogue is active")
	assert_true(view.last_error != "", "the blocked action reports an error")
	for button in view.martial_buttons:
		assert_true(button.disabled, "martial buttons are disabled during the dialogue")
	_finish_dialogue(view)
	assert_true(not view.dialogue_view.is_active(), "the intro dialogue can be finished")
	view.press_action({"kind": "martial", "id": "basic_sword", "target": 0})
	assert_eq(int(view.battle.round), 2, "actions work again after the dialogue")
	view.free()


func test_boss_win_dialogue_plays_once() -> void:
	var view: Variant = _make_view()
	view.start("ma_youwei", 1, false)
	_finish_dialogue(view)
	view.battle.enemies[0].hp = 10
	view.press_action({"kind": "jianyi", "target": 0})
	assert_eq(int(view.battle.state()), Battle.State.WON, "jianyi finishes the weakened boss")
	assert_true(view.dialogue_view.is_active(), "the win dialogue plays after the victory")
	_finish_dialogue(view)
	assert_true(not view.dialogue_view.is_active(), "the win dialogue can be finished")
	view.refresh()
	assert_true(not view.dialogue_view.is_active(), "the win dialogue does not replay")
	view.free()


func test_missing_encounter_file_entry_is_fine() -> void:
	var view: Variant = _make_view()
	view.start("bandit", 1, true)
	view.start("bandit", 2, false)
	assert_eq(view.stage.enemy_actors.size(), 2, "restarting without an encounter entry keeps the stage working")
	assert_true(not view.dialogue_view.is_active(), "no dialogue is started for a bandit encounter")
	view.free()

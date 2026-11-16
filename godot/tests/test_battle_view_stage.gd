extends "res://tests/test_case.gd"

const Battle = preload("res://core/battle.gd")

const PLAYER_FRAME_RIGHT := Rect2(0, 96, 32, 48)
const ENEMY_FRAME_LEFT := Rect2(0, 144, 32, 48)


func _make_view() -> Variant:
	var view: Variant = load("res://ui/battle_view.gd").new()
	view.build_ui()
	return view


func _finish_dialogue(view: Variant) -> void:
	for i in range(40):
		if not view.dialogue_view.is_active():
			return
		view.dialogue_view.advance()


func test_sprites_built() -> void:
	var view: Variant = _make_view()
	view.start("bandit", 2, false)
	assert_eq(view.enemy_sprites.size(), 2, "one sprite per enemy")
	assert_true(view.player_sprite.texture is AtlasTexture, "the player sprite uses an atlas frame")
	assert_eq(view.player_sprite.texture.region, PLAYER_FRAME_RIGHT, "the player faces right, standing frame")
	for sprite in view.enemy_sprites:
		assert_true(sprite.texture is AtlasTexture, "each enemy sprite uses an atlas frame")
		assert_eq(sprite.texture.region, ENEMY_FRAME_LEFT, "enemies face left, standing frame")
	view.free()


func test_enemy_sprites_have_independent_textures() -> void:
	var view: Variant = _make_view()
	view.start("bandit", 2, false)
	assert_true(view.enemy_sprites[0].texture != view.enemy_sprites[1].texture, "each enemy has its own atlas texture")
	view.free()


func test_idle_animation_toggles() -> void:
	var view: Variant = _make_view()
	view.start("bandit", 1, false)
	view.tick(0.6)
	assert_near(view.player_sprite.texture.region.position.x, 64.0, 0.001, "the idle animation switches to the transition column")
	view.tick(0.5)
	assert_near(view.player_sprite.texture.region.position.x, 0.0, 0.001, "the idle animation switches back to the standing column")
	view.free()


func test_hit_flash_then_recovers() -> void:
	var view: Variant = _make_view()
	view.start("bandit", 1, false)
	view.press_action({"kind": "martial", "id": "basic_sword", "target": 0})
	assert_true(view.enemy_sprites[0].modulate.g < 0.8, "a damaged enemy flashes red")
	view.tick(0.3)
	assert_true(view.enemy_sprites[0].modulate.g > 0.95, "the flash recovers to the base tint")
	view.free()


func test_stunned_enemy_tinted_blue() -> void:
	var view: Variant = _make_view()
	view.start("bandit", 1, false)
	view.battle.enemies[0].stun_left = 1
	view.refresh()
	assert_true(view.enemy_sprites[0].modulate.b > view.enemy_sprites[0].modulate.r, "a stunned enemy is tinted blue")
	view.free()


func test_dead_enemy_faded() -> void:
	var view: Variant = _make_view()
	view.start("bandit", 1, false)
	view.battle.enemies[0].hp = 0
	view.refresh()
	assert_true(view.enemy_sprites[0].modulate.a < 0.5, "a fallen enemy fades out")
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
	assert_eq(view.enemy_sprites.size(), 2, "restarting without an encounter entry keeps the stage working")
	assert_true(not view.dialogue_view.is_active(), "no dialogue is started for a bandit encounter")
	view.free()

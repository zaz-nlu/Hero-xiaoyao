extends "res://tests/test_case.gd"

const CharacterSprite = preload("res://world/character_sprite.gd")


func _make():
	var character = CharacterSprite.new()
	character.setup("vendor")
	return character


func test_frame_rows() -> void:
	var character = _make()
	character.set_facing("down")
	assert_eq(character.current_frame_index(), 0, "down idle")
	character.set_facing("up")
	assert_eq(character.current_frame_index(), 5, "up idle")
	character.set_facing("right")
	assert_eq(character.current_frame_index(), 10, "right idle")
	character.set_facing("left")
	assert_eq(character.current_frame_index(), 15, "left idle")
	character.free()


func test_walk_cycle() -> void:
	var character = _make()
	character.set_facing("right")
	character.set_moving(true)
	assert_eq(character.current_frame_index(), 11, "walk starts on column 1")
	character.advance(0.125)
	assert_eq(character.current_frame_index(), 12, "walk advances to column 2")
	character.advance(0.125)
	assert_eq(character.current_frame_index(), 13, "walk advances to column 3")
	character.advance(0.125)
	assert_eq(character.current_frame_index(), 14, "walk advances to column 4")
	character.advance(0.125)
	assert_eq(character.current_frame_index(), 11, "walk wraps back to column 1")
	character.free()


func test_stop_returns_to_idle() -> void:
	var character = _make()
	character.set_facing("down")
	character.set_moving(true)
	character.advance(0.3)
	character.set_moving(false)
	assert_eq(character.current_frame_index(), 0, "stopping returns to the idle column")
	character.free()


func test_sprite_node_configured() -> void:
	var character = _make()
	var sprite := character.get_node("Sprite") as Sprite3D
	assert_true(sprite != null, "sprite child exists")
	if sprite != null:
		assert_eq(sprite.hframes, 5, "five animation columns")
		assert_eq(sprite.vframes, 4, "four facing rows")
		assert_eq(sprite.billboard, BaseMaterial3D.BILLBOARD_FIXED_Y, "fixed y billboard")
		assert_eq(
			sprite.texture_filter,
			BaseMaterial3D.TEXTURE_FILTER_NEAREST,
			"nearest texture filter"
		)
		assert_true(sprite.texture != null, "sprite texture is set")
	character.free()

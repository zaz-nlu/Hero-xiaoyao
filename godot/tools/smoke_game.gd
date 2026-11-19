extends SceneTree

# Frame-based integration smoke test (run headless or windowed):
#   godot --headless --path godot -s res://tools/smoke_game.gd
# Boots the real main scene, walks to Ma Youwei, talks, enters the battle, and checks
# that the battle UI really fills the window. Prints "SMOKE OK" and exits 0, or prints
# "SMOKE FAIL: <reason>" and exits 1. Layout only resolves after real frames, which is
# why this is not a unit test.

var game: Node
var frames: int = 0
var failed: bool = false
var expected_units: int = 0


func _initialize() -> void:
	# The headless window is stuck at 64x64, far too small for a 230 px tall panel, so run
	# the game inside a SubViewport of the real size.
	var sv := SubViewport.new()
	sv.size = Vector2i(1280, 720)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sv)
	Engine.set_meta("skip_title", true)
	var scene: PackedScene = load("res://app/game.tscn")
	game = scene.instantiate()
	sv.add_child(game)


func _fail(reason: String) -> void:
	print("SMOKE FAIL: ", reason)
	failed = true
	quit(1)


func _process(_delta: float) -> bool:
	if failed:
		return false
	frames += 1
	var cur: Variant = game.current
	if frames == 5:
		if game.current_kind != "town":
			_fail("game did not start in the town")
			return false
		var door: Vector2 = cur.tavern_door()
		cur.player_pos = door
		cur.player.position = Vector3(door.x, 0.0, door.y)
	elif frames == 10:
		if not cur.try_interact():
			_fail("could not enter the tavern")
			return false
	elif frames == 15:
		if game.current_kind != "tavern":
			_fail("did not enter the tavern (kind=%s)" % game.current_kind)
			return false
		cur.player_pos = Vector2(11.0, -4.0)
		cur.player.position = Vector3(11.0, 0.0, -4.0)
		cur.check_story(0.016)
	elif frames == 20:
		if not cur.is_dialogue_active():
			_fail("the ambush opening narration did not start")
			return false
		var guard: int = 0
		while cur.is_dialogue_active() and guard < 60:
			cur.dialogue_view.advance()
			guard += 1
	elif frames == 25:
		# brawl entrance (about 1.5 s) + the Zixia pre-fight show (about 6 s)
		expected_units = int(cur.bandit_count()) + 2  # player + Ma Youwei + bandits
		cur.advance(14.0)
		if not cur.is_dialogue_active():
			_fail("the pre-fight/ambush dialogue did not follow the brawl animation")
			return false
	elif frames == 30:
		# the pre-fight end dialogue chains into the ambush dialogue: keep going until the fight starts
		for round in range(6):
			var guard2: int = 0
			while cur.is_dialogue_active() and guard2 < 60:
				cur.dialogue_view.advance()
				guard2 += 1
			if game.current_kind != "tavern":
				break
			cur.advance(1.0)
	elif frames == 45:
		if game.current_kind != "battle":
			_fail("did not enter the battle after the ambush (kind=%s)" % game.current_kind)
			return false
		var view: Control = game.current
		var window: Vector2 = game.get_viewport().get_visible_rect().size
		if view.size.x < window.x - 1.0 or view.size.y < window.y - 1.0:
			_fail("battle view %s does not fill the window %s" % [view.size, window])
			return false
		if view.stage == null or not is_instance_valid(view.stage):
			_fail("the tactics battle has no 3D stage")
			return false
		if view.battle == null:
			_fail("the tactics battle was not assembled")
			return false
		if view.battle.get_unit("ma_youwei") == null:
			_fail("the ambush battle has no Ma Youwei")
			return false
		if int(view.battle.units.size()) != expected_units:
			_fail(
				"the tactics battle should have leader + bandits (%d), got %d"
				% [expected_units, int(view.battle.units.size())])
			return false
		print("SMOKE OK")
		quit(0)
	return false

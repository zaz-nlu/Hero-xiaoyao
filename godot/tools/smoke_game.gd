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


func _initialize() -> void:
	# The headless window is stuck at 64x64, far too small for a 230 px tall panel, so run
	# the game inside a SubViewport of the real size.
	var sv := SubViewport.new()
	sv.size = Vector2i(1280, 720)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sv)
	Engine.set_meta("skip_title", true)
	var scene: PackedScene = load("res://ui/game.tscn")
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
		cur.player_pos = Vector2(8.5, 3.0)
		cur.player.position = Vector3(8.5, 0, 3.0)
	elif frames == 10:
		if not cur.try_interact():
			_fail("could not talk to Ma Youwei")
	elif frames == 20:
		var guard: int = 0
		while cur.is_dialogue_active() and guard < 60:
			cur.dialogue_view.advance()
			guard += 1
	elif frames == 40:
		if game.current_kind != "battle":
			_fail("did not enter the battle after the dialogue (kind=%s)" % game.current_kind)
			return false
		var view: Control = game.current
		var window: Vector2 = game.get_viewport().get_visible_rect().size
		if view.size.x < window.x - 1.0 or view.size.y < window.y - 1.0:
			_fail("battle view %s does not fill the window %s" % [view.size, window])
			return false
		var panel: Control = view.get_node("BottomPanel")
		var bottom: float = panel.global_position.y + panel.size.y
		if panel.global_position.y < 0.0 or bottom > window.y + 1.0:
			_fail("bottom panel is off screen (y=%s, bottom=%s, window h=%s)" % [panel.global_position.y, bottom, window.y])
			return false
		if view.stage == null or not is_instance_valid(view.stage):
			_fail("battle has no 3D stage")
			return false
		print("SMOKE OK")
		quit(0)
	return false

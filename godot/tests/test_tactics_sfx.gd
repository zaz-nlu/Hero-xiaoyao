extends "res://tests/test_case.gd"

const AssetPaths = preload("res://shared/resources/asset_paths.gd")
const GameState = preload("res://core/game_state.gd")
const TacticsSfx = preload("res://features/tactics/tactics_sfx.gd")

const SFX_KEYS := [
	"hit_perfect", "hit_counter", "hit_block", "hit_plain",
	"stun", "jianyi", "weak_hit",
]


class FakeAudio:
	var calls: Array = []

	func play_sfx(name: String, volume: float = 1.0) -> void:
		calls.append({"name": name, "volume": volume})


func _make_view() -> Dictionary:
	GameState.reset()
	var tree: Variant = Engine.get_meta("test_tree", null)
	var holder := Control.new()
	holder.size = Vector2(1152.0, 720.0)
	if tree != null:
		tree.root.add_child(holder)
	var view: Variant = load("res://features/tactics/tactics_view.gd").new()
	view.use_3d = false
	holder.add_child(view)
	view.size = Vector2(1152.0, 720.0)
	return {"holder": holder, "view": view}


func _finish(holder: Control) -> void:
	holder.free()
	GameState.reset()


func test_key_for_maps_core_events() -> void:
	assert_eq(TacticsSfx.key_for({"type": "hit", "outcome": "perfect"}), "hit_perfect",
		"a perfect counter maps to the perfect parry")
	assert_eq(TacticsSfx.key_for({"type": "hit", "outcome": "counter"}), "hit_counter",
		"a normal counter maps to the soft parry")
	assert_eq(TacticsSfx.key_for({"type": "hit", "outcome": "scrape"}), "hit_block",
		"a scrape maps to the block")
	assert_eq(TacticsSfx.key_for({"type": "hit", "outcome": "none"}), "hit_plain",
		"a plain hit maps to the hit sound")
	assert_eq(TacticsSfx.key_for({"type": "hit"}), "hit_plain",
		"a hit without an outcome is a plain hit")
	assert_eq(TacticsSfx.key_for({"type": "stun"}), "stun", "stun maps to the break sound")
	assert_eq(TacticsSfx.key_for({"type": "jianyi"}), "jianyi", "jianyi maps to the perfect sound")
	assert_eq(TacticsSfx.key_for({"type": "dead"}), "dead", "dead has its own key")
	assert_eq(TacticsSfx.key_for({"type": "move"}), "", "unmapped events are silent")
	assert_eq(TacticsSfx.key_for({"type": "counter_hit"}), "",
		"the counter damage event is carried by the hit event")


func test_data_sfx_files_exist_and_values_match() -> void:
	for key in SFX_KEYS:
		var entry: Dictionary = TacticsSfx.entry_for(key)
		assert_true(not entry.is_empty(), "the data file defines %s" % key)
		var sfx := str(entry.get("sfx", ""))
		assert_true(sfx != "", "%s has a sound" % key)
		assert_true(
			FileAccess.file_exists(AssetPaths.AUDIO + sfx + ".wav"),
			"%s: %s.wav exists in res://assets/audio" % [key, sfx])
	var dead: Dictionary = TacticsSfx.entry_for("dead")
	assert_eq(str(dead.get("sfx", "missing")), "", "dead plays no sound")
	assert_eq(int(TacticsSfx.entry_for("hit_perfect").get("hitstop_ms", 0)), 70,
		"the perfect parry has a 70ms hitstop")
	assert_eq(int(TacticsSfx.entry_for("stun").get("hitstop_ms", 0)), 90,
		"breaking toughness has a 90ms hitstop")
	assert_true(not TacticsSfx.entry_for("hit_block").is_empty()
		and int(TacticsSfx.entry_for("hit_block").get("hitstop_ms", -1)) == 0,
		"a scrape does not freeze time")


func test_play_events_with_null_audio_does_not_crash() -> void:
	var fx := TacticsSfx.new()
	fx.play_events(null, [
		{"type": "hit", "outcome": "perfect"},
		{"type": "stun"},
		{"type": "dead"},
		{"type": "move"},
	])
	assert_true(true, "a null audio object is ignored")


func test_play_events_plays_mapped_sounds_in_order() -> void:
	var fake := FakeAudio.new()
	var fx := TacticsSfx.new()
	fx.play_events(fake, [
		{"type": "hit", "outcome": "perfect"},
		{"type": "stun"},
		{"type": "jianyi"},
		{"type": "hit", "outcome": "scrape"},
		{"type": "hit", "outcome": "counter"},
		{"type": "hit", "outcome": "none"},
		{"type": "dead"},
		{"type": "move"},
	])
	assert_eq(fake.calls.size(), 6, "only the six mapped events play a sound")
	if fake.calls.size() != 6:
		return
	var expected := ["sfx_parry", "sfx_break", "sfx_perfect", "sfx_block",
		"sfx_parry_soft", "sfx_hit"]
	for i in range(expected.size()):
		assert_eq(str(fake.calls[i]["name"]), expected[i],
			"call %d follows the data mapping" % i)
	assert_near(float(fake.calls[0]["volume"]), 1.0, 0.0001, "perfect parry volume")
	assert_near(float(fake.calls[3]["volume"]), 0.9, 0.0001, "block volume")
	assert_near(float(fake.calls[4]["volume"]), 0.9, 0.0001, "soft parry volume")
	assert_near(float(fake.calls[5]["volume"]), 1.0, 0.0001, "plain hit volume")


func test_hitstop_is_ignored_in_headless() -> void:
	if DisplayServer.get_name() != "headless" and DisplayServer.get_name() != "dummy":
		return
	Engine.time_scale = 1.0
	var holder := Control.new()
	var tree: Variant = Engine.get_meta("test_tree", null)
	if tree != null:
		tree.root.add_child(holder)
	var fx := TacticsSfx.new()
	fx.setup(holder)
	fx.play_events(null, [{"type": "stun"}, {"type": "hit", "outcome": "perfect"}])
	assert_near(Engine.time_scale, 1.0, 0.0001, "headless runs never slow time down")
	holder.free()


func test_restart_key_is_disabled_for_game_battles() -> void:
	GameState.reset()
	var built := _make_view()
	var view: Variant = built["view"]
	view.start_from_game("bandit", 1, false, "tavern")
	assert_true(view.battle != null, "the game battle is assembled")
	if view.battle == null:
		_finish(built["holder"])
		return
	var battle: Variant = view.battle
	view._player_input.handle_key(KEY_R)
	assert_true(view.battle == battle, "R does not restart a battle started from the game")
	_finish(built["holder"])

	var sandbox := _make_view()
	var sandbox_view: Variant = sandbox["view"]
	sandbox_view.start()
	var fresh: Variant = sandbox_view.battle
	sandbox_view._player_input.handle_key(KEY_R)
	assert_true(sandbox_view.battle != fresh, "R still restarts the sandbox battle")
	_finish(sandbox["holder"])


func test_defeat_still_syncs_mastery_total() -> void:
	GameState.reset()
	var built := _make_view()
	var view: Variant = built["view"]
	view.start_from_game("bandit", 1, false, "tavern")
	assert_true(view.battle != null, "the game battle is assembled")
	if view.battle == null:
		_finish(built["holder"])
		return
	var battle: Variant = view.battle
	battle.mastery.add_exp("basic_sword", 5)
	battle.get_unit("player").unit.hp = 0
	view._check_result()
	assert_eq(view.state(), "result", "the defeat reaches the result overlay")
	view.restart_button.pressed.emit()
	assert_eq(
		int(GameState.mastery_total.get("basic_sword", 0)),
		int(battle.mastery.exp_of("basic_sword")),
		"a defeat syncs the mastery earned during the battle")
	_finish(built["holder"])


func test_battle_finished_is_emitted_once() -> void:
	GameState.reset()
	var results: Array = []
	var built := _make_view()
	var view: Variant = built["view"]
	view.start_from_game("bandit", 1, false, "tavern")
	if view.battle == null:
		assert_true(false, "the game battle is assembled")
		_finish(built["holder"])
		return
	view.battle_finished.connect(func(result): results.append(result))
	for unit in view.battle.units:
		if unit.side == "enemy":
			unit.unit.hp = 0
	view._check_result()
	view.restart_button.pressed.emit()
	view.restart_button.pressed.emit()
	assert_eq(results.size(), 1, "pressing continue twice reports the result once")
	_finish(built["holder"])

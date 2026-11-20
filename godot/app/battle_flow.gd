extends RefCounted

# Battle entry/return flow. The router creates the view; this module keeps the
# encounter bookkeeping and asks the router for the return scene.

signal jingle_requested(track: String)

const GameState = preload("res://core/game_state.gd")
const Quests = preload("res://core/quests.gd")
const Progression = preload("res://core/progression.gd")

const BOSS_ENEMY_ID := "ma_youwei"

var _router: Variant = null
var _audio: Variant = null
var _battle_enemy: String = ""
var _battle_count: int = 0
var _battle_origin: String = ""
var _layout_return_id: String = ""
var _layout_return_pos: Variant = null


func _init(router: Variant) -> void:
	_router = router


func is_boss_encounter() -> bool:
	return _battle_enemy == BOSS_ENEMY_ID


func record_encounter_origin(scene: Node, kind: String) -> void:
	if scene == null:
		return
	var origin: Variant = scene
	match kind:
		"town":
			GameState.town_return_pos = origin.player_pos
			_battle_origin = "town"
			GameState.battle_backdrop = "town"
		"tavern":
			_battle_origin = "tavern"
			GameState.battle_backdrop = "tavern"
		"forest":
			GameState.forest_return_pos = origin.player_pos
			_battle_origin = "forest"
			GameState.battle_backdrop = "forest"
		"layout":
			# 正式布局战斗：记住地图 ID 与合法返回位置，打完回到同一张地图。
			_layout_return_id = str(origin.call("document_id"))
			var layout_pos: Variant = origin.get("player_pos")
			_layout_return_pos = layout_pos if layout_pos is Vector2 else null
			_battle_origin = "layout"
			GameState.battle_backdrop = "town"


func show_battle(
	audio: Variant, enemy_id: String, count: int, first_strike: bool, play_intro: bool
) -> void:
	_audio = audio
	_battle_enemy = enemy_id
	_battle_count = count
	_router.show_battle(
		audio,
		enemy_id,
		count,
		first_strike,
		play_intro,
		enemy_id == BOSS_ENEMY_ID,
		Callable(self, "_on_battle_finished"),
	)


func _on_battle_finished(result: String) -> void:
	jingle_requested.emit("jingle_victory" if result == "won" else "jingle_defeat")
	var origin := _battle_origin
	var pending: Variant = GameState.pending_forest_encounter
	if result == "won":
		Quests.notify("defeat", _battle_enemy, _battle_count)
		if _battle_enemy == BOSS_ENEMY_ID:
			GameState.set_flag("boss_defeated")
		if origin == "forest" \
				and (_battle_enemy == "bandit" or _battle_enemy == "bandit_scout"):
			GameState.forest_bandits_killed += _battle_count
		if origin == "forest" and pending is Dictionary:
			var encounter: Dictionary = pending
			var kind := str(encounter.get("kind", ""))
			if kind == "patrol":
				GameState.set_flag("patrol_defeated_%d" % int(encounter.get("id", -1)))
			elif kind == "scout":
				GameState.set_flag("scout_defeated")
	_battle_origin = ""
	GameState.battle_backdrop = "town"
	GameState.pending_forest_encounter = null
	if origin == "layout":
		var return_id := _layout_return_id
		var return_pos: Variant = _layout_return_pos
		_layout_return_id = ""
		_layout_return_pos = null
		# 返回位置由 LayoutWalk 校验；进入圈在返回时先视为已在圈内，不会立即重触发。
		var shown: bool = _router.show_layout(_audio, return_id, return_pos)
		if not shown:
			_router.show_town(_audio)
	elif origin == "forest":
		if result != "won":
			# A loss drops the player back at the forest spawn; the patrol resets.
			GameState.forest_return_pos = null
		_router.show_forest(_audio)
	elif origin == "tavern" and result == "won" and GameState.has_flag("boss_defeated"):
		_router.start_demo_ending(_audio)
	elif origin == "tavern":
		if result != "won" and not GameState.has_flag("defeat_hint_shown"):
			# First loss in the tavern: nudge the player towards preparing (forest, side quests).
			GameState.set_flag("defeat_hint_shown")
			Progression.push_toast("也许该先去紫霞林历练一番，再来对付他们")
		_router.show_tavern(_audio)
	else:
		_router.show_town(_audio)

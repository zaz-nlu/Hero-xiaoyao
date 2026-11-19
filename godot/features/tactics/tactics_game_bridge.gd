extends RefCounted

# 战旗视图与游戏流程的接线：把 GameState 里的遭遇参数交给 tactics_session，
# 并用「继续」按钮把胜负交回 BattleFlow。沙盒运行（tactics_sandbox）不经过这里。

const TacticsSession = preload("res://features/tactics/tactics_session.gd")
const TacticsSfx = preload("res://features/tactics/tactics_sfx.gd")
const TacticsDialogueFlow = preload("res://features/tactics/tactics_dialogue_flow.gd")

var from_game: bool = false

var _sfx: Variant = TacticsSfx.new()
var _dialogue: Variant = TacticsDialogueFlow.new()
var _reported: bool = false
var _result_battle: Variant = null


func prepare(view, enemy_id: String, count: int, first_strike: bool, origin: String) -> void:
	var built: Dictionary = TacticsSession.build(enemy_id, count, first_strike, origin)
	if not bool(built.get("ok", false)):
		view._ensure_ui()
		view.panel.show_message("组装失败：%s" % str(built.get("errors", [])))
		return
	from_game = true
	var group: Array = built.get("group", [])
	view.start(str(built.get("map_id", "")), group, int(built.get("seed", 1)), built)
	view._player_input.announce_view_controls()
	_dialogue.build(view)
	_dialogue.reset(str(built.get("encounter_id", enemy_id)))


func button_text() -> String:
	return "继续" if from_game else "重来"


# 从游戏进入时禁用 R 键重来：重来会丢弃本场战斗并重复结算。
func can_restart() -> bool:
	return not from_game


# 战斗事件统一出口：视图把同一批事件交给音效/顿帧层（音频为空时静默）。
func play_events(view, events: Array) -> void:
	if view == null or events.is_empty():
		return
	_sfx.setup(view)
	_sfx.play_events(view.audio, events)


func result_callback(view, restart: Callable) -> Callable:
	return Callable(self, "_on_result").bind(view, restart)


# 结算展示：游戏内胜利先播遭遇的胜利对话，播完再显示结果层；沙盒与战败直接显示。
# 同一场战斗只结算展示一次，对话播放期间不会重复弹出结果层。
func show_result(view) -> void:
	if view == null:
		return
	var battle = view.battle
	if battle == null or battle == _result_battle:
		return
	_result_battle = battle
	if not from_game:
		_show_result_overlay(view)
		return
	_dialogue.maybe_play_win(
		str(battle.result()) == "win", Callable(self, "_show_result_overlay").bind(view))


func _show_result_overlay(view) -> void:
	if view != null:
		view._result_layer.show_result(view.battle, button_text())


func _on_result(view, restart: Callable) -> void:
	if not from_game:
		restart.call()
		return
	if _reported:
		return
	_reported = true
	var battle = view.battle
	if battle != null and str(battle.result()) == "win":
		TacticsSession.settle(battle)
	else:
		TacticsSession.settle_defeat(battle)
	view.emit_signal("battle_finished", _result_code(battle))


# 战旗暂没有超时规则；未知结果按超时上报，保持与旧战斗相同的回调契约。
func _result_code(battle) -> String:
	if battle == null:
		return "lost"
	match str(battle.result()):
		"win":
			return "won"
		"lose":
			return "lost"
	return "timeout"

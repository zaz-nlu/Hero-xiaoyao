extends RefCounted

# 新游戏开场编排：调用前 game.start_new_game 已完成持久状态重置。
# 开场依次为：序幕字幕页 → 书生讲故事小场景 → 小镇；两段序幕后才进入小镇。
# 这里只决定“直接进小镇”还是“先播序幕”，两段场景的衔接由 scene_router 负责。
# 序幕界面在 features/opening/，场景切换仍走 app/scene_router.gd。

const GameState = preload("res://core/game_state.gd")
const Progression = preload("res://core/progression.gd")
const Quests = preload("res://core/quests.gd")


static func start(game: Variant) -> void:
	if _skip_requested():
		_enter_town(game)
		return
	var on_finished := func() -> void:
		GameState.set_flag("opening_done")
		_enter_town(game)
	game.show_opening(on_finished)


# 与原来的开场提示文案、去重 flag 保持一致；_ready 的 skip_title 分支也走这里。
static func show_intro_hints() -> void:
	if GameState.has_flag("intro_hint_shown"):
		return
	GameState.set_flag("intro_hint_shown")
	Progression.push_toast("按 C 打开角色面板，可以分配 3 点属性点")
	Progression.push_toast("按 J 查看任务，Shift 可以蹲伏")


static func _enter_town(game: Variant) -> void:
	# 序幕里说书先生提到的主线：两天后紫霞派在酒馆收徒。
	Quests.start("zixia_recruit")
	game.show_town()
	show_intro_hints()
	game.call("_schedule_autosave")


static func _skip_requested() -> bool:
	if Engine.has_meta("skip_opening") and bool(Engine.get_meta("skip_opening")):
		return true
	return Engine.has_meta("skip_title") and bool(Engine.get_meta("skip_title"))

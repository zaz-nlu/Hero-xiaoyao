extends RefCounted

# 酒馆故事导演：normal/brawl/aftermath 与 ambush 阶段、故事触发、对话完成、
# 前戏完成和挑战 Boss 的流程。通过明确事件与控制器协作。

signal state_requested(new_state: String, animate: bool, stagger: bool)
signal cutscene_requested(active: bool)
signal dialogue_requested(path: String)
signal prefight_requested
signal encounter_requested(enemy_id: String, count: int, first_strike: bool)

const DataLoader = preload("res://core/data_loader.gd")
const GameState = preload("res://core/game_state.gd")
const Calendar = preload("res://core/calendar.gd")
const Prefight = preload("res://core/prefight.gd")
const Quests = preload("res://core/quests.gd")

const AMBUSH_OPEN_PATH := DataLoader.TAVERN_AMBUSH_OPEN_PATH
const AMBUSH_MANY_PATH := DataLoader.TAVERN_AMBUSH_MANY_PATH
const AMBUSH_FEW_PATH := DataLoader.TAVERN_AMBUSH_FEW_PATH
const PREFIGHT_END_PATH := DataLoader.TAVERN_PREFIGHT_END_PATH
const TAUNT_PATH := "res://data/dialogues/tavern_bandits_taunt.json"
const CONFRONT_PATH := "res://data/dialogues/tavern_zixia_confront.json"
const KEEPER_EARLY_PATH := "res://data/dialogues/npc_tavern_keeper_early.json"
const KEEPER_RECRUIT_PATH := "res://data/dialogues/npc_tavern_keeper_recruit.json"
const STATES: Array[String] = ["normal", "brawl", "aftermath"]

var state := "normal"

var _ambush_stage := ""
var _ambush_triggered := false
var _ambush_elapsed := 0.0
var _ambush_rect := Rect2()
var _ambush_timeout := 14.0
var _dialogue_pending := false


func setup(data: Dictionary) -> void:
	state = "normal"
	_ambush_stage = ""
	_ambush_triggered = false
	_ambush_elapsed = 0.0
	_ambush_rect = Rect2()
	_ambush_timeout = 14.0
	var ambush_value: Variant = data.get("ambush", null)
	if not (ambush_value is Dictionary):
		return
	var ambush: Dictionary = ambush_value
	var rect_value: Variant = ambush.get("rect", null)
	if rect_value is Array:
		var rect: Array = rect_value
		if rect.size() >= 4:
			var x0 := float(rect[0])
			var z0 := float(rect[1])
			var x1 := float(rect[2])
			var z1 := float(rect[3])
			if x1 > x0 and z1 > z0:
				_ambush_rect = Rect2(x0, z0, x1 - x0, z1 - z0)
	_ambush_timeout = float(ambush.get("timeout", _ambush_timeout))


func set_initial_state(forced: String) -> void:
	state = forced if forced != "" else _initial_state()


func set_state(new_state: String, animate: bool, anim_active: bool) -> void:
	if not STATES.has(new_state):
		return
	if new_state == state and not anim_active:
		return
	_change_state(new_state, animate, false)


func cycle_state(anim_active: bool) -> void:
	var next := "normal"
	if state == "normal":
		next = "brawl"
	elif state == "brawl":
		next = "aftermath"
	set_state(next, true, anim_active)


func check_story(
	delta: float,
	player_pos: Vector2,
	skip_actors: bool,
	cutscene_running: bool,
	dialogue_active: bool
) -> void:
	if skip_actors or _ambush_triggered:
		return
	if state != "normal" or cutscene_running:
		return
	# 主线“紫霞收徒”进行中：马匪只在约定时间后、与掌柜说话才出现，不再靠走进酒馆触发。
	if recruit_mode():
		return
	if dialogue_active:
		return
	_ambush_elapsed += maxf(0.0, delta)
	var in_zone: bool = _ambush_rect.size != Vector2.ZERO \
		and _ambush_rect.has_point(player_pos)
	if in_zone or _ambush_elapsed >= _ambush_timeout:
		_trigger_ambush()


# 主线“紫霞收徒”正在进行：酒馆事件由掌柜对话 + 日期触发。
func recruit_mode() -> bool:
	return state == "normal" and Quests.state("zixia_recruit") == "active"


# 与掌柜交谈：到了约定时间 → 播放收徒前的对话，结束后马匪闯入；没到时间 → 提示等待。
# 返回空串表示不是特殊情况（走普通对话）。
func keeper_dialogue() -> String:
	if not recruit_mode():
		return ""
	if Calendar.recruit_due():
		_ambush_stage = "keeper"
		return KEEPER_RECRUIT_PATH
	return KEEPER_EARLY_PATH


# 酒馆里还剩几个马匪：森林里打倒得越多，头子带的人越少（最少 2 个）。
func bandit_count() -> int:
	return clampi(5 - int(GameState.forest_bandits_killed), 2, 5)


func begin_challenge() -> bool:
	var path: String = AMBUSH_MANY_PATH if bandit_count() >= 4 else AMBUSH_FEW_PATH
	_ambush_stage = "challenge"
	if _request_dialogue(path):
		return true
	_ambush_stage = ""
	return false


func prefight_unavailable() -> void:
	_begin_ambush_dialogue()


func finish_prefight(_result: Dictionary = {}) -> void:
	_ambush_stage = "prefight_end"
	if not _request_dialogue(PREFIGHT_END_PATH):
		_begin_ambush_dialogue()


func on_animation_finished() -> void:
	_after_walk_in()


func on_state_applied(anim_active: bool) -> void:
	if not anim_active:
		_after_walk_in()


# 入场动画结束：马匪先到 → 对话后紫霞派进门 → 对质对话 → 混战演出。
func _after_walk_in() -> void:
	if _ambush_stage == "animating":
		_continue_after_entrance()
	elif _ambush_stage == "animating2":
		_ambush_stage = "confront"
		if not _request_dialogue(CONFRONT_PATH):
			_start_fight()


func dialogue_started() -> void:
	_dialogue_pending = false


func on_dialogue_finished() -> bool:
	if _ambush_stage == "taunt":
		_zixia_enter()
		return true
	if _ambush_stage == "confront":
		_start_fight()
		return true
	if _ambush_stage == "keeper":
		_ambush_stage = ""
		_trigger_ambush()
		return true
	if _ambush_stage == "open":
		_finish_ambush_open()
		return true
	if _ambush_stage == "prefight_end":
		_begin_ambush_dialogue()
		return true
	if _ambush_stage == "ambush":
		_finish_ambush_encounter()
		return true
	if _ambush_stage == "challenge":
		_ambush_stage = ""
		_emit_ambush_encounter()
		return true
	return false


func _initial_state() -> String:
	if GameState.has_flag("boss_defeated"):
		return "aftermath"
	if GameState.has_flag("bandits_entered"):
		return "brawl"
	return "normal"


func _change_state(new_state: String, animate: bool, stagger: bool) -> void:
	state = new_state
	state_requested.emit(new_state, animate, stagger)


func _trigger_ambush() -> void:
	if _ambush_triggered:
		return
	_ambush_triggered = true
	GameState.set_flag("bandits_entered")
	cutscene_requested.emit(true)
	_ambush_stage = "open"
	if not _request_dialogue(AMBUSH_OPEN_PATH):
		_finish_ambush_open()


func _finish_ambush_open() -> void:
	_ambush_stage = "animating"
	_change_state("brawl", true, true)


func _continue_after_entrance() -> void:
	if GameState.has_flag("prefight_done"):
		_begin_ambush_dialogue()
		return
	_ambush_stage = "taunt"
	if not _request_dialogue(TAUNT_PATH):
		_zixia_enter()


func _zixia_enter() -> void:
	GameState.set_flag("zixia_entered")
	_ambush_stage = "animating2"
	_change_state("brawl", true, false)


func _start_fight() -> void:
	_ambush_stage = "prefight"
	prefight_requested.emit()


func _begin_ambush_dialogue() -> void:
	_ambush_stage = "ambush"
	var path: String = AMBUSH_MANY_PATH if bandit_count() >= 4 else AMBUSH_FEW_PATH
	if not _request_dialogue(path):
		_finish_ambush_encounter()


func _finish_ambush_encounter() -> void:
	_ambush_stage = ""
	cutscene_requested.emit(false)
	_emit_ambush_encounter()


func _emit_ambush_encounter() -> void:
	var count: int = bandit_count()
	# 头子的带伤状态来自前戏；战败重来或读档后缓存为空时按同一 N 重新推演一次。
	var loss: int = int(GameState.prefight_loss_cached)
	if loss <= 0:
		loss = int(Prefight.simulate(count).get("boss_damage", 0))
		GameState.prefight_loss_cached = loss
	GameState.boss_hp_loss = loss
	GameState.encounter_group = [
		{"id": "ma_youwei", "count": 1},
		{"id": "bandit", "count": count},
	]
	encounter_requested.emit("ma_youwei", 1, false)


func _request_dialogue(path: String) -> bool:
	_dialogue_pending = true
	dialogue_requested.emit(path)
	var started := not _dialogue_pending
	_dialogue_pending = false
	return started

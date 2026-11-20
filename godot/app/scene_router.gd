extends RefCounted

# Owns the active scene node and its kind, performs the detach-then-free
# replacement, routes scene signals, and applies the per-scene presentation
# (return point, profile unlocks, overlay, music/ambience, autosave).

signal route_will_change(previous_kind: String)
signal scene_entered(kind: String, scene: Node)

const GameState = preload("res://core/game_state.gd")
const OpeningData = preload("res://core/opening_data.gd")
const Profile = preload("res://core/profile.gd")
const Progression = preload("res://core/progression.gd")
const LayoutTriggers = preload("res://core/layouts/layout_triggers.gd")
const TownData = preload("res://shared/resources/town_data.gd")

const TOWN_SCENE := "res://features/town/town.gd"
const TAVERN_SCENE := "res://features/tavern/tavern.gd"
const FOREST_SCENE := "res://features/forest/forest.gd"
const BATTLE_SCENE := "res://features/battle/battle_view.gd"
const TACTICS_SCENE := "res://features/tactics/tactics_view.gd"
const TITLE_SCREEN_SCENE := "res://features/title/title_screen.gd"
const OPENING_SCENE := "res://features/opening/opening_sequence.gd"
const TOWN_STORYTELLER := "res://features/opening/town_storyteller.gd"
const LAYOUT_SCENE := "res://features/layouts/layout_walk.gd"
const TOWN_ENDING := "res://features/ending/town_ending.gd"
const ENDING_TAVERN_DIALOGUE := "res://data/dialogues/ending_tavern.json"

var current: Node = null
var current_kind: String = ""

var _parent: Node = null
var _on_encounter: Callable
var _on_new_game: Callable
var _on_continue: Callable
var _set_overlay_enabled: Callable
var _schedule_autosave: Callable
var _profile_path: Callable
var _audio: Variant = null
var _battle_boss: bool = false


func setup(
	parent: Node,
	on_encounter: Callable,
	on_new_game: Callable,
	on_continue: Callable,
	set_overlay_enabled: Callable,
	schedule_autosave: Callable,
	profile_path: Callable,
) -> void:
	_parent = parent
	_on_encounter = on_encounter
	_on_new_game = on_new_game
	_on_continue = on_continue
	_set_overlay_enabled = set_overlay_enabled
	_schedule_autosave = schedule_autosave
	_profile_path = profile_path


func show_title(audio: Variant, save_dir: String) -> void:
	_audio = audio
	_begin_route()
	var title: Variant = load(TITLE_SCREEN_SCENE).new()
	title.name = "TitleScreen"
	title.game = _parent
	title.audio = audio
	title.save_dir = save_dir
	_parent.add_child(title)
	if not title.is_inside_tree():
		title.build()
	title.connect("new_game_requested", _on_new_game)
	title.connect("continue_requested", _on_continue)
	title.connect("load_requested", _on_continue)
	title.connect("quit_requested", Callable(self, "_on_quit_requested"))
	_finish_route("title", title)


# 新游戏序幕：router 创建播放器、注入音频；数据校验失败时仍继续，由编排方
# 通过 on_finished 接回小镇（错误会以 toast 告知）。
# 字幕页结束后自动进入书生讲故事小场景，两段都结束才调用 on_finished。
# 序幕：字幕页 → 东方阳 vs 东方云 + 索尔（教学战斗）→ 战后字幕页 → 书生讲故事。
# part = "slides" 为战前页，"slides_after" 为战后页；没有战斗配置时直接接战后页。
func show_opening(audio: Variant, on_finished: Callable, part: String = "slides") -> void:
	_audio = audio
	_begin_route()
	var opening: Variant = load(OPENING_SCENE).new()
	opening.name = "OpeningSequence"
	opening.set("audio", audio)
	_parent.add_child(opening)
	var data := OpeningData.load_opening()
	if not bool(data.get("ok", false)):
		for message in data.get("errors", []):
			Progression.push_toast(str(message))
	var next: Callable = Callable(self, "_continue_to_opening_story").bind(audio, on_finished)
	if part == "slides":
		next = Callable(self, "_start_opening_duel").bind(audio, on_finished, data)
	else:
		data = data.duplicate()
		data["slides"] = data.get("slides_after", data.get("slides", []))
	opening.connect("finished", next)
	opening.build(data)
	_finish_route("opening", opening)


# 教学战斗：战败就重来，战胜后接战后字幕页。结果不写入存档里的养成状态。
func _start_opening_duel(audio: Variant, on_finished: Callable, data: Dictionary) -> void:
	var duel: Dictionary = data.get("duel", {})
	var group: Array = duel.get("enemies", [])
	if group.is_empty():
		show_opening(audio, on_finished, "slides_after")
		return
	GameState.encounter_group = group.duplicate(true)
	GameState.battle_backdrop = str(duel.get("origin", "opening_duel"))
	show_battle(audio, str((group[0] as Dictionary).get("id", "")), 1, true, false, true,
		Callable(self, "_on_opening_duel_finished").bind(audio, on_finished, data))


func _on_opening_duel_finished(result: String, audio: Variant, on_finished: Callable, data: Dictionary) -> void:
	if result == "won":
		show_opening(audio, on_finished, "slides_after")
	else:
		_start_opening_duel(audio, on_finished, data)


# 序幕第二段：书生讲故事。直接在紫霞镇地图上演出（不另开场景），讲完后玩家拿回控制权。
func _continue_to_opening_story(audio: Variant, on_finished: Callable) -> void:
	show_town(audio)
	_set_overlay_enabled.call(false)
	var story: Node = load(TOWN_STORYTELLER).new()
	story.name = "TownStoryteller"
	current.add_child(story)
	story.connect("finished", Callable(self, "_on_town_story_finished").bind(on_finished))
	story.call("begin", current, audio, OpeningData.load_opening())


func _on_town_story_finished(on_finished: Callable) -> void:
	_set_overlay_enabled.call(true)
	_audio.play_music("music_town")
	on_finished.call()


func show_town(audio: Variant) -> void:
	_audio = audio
	_begin_route()
	var town: Variant = load(TOWN_SCENE).new()
	_parent.add_child(town)
	if not town.is_inside_tree():
		town.build()
		town.build_hud()
	town.connect("encounter_requested", _on_encounter)
	town.connect("enter_requested", Callable(self, "_on_enter_requested"))
	_finish_route("town", town)


func show_tavern(audio: Variant) -> void:
	_audio = audio
	_begin_route()
	var tavern: Variant = load(TAVERN_SCENE).new()
	_parent.add_child(tavern)
	if not tavern.is_inside_tree():
		tavern.build()
		tavern.build_hud()
	tavern.connect("exit_requested", Callable(self, "_on_tavern_exit_requested"))
	tavern.connect("encounter_requested", _on_encounter)
	tavern.connect("state_changed", Callable(self, "_on_tavern_state_changed"))
	_finish_route("tavern", tavern)


# Demo 结尾：击败马匪后回到酒馆播一段收尾对话，播完到酒馆外的紫霞镇街上演出（紫殇登场）。
func start_demo_ending(audio: Variant) -> void:
	show_tavern(audio)
	var tavern: Variant = current
	var started: bool = bool(tavern.call("_play_story_dialogue", ENDING_TAVERN_DIALOGUE))
	if started and tavern.dialogue_view != null:
		tavern.dialogue_view.connect(
			"finished", Callable(self, "show_town_ending").bind(audio), CONNECT_ONE_SHOT)
	else:
		show_town_ending(audio)


func show_town_ending(audio: Variant) -> void:
	show_town(audio)
	_set_overlay_enabled.call(false)
	var ending: Node = load(TOWN_ENDING).new()
	ending.name = "TownEnding"
	current.add_child(ending)
	ending.connect("finished", Callable(self, "_on_demo_ending_finished"))
	ending.call("begin", current, audio)


func _on_demo_ending_finished() -> void:
	GameState.set_flag("demo_ending_done")
	_parent.call("go_to_title")


func show_forest(audio: Variant) -> void:
	_audio = audio
	_begin_route()
	var forest: Variant = load(FOREST_SCENE).new()
	_parent.add_child(forest)
	if not forest.is_inside_tree():
		forest.build()
		forest.build_hud()
	forest.connect("exit_requested", Callable(self, "_on_forest_exit_requested"))
	forest.connect("encounter_requested", _on_encounter)
	_finish_route("forest", forest)


# 可复用的布局路由 API：map_id 只能是 data/layouts/<id>.json 的安全 ID。
# return_pos 用于战斗后回到原布局位置；非法时由 LayoutWalk 自己退回出生点。
func show_layout(audio: Variant, map_id: String, return_pos: Variant = null) -> bool:
	var path := LayoutTriggers.layout_path(map_id)
	if path == "":
		return false
	_audio = audio
	_begin_route()
	var layout: Variant = load(LAYOUT_SCENE).new()
	layout.map_path = path
	layout.playtest_mode = false
	layout.return_position = return_pos
	_parent.add_child(layout)
	if not layout.is_inside_tree():
		layout.build()
	layout.connect("encounter_requested", _on_encounter)
	layout.connect("exit_requested", Callable(self, "_on_layout_exit_requested"))
	_finish_route("layout", layout)
	return true


func show_battle(
	audio: Variant,
	enemy_id: String,
	count: int,
	first_strike: bool,
	play_intro: bool,
	boss: bool,
	on_finished: Callable,
) -> void:
	_audio = audio
	_begin_route()
	if not _legacy_battle():
		var tactics: Variant = load(TACTICS_SCENE).new()
		_parent.add_child(tactics)
		tactics.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tactics.set("audio", audio)
		tactics.connect("battle_finished", on_finished)
		tactics.start_from_game(enemy_id, count, first_strike, str(GameState.battle_backdrop))
		_battle_boss = boss
		_finish_route("battle", tactics)
		return
	var view: Variant = load(BATTLE_SCENE).new()
	_parent.add_child(view)
	if not view.is_inside_tree():
		view.build_ui()
	# Must also reset the offsets: set_anchors_preset() alone keeps the current (0x0) rect.
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.set("audio", audio)
	view.start(enemy_id, count, first_strike, play_intro)
	view.connect("battle_finished", on_finished)
	_battle_boss = boss
	_finish_route("battle", view)


# 兼容开关：仍依赖旧战斗的测试在启动处设置 Engine 元数据。
func _legacy_battle() -> bool:
	return Engine.has_meta("legacy_battle") and bool(Engine.get_meta("legacy_battle"))


func _begin_route() -> void:
	route_will_change.emit(current_kind)
	_release_current()


func _finish_route(kind: String, scene: Node) -> void:
	current = scene
	current_kind = kind
	scene_entered.emit(kind, scene)
	_present(kind, scene)


func _present(kind: String, scene: Node) -> void:
	match kind:
		"title":
			# Tests can drive the router before the Game node is inside the SceneTree;
			# check first so get_tree() never logs an engine error for a detached node.
			if _parent.is_inside_tree():
				var tree := _parent.get_tree()
				if tree != null:
					tree.paused = false
			_audio.play_music("music_title")
			_audio.play_ambience("")
		"opening":
			_set_overlay_enabled.call(false)
			_audio.play_ambience("")
		"town":
			GameState.town_return_pos = null
			_set_overlay_enabled.call(true)
			_audio.play_music("music_town")
			_audio.play_ambience("")
			_schedule_autosave.call()
		"tavern":
			Profile.unlock("tavern_inside", str(_profile_path.call()))
			_set_overlay_enabled.call(true)
			_play_tavern_music(str(scene.current_state()))
			_audio.play_ambience("")
			_schedule_autosave.call()
		"forest":
			Profile.unlock("forest", str(_profile_path.call()))
			_set_overlay_enabled.call(true)
			_audio.play_music("music_forest")
			_audio.play_ambience("amb_forest_birds")
			_schedule_autosave.call()
		"layout":
			# 布局暂不参与存档槽；存档副作用留给后续正式接入。
			_set_overlay_enabled.call(true)
			_audio.play_music("music_town")
			_audio.play_ambience("")
		"battle":
			if str(GameState.battle_backdrop) == "opening_duel":
				# 序章教学战斗：整段沿用帝王威仪，字幕页到战斗再到战后字幕不换歌。
				_audio.play_cue("opening_empire")
			elif _battle_boss:
				_audio.play_music("music_battle_boss")
			else:
				_audio.play_music("music_battle")
			_audio.play_ambience("")


func _town_data() -> Dictionary:
	if current != null and current_kind == "town":
		var value: Variant = current.get("data")
		if value is Dictionary:
			return value
	return {}


func _on_enter_requested(place: String) -> void:
	if place == "forest":
		if current != null and current_kind == "town":
			GameState.town_return_pos = TownData.forest_return(_town_data())
		show_forest(_audio)
		return
	if place != "tavern":
		return
	if current != null and current_kind == "town":
		GameState.town_return_pos = current.tavern_return_pos()
	_audio.play_sfx("sfx_door")
	show_tavern(_audio)


func _on_tavern_exit_requested() -> void:
	_audio.play_sfx("sfx_door")
	show_town(_audio)


func _on_forest_exit_requested(place: String) -> void:
	if place == "town":
		show_town(_audio)
	elif place == "wasteland":
		Progression.push_toast("前方荒山，暂时过不去")


# 布局出口只接受 town/tavern/forest 或存在的布局 ID；目标已在编辑期校验。
func _on_layout_exit_requested(target: String) -> void:
	match target:
		"town":
			show_town(_audio)
		"tavern":
			_audio.play_sfx("sfx_door")
			show_tavern(_audio)
		"forest":
			show_forest(_audio)
		_:
			if LayoutTriggers.layout_path(target) != "":
				show_layout(_audio, target)


func _on_tavern_state_changed(new_state: String) -> void:
	if current_kind != "tavern":
		return
	_play_tavern_music(new_state)


func _on_quit_requested() -> void:
	if not _parent.is_inside_tree():
		return
	var tree := _parent.get_tree()
	if tree != null:
		tree.paused = false
		tree.quit()


func _play_tavern_music(tavern_state: String) -> void:
	if tavern_state == "brawl":
		_audio.play_music("music_battle")
	else:
		_audio.play_music("music_tavern")


func _release_current() -> void:
	if current == null:
		return
	var node: Node = current
	current = null
	current_kind = ""
	# Never free() synchronously: this is usually called from one of the node's own
	# signal callbacks ("locked object" error). Detach it, then free it at idle time.
	if node.get_parent() == _parent:
		_parent.remove_child(node)
	node.queue_free()

extends RefCounted

# Owns the active scene node and its kind, performs the detach-then-free
# replacement, routes scene signals, and applies the per-scene presentation
# (return point, profile unlocks, overlay, music/ambience, autosave).

signal route_will_change(previous_kind: String)
signal scene_entered(kind: String, scene: Node)

const GameState = preload("res://core/game_state.gd")
const Profile = preload("res://core/profile.gd")
const Progression = preload("res://core/progression.gd")

const TOWN_SCENE := "res://features/town/town.gd"
const TAVERN_SCENE := "res://features/tavern/tavern.gd"
const FOREST_SCENE := "res://features/forest/forest.gd"
const BATTLE_SCENE := "res://features/battle/battle_view.gd"
const TITLE_SCREEN_SCENE := "res://features/title/title_screen.gd"

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
		"battle":
			if _battle_boss:
				_audio.play_music("music_battle_boss")
			else:
				_audio.play_music("music_battle")
			_audio.play_ambience("")


func _on_enter_requested(place: String) -> void:
	if place == "forest":
		if current != null and current_kind == "town":
			GameState.town_return_pos = Vector2(0.0, 19.2)
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
		_audio.play_music("music_tavern_brawl")
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

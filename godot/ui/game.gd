extends Node

const GameState = preload("res://core/game_state.gd")
const Quests = preload("res://core/quests.gd")

const TOWN_SCENE := "res://world/town.gd"
const TAVERN_SCENE := "res://world/tavern.gd"
const BATTLE_SCENE := "res://ui/battle_view.gd"
const STATUS_OVERLAY_SCENE := "res://ui/status_overlay.gd"
const BOSS_ENEMY_ID := "ma_youwei"

var current: Node = null
var current_kind: String = ""
var overlay: Variant = null

var _battle_enemy: String = ""
var _battle_count: int = 0


func _ready() -> void:
	_ensure_overlay()
	show_town()


func _process(_delta: float) -> void:
	if overlay == null or current == null:
		return
	if current_kind == "town" or current_kind == "tavern":
		current.set("input_blocked", overlay.is_panel_open())


func _ensure_overlay() -> void:
	if overlay != null:
		return
	overlay = load(STATUS_OVERLAY_SCENE).new()
	overlay.name = "StatusOverlay"
	add_child(overlay)


func show_town() -> void:
	_ensure_overlay()
	_release_current()
	var town: Variant = load(TOWN_SCENE).new()
	add_child(town)
	if not town.is_inside_tree():
		town.build()
		town.build_hud()
	town.connect("encounter_requested", Callable(self, "_on_encounter_requested"))
	town.connect("enter_requested", Callable(self, "_on_enter_requested"))
	current = town
	current_kind = "town"
	GameState.town_return_pos = null
	overlay.enabled = true


func show_tavern() -> void:
	_ensure_overlay()
	_release_current()
	var tavern: Variant = load(TAVERN_SCENE).new()
	add_child(tavern)
	if not tavern.is_inside_tree():
		tavern.build()
		tavern.build_hud()
	tavern.connect("exit_requested", Callable(self, "_on_tavern_exit_requested"))
	tavern.connect("encounter_requested", Callable(self, "_on_encounter_requested"))
	current = tavern
	current_kind = "tavern"
	overlay.enabled = true


func _on_enter_requested(place: String) -> void:
	if place != "tavern":
		return
	if current != null and current_kind == "town":
		GameState.town_return_pos = current.tavern_return_pos()
	show_tavern()


func _on_tavern_exit_requested() -> void:
	show_town()


func _on_encounter_requested(enemy_id: String, count: int, first_strike: bool) -> void:
	if current != null and current_kind == "town":
		var town: Variant = current
		GameState.town_return_pos = town.player_pos
	show_battle(enemy_id, count, first_strike, false)


func show_battle(
	enemy_id: String, count: int, first_strike: bool, play_intro: bool
) -> void:
	_ensure_overlay()
	overlay.enabled = false
	overlay.close_all()
	_release_current()
	var view: Variant = load(BATTLE_SCENE).new()
	add_child(view)
	if not view.is_inside_tree():
		view.build_ui()
	# Must also reset the offsets: set_anchors_preset() alone keeps the current (0x0) rect.
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.start(enemy_id, count, first_strike, play_intro)
	view.connect("battle_finished", Callable(self, "_on_battle_finished"))
	current = view
	current_kind = "battle"
	_battle_enemy = enemy_id
	_battle_count = count


func _on_battle_finished(result: String) -> void:
	if result == "won":
		Quests.notify("defeat", _battle_enemy, _battle_count)
		if _battle_enemy == BOSS_ENEMY_ID:
			GameState.set_flag("boss_defeated")
	show_town()


func _release_current() -> void:
	if current == null:
		return
	var node: Node = current
	current = null
	current_kind = ""
	# Never free() synchronously: this is usually called from one of the node's own
	# signal callbacks ("locked object" error). Detach it, then free it at idle time.
	if node.get_parent() == self:
		remove_child(node)
	node.queue_free()

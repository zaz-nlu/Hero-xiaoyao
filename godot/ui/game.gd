extends Node

const GameState = preload("res://core/game_state.gd")

const TOWN_SCENE := "res://world/town.gd"
const BATTLE_SCENE := "res://ui/battle_view.gd"
const BOSS_ENEMY_ID := "ma_youwei"

var current: Node = null
var current_kind: String = ""

var _battle_enemy: String = ""


func _ready() -> void:
	show_town()


func show_town() -> void:
	_release_current()
	var town: Variant = load(TOWN_SCENE).new()
	add_child(town)
	if not town.is_inside_tree():
		town.build()
		town.build_hud()
	town.connect("encounter_requested", Callable(self, "_on_encounter_requested"))
	current = town
	current_kind = "town"
	GameState.town_return_pos = null


func _on_encounter_requested(enemy_id: String, count: int, first_strike: bool) -> void:
	if current != null and current_kind == "town":
		var town: Variant = current
		GameState.town_return_pos = town.player_pos
	show_battle(enemy_id, count, first_strike, false)


func show_battle(
	enemy_id: String, count: int, first_strike: bool, play_intro: bool
) -> void:
	_release_current()
	var view: Variant = load(BATTLE_SCENE).new()
	add_child(view)
	if not view.is_inside_tree():
		view.build_ui()
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.start(enemy_id, count, first_strike, play_intro)
	view.connect("battle_finished", Callable(self, "_on_battle_finished"))
	current = view
	current_kind = "battle"
	_battle_enemy = enemy_id


func _on_battle_finished(result: String) -> void:
	if result == "won" and _battle_enemy == BOSS_ENEMY_ID:
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

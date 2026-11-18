extends Control

signal battle_finished(result: String)

const Battle = preload("res://core/battle.gd")
const BattleActionBar = preload("res://features/battle/battle_action_bar.gd")
const BattleDialogueFlow = preload("res://features/battle/battle_dialogue_flow.gd")
const BattleEffects = preload("res://features/battle/battle_effects.gd")
const BattleEnemyHeads = preload("res://features/battle/battle_enemy_heads.gd")
const BattleHud = preload("res://features/battle/battle_hud.gd")
const BattleSession = preload("res://features/battle/battle_session.gd")

var selected_target: int = 0

var _session := BattleSession.new()
var _hud := BattleHud.new()
var _actions := BattleActionBar.new()
var _heads := BattleEnemyHeads.new()
var _effects := BattleEffects.new()
var _dialogue := BattleDialogueFlow.new()
var _built: bool = false

# ---------------------------------------------------------------- public forwarding
# 这些名字保留给测试与 app；真正的数据由各模块持有，数组/字典按引用返回，不复制。

var battle: Variant:
	get:
		return _session.battle

var last_error: String:
	get:
		return _session.last_error
	set(value):
		_session.last_error = value

# Set by the Game when the battle runs inside the game; null in standalone scenes.
var audio: Variant:
	get:
		return _effects.audio
	set(value):
		_effects.audio = value

var stage: Variant:
	get:
		return _effects.stage

var dialogue_view: Variant:
	get:
		return _dialogue.view

var top_bar: HBoxContainer:
	get:
		return _hud.top_bar

var player_label: Label:
	get:
		return _hud.player_label

var player_hp_bar: ProgressBar:
	get:
		return _hud.player_hp_bar

var player_hp_label: Label:
	get:
		return _hud.player_hp_label

var wound_label: Label:
	get:
		return _hud.wound_label

var jianyi_label: Label:
	get:
		return _hud.jianyi_label

var foresight_label: Label:
	get:
		return _hud.foresight_label

var jianyi_pips: Control:
	get:
		return _hud.jianyi_pips

var foresight_pips: Control:
	get:
		return _hud.foresight_pips

var enemies_container: Control:
	get:
		return _heads.enemies_container

var intent_labels: Array:
	get:
		return _heads.intent_labels

var foresight_labels: Array:
	get:
		return _heads.foresight_labels

var weak_labels: Array:
	get:
		return _heads.weak_labels

var enemy_info_labels: Array:
	get:
		return _heads.enemy_info_labels

var target_buttons: Array:
	get:
		return _heads.target_buttons

var enemy_head_labels: Array:
	get:
		return _heads.enemy_head_labels

var enemy_hp_bars: Array:
	get:
		return _heads.enemy_hp_bars

var enemy_hp_labels: Array:
	get:
		return _heads.enemy_hp_labels

var enemy_tough_labels: Array:
	get:
		return _heads.enemy_tough_labels

var enemy_stun_labels: Array:
	get:
		return _heads.enemy_stun_labels

var enemy_markers: Array:
	get:
		return _heads.enemy_markers

var martial_row: HBoxContainer:
	get:
		return _actions.martial_row

var martial_buttons: Array:
	get:
		return _actions.martial_buttons

var martial_badges: Array:
	get:
		return _actions.martial_badges

var jianyi_button: Button:
	get:
		return _actions.jianyi_button

var probe_button: Button:
	get:
		return _actions.probe_button

var foresight_button: Button:
	get:
		return _actions.foresight_button

var herb_button: Button:
	get:
		return _actions.herb_button

var jianyi_badge: Label:
	get:
		return _actions.jianyi_badge

var probe_badge: Label:
	get:
		return _actions.probe_badge

var foresight_badge: Label:
	get:
		return _actions.foresight_badge

var herb_badge: Label:
	get:
		return _actions.herb_badge

var result_label: Label:
	get:
		return _hud.result_label

var return_button: Button:
	get:
		return _hud.return_button

var log_label: RichTextLabel:
	get:
		return _effects.log_label


func _ready() -> void:
	build_ui()
	# A standalone run of this scene (debug) starts a default fight. When Game owns the view it
	# calls start() itself, and an extra start() here would swallow GameState.encounter_group.
	var parent := get_parent()
	if parent == null or parent == get_tree().root:
		start("bandit", 1, true)


func build_ui() -> void:
	if _built:
		return
	_built = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.scenario_selected.connect(_on_scenario_selected)
	_hud.return_requested.connect(press_return)
	_actions.martial_pressed.connect(_on_martial_pressed)
	_actions.special_pressed.connect(_on_special_pressed)
	_heads.enemy_selected.connect(_on_enemy_selected)
	_dialogue.finished.connect(_on_dialogue_finished)
	var row := _hud.build(self)
	_actions.build(row)
	_heads.build(self)
	_effects.build_log(self)
	_dialogue.build(self)
	_hud.set_top_bar_visible(_debug_buttons_visible())


func start(
	enemy_id: String, enemy_count: int, first_strike: bool, play_intro: bool = true
) -> void:
	if not _session.start(enemy_id, enemy_count, first_strike):
		return
	selected_target = 0
	_dialogue.reset(enemy_id)
	_heads.set_compact(_session.battle.enemies.size() >= 4)
	_effects.reset_stage_state(_session.battle)
	_heads.rebuild(_session.battle)
	_actions.rebuild(_session.battle)
	_effects.create_stage(self, _session.battle)
	if play_intro:
		_dialogue.play_intro()
	refresh()


func press_action(action: Dictionary) -> void:
	if battle == null:
		return
	# The intro/win dialogue blocks every action until it is finished.
	if _dialogue.is_active():
		_session.last_error = "dialogue active"
		return
	_effects.play_sfx("sfx_confirm")
	_session.submit(action)
	refresh()


func press_return() -> void:
	if battle == null:
		return
	var current_state: int = battle.state()
	if current_state == Battle.State.ONGOING:
		return
	var result := ""
	match current_state:
		Battle.State.WON:
			result = "won"
		Battle.State.LOST:
			result = "lost"
		Battle.State.TIMEOUT:
			result = "timeout"
	if result == "":
		return
	emit_signal("battle_finished", result)


func refresh() -> void:
	if battle == null:
		return
	_hud.refresh_player(battle)
	_heads.refresh(battle, selected_target)
	_actions.refresh(battle, selected_target, _dialogue.is_active())
	_hud.refresh_result(battle, _session.last_error)
	_effects.refresh(battle)
	_dialogue.maybe_play_win(battle.state() == Battle.State.WON)
	_hud.refresh_return(battle, _dialogue.is_active())
	_session.settle_exp()
	_session.sync_mastery_total()


func _process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if battle == null:
		return
	_effects.tick(delta)
	_update_enemy_head_positions()


func _on_scenario_selected(enemy_id: String, enemy_count: int, first_strike: bool) -> void:
	start(enemy_id, enemy_count, first_strike)


func _on_martial_pressed(index: int) -> void:
	if battle == null or index < 0 or index >= battle.loadout.size():
		return
	press_action({"kind": "martial", "id": str(battle.loadout[index]), "target": selected_target})


func _on_special_pressed(kind: String) -> void:
	match kind:
		"jianyi":
			press_action({"kind": "jianyi", "target": selected_target})
		"probe":
			press_action({"kind": "probe", "target": selected_target})
		"foresight":
			press_action({"kind": "foresight"})
		"herb":
			press_action({"kind": "item", "id": "herb"})


func _on_enemy_selected(index: int) -> void:
	selected_target = index
	refresh()


func _on_dialogue_finished() -> void:
	refresh()


func _update_enemy_head_positions() -> void:
	if battle == null or stage == null or not is_instance_valid(stage):
		return
	if not is_inside_tree() or not stage.is_inside_tree():
		return
	var camera: Camera3D = stage.camera
	if camera == null or not is_instance_valid(camera) or not camera.is_inside_tree():
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var view_size: Vector2 = viewport.get_visible_rect().size
	_heads.update_positions(stage.enemy_actors, camera, view_size)














# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	var code: int = key_event.keycode
	if code == 0:
		code = key_event.physical_keycode
	if code == KEY_F1:
		_toggle_log()
		_mark_input_handled()
		return
	if battle == null or _dialogue.is_active():
		return
	var slot: int = _slot_for_key(code)
	if slot < 0:
		return
	if _activate_slot(slot):
		_mark_input_handled()


func _slot_for_key(code: int) -> int:
	match code:
		KEY_1:
			return 0
		KEY_2:
			return 1
		KEY_3:
			return 2
		KEY_4:
			return 3
		KEY_5:
			return 4
		KEY_6:
			return 5
		KEY_7:
			return 6
		KEY_8:
			return 7
		_:
			return -1


func _activate_slot(slot: int) -> bool:
	if battle == null or slot < 0:
		return false
	if slot < _actions.martial_buttons.size():
		var button: Button = _actions.martial_buttons[slot]
		if button.disabled:
			return false
		_on_martial_pressed(slot)
		return true
	if slot == BattleActionBar.SPECIAL_SLOT_JIANYI:
		if _actions.jianyi_button == null or _actions.jianyi_button.disabled:
			return false
		_on_special_pressed("jianyi")
		return true
	if slot == BattleActionBar.SPECIAL_SLOT_PROBE:
		if _actions.probe_button == null or _actions.probe_button.disabled:
			return false
		_on_special_pressed("probe")
		return true
	if slot == BattleActionBar.SPECIAL_SLOT_FORESIGHT:
		if _actions.foresight_button == null or _actions.foresight_button.disabled:
			return false
		_on_special_pressed("foresight")
		return true
	if slot == BattleActionBar.SPECIAL_SLOT_HERB:
		if _actions.herb_button == null or _actions.herb_button.disabled:
			return false
		_on_special_pressed("herb")
		return true
	return false


func _toggle_log() -> void:
	if _effects.log_label != null:
		_effects.log_label.visible = not _effects.log_label.visible


func _mark_input_handled() -> void:
	if not is_inside_tree():
		return
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _debug_buttons_visible() -> bool:
	if not is_inside_tree():
		return false
	var tree := get_tree()
	if tree == null:
		return false
	# The scenario shortcuts are only for running battle_view.gd on its own.
	return get_parent() == tree.root

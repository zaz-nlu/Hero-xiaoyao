extends Control

signal battle_finished(result: String)

const Battle = preload("res://core/battle.gd")
const BattleStage = preload("res://world/battle_stage.gd")
const Counter = preload("res://core/counter.gd")
const DataLoader = preload("res://core/data_loader.gd")
const Dialogue = preload("res://core/dialogue.gd")
const Jianyi = preload("res://core/jianyi.gd")
const Mastery = preload("res://core/mastery.gd")
const MoveTypes = preload("res://core/move_types.gd")
const Unit = preload("res://core/unit.gd")

const PLAYER_PATH := "res://data/player.json"
const MARTIALS_PATH := "res://data/martials.json"
const ENEMIES_PATH := "res://data/enemies.json"
const ENCOUNTERS_PATH := "res://data/encounters.json"
const SPEAKERS_PATH := "res://data/speakers.json"

const STUN_COLOR := Color(0.6, 0.7, 1.0, 1.0)
const DEAD_COLOR := Color(1.0, 1.0, 1.0, 0.3)
const PERFECT_POPUP_COLOR := Color(1.0, 0.85, 0.3)
const ADVANTAGE_POPUP_COLOR := Color(0.5, 1.0, 0.7)
const BARELY_POPUP_COLOR := Color(0.85, 0.85, 0.85)
const STUN_POPUP_COLOR := Color(0.6, 0.8, 1.0)
const LOG_LINES := 8

var battle: Variant = null
var selected_target: int = 0
var last_error: String = ""

var stage: Variant = null
var dialogue_view: Variant = null

var _current_enemy_id: String = ""
var _win_dialogue_played: bool = false
var _log_seen: int = 0
var _last_hp_player: int = 0
var _last_hp_enemies: Array = []
var _last_wound_enemies: Array = []

var player_label: Label = null
var enemies_container: VBoxContainer = null
var intent_labels: Array = []
var weak_labels: Array = []
var enemy_info_labels: Array = []
var target_buttons: Array = []
var martial_row: HBoxContainer = null
var martial_buttons: Array = []
var jianyi_button: Button = null
var probe_button: Button = null
var result_label: Label = null
var return_button: Button = null
var log_label: RichTextLabel = null


func _ready() -> void:
	build_ui()
	start("bandit", 1, true)


func build_ui() -> void:
	var top_bar := HBoxContainer.new()
	top_bar.name = "TopBar"
	top_bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	top_bar.position = Vector2(16.0, 12.0)
	top_bar.add_theme_constant_override("separation", 8)
	add_child(top_bar)

	var bandit_button := Button.new()
	bandit_button.text = "打马匪（先手）"
	bandit_button.pressed.connect(_on_scenario_pressed.bind("bandit", 1, true))
	top_bar.add_child(bandit_button)

	var two_bandits_button := Button.new()
	two_bandits_button.text = "打两个马匪"
	two_bandits_button.pressed.connect(_on_scenario_pressed.bind("bandit", 2, false))
	top_bar.add_child(two_bandits_button)

	var boss_button := Button.new()
	boss_button.text = "打马友为"
	boss_button.pressed.connect(_on_scenario_pressed.bind("ma_youwei", 1, false))
	top_bar.add_child(boss_button)

	var panel := ColorRect.new()
	panel.name = "BottomPanel"
	panel.color = Color(0.05, 0.04, 0.08, 0.78)
	panel.anchor_left = 0.0
	panel.anchor_top = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 0.0
	panel.offset_top = -230.0
	panel.offset_right = 0.0
	panel.offset_bottom = 0.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var margin := MarginContainer.new()
	margin.name = "PanelMargin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.name = "PanelRow"
	row.add_theme_constant_override("separation", 18)
	margin.add_child(row)

	var left := VBoxContainer.new()
	left.name = "LeftColumn"
	left.add_theme_constant_override("separation", 4)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)

	player_label = Label.new()
	player_label.name = "PlayerLabel"
	left.add_child(player_label)

	enemies_container = VBoxContainer.new()
	enemies_container.name = "Enemies"
	enemies_container.add_theme_constant_override("separation", 2)
	left.add_child(enemies_container)

	var martial_box := VBoxContainer.new()
	martial_box.name = "MartialBox"
	martial_box.add_theme_constant_override("separation", 4)
	left.add_child(martial_box)

	martial_row = HBoxContainer.new()
	martial_row.name = "MartialRow"
	martial_row.add_theme_constant_override("separation", 8)
	martial_box.add_child(martial_row)

	var special_row := HBoxContainer.new()
	special_row.name = "SpecialRow"
	special_row.add_theme_constant_override("separation", 8)
	martial_box.add_child(special_row)

	jianyi_button = Button.new()
	jianyi_button.text = "剑意"
	jianyi_button.pressed.connect(_on_jianyi_pressed)
	special_row.add_child(jianyi_button)

	probe_button = Button.new()
	probe_button.text = "试探"
	probe_button.pressed.connect(_on_probe_pressed)
	special_row.add_child(probe_button)

	var bottom_row := HBoxContainer.new()
	bottom_row.name = "BottomRow"
	bottom_row.add_theme_constant_override("separation", 12)
	left.add_child(bottom_row)

	result_label = Label.new()
	result_label.name = "ResultLabel"
	result_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_row.add_child(result_label)

	return_button = Button.new()
	return_button.name = "ReturnButton"
	return_button.text = "返回小镇"
	return_button.visible = false
	return_button.pressed.connect(press_return)
	bottom_row.add_child(return_button)

	log_label = RichTextLabel.new()
	log_label.name = "LogLabel"
	log_label.bbcode_enabled = false
	log_label.scroll_active = true
	log_label.scroll_following = true
	log_label.fit_content = false
	log_label.custom_minimum_size = Vector2(340.0, 0.0)
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(log_label)

	dialogue_view = load("res://ui/dialogue_view.gd").new()
	dialogue_view.name = "DialogueView"
	dialogue_view.build_ui()
	dialogue_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialogue_view.visible = false
	dialogue_view.z_index = 100
	dialogue_view.connect("finished", Callable(self, "_on_dialogue_finished"))
	add_child(dialogue_view)


func start(
	enemy_id: String, enemy_count: int, first_strike: bool, play_intro: bool = true
) -> void:
	var player_data: Dictionary = DataLoader.load_player(PLAYER_PATH)
	var loaded_martials: Dictionary = DataLoader.load_martials(MARTIALS_PATH)
	var martials: Dictionary = loaded_martials.get("defs", {})
	var loaded_enemies: Dictionary = DataLoader.load_enemies(ENEMIES_PATH)
	var enemy_defs: Dictionary = loaded_enemies.get("defs", {})
	var enemy_def: Variant = enemy_defs.get(enemy_id, null)
	if enemy_def == null:
		last_error = "未知敌人：%s" % enemy_id
		return

	var loadout: Array = []
	var raw_loadout: Variant = player_data.get("loadout", [])
	if raw_loadout is Array:
		loadout = raw_loadout
	var learned: Array = []
	var raw_learned: Variant = player_data.get("learned", [])
	if raw_learned is Array:
		learned = raw_learned

	var stats: Dictionary = {}
	var raw_stats: Variant = player_data.get("stats", {})
	if raw_stats is Dictionary:
		stats = raw_stats.duplicate()
	var player: Variant = Unit.make_player(
		str(player_data.get("name", "")),
		stats,
		int(player_data.get("max_hp", 0)),
		int(player_data.get("jianyi_max", 0))
	)
	var enemies: Array = []
	for i in range(enemy_count):
		enemies.append(Unit.from_enemy(enemy_def))
	var mastery: Variant = Mastery.new()
	for raw_learned_id in learned:
		mastery.learn(str(raw_learned_id))
	for raw_id in loadout:
		mastery.learn(str(raw_id))
	battle = Battle.new(player, enemies, loadout, mastery, martials, 1, first_strike)

	selected_target = 0
	last_error = ""
	_current_enemy_id = enemy_id
	_win_dialogue_played = false
	_reset_stage_state()
	_rebuild_enemy_groups()
	_rebuild_martial_buttons()
	_create_stage()
	if play_intro:
		_play_intro_dialogue()
	refresh()


func press_action(action: Dictionary) -> void:
	if battle == null:
		return
	# The intro/win dialogue blocks every action until it is finished.
	if _dialogue_active():
		last_error = "dialogue active"
		return
	var result: Dictionary = battle.submit(action)
	if bool(result.get("ok", false)):
		last_error = ""
	else:
		last_error = str(result.get("error", "action failed"))
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


func _refresh_return_button() -> void:
	if return_button == null or battle == null:
		return
	return_button.visible = battle.state() != Battle.State.ONGOING and not _dialogue_active()


func refresh() -> void:
	if battle == null:
		return
	player_label.text = _player_text()
	for i in range(battle.enemies.size()):
		_refresh_enemy_group(i)
	_refresh_martial_buttons()
	_refresh_special_buttons()
	result_label.text = _result_text()
	log_label.text = _log_text()
	_update_actor_effects()
	_process_new_log()
	_maybe_play_win_dialogue()
	_refresh_return_button()


func _process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if battle == null:
		return
	# In the scene tree the stage advances itself in its own _process; only drive it
	# from here when it is detached (headless tests), otherwise effects run at 2x speed.
	if stage != null and is_instance_valid(stage) and not stage.is_inside_tree():
		stage.advance(delta)


func _on_scenario_pressed(enemy_id: String, enemy_count: int, first_strike: bool) -> void:
	start(enemy_id, enemy_count, first_strike)


func _on_martial_pressed(index: int) -> void:
	if battle == null or index < 0 or index >= battle.loadout.size():
		return
	press_action({"kind": "martial", "id": str(battle.loadout[index]), "target": selected_target})


func _on_jianyi_pressed() -> void:
	press_action({"kind": "jianyi", "target": selected_target})


func _on_probe_pressed() -> void:
	press_action({"kind": "probe", "target": selected_target})


func _on_target_pressed(index: int) -> void:
	selected_target = index
	refresh()


func _rebuild_enemy_groups() -> void:
	for child in enemies_container.get_children():
		child.free()
	intent_labels.clear()
	weak_labels.clear()
	enemy_info_labels.clear()
	target_buttons.clear()
	for i in range(battle.enemies.size()):
		var row := HBoxContainer.new()
		row.name = "Enemy%d" % i
		row.add_theme_constant_override("separation", 8)

		var info_label := Label.new()
		info_label.custom_minimum_size = Vector2(260, 0)
		row.add_child(info_label)

		var intent_label := Label.new()
		intent_label.custom_minimum_size = Vector2(200, 0)
		row.add_child(intent_label)

		var weak_label := Label.new()
		weak_label.custom_minimum_size = Vector2(140, 0)
		row.add_child(weak_label)

		var target_button := Button.new()
		target_button.text = "选为目标"
		target_button.pressed.connect(_on_target_pressed.bind(i))
		row.add_child(target_button)

		enemies_container.add_child(row)
		enemy_info_labels.append(info_label)
		intent_labels.append(intent_label)
		weak_labels.append(weak_label)
		target_buttons.append(target_button)


func _rebuild_martial_buttons() -> void:
	for child in martial_row.get_children():
		child.free()
	martial_buttons.clear()
	for i in range(battle.loadout.size()):
		var button := Button.new()
		button.pressed.connect(_on_martial_pressed.bind(i))
		martial_row.add_child(button)
		martial_buttons.append(button)


func _refresh_enemy_group(index: int) -> void:
	var enemy: Variant = battle.enemies[index]
	if index < enemy_info_labels.size():
		var info_label: Label = enemy_info_labels[index]
		info_label.text = _enemy_info_text(enemy)
	if index < intent_labels.size():
		var intent_label: Label = intent_labels[index]
		intent_label.text = _intent_text(index)
	if index < weak_labels.size():
		var weak_label: Label = weak_labels[index]
		weak_label.text = _weak_text(enemy)
	if index < target_buttons.size():
		var target_button: Button = target_buttons[index]
		target_button.text = "已选为目标" if index == selected_target else "选为目标"
		target_button.disabled = enemy.is_dead()


func _refresh_martial_buttons() -> void:
	var over: bool = battle.state() != Battle.State.ONGOING
	var target_alive: bool = _target_alive()
	var locked: bool = over or _dialogue_active()
	for i in range(martial_buttons.size()):
		var button: Button = martial_buttons[i]
		var id: String = str(battle.loadout[i])
		var name_text: String = id
		if battle.martials.has(id):
			name_text = str(battle.martials[id].name)
		var verdict: int = battle.preview(id, selected_target)
		button.text = "%s %s" % [name_text, _verdict_mark(verdict)]
		button.disabled = locked or not target_alive


func _refresh_special_buttons() -> void:
	var over: bool = battle.state() != Battle.State.ONGOING
	var target_alive: bool = _target_alive()
	var locked: bool = over or _dialogue_active()
	var points: int = int(battle.player.jianyi_points)
	jianyi_button.text = "剑意(%d)" % points
	jianyi_button.disabled = locked or not target_alive \
			or not Jianyi.can_strike(battle.player, battle.enemies[selected_target])
	probe_button.text = "试探"
	probe_button.disabled = locked or not target_alive


func _target_alive() -> bool:
	if selected_target < 0 or selected_target >= battle.enemies.size():
		return false
	var target: Variant = battle.enemies[selected_target]
	return not target.is_dead()


func _reset_stage_state() -> void:
	_log_seen = 0
	_last_hp_enemies.clear()
	_last_wound_enemies.clear()
	_last_hp_player = int(battle.player.hp)
	for enemy in battle.enemies:
		_last_hp_enemies.append(int(enemy.hp))
		_last_wound_enemies.append(int(enemy.wound))


func _create_stage() -> void:
	if stage != null and is_instance_valid(stage):
		stage.queue_free()
		stage = null
	if battle == null:
		return
	var ids: Array = []
	for enemy in battle.enemies:
		ids.append(str(enemy.id))
	var built: Variant = BattleStage.new()
	built.name = "BattleStage"
	add_child(built)
	move_child(built, 0)
	built.build(ids)
	stage = built


func _update_actor_effects() -> void:
	if battle == null or stage == null or not is_instance_valid(stage):
		return
	var player_actor: Variant = stage.player_actor
	if player_actor != null:
		var hp: int = int(battle.player.hp)
		if hp < _last_hp_player:
			var lost: int = _last_hp_player - hp
			stage.popup(
				"-%d" % lost,
				stage.actor_position(player_actor),
				Color(1.0, 0.35, 0.35)
			)
			stage.flash(player_actor)
		_last_hp_player = hp
		stage.set_actor_base(player_actor, Color.WHITE)
	for i in range(stage.enemy_actors.size()):
		if i >= battle.enemies.size():
			break
		var enemy: Variant = battle.enemies[i]
		var actor: Variant = stage.enemy_actors[i]
		if i < _last_hp_enemies.size() and int(enemy.hp) < int(_last_hp_enemies[i]):
			var lost_hp: int = int(_last_hp_enemies[i]) - int(enemy.hp)
			stage.popup(
				"-%d" % lost_hp,
				stage.actor_position(actor),
				Color(1.0, 0.85, 0.3)
			)
			if not enemy.is_dead():
				stage.flash(actor)
		if i < _last_wound_enemies.size() and int(enemy.wound) > int(_last_wound_enemies[i]):
			var wound_gain: int = int(enemy.wound) - int(_last_wound_enemies[i])
			stage.popup(
				"剑意 -%d" % wound_gain,
				stage.actor_position(actor),
				Color(0.75, 0.5, 1.0),
				1.3
			)
		if i < _last_hp_enemies.size():
			_last_hp_enemies[i] = int(enemy.hp)
		if i < _last_wound_enemies.size():
			_last_wound_enemies[i] = int(enemy.wound)
		if enemy.is_dead():
			stage.set_actor_base(actor, DEAD_COLOR)
		elif enemy.is_stunned():
			stage.set_actor_base(actor, STUN_COLOR)
		else:
			stage.set_actor_base(actor, Color.WHITE)


func _process_new_log() -> void:
	if battle == null or stage == null or not is_instance_valid(stage):
		return
	var start_index: int = mini(_log_seen, battle.log.size())
	for i in range(start_index, battle.log.size()):
		_handle_log_line(str(battle.log[i]))
	_log_seen = battle.log.size()


func _handle_log_line(line: String) -> void:
	if line.contains("act:player"):
		stage.lunge(stage.player_actor, 0.9)
	var enemy_index: int = _enemy_index_from_line(line)
	if enemy_index < 0:
		return
	if enemy_index < stage.enemy_actors.size():
		stage.lunge(stage.enemy_actors[enemy_index], -0.9)
	var player_actor: Variant = stage.player_actor
	if line.contains("verdict=ADVANTAGE") and line.contains("perfect=true"):
		stage.popup(
			"完美破招！",
			stage.actor_position(player_actor),
			PERFECT_POPUP_COLOR,
			1.6
		)
	elif line.contains("verdict=ADVANTAGE"):
		stage.popup(
			"破！",
			stage.actor_position(player_actor),
			ADVANTAGE_POPUP_COLOR,
			1.3
		)
	elif line.contains("verdict=BARELY"):
		stage.popup(
			"勉强",
			stage.actor_position(player_actor),
			BARELY_POPUP_COLOR,
			1.0
		)
	if line.contains("stunned=true") and enemy_index < stage.enemy_actors.size():
		stage.popup(
			"破势！",
			stage.actor_position(stage.enemy_actors[enemy_index]),
			STUN_POPUP_COLOR,
			1.5
		)


func _enemy_index_from_line(line: String) -> int:
	var marker := "act:e"
	var at: int = line.find(marker)
	if at < 0:
		return -1
	var digits := ""
	var i: int = at + marker.length()
	while i < line.length():
		var ch: String = line.substr(i, 1)
		if not ch.is_valid_int():
			break
		digits += ch
		i += 1
	if digits == "":
		return -1
	return int(digits)


func _dialogue_active() -> bool:
	return dialogue_view != null and bool(dialogue_view.is_active())


func _on_dialogue_finished() -> void:
	refresh()


func _play_intro_dialogue() -> void:
	var entry: Variant = _encounter_entry(_current_enemy_id)
	if not (entry is Dictionary):
		return
	var intro_path: String = str(entry.get("intro", ""))
	if intro_path == "":
		return
	_play_dialogue(intro_path)


func _maybe_play_win_dialogue() -> void:
	if _win_dialogue_played or battle == null:
		return
	if battle.state() != Battle.State.WON:
		return
	_win_dialogue_played = true
	var entry: Variant = _encounter_entry(_current_enemy_id)
	if not (entry is Dictionary):
		return
	var win_path: String = str(entry.get("win", ""))
	if win_path == "":
		return
	_play_dialogue(win_path)


func _encounter_entry(enemy_id: String) -> Variant:
	if enemy_id == "" or not FileAccess.file_exists(ENCOUNTERS_PATH):
		return null
	var text: String = FileAccess.get_file_as_string(ENCOUNTERS_PATH)
	if text == "":
		return null
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return null
	var data: Dictionary = parsed
	return data.get(enemy_id, null)


func _play_dialogue(path: String) -> void:
	if dialogue_view == null:
		return
	var speakers: Dictionary = Dialogue.load_speakers(SPEAKERS_PATH).get("defs", {})
	var loaded: Dictionary = Dialogue.load_file(path, speakers)
	var errors: Array = loaded.get("errors", [])
	if not errors.is_empty():
		push_warning("dialogue skipped: %s (%s)" % [path, str(errors)])
		return
	var lines: Array = loaded.get("lines", [])
	if lines.is_empty():
		return
	dialogue_view.start(lines)


func _player_text() -> String:
	var player: Variant = battle.player
	return "%s HP %d/%d 伤 %d 剑意 %d/%d" % [
		str(player.name),
		int(player.hp),
		int(player.max_hp),
		int(player.wound),
		int(player.jianyi_points),
		int(player.jianyi_max),
	]


func _enemy_info_text(enemy: Variant) -> String:
	var text: String = "%s HP %d/%d 耐性 %s/%d" % [
		str(enemy.name),
		int(enemy.hp),
		int(enemy.max_hp),
		_number_text(enemy.toughness_left),
		int(enemy.toughness_max),
	]
	if int(enemy.stun_left) > 0:
		text += " 晕眩 %d" % int(enemy.stun_left)
	return text


func _intent_text(index: int) -> String:
	var enemy: Variant = battle.enemies[index]
	if enemy.is_dead():
		return "（已倒下）"
	if enemy.is_stunned():
		return "（晕眩，不出招）"
	var intent: Dictionary = {}
	if index < battle.intents.size():
		intent = battle.intents[index]
	if intent.is_empty():
		return "（无意图）"
	var type_id: String = str(intent.get("type", ""))
	var type_name: String = str(MoveTypes.NAMES.get(type_id, type_id))
	return "下一招：%s（%s）" % [str(intent.get("name", "")), type_name]


func _weak_text(enemy: Variant) -> String:
	if not enemy.weak_revealed or enemy.weak_moves.is_empty():
		return "弱点：未知"
	var names := PackedStringArray()
	for raw_move_id in enemy.weak_moves:
		names.append(_move_name(enemy, str(raw_move_id)))
	return "弱点：%s" % ", ".join(names)


func _move_name(enemy: Variant, move_id: String) -> String:
	if enemy.def == null:
		return move_id
	for raw_move in enemy.def.moves:
		var move: Dictionary = raw_move
		if str(move.get("id", "")) == move_id:
			return str(move.get("name", move_id))
	return move_id


func _verdict_mark(verdict: int) -> String:
	match verdict:
		Counter.Verdict.ADVANTAGE:
			return "✅"
		Counter.Verdict.BARELY:
			return "⚠"
		_:
			return "❌"


func _result_text() -> String:
	var current: int = battle.state()
	var state_text := ""
	match current:
		Battle.State.WON:
			state_text = "胜利"
		Battle.State.LOST:
			state_text = "战败"
		Battle.State.TIMEOUT:
			state_text = "僵局"
	if state_text != "":
		if last_error != "":
			return "%s（%s）" % [state_text, last_error]
		return state_text
	if last_error != "":
		return last_error
	return ""


func _log_text() -> String:
	var lines := PackedStringArray()
	var start_index: int = maxi(0, battle.log.size() - LOG_LINES)
	for i in range(start_index, battle.log.size()):
		lines.append(str(battle.log[i]))
	return "\n".join(lines)


func _number_text(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return str(snappedf(value, 0.1))

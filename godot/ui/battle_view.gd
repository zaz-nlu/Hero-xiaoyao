extends Control

signal battle_finished(result: String)

const Battle = preload("res://core/battle.gd")
const Counter = preload("res://core/counter.gd")
const DataLoader = preload("res://core/data_loader.gd")
const Dialogue = preload("res://core/dialogue.gd")
const Jianyi = preload("res://core/jianyi.gd")
const Mastery = preload("res://core/mastery.gd")
const MoveTypes = preload("res://core/move_types.gd")
const SpriteSheet = preload("res://ui/sprite_sheet.gd")
const Unit = preload("res://core/unit.gd")

const PLAYER_PATH := "res://data/player.json"
const MARTIALS_PATH := "res://data/martials.json"
const ENEMIES_PATH := "res://data/enemies.json"
const ENCOUNTERS_PATH := "res://data/encounters.json"
const SPEAKERS_PATH := "res://data/speakers.json"

const PLAYER_SPRITE_ID := "ren_xiaoyao"
const SPRITE_SIZE := Vector2(128, 192)
const IDLE_INTERVAL := 0.5
const IDLE_COLUMN_A := 0
const IDLE_COLUMN_B := 2
const FLASH_TIME := 0.25
const BASE_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const HIT_COLOR := Color(1.0, 0.35, 0.35, 1.0)
const STUN_COLOR := Color(0.6, 0.7, 1.0, 1.0)
const DEAD_COLOR := Color(1.0, 1.0, 1.0, 0.3)

var battle: Variant = null
var selected_target: int = 0
var last_error: String = ""

var player_sprite: TextureRect = null
var enemies_stage: HBoxContainer = null
var enemy_sprites: Array = []
var dialogue_view: Variant = null

var _current_enemy_id: String = ""
var _win_dialogue_played: bool = false
var _idle_time: float = 0.0
var _idle_column: int = IDLE_COLUMN_A
var _player_flash: float = 0.0
var _enemy_flash: Array = []
var _last_hp_player: int = 0
var _last_hp_enemies: Array = []

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
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var scenario_row := HBoxContainer.new()
	scenario_row.name = "ScenarioRow"
	scenario_row.add_theme_constant_override("separation", 8)
	column.add_child(scenario_row)

	var bandit_button := Button.new()
	bandit_button.text = "打马匪（先手）"
	bandit_button.pressed.connect(_on_scenario_pressed.bind("bandit", 1, true))
	scenario_row.add_child(bandit_button)

	var two_bandits_button := Button.new()
	two_bandits_button.text = "打两个马匪"
	two_bandits_button.pressed.connect(_on_scenario_pressed.bind("bandit", 2, false))
	scenario_row.add_child(two_bandits_button)

	var boss_button := Button.new()
	boss_button.text = "打马友为"
	boss_button.pressed.connect(_on_scenario_pressed.bind("ma_youwei", 1, false))
	scenario_row.add_child(boss_button)

	var stage_row := HBoxContainer.new()
	stage_row.name = "StageRow"
	stage_row.add_theme_constant_override("separation", 16)
	column.add_child(stage_row)

	player_sprite = _make_sprite(PLAYER_SPRITE_ID, SpriteSheet.DIR_RIGHT)
	player_sprite.name = "PlayerSprite"
	stage_row.add_child(player_sprite)

	enemies_stage = HBoxContainer.new()
	enemies_stage.name = "EnemiesStage"
	enemies_stage.add_theme_constant_override("separation", 16)
	enemies_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_row.add_child(enemies_stage)

	player_label = Label.new()
	player_label.name = "PlayerLabel"
	column.add_child(player_label)

	enemies_container = VBoxContainer.new()
	enemies_container.name = "Enemies"
	enemies_container.add_theme_constant_override("separation", 4)
	column.add_child(enemies_container)

	var martial_box := VBoxContainer.new()
	martial_box.name = "MartialBox"
	martial_box.add_theme_constant_override("separation", 4)
	column.add_child(martial_box)

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

	result_label = Label.new()
	result_label.name = "ResultLabel"
	column.add_child(result_label)

	return_button = Button.new()
	return_button.name = "ReturnButton"
	return_button.text = "返回小镇"
	return_button.visible = false
	return_button.pressed.connect(press_return)
	column.add_child(return_button)

	log_label = RichTextLabel.new()
	log_label.name = "LogLabel"
	log_label.bbcode_enabled = false
	log_label.scroll_active = true
	log_label.scroll_following = true
	log_label.fit_content = false
	log_label.custom_minimum_size = Vector2(0, 200)
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(log_label)

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
	_update_stage()
	_maybe_play_win_dialogue()
	_refresh_return_button()


func _process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if battle == null:
		return
	_idle_time += delta
	while _idle_time >= IDLE_INTERVAL:
		_idle_time -= IDLE_INTERVAL
		_idle_column = IDLE_COLUMN_B if _idle_column == IDLE_COLUMN_A else IDLE_COLUMN_A
		_apply_idle_column()
	_tick_flash_timers(delta)


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
	if enemies_stage != null:
		for child in enemies_stage.get_children():
			child.free()
	intent_labels.clear()
	weak_labels.clear()
	enemy_info_labels.clear()
	target_buttons.clear()
	enemy_sprites.clear()
	for i in range(battle.enemies.size()):
		var row := HBoxContainer.new()
		row.name = "Enemy%d" % i
		row.add_theme_constant_override("separation", 8)

		if enemies_stage != null:
			var sprite: TextureRect = _make_sprite(str(battle.enemies[i].id), SpriteSheet.DIR_LEFT)
			sprite.name = "EnemySprite%d" % i
			enemies_stage.add_child(sprite)
			enemy_sprites.append(sprite)

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
	_idle_time = 0.0
	_idle_column = IDLE_COLUMN_A
	_player_flash = 0.0
	_enemy_flash.clear()
	_last_hp_enemies.clear()
	_last_hp_player = int(battle.player.hp)
	for enemy in battle.enemies:
		_enemy_flash.append(0.0)
		_last_hp_enemies.append(int(enemy.hp))
	_set_sprite_column(player_sprite, IDLE_COLUMN_A)


func _make_sprite(sprite_id: String, direction: int) -> TextureRect:
	var sprite := TextureRect.new()
	sprite.texture = SpriteSheet.frame(sprite_id, direction, 0)
	sprite.set_meta("direction", direction)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.custom_minimum_size = SPRITE_SIZE
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sprite


func _set_sprite_column(sprite: TextureRect, column: int) -> void:
	if sprite == null:
		return
	var current: Texture2D = sprite.texture
	if not (current is AtlasTexture):
		return
	var current_atlas: AtlasTexture = current as AtlasTexture
	var direction: int = int(sprite.get_meta("direction", SpriteSheet.DIR_DOWN))
	var atlas := AtlasTexture.new()
	atlas.atlas = current_atlas.atlas
	atlas.region = Rect2(
		column * SpriteSheet.FRAME_W,
		direction * SpriteSheet.FRAME_H,
		SpriteSheet.FRAME_W,
		SpriteSheet.FRAME_H
	)
	sprite.texture = atlas


func _apply_idle_column() -> void:
	_set_sprite_column(player_sprite, _idle_column)
	for i in range(enemy_sprites.size()):
		if battle == null or i >= battle.enemies.size():
			break
		var enemy: Variant = battle.enemies[i]
		if enemy.is_dead() or enemy.is_stunned():
			continue
		var sprite: TextureRect = enemy_sprites[i]
		_set_sprite_column(sprite, _idle_column)


func _update_stage() -> void:
	if battle == null:
		return
	if player_sprite != null:
		if int(battle.player.hp) < _last_hp_player:
			_player_flash = FLASH_TIME
		_last_hp_player = int(battle.player.hp)
		if _player_flash > 0.0:
			player_sprite.modulate = HIT_COLOR
		else:
			player_sprite.modulate = BASE_COLOR
	for i in range(enemy_sprites.size()):
		if i >= battle.enemies.size():
			break
		var enemy: Variant = battle.enemies[i]
		var sprite: TextureRect = enemy_sprites[i]
		if i < _last_hp_enemies.size() and int(enemy.hp) < int(_last_hp_enemies[i]):
			if enemy.is_dead():
				_enemy_flash[i] = 0.0
			else:
				_enemy_flash[i] = FLASH_TIME
		if i < _last_hp_enemies.size():
			_last_hp_enemies[i] = int(enemy.hp)
		if i < _enemy_flash.size() and float(_enemy_flash[i]) > 0.0 and not enemy.is_dead():
			sprite.modulate = HIT_COLOR
		else:
			sprite.modulate = _enemy_base_color(enemy)


func _tick_flash_timers(delta: float) -> void:
	if _player_flash > 0.0:
		_player_flash = maxf(0.0, _player_flash - delta)
		if _player_flash <= 0.0 and player_sprite != null:
			player_sprite.modulate = BASE_COLOR
	for i in range(_enemy_flash.size()):
		if float(_enemy_flash[i]) <= 0.0:
			continue
		_enemy_flash[i] = maxf(0.0, float(_enemy_flash[i]) - delta)
		if float(_enemy_flash[i]) > 0.0:
			continue
		if battle == null or i >= battle.enemies.size() or i >= enemy_sprites.size():
			continue
		var sprite: TextureRect = enemy_sprites[i]
		sprite.modulate = _enemy_base_color(battle.enemies[i])


func _enemy_base_color(enemy: Variant) -> Color:
	if enemy.is_dead():
		return DEAD_COLOR
	if enemy.is_stunned():
		return STUN_COLOR
	return BASE_COLOR


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
	var start_index: int = maxi(0, battle.log.size() - 30)
	for i in range(start_index, battle.log.size()):
		lines.append(str(battle.log[i]))
	return "\n".join(lines)


func _number_text(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return str(snappedf(value, 0.1))

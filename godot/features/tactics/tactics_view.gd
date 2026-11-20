extends Control

signal battle_finished(result: String)

# 战棋灰盒视图的控制器：组装 TacticsBattle，创建棋盘/行动条/面板/反制菜单/结算层，
# 并把鼠标与键盘操作翻译成 core 的公开方法。视图只调用规则，不改规则。
# 游戏内由 scene_router 走 start_from_game；tactics_sandbox 仍可独立运行。
#
# 状态机：IDLE（开始下一回合）→ PLAYER / ENEMY → 结算。
# 无渲染（headless）时敌人回合与结算暂停立即执行，便于自动测试。
# 键盘：1-9 选武学，M 移动，J 剑意，空格待机/结束，A 交给 bot，R 重来（游戏内禁用）。
# 玩家输入、敌方演出与结算层分别在同目录的辅助脚本中，本文件只保留编排与状态机。

const TacticsSetup = preload("res://core/tactics/tactics_setup.gd")
const GameBridge = preload("res://features/tactics/tactics_game_bridge.gd")
const Board = preload("res://features/tactics/tactics_board.gd")
const Stage = preload("res://features/tactics/tactics_stage.gd")
const TacticsPanel = preload("res://features/tactics/tactics_panel.gd")
const ReactionMenu = preload("res://features/tactics/tactics_reaction_menu.gd")
const TurnBar = preload("res://features/tactics/tactics_turn_bar.gd")
const UnitCard = preload("res://features/tactics/tactics_unit_card.gd")
const BioCard = preload("res://features/tactics/tactics_bio_card.gd")
const LogFeed = preload("res://features/tactics/tactics_log_feed.gd")
const EnemyDirector = preload("res://features/tactics/tactics_enemy_director.gd")
const PlayerInput = preload("res://features/tactics/tactics_player_input.gd")
const ResultLayer = preload("res://features/tactics/tactics_result_overlay.gd")
const LogText = preload("res://features/tactics/tactics_log_text.gd")

const STATE_IDLE := "idle"
const STATE_PLAYER := "player"
const STATE_ENEMY := "enemy"
const STATE_RESULT := "result"

const DEFAULT_GROUP := [{"id": "ma_youwei", "count": 1}, {"id": "bandit", "count": 5}]

var battle: Variant = null
var board: Variant = null
var stage: Variant = null
var turn_bar: Variant = null
var panel: Variant = null
var reaction_menu: Variant = null
var result_overlay: Control = null
var result_label: Label = null
var result_stats_label: Label = null
var restart_button: Button = null
var log_feed: Control = null
var unit_card: Control = null
var bio_card: Control = null
var rng := RandomNumberGenerator.new()
var auto_reactions: bool = false
var use_3d: bool = true
var audio: Variant = null

var _map_id: String = "tavern_brawl"
var _group: Array = []
var _seed: int = 1
var _state: String = STATE_IDLE
var _actor_id: String = ""
var _hover_unit_id: String = ""
var _ui_ready: bool = false

var _player_input: PlayerInput = null
var _enemy_director: EnemyDirector = null
var _result_layer: ResultLayer = null
var _bridge: Variant = GameBridge.new()


func _init() -> void:
	_player_input = PlayerInput.new()
	_player_input.setup(self)
	_enemy_director = EnemyDirector.new()
	_enemy_director.setup(self)
	_result_layer = ResultLayer.new()


func _ready() -> void:
	_ensure_ui()


func start(map_id: String = "tavern_brawl", group: Array = [], seed_value: int = 1, prebuilt: Dictionary = {}) -> void:
	_map_id = map_id
	_seed = seed_value
	if group.is_empty():
		_group = DEFAULT_GROUP.duplicate(true)
	else:
		_group = group.duplicate(true)
	_ensure_ui()
	_reset_runtime()
	_result_layer.hide_result()
	if bio_card != null:
		bio_card.close()
	if log_feed != null:
		log_feed.clear()
	panel.show_message("")
	panel.show_unit_info("")
	auto_reactions = false
	rng = RandomNumberGenerator.new()
	rng.seed = _seed

	var built: Dictionary = prebuilt
	if built.is_empty():
		built = TacticsSetup.build(_map_id, _group, null, _seed)
	if not bool(built.get("ok", false)):
		battle = null
		_state = STATE_IDLE
		panel.show_message("组装失败：%s" % str(built.get("errors", [])))
		return
	battle = built["battle"]
	var meta: Dictionary = built.get("meta", {})
	if stage != null:
		stage.set_backdrop(str(meta.get("backdrop", "")))
	_append_log("—— %s ——" % str(meta.get("name", _map_id)))
	_next_phase()


func restart() -> void:
	if _map_id == "":
		return
	start(_map_id, _group, _seed)

func start_from_game(enemy_id: String, count: int, first_strike: bool, origin: String) -> void:
	_bridge.prepare(self, enemy_id, count, first_strike, origin)


func state() -> String:
	return _state

func is_waiting_reaction() -> bool:
	return _enemy_director.waiting_reaction


func reaction_options() -> Array:
	return _enemy_director.reaction_options()

func choose_reaction(defender_id: String, martial_id: String) -> void:
	_enemy_director.choose_reaction(defender_id, martial_id)


func click_cell(cell: Vector2i) -> void:
	_player_input.click_cell(cell)


func choose_mode(mode: String, martial_id: String = "") -> void:
	_player_input.choose_mode(mode, martial_id)


func bot_play_player_turn() -> void:
	_player_input.bot_play_player_turn()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if bio_card != null and bio_card.is_open():
		bio_card.handle_key(key_event.keycode)
		return
	_player_input.handle_key(key_event.keycode)


func _ensure_ui() -> void:
	if _ui_ready:
		return
	_ui_ready = true
	mouse_filter = Control.MOUSE_FILTER_PASS

	turn_bar = TurnBar.new()
	turn_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	turn_bar.offset_bottom = 108.0
	add_child(turn_bar)

	board = null
	stage = null
	if use_3d:
		# Node3D 与 2D 控件共用同一 viewport：3D 先绘制，UI 叠在上面。
		stage = Stage.new()
		stage.name = "TacticsStage"
		add_child(stage)
		move_child(stage, 0)
		board = stage
	else:
		board = Board.new()
		board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		board.offset_left = 12.0
		board.offset_top = 66.0
		board.offset_right = -12.0
		board.offset_bottom = -196.0
		add_child(board)
	board.cell_clicked.connect(_on_cell_clicked)
	board.cell_hovered.connect(_on_cell_hovered)
	board.cell_inspected.connect(inspect_cell)

	log_feed = LogFeed.new()
	log_feed.set_anchors_preset(Control.PRESET_TOP_LEFT)
	log_feed.offset_left = 16.0
	log_feed.offset_top = 118.0
	log_feed.offset_right = 470.0
	log_feed.offset_bottom = 320.0
	add_child(log_feed)

	unit_card = UnitCard.new()
	unit_card.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	unit_card.offset_left = 16.0
	unit_card.offset_top = -201.0
	unit_card.offset_right = 316.0
	unit_card.offset_bottom = -16.0
	add_child(unit_card)

	panel = TacticsPanel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -188.0
	add_child(panel)
	panel.mode_selected.connect(_on_mode_selected)

	reaction_menu = ReactionMenu.new()
	reaction_menu.set_anchors_preset(Control.PRESET_CENTER)
	reaction_menu.offset_left = -250.0
	reaction_menu.offset_top = -40.0
	reaction_menu.offset_right = 250.0
	reaction_menu.offset_bottom = 220.0
	add_child(reaction_menu)
	reaction_menu.chosen.connect(_enemy_director.choose_reaction)

	bio_card = BioCard.new()
	add_child(bio_card)

	_result_layer.build_overlay(self, _bridge.result_callback(self, restart))
	result_overlay = _result_layer.overlay
	result_label = _result_layer.result_label
	result_stats_label = _result_layer.stats_label
	restart_button = _result_layer.restart_button

	if stage != null:
		stage.ui_controls = [
			turn_bar, unit_card, bio_card, panel, reaction_menu, result_overlay]


func _reset_runtime() -> void:
	_actor_id = ""
	_hover_unit_id = ""
	_player_input.reset()
	_enemy_director.reset()
	_state = STATE_IDLE


func _next_phase() -> void:
	if battle == null:
		return
	_append_events(battle.take_pending())
	if battle.result() != "":
		_enter_result()
		return
	_state = STATE_IDLE
	_player_input.reset()
	var actor_id: String = battle.begin_turn()
	if actor_id == "":
		if battle.result() != "":
			_enter_result()
		else:
			_actor_id = ""
			_refresh_all()
		return
	var unit = battle.get_unit(actor_id)
	if unit != null and unit.side == "player":
		_enter_player_turn(actor_id)
	else:
		_enter_enemy_turn(actor_id)


func _enter_player_turn(actor_id: String) -> void:
	_state = STATE_PLAYER
	_actor_id = actor_id
	_player_input.reset()
	panel.setup(battle, actor_id)
	panel.set_interactive(true)
	panel.set_selected("", "")
	panel.show_message("")
	panel.show_unit_info("")
	var unit = battle.get_unit(actor_id)
	if unit != null:
		_player_input.idle_overlays(unit)
	_refresh_all()


func _enter_enemy_turn(actor_id: String) -> void:
	_state = STATE_ENEMY
	_actor_id = actor_id
	_player_input.reset()
	panel.setup(battle, actor_id)
	panel.set_interactive(false)
	panel.set_selected("", "")
	var unit = battle.get_unit(actor_id)
	if unit != null:
		panel.show_message("敌方行动：%s" % str(unit.unit.name))
	_refresh_all()

	_enemy_director.begin(actor_id)


func _check_result() -> bool:
	if battle != null and battle.result() != "":
		_enter_result()
		return true
	return false


func _enter_result() -> void:
	_state = STATE_RESULT
	_enemy_director.cancel()
	_player_input.clear_mode()
	_bridge.show_result(self)
	panel.set_interactive(false)
	_refresh_all()


func _refresh_all() -> void:
	if battle == null:
		return
	if turn_bar != null:
		turn_bar.refresh(battle)
	if board != null:
		board.set_state(battle, _player_input.overlays)
	if panel != null:
		panel.refresh(battle, _actor_id)
	if unit_card != null:
		var card_id := _actor_id
		if _hover_unit_id != "" and battle.get_unit(_hover_unit_id) != null:
			card_id = _hover_unit_id
		unit_card.show_unit(battle, card_id)


func _on_cell_clicked(cell: Vector2i) -> void:
	if _inspects_on_click(cell):
		inspect_cell(cell)
		return
	click_cell(cell)


# 打开单位介绍卡（己方/敌方均可）。仅当格子上有存活单位时生效。
func inspect_cell(cell: Vector2i) -> void:
	if battle == null or battle.grid == null or not battle.grid.in_bounds(cell):
		return
	var unit = battle.unit_at(cell)
	if unit != null and bio_card != null:
		bio_card.open_for(unit)


func is_bio_open() -> bool:
	return bio_card != null and bool(bio_card.is_open())


func bio_unit_id() -> String:
	return str(bio_card.unit_id()) if bio_card != null else ""


# 玩家回合、未选动作模式时，点单位格查看人物简介；移动/攻击/剑意模式下走原逻辑。
func _inspects_on_click(cell: Vector2i) -> bool:
	if _state != STATE_PLAYER or _player_input.mode != "":
		return false
	if battle == null or battle.grid == null or not battle.grid.in_bounds(cell):
		return false
	return battle.unit_at(cell) != null


func _on_cell_hovered(cell: Vector2i) -> void:
	_player_input.on_cell_hovered(cell)
	if battle == null or unit_card == null:
		return
	var hovered = null
	if battle.grid != null and battle.grid.in_bounds(cell):
		hovered = battle.unit_at(cell)
	_hover_unit_id = str(hovered.id) if hovered != null else ""
	unit_card.show_unit(battle, _hover_unit_id if _hover_unit_id != "" else _actor_id)


func _on_mode_selected(mode: String, martial_id: String) -> void:
	choose_mode(mode, martial_id)


func _delay(seconds: float, next: Callable) -> void:
	var server := DisplayServer.get_name()
	if server == "headless" or server == "dummy" or not is_inside_tree():
		next.call()
		return
	var tree := get_tree()
	if tree == null:
		next.call()
		return
	var timer := tree.create_timer(seconds, false)
	timer.timeout.connect(next)


func _panel_message(text: String) -> void:
	if panel != null:
		panel.show_message(text)


func _append_events(events: Array) -> void:
	for event in events:
		if event is Dictionary:
			_append_log(_event_text(event))
	if stage != null:
		stage.show_events(events)
	_bridge.play_events(self, events)


func _append_log(text: String) -> void:
	if log_feed != null:
		log_feed.add_line(text)


func _event_text(event: Dictionary) -> String:
	match str(event.get("type", "")):
		"move":
			return "%s 移动到 %s" % [_unit_name(event.get("unit", "")), _cell_text(event.get("to"))]
		"attack":
			return "%s 使用 %s → %s" % [
				_unit_name(event.get("unit", "")),
				_action_name(event.get("unit", ""), str(event.get("martial_id", ""))),
				_cell_text(event.get("target"))]
		"hit":
			var text := "%s 打 %s 造成 %d（%s）" % [
				_unit_name(event.get("attacker", "")),
				_unit_name(event.get("defender", "")),
				int(event.get("damage", 0)),
				_relation_text(str(event.get("relation", "front")))]
			var reaction := str(event.get("reaction", ""))
			if reaction != "":
				text += " 反制:%s" % _martial_name(reaction)
			if bool(event.get("perfect", false)):
				text += " [完美]"
			return text
		"counter_hit":
			return "%s 反击 %s 造成 %d" % [
				_unit_name(event.get("attacker", "")),
				_unit_name(event.get("defender", "")),
				int(event.get("damage", 0))]
		"jianyi":
			return "%s 剑意 → %s 造成 %d" % [
				_unit_name(event.get("unit", "")),
				_unit_name(event.get("defender", "")),
				int(event.get("damage", 0))]
		"dead":
			return "%s 倒下" % _unit_name(event.get("unit", ""))
		"stun":
			return "%s 被破势晕眩" % _unit_name(event.get("unit", ""))
		"stunned_skip":
			return "%s 晕眩中，跳过行动" % _unit_name(event.get("unit", ""))
		_:
			return ""


func _unit_name(uid: Variant) -> String:
	var key := str(uid)
	if battle == null:
		return key
	var unit = battle.get_unit(key)
	if unit == null:
		return key
	return str(unit.unit.name)


func _martial_name(martial_id: String) -> String:
	if battle == null or not battle.martials.has(martial_id):
		return martial_id
	return str(battle.martials[martial_id].name)


# 招式名优先用玩家武学名，其次用敌人 def.moves 里的 name，最后退回 id；带形态后缀。
func _action_name(uid: Variant, martial_id: String) -> String:
	if battle != null and battle.martials.has(martial_id):
		return LogText.with_form(str(battle.martials[martial_id].name), battle.martials[martial_id])
	var unit = battle.get_unit(str(uid)) if battle != null else null
	if unit != null and unit.unit != null and unit.unit.def != null:
		for move in unit.unit.def.moves:
			if not (move is Dictionary) or str(move.get("id", "")) != martial_id:
				continue
			var move_name := str(move.get("name", ""))
			if move_name != "":
				return LogText.with_form(move_name, move)
	return martial_id


func _cell_text(cell: Variant) -> String:
	if cell is Vector2i:
		return "(%d,%d)" % [cell.x, cell.y]
	return "?"


func _relation_text(relation: String) -> String:
	match relation:
		"back":
			return "背面"
		"side":
			return "侧面"
		_:
			return "正面"

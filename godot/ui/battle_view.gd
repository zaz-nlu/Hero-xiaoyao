extends Control

signal battle_finished(result: String)

const Battle = preload("res://core/battle.gd")
const BattleStage = preload("res://world/battle_stage.gd")
const Counter = preload("res://core/counter.gd")
const DataLoader = preload("res://core/data_loader.gd")
const Dialogue = preload("res://core/dialogue.gd")
const GameState = preload("res://core/game_state.gd")
const Jianyi = preload("res://core/jianyi.gd")
const Mastery = preload("res://core/mastery.gd")
const MoveTypes = preload("res://core/move_types.gd")
const Progression = preload("res://core/progression.gd")
const Unit = preload("res://core/unit.gd")
const Hud = preload("res://ui/battle_hud_style.gd")
const ImageCache = preload("res://ui/image_cache.gd")
const AiAssets = preload("res://world/ai_assets.gd")
const IconLib = preload("res://ui/icon_lib.gd")
const SkillSlot = preload("res://ui/skill_slot.gd")
const HudBar = preload("res://ui/hud_bar.gd")
const HudPips = preload("res://ui/hud_pips.gd")
const HudDivider = preload("res://ui/hud_divider.gd")
const OrnatePanel = preload("res://ui/ornate_panel.gd")
const OrnateBox = preload("res://ui/ornate_box.gd")

const PLAYER_PATH := "res://data/player.json"
const MARTIALS_PATH := "res://data/martials.json"
const ENEMIES_PATH := "res://data/enemies.json"
const ENCOUNTERS_PATH := "res://data/encounters.json"
const SPEAKERS_PATH := "res://data/speakers.json"
const PLAYER_PORTRAIT_PATH := "res://assets/portraits/ren_xiaoyao.png"

const STUN_COLOR := Color(0.6, 0.7, 1.0, 1.0)
const DEAD_COLOR := Color(1.0, 1.0, 1.0, 0.3)
const PERFECT_POPUP_COLOR := Color(1.0, 0.85, 0.3)
const ADVANTAGE_POPUP_COLOR := Color(0.5, 1.0, 0.7)
const BARELY_POPUP_COLOR := Color(0.85, 0.85, 0.85)
const STUN_POPUP_COLOR := Color(0.6, 0.8, 1.0)
const FORESIGHT_POPUP_COLOR := Color(0.3, 0.85, 0.9)
const HERB_COLOR := Color(0.45, 0.8, 0.4)
const HERB_HEAL_BASE := 30
const LOG_LINES := 8

const CARD_WIDTH := 82.0
const CARD_HEIGHT := 104.0
const HUD_HEIGHT := 172.0
const SPECIAL_SLOT_JIANYI := 4
const SPECIAL_SLOT_PROBE := 5
const SPECIAL_SLOT_FORESIGHT := 6
const SPECIAL_SLOT_HERB := 7
const HEAD_WIDTH := 138.0
const COMPACT_HEAD_WIDTH := 104.0
const HEAD_HEIGHT := 56.0
const HEAD_WORLD_OFFSET := 2.6
const HEAD_SCREEN_GAP := 10.0

const STAT_NAMES := {
	"power": "力道",
	"speed": "身法",
	"defense": "护体",
	"recovery": "养气",
	"skill": "剑术",
	"constitution": "体质",
}

var battle: Variant = null
var selected_target: int = 0
var last_error: String = ""
# Set by the Game when the battle runs inside the game; null in standalone scenes.
var audio: Variant = null

var stage: Variant = null
var dialogue_view: Variant = null

var _current_enemy_id: String = ""
var _win_dialogue_played: bool = false
var _exp_settled: bool = false
var _compact_heads: bool = false
var _log_seen: int = 0
var _last_hp_player: int = 0
var _last_hp_enemies: Array = []
var _last_wound_enemies: Array = []

var top_bar: HBoxContainer = null
var player_label: Label = null
var player_hp_bar: ProgressBar = null
var player_hp_label: Label = null
var wound_label: Label = null
var jianyi_label: Label = null
var foresight_label: Label = null
var jianyi_pips: Control = null
var foresight_pips: Control = null
var enemies_container: Control = null
var intent_labels: Array = []
var foresight_labels: Array = []
var weak_labels: Array = []
var enemy_info_labels: Array = []
var target_buttons: Array = []
var enemy_head_labels: Array = []
var enemy_hp_bars: Array = []
var enemy_hp_labels: Array = []
var enemy_tough_labels: Array = []
var enemy_stun_labels: Array = []
var enemy_markers: Array = []
var martial_row: HBoxContainer = null
var martial_buttons: Array = []
var martial_badges: Array = []
var jianyi_button: Button = null
var probe_button: Button = null
var foresight_button: Button = null
var herb_button: Button = null
var jianyi_badge: Label = null
var probe_badge: Label = null
var foresight_badge: Label = null
var herb_badge: Label = null
var result_label: Label = null
var return_button: Button = null
var log_label: RichTextLabel = null


func _ready() -> void:
	build_ui()
	# A standalone run of this scene (debug) starts a default fight. When Game owns the view it
	# calls start() itself, and an extra start() here would swallow GameState.encounter_group.
	var parent := get_parent()
	if parent == null or parent == get_tree().root:
		start("bandit", 1, true)


func build_ui() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_top_bar()
	_build_bottom_hud()
	_build_result_banner()
	_build_head_layer()
	_build_log()
	_build_dialogue()
	top_bar.visible = _debug_buttons_visible()


func start(
	enemy_id: String, enemy_count: int, first_strike: bool, play_intro: bool = true
) -> void:
	var player_data: Dictionary = DataLoader.load_player(PLAYER_PATH)
	var loaded_martials: Dictionary = DataLoader.load_martials(MARTIALS_PATH)
	var martials: Dictionary = loaded_martials.get("defs", {})
	var loaded_enemies: Dictionary = DataLoader.load_enemies(ENEMIES_PATH)
	var enemy_defs: Dictionary = loaded_enemies.get("defs", {})
	# 混编敌人组优先于 enemy_id / enemy_count；读取后立即清空。
	var raw_group: Variant = GameState.encounter_group
	var group: Array = []
	if raw_group is Array and not (raw_group as Array).is_empty():
		group = raw_group
		GameState.encounter_group = []

	var loadout: Array = []
	var raw_loadout: Variant = player_data.get("loadout", [])
	if raw_loadout is Array:
		loadout = raw_loadout
	var learned: Array = []
	var raw_learned: Variant = player_data.get("learned", [])
	if raw_learned is Array:
		learned = raw_learned

	var stats: Dictionary = {}
	var base_stats: Dictionary = {}
	var raw_stats: Variant = player_data.get("stats", {})
	if raw_stats is Dictionary:
		base_stats = raw_stats
		stats = Progression.final_stats(base_stats)
	var player_realm := str(GameState.realm_id)
	var max_hp := 0
	if player_data.has("max_hp"):
		max_hp = int(player_data.get("max_hp", 0))
	else:
		max_hp = Progression.max_hp(base_stats)
	var player: Variant = Unit.make_player(
		str(player_data.get("name", "")),
		stats,
		max_hp,
		int(player_data.get("jianyi_max", 0)),
		int(player_data.get("foresight_max", 0)),
		player_realm
	)
	var enemies: Array = []
	if not group.is_empty():
		enemies = _build_group_enemies(group, enemy_defs)
		if enemies.is_empty():
			last_error = "未知敌人组"
			return
	else:
		var enemy_def: Variant = enemy_defs.get(enemy_id, null)
		if enemy_def == null:
			last_error = "未知敌人：%s" % enemy_id
			return
		for i in range(enemy_count):
			enemies.append(Unit.from_enemy(enemy_def))
	# 前戏里紫霞师姐打掉的伤势只作用于马匪头子：当前气血降低、上限不变，
	# 血条显示成 "207/295" 这样的带伤状态。小兵保持满血。
	var boss_hp_loss: int = int(GameState.boss_hp_loss)
	if boss_hp_loss > 0:
		for enemy in enemies:
			if str(enemy.id) == "ma_youwei":
				enemy.hp = maxi(1, int(enemy.hp) - boss_hp_loss)
		GameState.boss_hp_loss = 0
	var mastery: Variant = Mastery.new()
	mastery.set_grades(_martial_grades(martials))
	mastery.import_exp(GameState.mastery_total)
	for raw_learned_id in learned:
		mastery.learn(str(raw_learned_id))
	for raw_id in loadout:
		mastery.learn(str(raw_id))
	for raw_martial_id in GameState.mastery_exp.keys():
		mastery.add_exp(str(raw_martial_id), int(GameState.mastery_exp[raw_martial_id]))
	GameState.mastery_exp.clear()
	battle = Battle.new(player, enemies, loadout, mastery, martials, 1, first_strike)
	# Share the persistent dictionary so recognized moves carry over between battles.
	battle.known_moves = GameState.known_moves
	# Share the persistent inventory so herbs eaten in a fight stay eaten.
	battle.inventory = GameState.inventory

	selected_target = 0
	last_error = ""
	_current_enemy_id = enemy_id
	_win_dialogue_played = false
	_exp_settled = false
	_compact_heads = enemies.size() >= 4
	_reset_stage_state()
	_rebuild_enemy_groups()
	_rebuild_martial_buttons()
	_create_stage()
	if play_intro:
		_play_intro_dialogue()
	refresh()


# 按列表顺序展开混编敌人组，第一个通常是头目；最多 6 个。
func _build_group_enemies(group: Array, enemy_defs: Dictionary) -> Array:
	var result: Array = []
	for raw_entry in group:
		if not (raw_entry is Dictionary):
			continue
		var entry: Dictionary = raw_entry
		var def: Variant = enemy_defs.get(str(entry.get("id", "")), null)
		if def == null:
			continue
		var count: int = maxi(0, int(entry.get("count", 1)))
		for i in range(count):
			if result.size() >= 6:
				return result
			result.append(Unit.from_enemy(def))
	return result


func press_action(action: Dictionary) -> void:
	if battle == null:
		return
	# The intro/win dialogue blocks every action until it is finished.
	if _dialogue_active():
		last_error = "dialogue active"
		return
	_play_sfx("sfx_confirm")
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
	_refresh_player_card()
	for i in range(battle.enemies.size()):
		_refresh_enemy_group(i)
	_refresh_martial_buttons()
	_refresh_special_buttons()
	_refresh_result_banner()
	log_label.text = _log_text()
	_update_actor_effects()
	_process_new_log()
	_maybe_play_win_dialogue()
	_refresh_return_button()
	_settle_mastery_exp()
	_sync_mastery_total()


func _martial_grades(martials: Dictionary) -> Dictionary:
	var grades := {}
	for raw_id in martials.keys():
		var id := str(raw_id)
		grades[id] = str(martials[raw_id].grade)
	return grades


func _settle_mastery_exp() -> void:
	if _exp_settled or battle == null:
		return
	if battle.state() != Battle.State.WON:
		return
	_exp_settled = true
	var levels_before := {}
	for id in battle.martials.keys():
		levels_before[str(id)] = int(battle.mastery.level(str(id)))
	var gained: Dictionary = battle.settle_exp()
	if gained.is_empty():
		return
	var parts := PackedStringArray()
	for raw_id in gained.keys():
		var id := str(raw_id)
		parts.append("%s +%d" % [_martial_name(id), int(gained[raw_id])])
	if not parts.is_empty():
		Progression.push_toast("熟练度 " + "、".join(parts))
	var upgrades := PackedStringArray()
	for raw_id in gained.keys():
		var id := str(raw_id)
		var after := int(battle.mastery.level(id))
		var before := int(levels_before.get(id, after))
		if after > before:
			upgrades.append("%s 升至 Lv.%d" % [_martial_name(id), after])
	if not upgrades.is_empty():
		Progression.push_toast("、".join(upgrades))


func _sync_mastery_total() -> void:
	if battle == null or battle.mastery == null:
		return
	GameState.mastery_total = battle.mastery.export_exp()


func _process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if battle == null:
		return
	# In the scene tree the stage advances itself in its own _process; only drive it
	# from here when it is detached (headless tests), otherwise effects run at 2x speed.
	if stage != null and is_instance_valid(stage) and not stage.is_inside_tree():
		stage.advance(delta)
	_update_enemy_head_positions()


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


func _on_foresight_pressed() -> void:
	press_action({"kind": "foresight"})


func _on_herb_pressed() -> void:
	press_action({"kind": "item", "id": "herb"})


func _on_target_pressed(index: int) -> void:
	selected_target = index
	refresh()


func _rebuild_enemy_groups() -> void:
	for child in enemies_container.get_children():
		child.free()
	intent_labels.clear()
	foresight_labels.clear()
	weak_labels.clear()
	enemy_info_labels.clear()
	target_buttons.clear()
	enemy_head_labels.clear()
	enemy_hp_bars.clear()
	enemy_hp_labels.clear()
	enemy_tough_labels.clear()
	enemy_stun_labels.clear()
	enemy_markers.clear()
	if battle == null:
		return
	for i in range(battle.enemies.size()):
		_build_enemy_head(i)


func _rebuild_martial_buttons() -> void:
	for child in martial_row.get_children():
		child.free()
	martial_buttons.clear()
	martial_badges.clear()
	if battle == null:
		return
	for i in range(battle.loadout.size()):
		var id: String = str(battle.loadout[i])
		var button := _build_card_button(
			i, _martial_color(id), _martial_glyph(id), _martial_name(id),
			"", Hud.GOLD, id
		)
		button.name = "MartialCard%d" % i
		button.tooltip_text = _martial_tooltip(id)
		button.pressed.connect(_on_martial_pressed.bind(i))
		martial_row.add_child(button)
		martial_buttons.append(button)
		martial_badges.append(button.get_node("VerdictBadge"))


func _refresh_enemy_group(index: int) -> void:
	if battle == null or index < 0 or index >= battle.enemies.size():
		return
	var enemy: Variant = battle.enemies[index]
	var dead: bool = enemy.is_dead()
	if index < enemy_info_labels.size():
		var info_label: Label = enemy_info_labels[index]
		info_label.text = _enemy_info_text(enemy)
	if index < enemy_hp_labels.size():
		var hp_label: Label = enemy_hp_labels[index]
		_fit_hp_label(hp_label, int(enemy.hp), int(enemy.max_hp), 10)
	if index < enemy_hp_bars.size():
		var hp_bar: ProgressBar = enemy_hp_bars[index]
		hp_bar.max_value = maxf(1.0, float(enemy.max_hp))
		hp_bar.value = float(maxi(0, int(enemy.hp)))
	if index < enemy_tough_labels.size():
		var tough_label: Label = enemy_tough_labels[index]
		tough_label.text = _toughness_text(enemy)
	if index < enemy_stun_labels.size():
		var stun_label: Label = enemy_stun_labels[index]
		stun_label.visible = enemy.is_stunned()
		if stun_label.visible:
			stun_label.text = "晕眩"
	if index < intent_labels.size():
		var intent_label: Label = intent_labels[index]
		intent_label.text = _intent_text(index)
	if index < foresight_labels.size():
		var foresight_label_node: Label = foresight_labels[index]
		var foresight_text: String = _foresight_text(index)
		foresight_label_node.text = foresight_text
		foresight_label_node.visible = foresight_text != ""
	if index < weak_labels.size():
		var weak_label: Label = weak_labels[index]
		weak_label.text = _weak_text(enemy)
		weak_label.visible = enemy.weak_revealed and not enemy.weak_moves.is_empty()
	if index < target_buttons.size():
		var target_button: Button = target_buttons[index]
		target_button.disabled = dead
		if dead:
			target_button.tooltip_text = ""
		elif index == selected_target:
			target_button.tooltip_text = "当前目标"
		else:
			target_button.tooltip_text = "点击选为目标"
	if index < enemy_markers.size():
		var marker: Label = enemy_markers[index]
		marker.visible = index == selected_target and not dead
	if index < enemy_head_labels.size():
		var head: Panel = enemy_head_labels[index]
		head.add_theme_stylebox_override(
			"panel", Hud.head_style(index == selected_target, dead)
		)
		if head.has_method("set_frame"):
			head.call(
				"set_frame",
				Hud.GOLD_BRIGHT if index == selected_target and not dead else Hud.GOLD
			)
		head.modulate = Color(0.62, 0.62, 0.66, 0.72) if dead else Color.WHITE
		head.z_index = 10 if index == selected_target else 0
		_fit_enemy_head(head)


func _refresh_martial_buttons() -> void:
	var over: bool = battle.state() != Battle.State.ONGOING
	var target_alive: bool = _target_alive()
	var locked: bool = over or _dialogue_active()
	var intent_known: bool = battle.is_move_known(selected_target)
	for i in range(martial_buttons.size()):
		var button: Button = martial_buttons[i]
		var id: String = str(battle.loadout[i])
		var verdict: int = battle.preview(id, selected_target)
		if i < martial_badges.size():
			var badge: Label = martial_badges[i]
			if intent_known:
				_set_badge(badge, _verdict_mark(verdict), _verdict_color(verdict))
			else:
				_set_badge(badge, "？", Hud.MUTED)
		if intent_known:
			button.tooltip_text = _martial_tooltip(id)
		else:
			button.tooltip_text = "%s\n出招未知，无法判断" % _martial_tooltip(id)
		button.disabled = locked or not target_alive
		_set_card_look(button, button.disabled)


func _refresh_special_buttons() -> void:
	var over: bool = battle.state() != Battle.State.ONGOING
	var target_alive: bool = _target_alive()
	var locked: bool = over or _dialogue_active()
	var points: int = int(battle.player.jianyi_points)
	var cap: int = int(battle.player.jianyi_max)
	var can_strike := false
	if selected_target >= 0 and selected_target < battle.enemies.size():
		can_strike = Jianyi.can_strike(battle.player, battle.enemies[selected_target])
	jianyi_button.disabled = locked or not target_alive or not can_strike
	probe_button.disabled = locked or not target_alive
	_set_card_look(jianyi_button, jianyi_button.disabled)
	_set_card_look(probe_button, probe_button.disabled)
	if jianyi_badge != null:
		_set_badge(jianyi_badge, "%d/%d" % [points, cap], Hud.JIANYI_PURPLE.lightened(0.3))
	if probe_badge != null:
		_set_badge(probe_badge, "", Hud.TOUGH_GOLD)
	if foresight_button != null:
		foresight_button.disabled = locked or not battle.foresight_available()
		_set_card_look(foresight_button, foresight_button.disabled)
		foresight_button.tooltip_text = _foresight_tooltip()
	if foresight_badge != null:
		_set_badge(
			foresight_badge,
			"%d/%d" % [int(battle.player.foresight_points), int(battle.player.foresight_max)],
			Hud.FORESIGHT_CYAN.lightened(0.3)
		)
	if herb_button != null:
		var herb_count: int = int(battle.inventory.get("herb", 0))
		var hp_full: bool = int(battle.player.hp) \
				>= int(battle.player.max_hp) - int(battle.player.wound)
		herb_button.disabled = locked or herb_count <= 0 or hp_full
		_set_card_look(herb_button, herb_button.disabled)
		herb_button.tooltip_text = _herb_tooltip()
	if herb_badge != null:
		_set_badge(
			herb_badge,
			"×%d" % int(battle.inventory.get("herb", 0)),
			HERB_COLOR.lightened(0.3)
		)


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
		var sprite_id := str(enemy.id)
		if enemy.def != null and str(enemy.def.sprite) != "":
			sprite_id = str(enemy.def.sprite)
		ids.append(sprite_id)
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
	if line.contains(" dmg "):
		_play_sfx("sfx_hit")
	if line.contains("act:player item"):
		# 吃药不攻击、不前冲，只在头顶弹一个绿色回血数字。
		_play_sfx("sfx_heal")
		var healed: int = _item_heal_from_line(line)
		if healed > 0:
			stage.popup(
				"+%d" % healed,
				stage.actor_position(stage.player_actor),
				HERB_COLOR,
				1.2
			)
		return
	if line.contains("regen:player"):
		_play_sfx("sfx_heal")
	if line.contains("act:player"):
		stage.lunge(stage.player_actor, 0.9)
	if line.contains("act:player foresight"):
		stage.popup(
			"料敌机先！",
			stage.actor_position(stage.player_actor),
			FORESIGHT_POPUP_COLOR,
			0.75
		)
		return
	var enemy_index: int = _enemy_index_from_line(line)
	if enemy_index < 0:
		return
	if enemy_index < stage.enemy_actors.size():
		stage.lunge(stage.enemy_actors[enemy_index], -0.9)
	var player_actor: Variant = stage.player_actor
	if line.contains("verdict=ADVANTAGE") and line.contains("perfect=true"):
		_play_sfx("sfx_perfect")
		stage.popup(
			"完美破招！",
			stage.actor_position(player_actor),
			PERFECT_POPUP_COLOR,
			1.6
		)
	elif line.contains("verdict=ADVANTAGE"):
		_play_sfx("sfx_counter")
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
		_play_sfx("sfx_stun")
		stage.popup(
			"破势！",
			stage.actor_position(stage.enemy_actors[enemy_index]),
			STUN_POPUP_COLOR,
			1.5
		)


func _play_sfx(track: String, volume: float = 1.0) -> void:
	if audio == null or not is_instance_valid(audio):
		return
	audio.play_sfx(track, volume)


func _item_heal_from_line(line: String) -> int:
	var marker := " heal "
	var at: int = line.rfind(marker)
	if at < 0:
		return 0
	var tail: String = line.substr(at + marker.length()).strip_edges()
	if not tail.is_valid_int():
		return 0
	return int(tail)


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
	return str(battle.player.name)


func _enemy_info_text(enemy: Variant) -> String:
	return str(enemy.name)


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
	if not battle.is_move_known(index):
		return "下一招：？？？"
	var type_id: String = str(intent.get("type", ""))
	var type_name: String = str(MoveTypes.NAMES.get(type_id, type_id))
	return "下一招：%s（%s）" % [str(intent.get("name", "")), type_name]


func _foresight_text(index: int) -> String:
	if battle == null or index < 0 or index >= battle.enemies.size():
		return ""
	var moves: Array = battle.foreseen(index)
	if moves.is_empty():
		return ""
	var names := PackedStringArray()
	for raw_move in moves:
		var move: Dictionary = raw_move
		names.append(str(move.get("name", move.get("id", ""))))
	return "预判：%s" % " → ".join(names)


func _foresight_tooltip() -> String:
	var left: int = 0
	if battle != null and battle.player != null:
		left = int(battle.player.foresight_points)
	return "料敌机先：花一回合看清所有敌人接下来两次出招（剩余 %d 次）" % left


func _herb_tooltip() -> String:
	var left: int = 0
	if battle != null:
		left = int(battle.inventory.get("herb", 0))
	return "草药：恢复气血（药效 %d，受恢复属性加成，剩余 %d 份）" % [HERB_HEAL_BASE, left]


func _weak_text(enemy: Variant) -> String:
	if not enemy.weak_revealed or enemy.weak_moves.is_empty():
		return "弱点：？"
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


# ---------------------------------------------------------------- hud build

func _build_top_bar() -> void:
	top_bar = HBoxContainer.new()
	top_bar.name = "TopBar"
	top_bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	top_bar.position = Vector2(16.0, 12.0)
	top_bar.add_theme_constant_override("separation", 8)
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.visible = false
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
	boss_button.text = "打马匪头子"
	boss_button.pressed.connect(_on_scenario_pressed.bind("ma_youwei", 1, false))
	top_bar.add_child(boss_button)


func _build_bottom_hud() -> void:
	var panel := Panel.new()
	panel.name = "BottomPanel"
	panel.anchor_left = 0.0
	panel.anchor_top = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 0.0
	panel.offset_top = -HUD_HEIGHT
	panel.offset_right = 0.0
	panel.offset_bottom = 0.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	add_child(panel)

	# A soft dark fade so the HUD melts into the scene instead of cutting it off.
	var backdrop := TextureRect.new()
	backdrop.name = "Backdrop"
	backdrop.texture = Hud.vertical_gradient(Color(0.03, 0.02, 0.05, 0.0), Color(0.03, 0.02, 0.05, 0.93))
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(backdrop)

	var margin := MarginContainer.new()
	margin.name = "PanelMargin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.name = "PanelRow"
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

	row.add_child(_build_character_card())
	row.add_child(_build_skill_bar())
	_build_return_button()


func _build_character_card() -> Control:
	var card := OrnatePanel.new()
	card.name = "CharacterCard"
	card.custom_minimum_size = Vector2(268.0, 0.0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", Hud.plate_style())
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

	row.add_child(_build_portrait_frame())

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 3)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)

	player_label = Label.new()
	player_label.name = "PlayerLabel"
	Hud.configure_label(player_label, 20, Hud.TEXT)
	player_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	player_label.add_theme_constant_override("outline_size", 4)
	info.add_child(player_label)

	var rule := TextureRect.new()
	rule.texture = Hud.horizontal_fade_line(Hud.GOLD)
	rule.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rule.stretch_mode = TextureRect.STRETCH_SCALE
	rule.custom_minimum_size = Vector2(0.0, 2.0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(rule)

	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 6)
	hp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(hp_row)

	var hp_title := Label.new()
	hp_title.text = "气血"
	Hud.configure_label(hp_title, 12, Hud.MUTED)
	hp_row.add_child(hp_title)

	player_hp_bar = HudBar.new()
	player_hp_bar.name = "PlayerHpBar"
	player_hp_bar.custom_minimum_size = Vector2(96.0, 20.0)
	player_hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	player_hp_bar.max_value = 1.0
	player_hp_bar.value = 0.0
	player_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_row.add_child(player_hp_bar)

	player_hp_label = Label.new()
	player_hp_label.name = "PlayerHpLabel"
	player_hp_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	player_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Hud.configure_label(player_hp_label, 12, Color.WHITE)
	player_hp_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	player_hp_label.add_theme_constant_override("outline_size", 4)
	player_hp_bar.add_child(player_hp_label)

	wound_label = Label.new()
	wound_label.name = "WoundLabel"
	Hud.configure_label(wound_label, 11, Hud.WOUND_RED)
	wound_label.visible = false
	info.add_child(wound_label)

	var jianyi_row := _build_pip_row("JianyiLabel", "剑意", Hud.JIANYI_PURPLE)
	jianyi_label = jianyi_row.get_node("Title")
	jianyi_pips = jianyi_row.get_node("Pips")
	info.add_child(jianyi_row)

	var foresight_row := _build_pip_row("ForesightLabel", "料敌", Hud.FORESIGHT_CYAN)
	foresight_label = foresight_row.get_node("Title")
	foresight_pips = foresight_row.get_node("Pips")
	info.add_child(foresight_row)

	return card


func _build_pip_row(node_name: String, title: String, color: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title_label := Label.new()
	title_label.name = "Title"
	title_label.text = title
	title_label.custom_minimum_size = Vector2(30.0, 0.0)
	Hud.configure_label(title_label, 12, color)
	row.add_child(title_label)
	var pips := HudPips.new()
	pips.name = "Pips"
	pips.color = color
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(pips)
	row.name = node_name + "Row"
	return row


func _build_portrait_frame() -> Control:
	var frame := OrnatePanel.new()
	frame.name = "PortraitFrame"
	frame.custom_minimum_size = Vector2(92.0, 92.0)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", Hud.panel_style(1.0, Hud.GOLD, 6))

	var placeholder := ColorRect.new()
	placeholder.name = "PortraitPlaceholder"
	placeholder.color = Color(0.24, 0.2, 0.28, 1.0)
	placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	placeholder.offset_left = 3.0
	placeholder.offset_top = 3.0
	placeholder.offset_right = -3.0
	placeholder.offset_bottom = -3.0
	placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(placeholder)

	var portrait := TextureRect.new()
	portrait.name = "Portrait"
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait.offset_left = 3.0
	portrait.offset_top = 3.0
	portrait.offset_right = -3.0
	portrait.offset_bottom = -3.0
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.texture = _portrait_texture()
	frame.add_child(portrait)
	return frame


func _portrait_texture() -> Texture2D:
	if not FileAccess.file_exists(PLAYER_PORTRAIT_PATH):
		return null
	var texture: Texture2D = ImageCache.texture(PLAYER_PORTRAIT_PATH)
	if texture == null:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	var width: float = float(texture.get_width())
	var height: float = float(texture.get_height())
	var side: float = minf(width * 0.62, height * 0.42)
	var left: float = clampf(width * 0.44 - side * 0.5, 0.0, maxf(0.0, width - side))
	atlas.region = Rect2(left, height * 0.01, side, side)
	atlas.filter_clip = true
	return atlas


# The hotbar: martial slots, a divider, then the special actions, on one lacquered plate.
func _build_skill_bar() -> Control:
	var plate := OrnateBox.new()
	plate.name = "SkillBar"
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_CENTER
	plate.add_theme_stylebox_override("panel", Hud.plate_style())

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(margin)

	var strip := HBoxContainer.new()
	strip.name = "CardStrip"
	strip.alignment = BoxContainer.ALIGNMENT_CENTER
	strip.add_theme_constant_override("separation", 6)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(strip)

	martial_row = HBoxContainer.new()
	martial_row.name = "MartialRow"
	martial_row.alignment = BoxContainer.ALIGNMENT_CENTER
	martial_row.add_theme_constant_override("separation", 8)
	martial_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(martial_row)

	strip.add_child(HudDivider.new())

	var special_row := HBoxContainer.new()
	special_row.name = "SpecialRow"
	special_row.add_theme_constant_override("separation", 8)
	special_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(special_row)
	_build_special_cards(special_row)
	return plate


func _build_special_cards(parent: Container) -> void:
	jianyi_button = _build_card_button(
		SPECIAL_SLOT_JIANYI, Hud.JIANYI_PURPLE, "剑", "剑意",
		"icon_special_jianyi.png", Hud.JIANYI_PURPLE
	)
	jianyi_button.name = "JianyiCard"
	jianyi_button.tooltip_text = "剑意：消耗一点剑意，对当前目标造成必中重伤。"
	jianyi_button.pressed.connect(_on_jianyi_pressed)
	parent.add_child(jianyi_button)
	jianyi_badge = jianyi_button.get_node("VerdictBadge")

	probe_button = _build_card_button(
		SPECIAL_SLOT_PROBE, Hud.TOUGH_GOLD, "探", "试探",
		"icon_special_probe.png", Hud.TOUGH_GOLD
	)
	probe_button.name = "ProbeCard"
	probe_button.tooltip_text = "试探：揭示当前目标下一招的弱点。"
	probe_button.pressed.connect(_on_probe_pressed)
	parent.add_child(probe_button)
	probe_badge = probe_button.get_node("VerdictBadge")

	foresight_button = _build_card_button(
		SPECIAL_SLOT_FORESIGHT, Hud.FORESIGHT_CYAN, "算", "预判",
		"icon_special_foresight.png", Hud.FORESIGHT_CYAN
	)
	foresight_button.name = "ForesightCard"
	foresight_button.tooltip_text = _foresight_tooltip()
	foresight_button.pressed.connect(_on_foresight_pressed)
	parent.add_child(foresight_button)
	foresight_badge = foresight_button.get_node("VerdictBadge")

	herb_button = _build_card_button(
		SPECIAL_SLOT_HERB, HERB_COLOR, "药", "草药",
		"icon_item_herbs.png", HERB_COLOR
	)
	herb_button.name = "HerbCard"
	herb_button.tooltip_text = _herb_tooltip()
	herb_button.pressed.connect(_on_herb_pressed)
	parent.add_child(herb_button)
	herb_badge = herb_button.get_node("VerdictBadge")


# Shown above the HUD once the fight is over.
func _build_return_button() -> void:
	return_button = Button.new()
	return_button.name = "ReturnButton"
	return_button.text = "返回小镇"
	return_button.anchor_left = 0.5
	return_button.anchor_right = 0.5
	return_button.anchor_top = 1.0
	return_button.anchor_bottom = 1.0
	return_button.offset_left = -90.0
	return_button.offset_right = 90.0
	return_button.offset_top = -HUD_HEIGHT - 52.0
	return_button.offset_bottom = -HUD_HEIGHT - 6.0
	return_button.visible = false
	return_button.pressed.connect(press_return)
	_style_card_button(return_button)
	return_button.add_theme_font_size_override("font_size", 20)
	return_button.add_theme_color_override("font_color", Hud.GOLD_BRIGHT)
	add_child(return_button)


func _empty_texture() -> Texture2D:
	var image := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	image.set_pixel(0, 0, Color(0.0, 0.0, 0.0, 0.0))
	return ImageTexture.create_from_image(image)


func _build_card_button(
	slot: int, icon_color: Color, glyph: String, title: String,
	icon_file: String = "", frame: Color = Hud.GOLD, martial_id: String = ""
) -> Button:
	var button := SkillSlot.new()
	button.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.text = ""
	button.clip_contents = false
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var texture: Texture2D = null
	var martial_icon: Texture2D = null
	if martial_id != "":
		martial_icon = IconLib.martial_icon(martial_id)
		if martial_icon != null:
			# 图标由下面的 TextureRect 绘制，SkillSlot 自绘的彩色圆/首字不再显示。
			texture = _empty_texture()
	elif icon_file != "":
		texture = AiAssets.load_texture(icon_file)
	button.setup(texture, icon_color, frame, glyph)
	if martial_icon != null:
		var icon_rect := TextureRect.new()
		icon_rect.name = "Icon"
		icon_rect.texture = martial_icon
		icon_rect.position = Vector2(15.0, 15.0)
		icon_rect.size = Vector2(52.0, 52.0)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(icon_rect)

	var key_label := Label.new()
	key_label.name = "KeyLabel"
	key_label.text = str(slot + 1)
	key_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	key_label.offset_left = 4.0
	key_label.offset_top = 4.0
	key_label.offset_right = 20.0
	key_label.offset_bottom = 20.0
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	key_label.add_theme_stylebox_override("normal", Hud.badge_style(frame))
	Hud.configure_label(key_label, 11, Hud.GOLD_BRIGHT)
	button.add_child(key_label)

	var badge := Label.new()
	badge.name = "VerdictBadge"
	badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	badge.offset_left = -42.0
	badge.offset_top = 4.0
	badge.offset_right = -4.0
	badge.offset_bottom = 20.0
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_stylebox_override("normal", Hud.badge_style(frame))
	Hud.configure_label(badge, 11, Hud.GOLD_BRIGHT)
	badge.visible = false
	button.add_child(badge)

	var name_label := Label.new()
	name_label.name = "CardName"
	name_label.text = title
	name_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	name_label.offset_top = -28.0
	name_label.offset_bottom = -4.0
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Hud.configure_label(name_label, 13, Hud.TEXT)
	button.add_child(name_label)

	return button


func _set_badge(label: Label, text: String, color: Color) -> void:
	if label == null:
		return
	label.text = text
	label.visible = text != ""
	label.add_theme_color_override("font_color", color)


func _style_card_button(button: Button) -> void:
	if button == null:
		return
	button.add_theme_stylebox_override("normal", Hud.card_style())
	button.add_theme_stylebox_override("hover", Hud.card_hover_style())
	button.add_theme_stylebox_override("pressed", Hud.card_pressed_style())
	button.add_theme_stylebox_override("disabled", Hud.card_disabled_style())
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", Hud.TEXT)
	button.add_theme_color_override("font_hover_color", Hud.GOLD_BRIGHT)
	button.add_theme_color_override("font_disabled_color", Hud.MUTED)
	button.add_theme_font_size_override("font_size", 14)


func _build_result_banner() -> void:
	result_label = Label.new()
	result_label.name = "ResultLabel"
	result_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	result_label.offset_left = 0.0
	result_label.offset_top = 16.0
	result_label.offset_right = 0.0
	result_label.offset_bottom = 84.0
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 44)
	result_label.add_theme_color_override("font_color", Hud.GOLD_BRIGHT)
	result_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	result_label.add_theme_constant_override("outline_size", 8)
	result_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_label.text = ""
	result_label.visible = false
	add_child(result_label)


func _build_head_layer() -> void:
	enemies_container = Control.new()
	enemies_container.name = "Enemies"
	enemies_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	enemies_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(enemies_container)


func _build_log() -> void:
	log_label = RichTextLabel.new()
	log_label.name = "LogLabel"
	log_label.position = Vector2(16.0, 16.0)
	log_label.size = Vector2(360.0, 160.0)
	log_label.bbcode_enabled = false
	log_label.scroll_active = true
	log_label.scroll_following = true
	log_label.fit_content = false
	log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_label.add_theme_stylebox_override(
		"normal", Hud.panel_style(0.6, Color(0.78, 0.65, 0.35, 0.5), 4)
	)
	log_label.add_theme_color_override("default_color", Color(0.9, 0.88, 0.8, 0.9))
	log_label.add_theme_font_size_override("normal_font_size", 11)
	log_label.visible = false
	add_child(log_label)


func _build_dialogue() -> void:
	dialogue_view = load("res://ui/dialogue_view.gd").new()
	dialogue_view.name = "DialogueView"
	dialogue_view.build_ui()
	dialogue_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialogue_view.visible = false
	dialogue_view.z_index = 100
	dialogue_view.connect("finished", Callable(self, "_on_dialogue_finished"))
	add_child(dialogue_view)


func _build_enemy_head(index: int) -> void:
	var head := OrnatePanel.new()
	head.name = "EnemyHead%d" % index
	var head_width: float = _head_width()
	head.custom_minimum_size = Vector2(head_width, HEAD_HEIGHT)
	head.size = Vector2(head_width, HEAD_HEIGHT)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_stylebox_override("panel", Hud.head_style(false, false))
	enemies_container.add_child(head)

	var marker := Label.new()
	marker.name = "TargetMarker"
	marker.text = "▼"
	marker.set_anchors_preset(Control.PRESET_CENTER_TOP)
	marker.offset_left = -24.0
	marker.offset_top = -20.0
	marker.offset_right = 24.0
	marker.offset_bottom = 0.0
	marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Hud.configure_label(marker, 18, Hud.GOLD_BRIGHT)
	marker.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	marker.add_theme_constant_override("outline_size", 5)
	marker.visible = false
	marker.z_index = 1
	head.add_child(marker)

	var margin := MarginContainer.new()
	margin.name = "HeadMargin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin_x: int = 4 if _compact_heads else 6
	margin.add_theme_constant_override("margin_left", margin_x)
	margin.add_theme_constant_override("margin_top", 3 if _compact_heads else 4)
	margin.add_theme_constant_override("margin_right", margin_x)
	margin.add_theme_constant_override("margin_bottom", 5 if _compact_heads else 6)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1 if _compact_heads else 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)

	var info_label := Label.new()
	info_label.name = "InfoLabel"
	info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Hud.configure_label(info_label, _head_font(15), Hud.TEXT)
	info_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	info_label.add_theme_constant_override("outline_size", 4)
	box.add_child(info_label)

	var hp_stack := Control.new()
	hp_stack.name = "HpStack"
	hp_stack.custom_minimum_size = Vector2(0.0, 16.0)
	hp_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(hp_stack)

	var hp_bar := HudBar.new()
	hp_bar.name = "HpBar"
	hp_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hp_bar.max_value = 1.0
	hp_bar.value = 0.0
	hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_stack.add_child(hp_bar)

	var hp_label := Label.new()
	hp_label.name = "HpLabel"
	hp_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Hud.configure_label(hp_label, _head_font(10), Color.WHITE)
	hp_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	hp_label.add_theme_constant_override("outline_size", 3)
	hp_stack.add_child(hp_label)

	var stat_row := HBoxContainer.new()
	stat_row.add_theme_constant_override("separation", 8)
	stat_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(stat_row)

	var tough_label := Label.new()
	tough_label.name = "ToughnessLabel"
	tough_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tough_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	Hud.configure_label(tough_label, _head_font(11), Hud.TOUGH_GOLD)
	stat_row.add_child(tough_label)

	var stun_label := Label.new()
	stun_label.name = "StunLabel"
	stun_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	Hud.configure_label(stun_label, _head_font(11), Hud.STUN_BLUE)
	stun_label.visible = false
	stat_row.add_child(stun_label)

	var intent_label := Label.new()
	intent_label.name = "IntentLabel"
	intent_label.add_theme_stylebox_override("normal", Hud.bubble_style())
	intent_label.clip_text = true
	intent_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	intent_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Hud.configure_label(intent_label, _head_font(11), Hud.TEXT)
	box.add_child(intent_label)

	var foresight_label_node := Label.new()
	foresight_label_node.name = "ForesightLabel"
	foresight_label_node.add_theme_stylebox_override("normal", Hud.bubble_style())
	foresight_label_node.clip_text = true
	foresight_label_node.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	foresight_label_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Hud.configure_label(foresight_label_node, _head_font(11), Hud.GOLD)
	foresight_label_node.visible = false
	box.add_child(foresight_label_node)

	var weak_label := Label.new()
	weak_label.name = "WeakLabel"
	weak_label.clip_text = true
	weak_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	weak_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Hud.configure_label(weak_label, _head_font(11), Hud.MUTED)
	weak_label.visible = false
	box.add_child(weak_label)

	var target_button := Button.new()
	target_button.name = "TargetButton"
	target_button.text = ""
	target_button.flat = true
	target_button.focus_mode = Control.FOCUS_NONE
	target_button.mouse_filter = Control.MOUSE_FILTER_STOP
	target_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	target_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	target_button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	target_button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	target_button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	target_button.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	target_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	target_button.pressed.connect(_on_target_pressed.bind(index))
	head.add_child(target_button)

	enemy_head_labels.append(head)
	enemy_info_labels.append(info_label)
	enemy_hp_bars.append(hp_bar)
	enemy_hp_labels.append(hp_label)
	enemy_tough_labels.append(tough_label)
	enemy_stun_labels.append(stun_label)
	enemy_markers.append(marker)
	intent_labels.append(intent_label)
	foresight_labels.append(foresight_label_node)
	weak_labels.append(weak_label)
	target_buttons.append(target_button)
	_fit_enemy_head(head)


# ---------------------------------------------------------------- hud refresh

# 气血数字在条上居中显示；位数多时自动缩小字号，避免大数字（如 5290）挤出标签。
func _fit_hp_label(label: Label, hp: int, max_hp: int, base_size: int) -> void:
	var text := "%d/%d" % [hp, max_hp]
	label.text = text
	var size := base_size
	if text.length() > 8:
		size = maxi(7, base_size - 3)
	elif text.length() > 5:
		size = maxi(8, base_size - 2)
	label.add_theme_font_size_override("font_size", size)


func _refresh_player_card() -> void:
	if battle == null or battle.player == null:
		return
	var player: Variant = battle.player
	if player_label != null:
		player_label.text = _player_text()
	if player_hp_bar != null:
		player_hp_bar.max_value = maxf(1.0, float(player.max_hp))
		player_hp_bar.value = float(maxi(0, int(player.hp)))
	if player_hp_label != null:
		_fit_hp_label(player_hp_label, int(player.hp), int(player.max_hp), 11)
	if wound_label != null:
		var wound: int = int(player.wound)
		wound_label.visible = wound > 0
		wound_label.text = "伤 %d" % wound
	if jianyi_pips != null:
		jianyi_pips.call("set_pips", int(player.jianyi_points), int(player.jianyi_max))
	if foresight_pips != null:
		foresight_pips.call("set_pips", int(player.foresight_points), int(player.foresight_max))


func _refresh_result_banner() -> void:
	if result_label == null or battle == null:
		return
	if battle.state() == Battle.State.ONGOING:
		result_label.text = ""
		result_label.visible = false
		return
	result_label.text = _result_text()
	result_label.visible = result_label.text != ""


func _head_width() -> float:
	return COMPACT_HEAD_WIDTH if _compact_heads else HEAD_WIDTH


func _head_font(base_size: int) -> int:
	return maxi(8, base_size - 1) if _compact_heads else base_size


func _fit_enemy_head(head: Panel) -> void:
	if head == null:
		return
	var margin: MarginContainer = (
		head.get_node_or_null("HeadMargin") as MarginContainer
	)
	if margin == null:
		return
	var needed: float = margin.get_combined_minimum_size().y
	head.size = Vector2(_head_width(), maxf(HEAD_HEIGHT, needed))


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
	var placements: Array = []
	for i in range(enemy_head_labels.size()):
		var head: Control = enemy_head_labels[i]
		if i >= battle.enemies.size() or i >= stage.enemy_actors.size():
			head.visible = false
			continue
		var actor: Variant = stage.enemy_actors[i]
		if actor == null or not is_instance_valid(actor):
			head.visible = false
			continue
		var world: Vector3 = actor.position + Vector3(0.0, HEAD_WORLD_OFFSET, 0.0)
		if camera.is_position_behind(world):
			head.visible = false
			continue
		head.visible = true
		var screen: Vector2 = camera.unproject_position(world)
		var head_size: Vector2 = head.size
		if head_size.x <= 0.0 or head_size.y <= 0.0:
			head_size = head.custom_minimum_size
		var x: float = screen.x - head_size.x * 0.5
		var y: float = screen.y - head_size.y - HEAD_SCREEN_GAP
		x = clampf(x, 0.0, maxf(0.0, view_size.x - head_size.x))
		y = maxf(0.0, y)
		if _compact_heads:
			y = minf(y, maxf(0.0, view_size.y - head_size.y))
		placements.append({"index": i, "pos": Vector2(x, y), "size": head_size})
	if _compact_heads:
		_resolve_head_overlaps(placements, view_size)
	for raw_entry in placements:
		var entry: Dictionary = raw_entry
		var head: Control = enemy_head_labels[int(entry["index"])]
		head.position = entry["pos"]


# 4 个以上敌人时标签更宽地铺开，容易在屏幕上叠在一起：按 x 排序后，
# 把与已放置标签相交的后一个标签往上错开 36 像素，并保持夹在屏幕内。
func _resolve_head_overlaps(placements: Array, view_size: Vector2) -> void:
	placements.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pos_a: Vector2 = a["pos"]
		var pos_b: Vector2 = b["pos"]
		return pos_a.x < pos_b.x
	)
	var placed: Array = []
	for raw_entry in placements:
		var entry: Dictionary = raw_entry
		var pos: Vector2 = entry["pos"]
		var head_size: Vector2 = entry["size"]
		var rect := Rect2(pos, head_size)
		var guard := 0
		while guard < 48:
			guard += 1
			var moved := false
			for raw_prev in placed:
				var prev: Rect2 = raw_prev
				if rect.intersects(prev):
					pos.y = maxf(0.0, pos.y - 36.0)
					rect = Rect2(pos, head_size)
					moved = true
					break
			if not moved:
				break
		pos.y = clampf(pos.y, 0.0, maxf(0.0, view_size.y - head_size.y))
		rect = Rect2(pos, head_size)
		entry["pos"] = pos
		placed.append(rect)


func _set_card_look(button: Button, dimmed: bool) -> void:
	if button == null:
		return
	button.modulate = Color(0.55, 0.55, 0.62, 0.8) if dimmed else Color.WHITE


func _toughness_text(enemy: Variant) -> String:
	var left: float = maxf(0.0, float(enemy.toughness_left))
	var shown: int = int(ceilf(left))
	var text := "◆".repeat(shown)
	if text == "":
		text = "—"
	return "耐性 %s" % text


func _verdict_color(verdict: int) -> Color:
	match verdict:
		Counter.Verdict.ADVANTAGE:
			return Color(0.55, 0.95, 0.65)
		Counter.Verdict.BARELY:
			return Color(0.95, 0.9, 0.7)
		_:
			return Color(0.95, 0.45, 0.4)


func _martial_name(id: String) -> String:
	if battle != null and battle.martials.has(id):
		return str(battle.martials[id].name)
	return id


func _martial_glyph(id: String) -> String:
	var name_text: String = _martial_name(id)
	if name_text.is_empty():
		return "?"
	return name_text.substr(0, 1)


func _martial_color(id: String) -> Color:
	if battle != null and battle.martials.has(id):
		var counters: Variant = battle.martials[id].counters
		if counters is Array and not counters.is_empty():
			return Hud.move_type_color(str(counters[0]))
	return Color(0.52, 0.54, 0.62)


func _martial_tooltip(id: String) -> String:
	if battle == null or not battle.martials.has(id):
		return id
	var martial: Variant = battle.martials[id]
	var lines := PackedStringArray()
	lines.append(str(martial.name))
	var mastery_level := 0
	if battle.mastery != null:
		mastery_level = int(battle.mastery.level(id))
	lines.append("品阶：%s · Lv.%d" % [Mastery.grade_name(str(martial.grade)), mastery_level])
	lines.append("伤害 %d · 先手 %d" % [int(martial.power), int(martial.initiative)])
	var counters := PackedStringArray()
	for raw_counter_id in martial.counters:
		var counter_id: String = str(raw_counter_id)
		counters.append(str(MoveTypes.NAMES.get(counter_id, counter_id)))
	if not counters.is_empty():
		lines.append("反制：%s" % ", ".join(counters))
	lines.append(
		"比试：%s（%d 级）" % [_stat_name(str(martial.advantage_stat)), int(martial.counter_level)]
	)
	for raw_effect in martial.effects:
		var effect: Dictionary = raw_effect
		if str(effect.get("kind", "")) == "reflect":
			lines.append(
				"效果：反弹 %d%% 伤害" % int(roundf(float(effect.get("value", 0.0)) * 100.0))
			)
	return "\n".join(lines)


func _stat_name(stat_id: String) -> String:
	return str(STAT_NAMES.get(stat_id, stat_id))


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
	if battle == null or _dialogue_active():
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
	if slot < martial_buttons.size():
		var button: Button = martial_buttons[slot]
		if button.disabled:
			return false
		_on_martial_pressed(slot)
		return true
	if slot == SPECIAL_SLOT_JIANYI:
		if jianyi_button == null or jianyi_button.disabled:
			return false
		_on_jianyi_pressed()
		return true
	if slot == SPECIAL_SLOT_PROBE:
		if probe_button == null or probe_button.disabled:
			return false
		_on_probe_pressed()
		return true
	if slot == SPECIAL_SLOT_FORESIGHT:
		if foresight_button == null or foresight_button.disabled:
			return false
		_on_foresight_pressed()
		return true
	if slot == SPECIAL_SLOT_HERB:
		if herb_button == null or herb_button.disabled:
			return false
		_on_herb_pressed()
		return true
	return false


func _toggle_log() -> void:
	if log_label != null:
		log_label.visible = not log_label.visible


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

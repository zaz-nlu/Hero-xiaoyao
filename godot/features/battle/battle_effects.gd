extends RefCounted

# 战斗演出与日志：舞台节点、日志控件、音效、血/伤变化弹字、冲刺与受击闪光。
# 舞台直接挂在视图下并保持在索引 0；树内由舞台自己推进，树外才由 tick 显式推进。

const BattleStage = preload("res://features/battle/battle_stage.gd")
const BattleText = preload("res://features/battle/battle_text.gd")
const Hud = preload("res://shared/ui/battle_hud_style.gd")

const STUN_COLOR := Color(0.6, 0.7, 1.0, 1.0)
const DEAD_COLOR := Color(1.0, 1.0, 1.0, 0.3)
const PERFECT_POPUP_COLOR := Color(1.0, 0.85, 0.3)
const ADVANTAGE_POPUP_COLOR := Color(0.5, 1.0, 0.7)
const BARELY_POPUP_COLOR := Color(0.85, 0.85, 0.85)
const STUN_POPUP_COLOR := Color(0.6, 0.8, 1.0)
const FORESIGHT_POPUP_COLOR := Color(0.3, 0.85, 0.9)
const LOG_LINES := 8

var stage: Variant = null
var log_label: RichTextLabel = null
var audio: Variant = null

var _log_seen: int = 0
var _last_hp_player: int = 0
var _last_hp_enemies: Array = []
var _last_wound_enemies: Array = []


func build_log(parent: Control) -> void:
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
	parent.add_child(log_label)


func create_stage(parent: Control, battle: Variant) -> void:
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
	parent.add_child(built)
	parent.move_child(built, 0)
	built.build(ids)
	stage = built


func reset_stage_state(battle: Variant) -> void:
	_log_seen = 0
	_last_hp_enemies.clear()
	_last_wound_enemies.clear()
	if battle == null:
		return
	_last_hp_player = int(battle.player.hp)
	for enemy in battle.enemies:
		_last_hp_enemies.append(int(enemy.hp))
		_last_wound_enemies.append(int(enemy.wound))


func refresh(battle: Variant) -> void:
	if battle == null:
		return
	log_label.text = _log_text(battle)
	_update_actor_effects(battle)
	_process_new_log(battle)


func tick(delta: float) -> void:
	# In the scene tree the stage advances itself in its own _process; only drive it
	# from here when it is detached (headless tests), otherwise effects run at 2x speed.
	if stage != null and is_instance_valid(stage) and not stage.is_inside_tree():
		stage.advance(delta)


func play_sfx(track: String, volume: float = 1.0) -> void:
	if audio == null or not is_instance_valid(audio):
		return
	audio.play_sfx(track, volume)


func _update_actor_effects(battle: Variant) -> void:
	if stage == null or not is_instance_valid(stage):
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


func _process_new_log(battle: Variant) -> void:
	if stage == null or not is_instance_valid(stage):
		return
	var start_index: int = mini(_log_seen, battle.log.size())
	for i in range(start_index, battle.log.size()):
		_handle_log_line(str(battle.log[i]))
	_log_seen = battle.log.size()


func _handle_log_line(line: String) -> void:
	if line.contains(" dmg "):
		play_sfx("sfx_hit")
	if line.contains("act:player item"):
		# 吃药不攻击、不前冲，只在头顶弹一个绿色回血数字。
		play_sfx("sfx_heal")
		var healed: int = _item_heal_from_line(line)
		if healed > 0:
			stage.popup(
				"+%d" % healed,
				stage.actor_position(stage.player_actor),
				BattleText.HERB_COLOR,
				1.2
			)
		return
	if line.contains("regen:player"):
		play_sfx("sfx_heal")
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
		play_sfx("sfx_perfect")
		stage.popup(
			"完美破招！",
			stage.actor_position(player_actor),
			PERFECT_POPUP_COLOR,
			1.6
		)
	elif line.contains("verdict=ADVANTAGE"):
		play_sfx("sfx_counter")
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
		play_sfx("sfx_stun")
		stage.popup(
			"破势！",
			stage.actor_position(stage.enemy_actors[enemy_index]),
			STUN_POPUP_COLOR,
			1.5
		)


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


func _log_text(battle: Variant) -> String:
	var lines := PackedStringArray()
	var start_index: int = maxi(0, battle.log.size() - LOG_LINES)
	for i in range(start_index, battle.log.size()):
		lines.append(str(battle.log[i]))
	return "\n".join(lines)

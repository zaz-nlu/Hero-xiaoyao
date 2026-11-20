extends RefCounted

# 玩家回合的输入与提示：动作模式选择、点击/悬停处理、可达与影响范围 overlay、键盘快捷键，
# 以及「交给 bot」入口。只调用 core 规则和视图的公开状态/编排方法，不持有战斗规则。

const TacticsBot = preload("res://core/tactics/tactics_bot.gd")
const TacticsEnergy = preload("res://core/tactics/tactics_energy.gd")

var view = null
var mode: String = ""
# 没选“移动”直接点蓝格时：第一下选中目标，再点同一格才移动。
var pending_move: Variant = null
var martial_id: String = ""
var overlays: Dictionary = {}


func setup(p_view) -> void:
	view = p_view


func reset() -> void:
	pending_move = null
	mode = ""
	martial_id = ""
	clear_overlays()


func clear_mode() -> void:
	pending_move = null
	mode = ""
	martial_id = ""


func clear_overlays() -> void:
	overlays = {"move": [], "attack": [], "affected": [], "selected": null}


func idle_overlays(unit) -> void:
	overlays = {
		"move": [], "attack": [], "affected": [], "selected": unit.pos,
	}
	if not unit.has_moved:
		overlays["move"] = view.battle.reachable_cells(unit.id).keys()


func click_cell(cell: Vector2i) -> void:
	if view.battle == null or view.state() != "player":
		return
	if not view.battle.grid.in_bounds(cell):
		view._panel_message("棋盘外")
		return
	match mode:
		"move":
			var result: Dictionary = view.battle.move(view._actor_id, cell)
			if not bool(result.get("ok", false)):
				view._panel_message("不能移动：%s" % _reason_text(result))
				return
			view._append_events(result.get("events", []))
			_after_action()
		"attack":
			var result: Dictionary = view.battle.attack(
				view._actor_id, martial_id, cell, {}, _energy())
			if not bool(result.get("ok", false)):
				view._panel_message("不能攻击：%s" % _reason_text(result))
				return
			view._append_events(result.get("events", []))
			_after_action()
		"jianyi":
			var result: Dictionary = view.battle.jianyi(view._actor_id, martial_id, cell)
			if not bool(result.get("ok", false)):
				view._panel_message("不能使用剑意：%s" % _reason_text(result))
				return
			view._append_events(result.get("events", []))
			_after_action()
		_:
			_click_idle(cell)


func choose_mode(p_mode: String, p_martial_id: String = "") -> void:
	if view.battle == null or view.state() != "player":
		view._panel_message("现在不是你的回合")
		return
	var unit = view.battle.get_unit(view._actor_id)
	if unit == null:
		return
	pending_move = null
	match p_mode:
		"move":
			if unit.has_moved:
				view._panel_message("本回合已经移动过了")
				return
			mode = "move"
			martial_id = ""
			overlays = {
				"move": view.battle.reachable_cells(view._actor_id).keys(),
				"attack": [], "affected": [], "selected": unit.pos,
			}
			view.panel.set_selected("move", "")
			view._refresh_all()
		"attack":
			if unit.has_acted:
				view._panel_message("本回合已经行动过了")
				return
			if not unit.loadout.has(p_martial_id) or not view.battle.martials.has(p_martial_id):
				view._panel_message("没有这门武学")
				return
			var cost := TacticsEnergy.cost_for(view.battle.martials[p_martial_id])
			if not unit.can_pay(_energy(), cost):
				view._panel_message("所选能量不足")
				return
			mode = "attack"
			martial_id = p_martial_id
			overlays = {
				"move": [], "attack": view.battle.attack_cells(view._actor_id, p_martial_id),
				"affected": [], "selected": unit.pos,
			}
			view.panel.set_selected("attack", p_martial_id)
			view._refresh_all()
		"jianyi":
			if unit.has_acted:
				view._panel_message("本回合已经行动过了")
				return
			if int(unit.unit.jianyi_points) <= 0:
				view._panel_message("没有剑意点数")
				return
			martial_id = _jianyi_martial(unit)
			if martial_id == "":
				view._panel_message("没有可用的武学")
				return
			mode = "jianyi"
			overlays = {
				"move": [], "attack": view.battle.attack_cells(view._actor_id, martial_id),
				"affected": [], "selected": unit.pos,
			}
			view.panel.set_selected("jianyi", "")
			view._refresh_all()
		"wait":
			if unit.has_acted:
				view._panel_message("本回合已经行动过了")
				return
			var result: Dictionary = view.battle.wait(view._actor_id)
			if not bool(result.get("ok", false)):
				view._panel_message(_reason_text(result))
				return
			mode = ""
			martial_id = ""
			view.panel.set_selected("", "")
			view._panel_message("待机")
			idle_overlays(unit)
			view._check_result()
			view._refresh_all()
		"release":
			if unit.has_acted:
				view._panel_message("本回合已经行动过了")
				return
			var result: Dictionary = view.battle.release_ziqi(view._actor_id)
			if not bool(result.get("ok", false)):
				view._panel_message(_reason_text(result))
				return
			mode = ""
			martial_id = ""
			view.panel.set_selected("", "")
			var released_events: Array = result.get("events", [])
			view._append_events(released_events)
			_after_action()
			for event in released_events:
				if str(event.get("type", "")) == "heal":
					view._append_log("运功回复 %d 气血" % int(event.get("amount", 0)))
			view._panel_message("运功回复气血")
		"end":
			mode = ""
			martial_id = ""
			view.panel.set_selected("", "")
			clear_overlays()
			var finished: String = view._actor_id
			view._actor_id = ""
			view.battle.end_turn(finished)
			view._next_phase()
		_:
			view._panel_message("未知操作")


func bot_play_player_turn() -> void:
	if view.battle == null or view.state() != "player":
		return
	view.auto_reactions = true
	mode = ""
	martial_id = ""
	view.panel.set_selected("", "")
	var actor: String = view._actor_id
	var events: Array = TacticsBot.take_turn(view.battle, actor, view.rng, "best")
	view._append_events(events)
	if view._check_result():
		return
	clear_overlays()
	if str(view.battle.current_actor) == actor:
		view.battle.end_turn(actor)
	view._next_phase()


func handle_key(keycode: int) -> void:
	if _modal_open():
		return
	match keycode:
		KEY_M:
			choose_mode("move", "")
		KEY_J:
			choose_mode("jianyi", "")
		KEY_H:
			choose_mode("release", "")
		KEY_Q:
			rotate_view(-1)
		KEY_E:
			rotate_view(1)
		KEY_SPACE:
			on_space()
		KEY_A:
			bot_play_player_turn()
		KEY_TAB:
			if view.state() == "player" and view.panel != null:
				view.panel.cycle_energy()
				view._refresh_all()
		KEY_R:
			if view._bridge.can_restart():
				view.restart()
				announce_view_controls()
		_:
			var index := int(keycode) - int(KEY_1)
			if index >= 0 and index <= 8 and view.state() == "player" \
					and view.panel != null and index < view.panel.martial_ids.size():
				choose_mode("attack", view.panel.martial_ids[index])


# 3D 舞台才可旋转；2D 灰盒没有 rotate_view，按 Q/E 时静默忽略。
func rotate_view(direction: int) -> void:
	if view == null or view.board == null:
		return
	if not view.board.has_method("rotate_view"):
		return
	view.board.rotate_view(direction)


# 战斗开始时提示视角键位：写进日志 feed 的淡色行，不算战斗事件。
func announce_view_controls() -> void:
	if view == null or view.log_feed == null:
		return
	view.log_feed.add_hint("Q/E 旋转视角")


# 介绍卡或剧情对话打开时按键不穿透到棋盘操作。
func _modal_open() -> bool:
	if view == null:
		return false
	if view.has_method("is_bio_open") and bool(view.is_bio_open()):
		return true
	var dialogue = view.get_node_or_null("TacticsDialogueView")
	if dialogue == null or not dialogue.visible:
		return false
	return dialogue.has_method("is_active") and bool(dialogue.is_active())


func on_space() -> void:
	var unit = null
	if view.battle != null:
		unit = view.battle.get_unit(view._actor_id)
	if view.state() == "player" and unit != null and not unit.has_acted:
		choose_mode("wait", "")
	else:
		choose_mode("end", "")


func on_cell_hovered(cell: Vector2i) -> void:
	if view.battle == null:
		return
	update_hover_info(cell)
	if view.state() != "player" or (mode != "attack" and mode != "jianyi"):
		return
	if martial_id == "":
		return
	if not view.battle.grid.in_bounds(cell):
		overlays["affected"] = []
	else:
		var cells: Array = []
		for target in view.battle.affected_units(view._actor_id, martial_id, cell):
			cells.append(target.pos)
		overlays["affected"] = cells
	if view.board != null:
		view.board.set_state(view.battle, overlays)


func update_hover_info(cell: Vector2i) -> void:
	if view.panel == null:
		return
	if view.battle == null or not view.battle.grid.in_bounds(cell):
		view.panel.show_unit_info("")
		return
	var unit = view.battle.unit_at(cell)
	if unit == null:
		view.panel.show_unit_info("")
		return
	var text := "%s   气血 %d/%d" % [
		str(unit.unit.name), int(unit.unit.hp), int(unit.unit.max_hp)]
	if int(unit.unit.toughness_max) > 0:
		text += "   韧性 %d/%d" % [
			int(ceil(float(unit.unit.toughness_left))), int(unit.unit.toughness_max)]
	if unit.unit.is_stunned():
		text += "   [晕眩]"
	view.panel.show_unit_info(text)


# 默认就亮着蓝色可移动格：第一下点蓝格选中（白色角标），再点同一格移动；点别处则取消。
func _click_idle(cell: Vector2i) -> void:
	var unit = view.battle.get_unit(view._actor_id)
	if unit == null:
		return
	var reachable: Array = []
	if not unit.has_moved:
		reachable = view.battle.reachable_cells(unit.id).keys()
	if cell == unit.pos or not reachable.has(cell):
		pending_move = null
		idle_overlays(unit)
		view._refresh_all()
		view._panel_message("点蓝色格子移动（点两次），或先选择一个动作")
		return
	if pending_move != null and Vector2i(pending_move) == cell:
		pending_move = null
		var result: Dictionary = view.battle.move(view._actor_id, cell)
		if not bool(result.get("ok", false)):
			view._panel_message("不能移动：%s" % _reason_text(result))
			return
		view._append_events(result.get("events", []))
		_after_action()
		return
	pending_move = cell
	overlays["selected"] = cell
	view._panel_message("再点一次，移动到这里")
	view._refresh_all()


func _after_action() -> void:
	var unit = view.battle.get_unit(view._actor_id)
	pending_move = null
	mode = ""
	martial_id = ""
	view.panel.set_selected("", "")
	view._panel_message("")
	if unit != null:
		idle_overlays(unit)
	if not view._check_result():
		view._refresh_all()


func _jianyi_martial(unit) -> String:
	for raw_id in unit.loadout:
		return str(raw_id)
	return ""


func _energy() -> String:
	if view.panel != null:
		return str(view.panel.energy)
	return "neili"


func _reason_text(result: Dictionary) -> String:
	match str(result.get("reason", "")):
		"unreachable":
			return "格子不在移动范围内"
		"already_moved":
			return "本回合已经移动过了"
		"already_acted":
			return "本回合已经行动过了"
		"out_of_range":
			return "目标不在射程内"
		"no_energy":
			return "所选能量不足"
		"no_uses":
			return "次数已经用尽"
		"no_jianyi":
			return "没有剑意点数"
		"full_hp":
			return "气血已满"
		"player_only":
			return "只能对自己使用"
		"not_in_loadout":
			return "没有这门武学"
		"battle_over":
			return "战斗已结束"
		"not_active":
			return "不是当前行动者"
		_:
			return str(result.get("reason", ""))

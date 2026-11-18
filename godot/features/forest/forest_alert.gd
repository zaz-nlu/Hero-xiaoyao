extends RefCounted

# 森林警报：发现玩家后的 0.6 秒延迟、潜行偷袭与 encounter 请求。
# 已击败 flag 由 controller 读取；这里只处理运行时警报状态。

signal encounter_requested(enemy_id: String, count: int, first_strike: bool)

const Stealth = preload("res://shared/gameplay/stealth.gd")
const GameState = preload("res://core/game_state.gd")
const ForestPatrol = preload("res://features/forest/forest_patrol.gd")

const ALERT_DELAY := 0.6

var alerted: bool = false
var timer: float = 0.0
var encounter_sent: bool = false
var pending_encounter: Dictionary = {}


func tick(delta: float) -> void:
	if not alerted or encounter_sent:
		return
	timer -= delta
	if timer <= 0.0:
		_finish_alert()


func check_detection(
	patrol: ForestPatrol,
	player_pos: Vector2,
	crouched: bool,
	in_hide: bool,
	blockers: Array
) -> void:
	for group_value in patrol.groups:
		var group: Dictionary = group_value
		if bool(group.get("alerted", false)):
			continue
		var members: Array = group["members"]
		for member_value in members:
			var member: Dictionary = member_value
			if _member_sees_player(member, player_pos, crouched, in_hide, blockers):
				_begin_group_alert(patrol, group, member, player_pos)
				return
	if patrol.scout.is_empty() or bool(patrol.scout.get("alerted", false)):
		return
	if _member_sees_player(patrol.scout, player_pos, crouched, in_hide, blockers):
		_begin_scout_alert(patrol, player_pos)


func _member_sees_player(
	member: Dictionary,
	player_pos: Vector2,
	crouched: bool,
	in_hide: bool,
	blockers: Array
) -> bool:
	var pos: Vector2 = member["pos"]
	var reach := _player_view_reach(
		float(member["vision"]), player_pos, crouched, in_hide
	)
	return Stealth.sees(
		pos,
		float(member["facing_angle"]),
		player_pos,
		reach,
		float(member["half_angle"]),
		blockers
	)


func _player_view_reach(
	base: float, _player_pos: Vector2, crouched: bool, in_hide: bool
) -> float:
	return Stealth.view_distance(base, crouched, in_hide)


func _begin_group_alert(
	patrol: ForestPatrol, group: Dictionary, spotter: Dictionary, player_pos: Vector2
) -> void:
	if alerted:
		return
	var members: Array = group["members"]
	var count := int(members.size())
	_begin_alert("bandit", count, "patrol", int(group["index"]))
	group["alerted"] = true
	for member_value in members:
		var member: Dictionary = member_value
		patrol.stop_member(member)
		patrol.face_member_toward(member, player_pos)
	patrol.show_alert_mark(spotter)


func _begin_scout_alert(patrol: ForestPatrol, player_pos: Vector2) -> void:
	if alerted:
		return
	_begin_alert("bandit_scout", 1, "scout", -1)
	patrol.scout["alerted"] = true
	patrol.stop_member(patrol.scout)
	patrol.face_member_toward(patrol.scout, player_pos)
	patrol.show_alert_mark(patrol.scout)


func _begin_alert(enemy_id: String, count: int, kind: String, id: int) -> void:
	alerted = true
	timer = ALERT_DELAY
	encounter_sent = false
	pending_encounter = {"enemy": enemy_id, "count": count}
	GameState.pending_forest_encounter = {"kind": kind, "id": id}


func _finish_alert() -> void:
	if encounter_sent:
		return
	encounter_sent = true
	var enemy_id := str(pending_encounter.get("enemy", "bandit"))
	var count := int(pending_encounter.get("count", 1))
	encounter_requested.emit(enemy_id, count, false)


func nearest_sneak_target(
	patrol: ForestPatrol,
	player_pos: Vector2,
	crouched: bool,
	in_hide: bool,
	blockers: Array
) -> Dictionary:
	if alerted:
		return {}
	var best: Dictionary = {}
	var best_dist := 9999.0
	for group_value in patrol.groups:
		var group: Dictionary = group_value
		if bool(group.get("alerted", false)):
			continue
		var members: Array = group["members"]
		for member_value in members:
			var member: Dictionary = member_value
			var target := _sneak_target_for(
				member,
				"bandit",
				members.size(),
				"patrol",
				int(group["index"]),
				group,
				player_pos,
				crouched,
				in_hide,
				blockers
			)
			if target.is_empty():
				continue
			var dist := player_pos.distance_to(Vector2(member["pos"]))
			if dist < best_dist:
				best = target
				best_dist = dist
	if not patrol.scout.is_empty() and not bool(patrol.scout.get("alerted", false)):
		var scout_target := _sneak_target_for(
			patrol.scout,
			"bandit_scout",
			1,
			"scout",
			-1,
			{},
			player_pos,
			crouched,
			in_hide,
			blockers
		)
		if not scout_target.is_empty():
			var scout_dist := player_pos.distance_to(Vector2(patrol.scout["pos"]))
			if scout_dist < best_dist:
				best = scout_target
				best_dist = scout_dist
	return best


func _sneak_target_for(
	member: Dictionary,
	enemy_id: String,
	count: int,
	kind: String,
	id: int,
	group: Dictionary,
	player_pos: Vector2,
	crouched: bool,
	in_hide: bool,
	blockers: Array
) -> Dictionary:
	var pos: Vector2 = member["pos"]
	var facing := float(member["facing_angle"])
	var reach := _player_view_reach(float(member["vision"]), player_pos, crouched, in_hide)
	var in_view := Stealth.sees(
		pos, facing, player_pos, reach, float(member["half_angle"]), blockers
	)
	if not Stealth.can_sneak(pos, facing, player_pos, in_view):
		return {}
	var target := {
		"member": member,
		"enemy_id": enemy_id,
		"count": count,
		"kind": kind,
		"id": id,
	}
	if not group.is_empty():
		target["group"] = group
	return target


func trigger_sneak(target: Dictionary, patrol: ForestPatrol) -> void:
	if alerted:
		return
	alerted = true
	encounter_sent = true
	var kind := str(target.get("kind", "patrol"))
	GameState.pending_forest_encounter = {"kind": kind, "id": int(target.get("id", -1))}
	var group_value: Variant = target.get("group", null)
	if group_value is Dictionary:
		var group: Dictionary = group_value
		group["alerted"] = true
		var members: Array = group["members"]
		for member_value in members:
			var member: Dictionary = member_value
			patrol.stop_member(member)
	var member_value: Variant = target.get("member", null)
	if member_value is Dictionary:
		var member: Dictionary = member_value
		patrol.stop_member(member)
	encounter_requested.emit(
		str(target.get("enemy_id", "bandit")),
		int(target.get("count", 1)),
		true
	)

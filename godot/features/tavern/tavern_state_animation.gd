extends RefCounted

# 家具与 NPC 共用的状态转换时间线：两系统提交节点变换/视觉 swap 任务，
# 本类只负责推进、插值与收尾。

signal finished

const TavernFurnitureVisuals = preload("res://shared/scenery/tavern/tavern_furniture_visuals.gd")

const ANIM_DURATION := 1.2

var active := false

var _t := 0.0
var _moves: Array = []
var _swaps: Array = []
var _npcs: Array = []


func begin() -> void:
	_moves.clear()
	_swaps.clear()
	_npcs.clear()
	active = false
	_t = 0.0


func add_move(node: Node3D, from: Transform3D, to: Transform3D) -> void:
	_moves.append({"node": node, "from": from, "to": to})


func add_swap(
	normal: Sprite3D,
	wrecked: Sprite3D,
	from_normal: float,
	from_wrecked: float,
	to_normal: float,
	to_wrecked: float
) -> void:
	_swaps.append({
		"normal": normal,
		"wrecked": wrecked,
		"from_normal": from_normal,
		"from_wrecked": from_wrecked,
		"to_normal": to_normal,
		"to_wrecked": to_wrecked,
	})


func add_npc_move(node: Node3D, from: Vector3, to: Vector3, delay: float = 0.0) -> void:
	_npcs.append({"node": node, "from": from, "to": to, "delay": delay})


func commit(animate: bool) -> void:
	active = animate and (not _moves.is_empty() or not _npcs.is_empty())


func advance(delta: float) -> float:
	var remaining := maxf(0.0, delta)
	if not active:
		return remaining
	var total := _total()
	var time_left := maxf(0.0, total - _t)
	_t += remaining
	if _t >= total:
		remaining = maxf(0.0, remaining - time_left)
		_finish()
		emit_signal("finished")
	else:
		_step()
		remaining = 0.0
	return remaining


func _total() -> float:
	var total: float = ANIM_DURATION
	for record_value in _npcs:
		if not (record_value is Dictionary):
			continue
		var record: Dictionary = record_value
		total = maxf(total, ANIM_DURATION + float(record.get("delay", 0.0)))
	return total


func _step() -> void:
	var weight := clampf(_t / ANIM_DURATION, 0.0, 1.0)
	for record_value in _moves:
		if not (record_value is Dictionary):
			continue
		var record: Dictionary = record_value
		var node_value: Variant = record.get("node", null)
		if not (node_value is Node3D):
			continue
		var from: Transform3D = record.get("from", Transform3D.IDENTITY)
		var to: Transform3D = record.get("to", Transform3D.IDENTITY)
		var from_q: Quaternion = from.basis.get_rotation_quaternion()
		var to_q: Quaternion = to.basis.get_rotation_quaternion()
		var basis := Basis(from_q.slerp(to_q, weight))
		(node_value as Node3D).transform = Transform3D(
			basis, from.origin.lerp(to.origin, weight)
		)
	for record_value in _swaps:
		if not (record_value is Dictionary):
			continue
		var swap: Dictionary = record_value
		var normal_value: Variant = swap.get("normal", null)
		var wrecked_value: Variant = swap.get("wrecked", null)
		if normal_value is Sprite3D:
			set_sprite_alpha(
				normal_value as Sprite3D,
				lerpf(float(swap.get("from_normal", 1.0)), float(swap.get("to_normal", 1.0)), weight)
			)
		if wrecked_value is Sprite3D:
			set_sprite_alpha(
				wrecked_value as Sprite3D,
				lerpf(float(swap.get("from_wrecked", 0.0)), float(swap.get("to_wrecked", 0.0)), weight)
			)
	for record_value in _npcs:
		if not (record_value is Dictionary):
			continue
		var record: Dictionary = record_value
		var node_value: Variant = record.get("node", null)
		if not (node_value is Node3D):
			continue
		var from: Vector3 = record.get("from", Vector3.ZERO)
		var to: Vector3 = record.get("to", Vector3.ZERO)
		var delay: float = float(record.get("delay", 0.0))
		var npc_weight := clampf((_t - delay) / ANIM_DURATION, 0.0, 1.0)
		(node_value as Node3D).position = from.lerp(to, npc_weight)


func _finish() -> void:
	for record_value in _moves:
		var record: Dictionary = record_value
		var node_value: Variant = record.get("node", null)
		if node_value is Node3D:
			var target_transform: Transform3D = record.get("to", Transform3D.IDENTITY)
			(node_value as Node3D).transform = target_transform
	for record_value in _npcs:
		var record: Dictionary = record_value
		var node_value: Variant = record.get("node", null)
		if node_value is Node3D:
			var node: Node3D = node_value
			var target_position: Vector3 = record.get("to", Vector3.ZERO)
			node.position = target_position
			node.call("set_moving", false)
	for record_value in _swaps:
		if not (record_value is Dictionary):
			continue
		var swap: Dictionary = record_value
		var normal_value: Variant = swap.get("normal", null)
		var wrecked_value: Variant = swap.get("wrecked", null)
		if normal_value is Sprite3D:
			set_sprite_alpha(normal_value as Sprite3D, float(swap.get("to_normal", 1.0)))
		if wrecked_value is Sprite3D:
			set_sprite_alpha(wrecked_value as Sprite3D, float(swap.get("to_wrecked", 0.0)))
	_moves.clear()
	_swaps.clear()
	_npcs.clear()
	active = false
	_t = 0.0


static func set_sprite_alpha(sprite: Sprite3D, alpha: float) -> void:
	TavernFurnitureVisuals.set_sprite_alpha(sprite, alpha)

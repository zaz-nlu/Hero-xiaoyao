extends RefCounted

const THRESHOLD := 100

var _order: Array[String] = []
var _speed: Dictionary = {}
var _ct: Dictionary = {}


static func ct_rate(speed: int) -> int:
	return 10 + speed


func add(unit_id: String, speed: int, initial_ct: int = 0) -> void:
	if unit_id == "":
		return
	if not _speed.has(unit_id):
		_order.append(unit_id)
	_speed[unit_id] = speed
	_ct[unit_id] = initial_ct


func remove(unit_id: String) -> void:
	_order.erase(unit_id)
	_speed.erase(unit_id)
	_ct.erase(unit_id)


func set_speed(unit_id: String, speed: int) -> void:
	if not _speed.has(unit_id):
		return
	_speed[unit_id] = speed


func ct_of(unit_id: String) -> int:
	return int(_ct.get(unit_id, 0))


func add_ct(unit_id: String, amount: int) -> void:
	if not _ct.has(unit_id):
		return
	_ct[unit_id] = int(_ct.get(unit_id, 0)) + amount


func next_actor() -> String:
	return _next_from(_ct, _speed)


func end_turn(unit_id: String, cost: int = THRESHOLD) -> void:
	if not _ct.has(unit_id):
		return
	_ct[unit_id] = int(_ct.get(unit_id, 0)) - cost


func preview(count: int) -> Array[String]:
	var result: Array[String] = []
	var ct := _ct.duplicate()
	var speeds := _speed.duplicate()
	for _i in range(count):
		var actor := _next_from(ct, speeds)
		if actor == "":
			break
		result.append(actor)
		ct[actor] = int(ct.get(actor, 0)) - THRESHOLD
	return result


func snapshot() -> Dictionary:
	return {
		"order": _order.duplicate(),
		"speed": _speed.duplicate(),
		"ct": _ct.duplicate(),
	}


func restore(data: Dictionary) -> void:
	var raw_order = data.get("order", [])
	var restored_order: Array[String] = []
	if raw_order is Array:
		for value in raw_order:
			restored_order.append(str(value))
	_order = restored_order
	var raw_speed = data.get("speed", {})
	_speed = raw_speed.duplicate() if raw_speed is Dictionary else {}
	var raw_ct = data.get("ct", {})
	_ct = raw_ct.duplicate() if raw_ct is Dictionary else {}


func _next_from(ct: Dictionary, speeds: Dictionary) -> String:
	if _order.is_empty():
		return ""
	var guard := 0
	while guard < 100000:
		var ready: Array[String] = []
		for unit_id in _order:
			if int(ct.get(unit_id, 0)) >= THRESHOLD:
				ready.append(unit_id)
		if not ready.is_empty():
			return _pick_from(ready, speeds)
		for unit_id in _order:
			ct[unit_id] = int(ct.get(unit_id, 0)) + ct_rate(int(speeds.get(unit_id, 0)))
		guard += 1
	return ""


func _pick_from(ready: Array[String], speeds: Dictionary) -> String:
	var best := ""
	var best_speed := -2147483648
	for unit_id in ready:
		var speed := int(speeds.get(unit_id, 0))
		if best == "" or speed > best_speed:
			best = unit_id
			best_speed = speed
	return best

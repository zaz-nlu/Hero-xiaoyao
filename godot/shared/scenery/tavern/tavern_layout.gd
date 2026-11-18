extends RefCounted

# 酒馆布局的静态数据/几何辅助：房间数值、家具状态的变换与可见性。


static func room_float(room: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = room.get(key, fallback)
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback


static func entry_float(entry: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = entry.get(key, fallback)
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback


static func transform_from_dict(entry_value: Variant) -> Transform3D:
	if not (entry_value is Dictionary):
		return Transform3D.IDENTITY
	var entry: Dictionary = entry_value
	var origin := Vector3.ZERO
	var pos_value: Variant = entry.get("pos", null)
	if pos_value is Array:
		var pos: Array = pos_value
		if pos.size() >= 3:
			origin = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	var basis := Basis.IDENTITY
	var rot_value: Variant = entry.get("rot", null)
	if rot_value is Array:
		var rot: Array = rot_value
		if rot.size() >= 3:
			var euler := Vector3(
				deg_to_rad(float(rot[0])),
				deg_to_rad(float(rot[1])),
				deg_to_rad(float(rot[2]))
			)
			basis = Basis.from_euler(euler)
	return Transform3D(basis, origin)


static func state_key(entry: Dictionary, s: String) -> String:
	if entry.has(s):
		return s
	if s != "normal" and entry.has("wrecked"):
		return "wrecked"
	return "normal"


static func transform_for(entry: Dictionary, s: String) -> Transform3D:
	var key: String = state_key(entry, s)
	var value: Variant = entry.get(key, null)
	if value is Dictionary:
		return transform_from_dict(value)
	var normal_value: Variant = entry.get("normal", null)
	return transform_from_dict(normal_value)


static func visible_for(entry: Dictionary, s: String) -> bool:
	var hidden_value: Variant = entry.get("hidden_in", [])
	if hidden_value is Array:
		var hidden: Array = hidden_value
		return not hidden.has(s)
	return true


# The wrecked table/bench art is already drawn fallen; cancel the node's wrecked
# tilt on that sprite so it reads upright once the transform animation ends.
static func wrecked_sprite_basis(entry: Dictionary) -> Basis:
	if entry.has("wrecked"):
		var target: Transform3D = transform_from_dict(entry.get("wrecked", {}))
		return target.basis.inverse()
	return Basis.IDENTITY

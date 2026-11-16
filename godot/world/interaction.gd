extends RefCounted

const RANGE := 2.4


static func nearest_npc(
	player_pos: Vector2, npc_positions: Dictionary, max_dist: float = RANGE
) -> String:
	var best_id: String = ""
	var best_dist: float = max_dist
	var found: bool = false
	for key in npc_positions.keys():
		var position_value: Variant = npc_positions[key]
		if not (position_value is Vector2):
			continue
		var npc_pos: Vector2 = position_value
		var dist: float = player_pos.distance_to(npc_pos)
		if dist <= max_dist and (not found or dist < best_dist):
			best_id = str(key)
			best_dist = dist
			found = true
	return best_id


static func load_npc_dialogues(path: String) -> Dictionary:
	var text: String = FileAccess.get_file_as_string(path)
	if text == "":
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {}
	var result: Dictionary = parsed
	return result

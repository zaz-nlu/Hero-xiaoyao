extends "res://tests/test_case.gd"

const TownData = preload("res://shared/resources/town_data.gd")
const Dialogue = preload("res://core/dialogue.gd")
const GameState = preload("res://core/game_state.gd")

const TOWN_PATH := "res://data/town.json"
const NPC_DIALOGUES_PATH := "res://data/npc_dialogues.json"
const SPEAKERS_PATH := "res://data/speakers.json"


func _new_town() -> Variant:
	var town: Variant = load("res://features/town/town.gd").new()
	town.build()
	town.build_hud()
	return town


func _finish_dialogue(town: Variant) -> void:
	for i in range(60):
		if not bool(town.dialogue_view.is_active()):
			return
		town.dialogue_view.advance()


func _town_data() -> Dictionary:
	return TownData.load_town(TOWN_PATH)["data"]


func _bounds_of(data: Dictionary) -> Rect2:
	var bounds: Dictionary = data.get("bounds", {})
	var x0 := float(bounds.get("x0", 0.0))
	var x1 := float(bounds.get("x1", 0.0))
	var z0 := float(bounds.get("z0", 0.0))
	var z1 := float(bounds.get("z1", 0.0))
	return Rect2(x0, z0, x1 - x0, z1 - z0)


func _in_rects(point: Vector2, rects: Array) -> bool:
	for rect_value in rects:
		if rect_value is Rect2:
			var rect: Rect2 = rect_value
			if rect.has_point(point):
				return true
	return false


func _npc_route(npc: Dictionary) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var wander_value: Variant = npc.get("wander", null)
	if not (wander_value is Dictionary):
		return result
	var wander: Dictionary = wander_value
	var route_value: Variant = wander.get("route", [])
	if not (route_value is Array):
		return result
	var route: Array = route_value
	for point_value in route:
		if not (point_value is Array):
			continue
		var point: Array = point_value
		if point.size() < 2:
			continue
		result.append(Vector2(float(point[0]), float(point[1])))
	return result


func _route_from_state(state: Dictionary) -> Array:
	return state.get("route", [])


func _distance_to_route(point: Vector2, route: Array) -> float:
	if route.is_empty():
		return 9999.0
	if route.size() == 1:
		var only: Vector2 = route[0]
		return point.distance_to(only)
	var best := 9999.0
	for i in range(route.size() - 1):
		var a: Vector2 = route[i]
		var b: Vector2 = route[i + 1]
		var closest := Geometry2D.get_closest_point_to_segment(point, a, b)
		best = minf(best, point.distance_to(closest))
	return best


func test_town_json_validates_with_new_npcs() -> void:
	var loaded: Dictionary = TownData.load_town(TOWN_PATH)
	assert_eq(loaded["errors"].size(), 0, str(loaded["errors"]))
	var data: Dictionary = loaded["data"]
	var npcs: Array = data.get("npcs", [])
	assert_true(npcs.size() >= 20, "the town has at least 20 npcs, got %d" % npcs.size())
	var buildings: Array = data.get("buildings", [])
	assert_eq(buildings.size(), 10, "ten buildings after the west expansion")


func test_npc_starts_and_routes_are_walkable() -> void:
	var data: Dictionary = _town_data()
	var bounds: Rect2 = _bounds_of(data)
	var blockers: Array = TownData.footprints(data)
	var npcs: Array = data.get("npcs", [])
	for npc_value in npcs:
		if not (npc_value is Dictionary):
			continue
		var npc: Dictionary = npc_value
		var id := str(npc.get("id", ""))
		var start := Vector2(float(npc.get("x", 0.0)), float(npc.get("z", 0.0)))
		assert_true(bounds.has_point(start), "npc %s start is inside bounds" % id)
		assert_true(not _in_rects(start, blockers), "npc %s start is not blocked" % id)
		var route: Array[Vector2] = _npc_route(npc)
		for point in route:
			assert_true(bounds.has_point(point), "npc %s route point is inside bounds" % id)
			assert_true(
				not _in_rects(point, blockers), "npc %s route point is not blocked" % id
			)


func test_npc_starts_are_spaced() -> void:
	var data: Dictionary = _town_data()
	var npcs: Array = data.get("npcs", [])
	for i in range(npcs.size()):
		var first: Dictionary = npcs[i]
		var first_pos := Vector2(float(first.get("x", 0.0)), float(first.get("z", 0.0)))
		for j in range(i + 1, npcs.size()):
			var second: Dictionary = npcs[j]
			var second_pos := Vector2(
				float(second.get("x", 0.0)), float(second.get("z", 0.0))
			)
			assert_true(
				first_pos.distance_to(second_pos) >= 1.2,
				"npcs %s and %s start at least 1.2 apart" % [
					str(first.get("id", "")), str(second.get("id", ""))
				]
			)


func test_every_npc_has_a_valid_dialogue() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(NPC_DIALOGUES_PATH))
	assert_true(parsed is Dictionary, "npc_dialogues.json is an object")
	if not (parsed is Dictionary):
		return
	var dialogues: Dictionary = parsed
	var speakers: Dictionary = Dialogue.load_speakers(SPEAKERS_PATH).get("defs", {})
	var data: Dictionary = _town_data()
	var npcs: Array = data.get("npcs", [])
	for npc_value in npcs:
		if not (npc_value is Dictionary):
			continue
		var npc: Dictionary = npc_value
		var id := str(npc.get("id", ""))
		assert_true(dialogues.has(id), "npc %s is registered in npc_dialogues.json" % id)
		if not dialogues.has(id):
			continue
		var entry_value: Variant = dialogues[id]
		if not (entry_value is Dictionary):
			assert_true(false, "npc %s dialogue entry is an object" % id)
			continue
		var entry: Dictionary = entry_value
		var paths: Array = []
		if entry.has("pool") and entry["pool"] is Array:
			paths = entry["pool"]
		elif entry.has("file"):
			paths.append(str(entry["file"]))
		assert_true(not paths.is_empty(), "npc %s has at least one dialogue file" % id)
		for path_value in paths:
			var loaded: Dictionary = Dialogue.load_file(str(path_value), speakers)
			var load_errors: Array = loaded.get("errors", [])
			var lines: Array = loaded.get("lines", [])
			assert_true(
				load_errors.is_empty(),
				"%s loads without errors: %s" % [str(path_value), str(load_errors)]
			)
			assert_true(lines.size() > 0, "%s has lines" % str(path_value))


func test_speakers_without_portraits_are_supported() -> void:
	var speakers: Dictionary = Dialogue.load_speakers(SPEAKERS_PATH).get("defs", {})
	for id in ["elder", "girl", "shopkeeper_m", "villager"]:
		assert_true(speakers.has(id), "speaker %s exists" % id)
		if speakers.has(id):
			var def: Dictionary = speakers[id]
			assert_eq(str(def.get("portrait", "")), "", "speaker %s has no portrait" % id)

	var view: Variant = load("res://shared/ui/dialogue_view.gd").new()
	view.build_ui()
	var loaded: Dictionary = Dialogue.load_file("res://data/dialogues/npc_elder.json", speakers)
	view.start(loaded.get("lines", []))
	assert_eq(str(view.name_label.text), "老者", "the portrait-less speaker still shows a name")
	assert_true(not bool(view.right_portrait.visible), "no right portrait is shown")
	assert_true(not bool(view.left_portrait.visible), "no left portrait is shown")
	view.free()


func test_wandering_npc_moves_along_route() -> void:
	GameState.reset()
	var town: Variant = _new_town()
	town.player_pos = Vector2(-60.0, 20.0)
	var waiter: Variant = town.npc_nodes["waiter"]
	var start := Vector2(waiter.position.x, waiter.position.z)
	var route: Array = _route_from_state(town.npc_wander["waiter"])
	var max_moved := 0.0
	for i in range(120):
		town.advance_npcs(0.1)
		var pos := Vector2(waiter.position.x, waiter.position.z)
		max_moved = maxf(max_moved, pos.distance_to(start))
		assert_true(
			_distance_to_route(pos, route) <= 0.3, "the waiter stays near its route"
		)
	assert_true(max_moved > 0.5, "the waiter actually walks, moved %.2f" % max_moved)
	town.free()


func test_wandering_npc_stops_near_player() -> void:
	GameState.reset()
	var town: Variant = _new_town()
	town.player_pos = Vector2(-60.0, 20.0)
	for i in range(30):
		town.advance_npcs(0.1)
	var waiter: Variant = town.npc_nodes["waiter"]
	var before := Vector2(waiter.position.x, waiter.position.z)
	town.player_pos = before + Vector2(1.0, 0.0)
	town.advance_npcs(0.5)
	var after := Vector2(waiter.position.x, waiter.position.z)
	assert_true(after.distance_to(before) < 0.001, "the waiter stops next to the player")
	assert_eq(str(waiter.facing), "right", "the waiter faces the player")
	town.free()


func test_villager_dialogue_pool_rotates() -> void:
	GameState.reset()
	var town: Variant = _new_town()
	var villager: Variant = town.npc_nodes["villager_1"]
	town.player_pos = Vector2(villager.position.x, villager.position.z)
	assert_true(town.try_interact(), "the first pool dialogue starts")
	assert_eq(str(town.current_npc_id), "villager_1", "the villager is the speaker")
	assert_true(
		str(town.dialogue_view.text_label.text).contains("酒馆"),
		"the first talk plays pool file a"
	)
	_finish_dialogue(town)

	town.player_pos = Vector2(villager.position.x, villager.position.z)
	assert_true(town.try_interact(), "the second pool dialogue starts")
	assert_true(
		str(town.dialogue_view.text_label.text).contains("紫霞派"),
		"the second talk rotates to pool file b"
	)
	_finish_dialogue(town)
	town.free()


func test_west_landmarks_exist() -> void:
	GameState.reset()
	var town: Variant = _new_town()
	for id in ["house_w2", "herb_shop", "tailor_shop", "house_w3"]:
		assert_true(
			town.find_child("Facade_%s" % id, true, false) != null,
			"Facade_%s exists" % id
		)
	assert_true(town.find_child("Well", true, false) != null, "the old well exists")
	assert_true(
		town.find_child("NoticeBoard", true, false) != null, "the notice board exists"
	)
	town.free()

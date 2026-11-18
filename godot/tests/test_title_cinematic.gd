extends "res://tests/test_case.gd"

const Cinematic = preload("res://features/title/title_cinematic.gd")
const Profile = preload("res://core/profile.gd")

const SHOTS_PATH := "res://data/title_shots.json"


func _temp_path(tag: String) -> String:
	return "user://test_cinematic_%s_%d.cfg" % [tag, Time.get_ticks_usec()]


func _cleanup_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _build_cinematic(path: String) -> Variant:
	var cinematic: Variant = Cinematic.new()
	cinematic.build(path)
	return cinematic


func _vec3(value: Variant) -> Vector3:
	var array: Array = value
	return Vector3(float(array[0]), float(array[1]), float(array[2]))


func _places(shot_list: Array) -> Array:
	var result: Array = []
	for shot_value in shot_list:
		var shot: Dictionary = shot_value
		result.append(str(shot.get("place", "")))
	return result


func test_default_profile_plays_town_far_and_tavern_outside() -> void:
	var path := _temp_path("defaults")
	var cinematic: Variant = _build_cinematic(path)
	assert_true(bool(cinematic.is_fallback()), "headless builds run in fallback mode")
	assert_eq(cinematic.shots.size(), 2, "only the always places have shots")
	assert_eq(str(cinematic.current_shot().get("id", "")), "town_far", "the reel starts far out")
	assert_eq(cinematic.caption_text(), "紫霞镇", "the first caption is the town")
	cinematic.free()
	_cleanup_file(path)


func test_newly_unlocked_place_appears_after_a_full_loop() -> void:
	var path := _temp_path("reload")
	var cinematic: Variant = _build_cinematic(path)
	assert_eq(cinematic.shots.size(), 2, "two shots before the unlock")
	assert_true(Profile.unlock("forest", path), "forest unlocks mid-session")
	cinematic.skip_to_next()
	cinematic.skip_to_next()
	assert_eq(cinematic.current_index, 0, "the reel wraps to the first shot")
	assert_true(
		_places(cinematic.shots).has("forest"),
		"the new place is picked up after the loop reloads the profile"
	)
	cinematic.free()
	_cleanup_file(path)


func test_pose_starts_at_from_and_ends_at_to() -> void:
	var path := _temp_path("pose")
	var cinematic: Variant = _build_cinematic(path)
	var shot: Dictionary = cinematic.current_shot()
	var from_data: Dictionary = shot.get("from", {})
	var to_data: Dictionary = shot.get("to", {})
	var pose: Dictionary = cinematic.camera_pose()
	var pose_pos: Vector3 = pose["pos"]
	var pose_look: Vector3 = pose["look"]
	assert_near(pose_pos.distance_to(_vec3(from_data.get("pos"))), 0.0)
	assert_near(pose_look.distance_to(_vec3(from_data.get("look"))), 0.0)
	assert_near(float(pose["fov"]), float(from_data.get("fov", 30.0)))

	cinematic.advance(float(shot.get("duration", 11.0)))
	var end_pose: Dictionary = cinematic.camera_pose()
	var end_pos: Vector3 = end_pose["pos"]
	var end_look: Vector3 = end_pose["look"]
	assert_near(end_pos.distance_to(_vec3(to_data.get("pos"))), 0.0)
	assert_near(end_look.distance_to(_vec3(to_data.get("look"))), 0.0)
	assert_near(float(end_pose["fov"]), float(to_data.get("fov", 30.0)))
	cinematic.free()
	_cleanup_file(path)


func test_camera_distance_is_monotonic() -> void:
	var path := _temp_path("monotonic")
	var cinematic: Variant = _build_cinematic(path)
	var shot: Dictionary = cinematic.current_shot()
	var from_data: Dictionary = shot.get("from", {})
	var start := _vec3(from_data.get("pos"))
	var duration := float(shot.get("duration", 11.0))
	var previous := 0.0
	var samples := int(round(duration / 0.1))
	for i in range(samples):
		cinematic.advance(0.1)
		var pose: Dictionary = cinematic.camera_pose()
		var pos: Vector3 = pose["pos"]
		var distance := pos.distance_to(start)
		assert_true(
			distance >= previous - 0.0001,
			"distance must not shrink at sample %d (%.4f -> %.4f)" % [i, previous, distance]
		)
		previous = distance
	assert_true(previous > 1.0, "the camera actually travels toward the subject")
	cinematic.free()
	_cleanup_file(path)


func test_fade_alpha_fades_in_and_out() -> void:
	var path := _temp_path("fade")
	var cinematic: Variant = _build_cinematic(path)
	assert_near(cinematic.fade_alpha(), 1.0, 0.0001, "the shot starts on black")
	cinematic.advance(0.4)
	assert_near(cinematic.fade_alpha(), 0.5, 0.0001, "black fades out over 0.8s")
	cinematic.advance(0.4)
	assert_near(cinematic.fade_alpha(), 0.0, 0.0001, "the middle of the shot is clear")
	cinematic.advance(2.0)
	assert_near(cinematic.fade_alpha(), 0.0, 0.0001, "the shot stays clear")

	var duration := float(cinematic.current_shot().get("duration", 11.0))
	cinematic.advance(duration - 0.4 - 2.8)
	assert_near(cinematic.fade_alpha(), 0.5, 0.0001, "black fades back in for the last 0.8s")
	cinematic.advance(0.4)
	assert_near(cinematic.fade_alpha(), 1.0, 0.0001, "the shot ends fully black")
	cinematic.free()
	_cleanup_file(path)


func test_caption_updates_on_switch_and_skip_loops() -> void:
	var path := _temp_path("caption")
	var cinematic: Variant = _build_cinematic(path)
	assert_eq(cinematic.caption_text(), "紫霞镇", "the first shot names the town")
	cinematic.skip_to_next()
	assert_eq(cinematic.current_index, 1, "skip_to_next moves forward")
	assert_eq(cinematic.caption_text(), "紫霞镇·酒馆", "the caption follows the shot")
	cinematic.skip_to_next()
	assert_eq(cinematic.current_index, 0, "a full round returns to the first shot")
	assert_eq(cinematic.caption_text(), "紫霞镇", "the caption resets with the loop")
	cinematic.free()
	_cleanup_file(path)


func test_every_shot_place_exists_in_profile() -> void:
	assert_true(FileAccess.file_exists(SHOTS_PATH), "the shot table exists")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SHOTS_PATH))
	assert_true(parsed is Dictionary, "the shot table is valid JSON")
	var known: Array = []
	for place_value in Profile.PLACES:
		var place: Dictionary = place_value
		known.append(str(place.get("id", "")))
	if parsed is Dictionary:
		var table: Dictionary = parsed
		var shots_value: Variant = table.get("shots", [])
		assert_true(shots_value is Array, "shots is an array")
		if shots_value is Array:
			var shot_list: Array = shots_value
			assert_true(not shot_list.is_empty(), "the shot table is not empty")
			for shot_value in shot_list:
				var shot: Dictionary = shot_value
				assert_true(
					known.has(str(shot.get("place", ""))),
					"shot %s uses a known place" % str(shot.get("id", ""))
				)

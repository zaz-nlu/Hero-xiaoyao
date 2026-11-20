extends "res://tests/test_case.gd"

const OpeningData = preload("res://core/opening_data.gd")
const OpeningBackdrop = preload("res://features/opening/opening_backdrop.gd")
const OpeningBattlefield = preload("res://features/opening/opening_battlefield.gd")
const OpeningSequence = preload("res://features/opening/opening_sequence.gd")

const SKY_FILES := {
	"ash": "bg_battle_ash.png",
	"dawn": "bg_battle_dawn.png",
	"dusk": "bg_battle_dusk.png",
	"gold": "bg_battle_gold.png",
}


func _storyteller() -> Dictionary:
	var data := OpeningData.load_opening()
	var value: Variant = data.get("storyteller", {})
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}


func _valid_data(backdrop: Dictionary) -> Dictionary:
	return {
		"music": {"intro": "opening_empire", "town": "opening_town"},
		"slides": [
			{"id": "s1", "seconds": 2.0, "lines": ["一句"], "backdrop": backdrop},
		],
		"storyteller": _storyteller(),
	}


func _errors_text(result: Dictionary) -> String:
	var text := ""
	for message in result.get("errors", []):
		text += str(message) + "\n"
	return text


func _field(seed: int, palette: String = "ash", density: int = 4,
		seconds: float = 8.0) -> Variant:
	var field: Variant = OpeningBattlefield.new()
	field.build(
		{"kind": "battlefield", "seed": seed, "palette": palette, "density": density},
		seconds
	)
	return field


func _art_slide(seconds: float = 4.0, zoom: float = 1.2) -> Dictionary:
	return {
		"id": "a1",
		"seconds": seconds,
		"lines": ["一句"],
		"backdrop": {"kind": "art", "image": "opening_duel_art.png", "zoom": zoom},
	}


func test_opening_json_accepts_art_backdrop() -> void:
	var data := OpeningData.load_opening()
	assert_true(bool(data.get("ok", false)), "the shipped opening.json validates")
	var found := false
	var slides_value: Variant = data.get("slides", [])
	var slides: Array = slides_value if slides_value is Array else []
	for slide_value in slides:
		var slide: Dictionary = slide_value
		var backdrop: Dictionary = slide.get("backdrop", {})
		if str(backdrop.get("kind", "")) == "art":
			found = true
			assert_eq(str(backdrop.get("image", "")), "opening_duel_art.png")
			assert_true(float(backdrop.get("zoom", 1.1)) > 1.0, "art zoom is above 1")
	assert_true(found, "the prologue has an art slide")


func test_bad_backdrops_report_errors() -> void:
	var no_image := OpeningData.validate(_valid_data({"kind": "art"}))
	assert_true(not bool(no_image.get("ok", true)), "art without image is rejected")
	assert_true(_errors_text(no_image).contains("image"), "the error names image")

	var missing := OpeningData.validate(
		_valid_data({"kind": "art", "image": "missing_duel.png"})
	)
	assert_true(not bool(missing.get("ok", true)), "a missing art file is rejected")
	assert_true(_errors_text(missing).contains("missing_duel"), "the error names the file")

	var no_seed := OpeningData.validate(
		_valid_data({"kind": "battlefield", "palette": "ash", "density": 4})
	)
	assert_true(not bool(no_seed.get("ok", true)), "battlefield without seed is rejected")
	assert_true(_errors_text(no_seed).contains("seed"), "the error names seed")


func test_same_seed_builds_identical_scene() -> void:
	var first: Variant = _field(7)
	var second: Variant = _field(7)
	var third: Variant = _field(8)
	var left: Array = first.actor_snapshot()
	var right: Array = second.actor_snapshot()
	assert_eq(left.size(), right.size(), "same seed builds the same actor count")
	for index in range(left.size()):
		var a: Dictionary = left[index]
		var b: Dictionary = right[index]
		assert_eq(str(a["id"]), str(b["id"]), "actor ids match for the same seed")
		assert_true(
			(a["position"] as Vector3).is_equal_approx(b["position"]),
			"actor positions match for the same seed"
		)
	assert_true(str(left) != str(third.actor_snapshot()), "another seed builds a different scene")
	first.free()
	second.free()
	third.free()


func test_actor_counts_and_sides() -> void:
	var field: Variant = _field(11, "ash", 12)
	assert_eq(field.actor_count(), 48, "density pairs plus two ranks per pair")
	# 交锋的对子沿战线散开（中心线随机偏移），所以按两军整体判断：帝国兵整体在左、敌兵整体在右。
	var imperial_sum := 0.0
	var imperial_n := 0
	var enemy_sum := 0.0
	var enemy_n := 0
	for entry_value in field.actor_snapshot():
		var entry: Dictionary = entry_value
		var pos: Vector3 = entry["position"]
		if str(entry["side"]) == "imperial":
			imperial_sum += pos.x
			imperial_n += 1
		else:
			enemy_sum += pos.x
			enemy_n += 1
	assert_true(imperial_n > 0 and enemy_n > 0, "both armies are present")
	assert_true(imperial_sum / float(imperial_n) < enemy_sum / float(enemy_n) - 1.0,
		"the imperial army stands to the left of the enemy army")
	var crowded: Variant = _field(12, "dusk", 26)
	assert_true(crowded.actor_count() <= 90, "the battlefield never exceeds 90 actors")
	assert_eq(crowded.actor_count(), 88, "density is capped to the actor budget")
	field.free()
	crowded.free()


func test_every_palette_picks_its_sky() -> void:
	for palette in ["ash", "dawn", "dusk", "gold"]:
		var field: Variant = _field(3, palette, 4)
		assert_eq(field.sky_file(), str(SKY_FILES[palette]), "the sky matches the palette")
		assert_true(field.actor_count() > 0, "the palette builds actors")
		field.free()


func test_advance_moves_camera_and_actors() -> void:
	var field: Variant = _field(5, "dawn", 6, 8.0)
	var cam_before: Vector3 = field.camera_position()
	var pos_before: Array = field.actor_positions()
	field.advance(0.7)
	assert_true(
		not field.camera_position().is_equal_approx(cam_before), "the camera keeps moving"
	)
	var moved := false
	var pos_after: Array = field.actor_positions()
	for index in range(pos_before.size()):
		var before: Vector3 = pos_before[index]
		var after: Vector3 = pos_after[index]
		if not before.is_equal_approx(after):
			moved = true
	assert_true(moved, "fighter animation advances with time")
	field.free()


func test_art_backdrop_zooms_over_time() -> void:
	var backdrop: Variant = OpeningBackdrop.new()
	backdrop.apply(_art_slide(4.0, 1.2))
	assert_eq(str(backdrop.current_kind), "art", "the art slide selects the art layer")
	assert_true(backdrop.backdrop_node != null, "the art layer is built")
	assert_near(backdrop.art_zoom(), 1.0, 0.001, "the art starts at zoom 1")
	backdrop.advance(2.0)
	assert_true(backdrop.art_zoom() > 1.0, "the art slowly zooms in")
	backdrop.advance(10.0)
	assert_near(backdrop.art_zoom(), 1.2, 0.001, "the zoom stops at the configured target")
	backdrop.free()


func test_sequence_swaps_backgrounds_between_pages() -> void:
	var opening: Variant = OpeningSequence.new()
	opening.build(OpeningData.load_opening())
	var backdrop: Variant = opening._backdrop
	assert_eq(str(backdrop.current_kind), "battlefield", "the first page is a battlefield")
	var first: Node = backdrop.backdrop_node
	assert_true(first != null, "the first page builds a background")
	var lines: Array = (opening.current_slide() as Dictionary).get("lines", [])
	for index in range(lines.size() + 1):
		opening.skip_line()
	assert_eq(opening.page_index(), 1, "skipping the first page moves to the second")
	assert_true(not is_instance_valid(first), "the old background is released")
	assert_true(backdrop.backdrop_node != null, "the next page builds its own background")
	var seen := {"battlefield": true}
	var guard := 0
	while not opening.is_finished() and guard < 40:
		guard += 1
		var slide: Dictionary = opening.current_slide()
		var backdrop_data: Dictionary = slide.get("backdrop", {})
		var kind := str(backdrop_data.get("kind", ""))
		seen[kind] = true
		if kind == "black":
			assert_true(backdrop.backdrop_node == null, "the black page has no 3D layer")
		else:
			assert_true(backdrop.backdrop_node != null, "page kind %s has a background" % kind)
		var count: int = (slide.get("lines", []) as Array).size()
		for index in range(count + 1):
			opening.skip_line()
	assert_true(opening.is_finished(), "the skip walk finishes the sequence")
	assert_true(seen.has("art"), "the art page is visited")
	opening.free()


func test_headless_sequence_runs_without_errors() -> void:
	var opening: Variant = OpeningSequence.new()
	opening.build(OpeningData.load_opening())
	opening.advance(opening.total_duration())
	assert_true(opening.is_finished(), "the whole prologue runs headless")
	opening.free()

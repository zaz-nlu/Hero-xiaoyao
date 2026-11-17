extends "res://tests/test_case.gd"

const SpriteGen = preload("res://tools/sprite_gen.gd")

const DEF_PATH := "res://data/sprites/ren_xiaoyao.json"
const FRAME_W := 32
const FRAME_H := 48
const SHEET_W := 160
const SHEET_H := 192

const REN_SNAPSHOT_PATH := "res://tests/fixtures/ren_xiaoyao_procedural.png"
const CAST_PATHS := {
	"zixia": "res://data/sprites/zixia.json",
	"zixia_disciple": "res://data/sprites/zixia_disciple.json",
	"vendor": "res://data/sprites/vendor.json",
	"ma_youwei": "res://data/sprites/ma_youwei.json",
	"bandit": "res://data/sprites/bandit.json",
}
const CAST_IDS: Array[String] = ["zixia", "zixia_disciple", "vendor", "ma_youwei", "bandit"]


func _def() -> Dictionary:
	return SpriteGen.load_def(DEF_PATH)


func _bbox(img: Image) -> Rect2i:
	var min_x: int = img.get_width()
	var min_y: int = img.get_height()
	var max_x: int = -1
	var max_y: int = -1
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			if img.get_pixel(x, y).a <= 0.0:
				continue
			if x < min_x:
				min_x = x
			if x > max_x:
				max_x = x
			if y < min_y:
				min_y = y
			if y > max_y:
				max_y = y
	if max_x < min_x or max_y < min_y:
		return Rect2i(0, 0, 0, 0)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


func _count_opaque(img: Image) -> int:
	var count: int = 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			if img.get_pixel(x, y).a > 0.0:
				count += 1
	return count


func _color_key(color: Color) -> int:
	var r: int = int(round(color.r * 255.0))
	var g: int = int(round(color.g * 255.0))
	var b: int = int(round(color.b * 255.0))
	return (r << 16) | (g << 8) | b


func _palette_keys(def: Dictionary) -> Dictionary:
	var keys: Dictionary = {}
	var palette: Dictionary = def.get("palette", {})
	for key in palette.keys():
		var color: Color = palette[key]
		keys[_color_key(color)] = true
	return keys


func _img_diff(a: Image, b: Image) -> int:
	var diff: int = 0
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				diff += 1
	return diff


func test_sheet_size() -> void:
	var sheet: Image = SpriteGen.render_sheet(_def())
	assert_eq(sheet.get_width(), SHEET_W, "sheet width is 5 frames")
	assert_eq(sheet.get_height(), SHEET_H, "sheet height is 4 directions")


func test_frame_corners_transparent() -> void:
	var def: Dictionary = _def()
	for direction in range(4):
		for frame in range(5):
			var img: Image = SpriteGen.render_frame(def, direction, frame)
			assert_eq(img.get_pixel(0, 0).a, 0.0, "direction %d frame %d top-left" % [direction, frame])
			assert_eq(
				img.get_pixel(FRAME_W - 1, 0).a, 0.0,
				"direction %d frame %d top-right" % [direction, frame]
			)
			assert_eq(
				img.get_pixel(0, FRAME_H - 1).a, 0.0,
				"direction %d frame %d bottom-left" % [direction, frame]
			)
			assert_eq(
				img.get_pixel(FRAME_W - 1, FRAME_H - 1).a, 0.0,
				"direction %d frame %d bottom-right" % [direction, frame]
			)


func test_frame_has_content_within_margin() -> void:
	var def: Dictionary = _def()
	for direction in range(4):
		for frame in range(5):
			var img: Image = SpriteGen.render_frame(def, direction, frame)
			var box: Rect2i = _bbox(img)
			assert_true(box.size.x > 0, "direction %d frame %d has content" % [direction, frame])
			assert_true(
				box.position.x >= 1, "direction %d frame %d stays right of the margin" % [direction, frame]
			)
			assert_true(
				box.position.y >= 1, "direction %d frame %d stays below the margin" % [direction, frame]
			)
			assert_true(
				box.position.x + box.size.x - 1 <= 30,
				"direction %d frame %d stays left of the margin" % [direction, frame]
			)
			assert_true(
				box.position.y + box.size.y - 1 <= 46,
				"direction %d frame %d stays above the margin" % [direction, frame]
			)
			assert_true(
				_count_opaque(img) > 300, "direction %d frame %d has a full body" % [direction, frame]
			)


func test_only_palette_colors() -> void:
	var def: Dictionary = _def()
	var allowed: Dictionary = _palette_keys(def)
	for direction in range(4):
		for frame in range(5):
			var img: Image = SpriteGen.render_frame(def, direction, frame)
			var ok: bool = true
			for y in range(FRAME_H):
				for x in range(FRAME_W):
					var color: Color = img.get_pixel(x, y)
					if color.a <= 0.0:
						continue
					if not allowed.has(_color_key(color)):
						ok = false
			assert_true(ok, "direction %d frame %d uses palette colours only" % [direction, frame])


func test_left_is_mirror_of_right() -> void:
	var def: Dictionary = _def()
	for frame in range(5):
		var right: Image = SpriteGen.render_frame(def, 2, frame)
		var left: Image = SpriteGen.render_frame(def, 3, frame)
		var ok: bool = true
		for y in range(FRAME_H):
			for x in range(FRAME_W):
				if left.get_pixel(x, y) != right.get_pixel(FRAME_W - 1 - x, y):
					ok = false
		assert_true(ok, "left frame %d is the mirror of the right frame" % frame)


func test_walk_frames_differ() -> void:
	var def: Dictionary = _def()
	var frame_0: Image = SpriteGen.render_frame(def, 0, 0)
	var frame_1: Image = SpriteGen.render_frame(def, 0, 1)
	var frame_3: Image = SpriteGen.render_frame(def, 0, 3)
	assert_true(_img_diff(frame_0, frame_1) > 0, "frame 0 and frame 1 are not identical")
	assert_true(_img_diff(frame_1, frame_3) > 10, "frame 1 and frame 3 differ by more than 10 pixels")


func test_transition_frames_bob_up() -> void:
	var def: Dictionary = _def()
	var frame_0: Image = SpriteGen.render_frame(def, 0, 0)
	var frame_2: Image = SpriteGen.render_frame(def, 0, 2)
	var box_0: Rect2i = _bbox(frame_0)
	var box_2: Rect2i = _bbox(frame_2)
	assert_eq(box_2.position.y, box_0.position.y - 1, "transition frame is one pixel higher")


func test_deterministic() -> void:
	var def: Dictionary = _def()
	var first: Image = SpriteGen.render_sheet(def)
	var second: Image = SpriteGen.render_sheet(def)
	assert_true(first.get_data() == second.get_data(), "render_sheet is deterministic")


func test_unknown_hair_style_is_skipped_not_fatal() -> void:
	var def: Dictionary = _def()
	def["hair_style"] = "nope"
	var sheet: Image = SpriteGen.render_sheet(def)
	assert_eq(sheet.get_width(), SHEET_W, "unknown hair style still renders a sheet")
	assert_eq(sheet.get_height(), SHEET_H, "unknown hair style keeps the sheet height")
	assert_true(_count_opaque(sheet) > 0, "unknown hair style still draws the base body")


func test_eyes_visible_in_front_view() -> void:
	var def: Dictionary = _def()
	var palette: Dictionary = def["palette"]
	var eye: Color = palette["eye"]
	var eye_key: int = _color_key(eye)
	var front: Image = SpriteGen.render_frame(def, 0, 0)
	var back: Image = SpriteGen.render_frame(def, 1, 0)
	assert_eq(_color_key(front.get_pixel(12, 11)), eye_key, "left eye is visible in the front view")
	assert_eq(_color_key(front.get_pixel(18, 11)), eye_key, "right eye is visible in the front view")
	assert_true(_color_key(back.get_pixel(12, 11)) != eye_key, "back view hides the left eye")
	assert_true(_color_key(back.get_pixel(18, 11)) != eye_key, "back view hides the right eye")


func _cast_def(id: String) -> Dictionary:
	return SpriteGen.load_def(CAST_PATHS[id])


func _sheet_hash(img: Image) -> int:
	var h: int = 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			h = (h * 31 + img.get_pixel(x, y).to_rgba32()) % 2147483648
	return h


func _has_key(img: Image, key: int) -> bool:
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var color: Color = img.get_pixel(x, y)
			if color.a > 0.0 and _color_key(color) == key:
				return true
	return false


func test_ren_xiaoyao_unchanged() -> void:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(REN_SNAPSHOT_PATH)
	assert_true(bytes.size() > 0, "ren_xiaoyao snapshot exists")
	if bytes.is_empty():
		return
	var golden: Image = Image.new()
	var err: Error = golden.load_png_from_buffer(bytes)
	assert_eq(err, OK, "ren_xiaoyao snapshot decodes")
	var sheet: Image = SpriteGen.render_sheet(_def())
	assert_eq(sheet.get_width(), golden.get_width(), "snapshot width matches the render")
	assert_eq(sheet.get_height(), golden.get_height(), "snapshot height matches the render")
	assert_eq(_sheet_hash(sheet), _sheet_hash(golden), "ren_xiaoyao output is unchanged")


func test_all_cast_defs_load() -> void:
	for id in CAST_IDS:
		var def: Dictionary = _cast_def(id)
		assert_true(not def.is_empty(), "%s loads" % id)
		var sheet: Image = SpriteGen.render_sheet(def)
		assert_eq(sheet.get_width(), SHEET_W, "%s sheet width" % id)
		assert_eq(sheet.get_height(), SHEET_H, "%s sheet height" % id)


func test_cast_frames_within_margin_and_nonempty() -> void:
	for id in CAST_IDS:
		var def: Dictionary = _cast_def(id)
		for direction in range(4):
			for frame in range(5):
				var img: Image = SpriteGen.render_frame(def, direction, frame)
				var tag: String = "%s direction %d frame %d" % [id, direction, frame]
				assert_eq(img.get_pixel(0, 0).a, 0.0, tag + " top-left")
				assert_eq(img.get_pixel(FRAME_W - 1, 0).a, 0.0, tag + " top-right")
				assert_eq(img.get_pixel(0, FRAME_H - 1).a, 0.0, tag + " bottom-left")
				assert_eq(img.get_pixel(FRAME_W - 1, FRAME_H - 1).a, 0.0, tag + " bottom-right")
				var box: Rect2i = _bbox(img)
				assert_true(box.size.x > 0, tag + " has content")
				assert_true(box.position.x >= 1, tag + " stays right of the margin")
				assert_true(box.position.y >= 1, tag + " stays below the margin")
				assert_true(box.position.x + box.size.x - 1 <= 30, tag + " stays left of the margin")
				assert_true(box.position.y + box.size.y - 1 <= 46, tag + " stays above the margin")
				assert_true(_count_opaque(img) > 300, tag + " has a full body")


func test_cast_only_palette_colors() -> void:
	for id in CAST_IDS:
		var def: Dictionary = _cast_def(id)
		var allowed: Dictionary = _palette_keys(def)
		for direction in range(4):
			for frame in range(5):
				var img: Image = SpriteGen.render_frame(def, direction, frame)
				var ok: bool = true
				for y in range(FRAME_H):
					for x in range(FRAME_W):
						var color: Color = img.get_pixel(x, y)
						if color.a <= 0.0:
							continue
						if not allowed.has(_color_key(color)):
							ok = false
				assert_true(
					ok,
					"%s direction %d frame %d uses palette colours only" % [id, direction, frame]
				)


func test_cast_left_is_mirror_of_right() -> void:
	for id in CAST_IDS:
		var def: Dictionary = _cast_def(id)
		for frame in range(5):
			var right: Image = SpriteGen.render_frame(def, 2, frame)
			var left: Image = SpriteGen.render_frame(def, 3, frame)
			var ok: bool = true
			for y in range(FRAME_H):
				for x in range(FRAME_W):
					if left.get_pixel(x, y) != right.get_pixel(FRAME_W - 1 - x, y):
						ok = false
			assert_true(ok, "%s left frame %d mirrors the right frame" % [id, frame])


func test_stocky_is_wider_than_normal() -> void:
	var wide: Image = SpriteGen.render_frame(_cast_def("ma_youwei"), 0, 0)
	var normal: Image = SpriteGen.render_frame(_cast_def("zixia_disciple"), 0, 0)
	assert_true(
		_bbox(wide).size.x >= _bbox(normal).size.x + 2,
		"stocky ma_youwei is at least two pixels wider than a normal build"
	)


func test_fur_collar_changes_pixels() -> void:
	var def: Dictionary = _cast_def("ma_youwei")
	var with_fur: Image = SpriteGen.render_frame(def, 0, 0)
	var stripped: Dictionary = def.duplicate(true)
	stripped["features"] = ["beard"]
	var without_fur: Image = SpriteGen.render_frame(stripped, 0, 0)
	assert_true(_img_diff(with_fur, without_fur) > 0, "fur collar changes the front pixels")
	assert_true(_has_key(with_fur, _color_key(def["palette"]["fur"])), "fur colour is drawn")


func test_beard_appears_front_only() -> void:
	var def: Dictionary = _cast_def("vendor")
	var beard_key: int = _color_key(def["palette"]["beard"])
	var front: Image = SpriteGen.render_frame(def, 0, 0)
	var back: Image = SpriteGen.render_frame(def, 1, 0)
	assert_true(_has_key(front, beard_key), "beard colour is visible in the front view")
	assert_true(not _has_key(back, beard_key), "beard is not drawn in the back view")


func test_robe_long_hides_legs() -> void:
	var def: Dictionary = _cast_def("zixia")
	var img: Image = SpriteGen.render_frame(def, 0, 0)
	var pants_key: int = _color_key(def["palette"]["pants"])
	for y in range(36, 41):
		for x in range(12, 20):
			assert_true(
				_color_key(img.get_pixel(x, y)) != pants_key,
				"zixia robe covers legs at %d,%d" % [x, y]
			)


func test_blade_shoulder_visible() -> void:
	var def: Dictionary = _cast_def("bandit")
	var img: Image = SpriteGen.render_frame(def, 0, 0)
	assert_true(_has_key(img, _color_key(def["palette"]["blade"])), "shoulder blade is visible")


func test_distinct_silhouettes() -> void:
	# ren_xiaoyao shares its exact geometry with zixia_disciple, so the five new
	# characters are the ones that can be pairwise distinct.
	var counts: Array[int] = []
	for id in CAST_IDS:
		counts.append(_count_opaque(SpriteGen.render_frame(_cast_def(id), 0, 0)))
	for i in range(counts.size()):
		for j in range(i + 1, counts.size()):
			assert_true(
				counts[i] != counts[j],
				"%s and %s silhouettes differ" % [CAST_IDS[i], CAST_IDS[j]]
			)

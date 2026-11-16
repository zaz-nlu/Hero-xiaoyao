extends "res://tests/test_case.gd"

const Pixelizer = preload("res://tools/pixelizer.gd")

const RECT_LEFT := 70
const RECT_TOP := 50
const RECT_WIDTH := 60
const RECT_HEIGHT := 100
const TOL := 40.0


func _synthetic(with_speck: bool = false) -> Image:
	var img: Image = Image.create_empty(200, 200, false, Image.FORMAT_RGBA8)
	img.fill(Color8(200, 190, 180))
	for y in range(RECT_TOP, RECT_TOP + RECT_HEIGHT):
		for x in range(RECT_LEFT, RECT_LEFT + RECT_WIDTH):
			img.set_pixel(x, y, Color8(200, 30, 30))
	if with_speck:
		for y in range(20, 22):
			for x in range(20, 22):
				img.set_pixel(x, y, Color8(20, 20, 20))
	return img


func _cropped() -> Image:
	return Pixelizer.crop_to_content(Pixelizer.extract_foreground(_synthetic(false), TOL))


func _count_opaque(img: Image) -> int:
	var count: int = 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			if img.get_pixel(x, y).a > 0.0:
				count += 1
	return count


func _is_source_opaque(src: Image, outline_x: int, outline_y: int) -> bool:
	var sx: int = outline_x - 1
	var sy: int = outline_y - 1
	if sx < 0 or sy < 0 or sx >= src.get_width() or sy >= src.get_height():
		return false
	return src.get_pixel(sx, sy).a > 0.0


func test_extract_foreground_removes_paper_background() -> void:
	var cut: Image = Pixelizer.extract_foreground(_synthetic(false), TOL)
	assert_eq(cut.get_pixel(0, 0).a, 0.0, "top-left corner is transparent")
	assert_eq(cut.get_pixel(199, 0).a, 0.0, "top-right corner is transparent")
	assert_eq(cut.get_pixel(0, 199).a, 0.0, "bottom-left corner is transparent")
	assert_eq(cut.get_pixel(199, 199).a, 0.0, "bottom-right corner is transparent")
	assert_eq(cut.get_pixel(100, 100).a, 1.0, "rectangle centre is opaque")
	assert_near(float(_count_opaque(cut)), 6000.0, 60.0, "only the rectangle survives")


func test_extract_foreground_drops_tiny_specks() -> void:
	var cut: Image = Pixelizer.extract_foreground(_synthetic(true), TOL)
	assert_eq(cut.get_pixel(20, 20).a, 0.0, "2x2 speck is dropped")
	assert_eq(cut.get_pixel(21, 21).a, 0.0, "every speck pixel is dropped")


func test_crop_to_content_matches_bounding_box() -> void:
	var cropped: Image = _cropped()
	assert_eq(cropped.get_width(), 60, "cropped width matches the rectangle")
	assert_eq(cropped.get_height(), 100, "cropped height matches the rectangle")


func test_resize_to_height_keeps_aspect() -> void:
	var resized: Image = Pixelizer.resize_to_height(_cropped(), 50)
	assert_eq(resized.get_height(), 50, "height matches the request")
	assert_eq(resized.get_width(), 30, "width keeps the aspect ratio")
	var binary_alpha: bool = true
	for y in range(resized.get_height()):
		for x in range(resized.get_width()):
			var alpha: float = resized.get_pixel(x, y).a
			if alpha != 0.0 and alpha != 1.0:
				binary_alpha = false
	assert_true(binary_alpha, "resized alpha is binary")


func test_no_background_fringe_after_resize() -> void:
	var resized: Image = Pixelizer.resize_to_height(_cropped(), 50)
	var all_red: bool = true
	for y in range(resized.get_height()):
		for x in range(resized.get_width()):
			var color: Color = resized.get_pixel(x, y)
			if color.a <= 0.0:
				continue
			if not (color.r * 255.0 > color.g * 255.0 + 80.0):
				all_red = false
	assert_true(all_red, "no paper colour bleeds into opaque pixels")


func test_quantize_limits_colors() -> void:
	var img: Image = Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(64):
			var t: float = float(x) / 63.0
			img.set_pixel(x, y, Color(1.0 - t, 0.2 * (1.0 - t) * t * 4.0, t, 1.0))
	var quantized: Image = Pixelizer.quantize(img, 8)
	assert_true(
		Pixelizer.count_unique_opaque_colors(quantized) <= 8,
		"quantize keeps at most the requested number of colours"
	)


func test_outline_grows_by_one_pixel_and_is_adjacent() -> void:
	var resized: Image = Pixelizer.resize_to_height(_cropped(), 50)
	var outline_color: Color = Color(1.0, 0.0, 1.0, 1.0)
	var outlined: Image = Pixelizer.add_outline(resized, outline_color)
	assert_eq(outlined.get_width(), resized.get_width() + 2, "outline adds one pixel on each side")
	assert_eq(outlined.get_height(), resized.get_height() + 2, "outline adds one pixel on top and bottom")
	assert_eq(outlined.get_pixel(1, 1), resized.get_pixel(0, 0), "original pixels keep their colour")

	var adjacent_ok: bool = true
	for y in range(outlined.get_height()):
		for x in range(outlined.get_width()):
			if outlined.get_pixel(x, y) != outline_color:
				continue
			var touches: bool = _is_source_opaque(resized, x - 1, y) \
					or _is_source_opaque(resized, x + 1, y) \
					or _is_source_opaque(resized, x, y - 1) \
					or _is_source_opaque(resized, x, y + 1)
			if not touches:
				adjacent_ok = false
	assert_true(adjacent_ok, "every outline pixel touches an opaque source pixel")


func test_process_end_to_end_height() -> void:
	var result: Image = Pixelizer.process(_synthetic(false), 40, 8, TOL)
	assert_eq(result.get_height(), 42, "processed height is the content height plus the outline")
	assert_true(
		Pixelizer.count_unique_opaque_colors(result) <= 9,
		"processed colours are the palette plus the outline colour"
	)

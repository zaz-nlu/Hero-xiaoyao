extends "res://tests/test_case.gd"

const Portrait = preload("res://tools/portrait_lib.gd")

const CANVAS_WIDTH := 200
const CANVAS_HEIGHT := 300
const SUBJECT_WIDTH := 80
const SUBJECT_HEIGHT := 200
const TOL := 40.0


# Ellipse with an 80x200 bounding box. A filled rectangle would fill its own
# crop bounding box completely, so the cropped image would have no transparent
# pixels and the resized corners could never be transparent.
func _synthetic() -> Image:
	var img: Image = Image.create_empty(CANVAS_WIDTH, CANVAS_HEIGHT, false, Image.FORMAT_RGBA8)
	img.fill(Color8(200, 190, 180))
	var center_x: float = float(CANVAS_WIDTH) * 0.5
	var center_y: float = float(CANVAS_HEIGHT) * 0.5
	var radius_x: float = float(SUBJECT_WIDTH) * 0.5
	var radius_y: float = float(SUBJECT_HEIGHT) * 0.5
	for y in range(CANVAS_HEIGHT):
		for x in range(CANVAS_WIDTH):
			var nx: float = (float(x) + 0.5 - center_x) / radius_x
			var ny: float = (float(y) + 0.5 - center_y) / radius_y
			if nx * nx + ny * ny <= 1.0:
				img.set_pixel(x, y, Color8(200, 30, 30))
	return img


func test_make_portrait_output_height() -> void:
	var result: Image = Portrait.make_portrait(_synthetic(), 100, TOL, 1)
	assert_eq(result.get_height(), 100, "output height matches the request")
	assert_eq(result.get_width(), 40, "output width keeps the subject aspect ratio")
	assert_eq(result.get_pixel(0, 0).a, 0.0, "top-left corner is transparent")
	assert_eq(result.get_pixel(result.get_width() - 1, 0).a, 0.0, "top-right corner is transparent")
	assert_eq(result.get_pixel(0, result.get_height() - 1).a, 0.0, "bottom-left corner is transparent")
	assert_eq(result.get_pixel(result.get_width() - 1, result.get_height() - 1).a, 0.0, "bottom-right corner is transparent")


func test_make_portrait_keeps_subject_color() -> void:
	var result: Image = Portrait.make_portrait(_synthetic(), 100, TOL, 1)
	var center: Color = result.get_pixel(result.get_width() >> 1, result.get_height() >> 1)
	assert_true(
		center.r * 255.0 > center.g * 255.0 + 80.0,
		"subject keeps its red colour"
	)


func test_make_portrait_feather_zero_is_binary() -> void:
	var result: Image = Portrait.make_portrait(_synthetic(), 77, TOL, 0)
	var binary_alpha: bool = true
	for y in range(result.get_height()):
		for x in range(result.get_width()):
			var alpha: float = result.get_pixel(x, y).a
			if not is_equal_approx(alpha, 0.0) and not is_equal_approx(alpha, 1.0):
				binary_alpha = false
	assert_true(binary_alpha, "feather 0 leaves only fully transparent or fully opaque pixels")


func test_make_portrait_feather_one_has_soft_edge() -> void:
	var result: Image = Portrait.make_portrait(_synthetic(), 77, TOL, 1)
	var soft_edge: bool = false
	for y in range(result.get_height()):
		for x in range(result.get_width()):
			var alpha: float = result.get_pixel(x, y).a
			if alpha > 0.0 and alpha < 1.0:
				soft_edge = true
				break
		if soft_edge:
			break
	assert_true(soft_edge, "feather 1 keeps the smooth alpha produced by resizing")

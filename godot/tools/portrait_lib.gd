extends RefCounted

const Pixelizer = preload("res://tools/pixelizer.gd")


static func make_portrait(img: Image, height: int, tol: float, feather: int) -> Image:
	var work: Image = Pixelizer.extract_foreground(img, tol)
	work = Pixelizer.crop_to_content(work)
	var w: int = work.get_width()
	var h: int = work.get_height()
	if w == 0 or h == 0 or height <= 0:
		return work
	var target_w: int = maxi(1, int(round(float(w) * float(height) / float(h))))
	work.resize(target_w, height, Image.INTERPOLATE_LANCZOS)
	if feather <= 0:
		_binarize_alpha(work)
	return work


static func _binarize_alpha(img: Image) -> void:
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var color: Color = img.get_pixel(x, y)
			color.a = 1.0 if color.a >= 0.5 else 0.0
			img.set_pixel(x, y, color)

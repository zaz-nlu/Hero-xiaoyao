extends RefCounted

const FRAME_W := 32
const FRAME_H := 48
const SHEET_COLS := 5
const SHEET_ROWS := 4

const HAIR_PONYTAIL_RIBBON := "ponytail_ribbon"
const PROP_SWORD_HIP := "sword_hip"


static func load_def(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text: String = FileAccess.get_file_as_string(path)
	if text == "":
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var raw: Dictionary = parsed
	if typeof(raw.get("palette", null)) != TYPE_DICTIONARY:
		return {}
	var raw_palette: Dictionary = raw["palette"]
	var palette: Dictionary = {}
	for key in raw_palette.keys():
		var value: Variant = raw_palette[key]
		if typeof(value) == TYPE_STRING:
			palette[str(key)] = Color.from_string(str(value), Color(1.0, 0.0, 1.0, 1.0))
		elif typeof(value) == TYPE_COLOR:
			palette[str(key)] = value
	var def: Dictionary = raw.duplicate(true)
	def["palette"] = palette
	return def


static func render_frame(def: Dictionary, direction: int, frame: int) -> Image:
	var img: Image = Image.create_empty(FRAME_W, FRAME_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	var palette_value: Variant = def.get("palette", {})
	if typeof(palette_value) != TYPE_DICTIONARY:
		return img
	var palette: Dictionary = palette_value
	if palette.is_empty():
		return img

	var ponytail: bool = false
	var hair_style: String = str(def.get("hair_style", ""))
	if hair_style == HAIR_PONYTAIL_RIBBON:
		ponytail = true
	elif hair_style != "":
		push_warning("sprite_gen: unsupported hair_style '%s', skipping" % hair_style)

	var sword: bool = false
	var props_value: Variant = def.get("props", [])
	if typeof(props_value) == TYPE_ARRAY:
		var props: Array = props_value
		for prop in props:
			var prop_name: String = str(prop)
			if prop_name == PROP_SWORD_HIP:
				sword = true
			elif prop_name != "":
				push_warning("sprite_gen: unsupported prop '%s', skipping" % prop_name)

	var bob: int = 1 if frame == 2 or frame == 4 else 0
	match direction:
		0:
			_draw_down(img, palette, frame, bob, ponytail, sword)
		1:
			_draw_up(img, palette, frame, bob, ponytail, sword)
		2:
			_draw_right(img, palette, frame, bob, ponytail, sword)
		_:
			_draw_right(img, palette, frame, bob, ponytail, sword)

	_outline(img, _color(palette, "outline"))
	if direction == 3:
		return _flip_h(img)
	return img


static func render_sheet(def: Dictionary) -> Image:
	var sheet: Image = Image.create_empty(
		FRAME_W * SHEET_COLS, FRAME_H * SHEET_ROWS, false, Image.FORMAT_RGBA8
	)
	sheet.fill(Color(0.0, 0.0, 0.0, 0.0))
	for direction in range(SHEET_ROWS):
		for frame in range(SHEET_COLS):
			var img: Image = render_frame(def, direction, frame)
			sheet.blit_rect(
				img,
				Rect2i(0, 0, FRAME_W, FRAME_H),
				Vector2i(frame * FRAME_W, direction * FRAME_H)
			)
	return sheet


static func _draw_down(
	img: Image, palette: Dictionary, frame: int, bob: int, ponytail: bool, sword: bool
) -> void:
	var hair: Color = _color(palette, "hair")
	var hair_shade: Color = _color(palette, "hair_shade")
	var skin: Color = _color(palette, "skin")
	var skin_shade: Color = _color(palette, "skin_shade")
	var ribbon: Color = _color(palette, "ribbon")
	var eye: Color = _color(palette, "eye")
	var mouth: Color = _color(palette, "mouth")
	var top: Color = _color(palette, "top")
	var top_shade: Color = _color(palette, "top_shade")
	var shirt: Color = _color(palette, "shirt")
	var shirt_shade: Color = _color(palette, "shirt_shade")
	var sash: Color = _color(palette, "sash")
	var pants: Color = _color(palette, "pants")
	var pants_shade: Color = _color(palette, "pants_shade")
	var boots: Color = _color(palette, "boots")
	var boots_shade: Color = _color(palette, "boots_shade")
	var band: Color = _color(palette, "band")
	var scabbard: Color = _color(palette, "scabbard")
	var gold: Color = _color(palette, "gold")

	if ponytail:
		_rect(img, 21, 3 - bob, 4, 7, hair)
		_px(img, 22, 4 - bob, ribbon)
		_px(img, 23, 4 - bob, ribbon)
		_px(img, 24, 5 - bob, ribbon)
		_px(img, 25, 6 - bob, ribbon)

	for y in range(3, 18):
		var span: Vector2i = _front_span(y)
		_rect(img, span.x, y - bob, span.y - span.x + 1, 1, skin)
	for y in range(16, 18):
		var span: Vector2i = _front_span(y)
		_rect(img, span.x, y - bob, span.y - span.x + 1, 1, skin_shade)
	for y in range(3, 18):
		var span: Vector2i = _front_span(y)
		_px(img, span.x, y - bob, skin_shade)

	for y in range(3, 8):
		var span: Vector2i = _front_span(y)
		_rect(img, span.x, y - bob, span.y - span.x + 1, 1, hair)
	_rect(img, 8, 8 - bob, 4, 1, hair)
	_rect(img, 20, 8 - bob, 4, 1, hair)
	_px(img, 13, 8 - bob, hair)
	_px(img, 14, 8 - bob, hair)
	_px(img, 17, 8 - bob, hair)
	_px(img, 18, 8 - bob, hair)
	_px(img, 13, 9 - bob, hair)
	_px(img, 17, 9 - bob, hair)
	_rect(img, 8, 8 - bob, 2, 5, hair)
	_rect(img, 22, 8 - bob, 2, 5, hair)
	for x in range(10, 22, 2):
		_px(img, x, 4 - bob, hair_shade)

	_rect(img, 12, 11 - bob, 2, 2, eye)
	_rect(img, 18, 11 - bob, 2, 2, eye)
	_rect(img, 15, 14 - bob, 2, 1, mouth)
	_px(img, 14, 13 - bob, mouth)
	_px(img, 17, 13 - bob, mouth)

	_rect(img, 14, 17 - bob, 4, 2, skin_shade)

	for y in range(19, 31):
		var span: Vector2i = _torso_span(y)
		_rect(img, span.x, y - bob, span.y - span.x + 1, 1, top)
	for y in range(19, 31):
		var span: Vector2i = _torso_span(y)
		var shade_x: int = maxi(span.x, 20)
		if shade_x <= span.y:
			_rect(img, shade_x, y - bob, span.y - shade_x + 1, 1, top_shade)
	_rect(img, 14, 19 - bob, 4, 1, shirt)
	_rect(img, 15, 20 - bob, 2, 1, shirt)
	_rect(img, 15, 21 - bob, 2, 1, shirt_shade)

	_rect(img, 10, 26 - bob, 12, 3, sash)
	_rect(img, 19, 27 - bob, 3, 2, sash)

	for y in range(29, 34):
		_rect(img, 9, y - bob, 14, 1, top)
		_rect(img, 21, y - bob, 2, 1, top_shade)
	_rect(img, 9, 34 - bob, 14, 1, top_shade)
	# The hanging sash tail sits in front of the coat hem.
	_rect(img, 20, 29 - bob, 2, 3, sash)

	_rect(img, 6, 20 - bob, 4, 9, shirt)
	_rect(img, 22, 20 - bob, 4, 9, shirt)
	_rect(img, 9, 20 - bob, 1, 9, shirt_shade)
	_rect(img, 25, 20 - bob, 1, 9, shirt_shade)
	_rect(img, 6, 28 - bob, 4, 1, band)
	_rect(img, 22, 28 - bob, 4, 1, band)

	var left_hand_dy: int = 0
	var right_hand_dy: int = 0
	if frame == 1:
		left_hand_dy = 1
		right_hand_dy = -1
	elif frame == 3:
		left_hand_dy = -1
		right_hand_dy = 1
	_rect(img, 7, 29 - bob + left_hand_dy, 2, 2, skin)
	_rect(img, 23, 29 - bob + right_hand_dy, 2, 2, skin)

	var left_bottom: int = 40
	var right_bottom: int = 40
	if frame == 1:
		right_bottom = 38
	elif frame == 3:
		left_bottom = 38
	var pants_top: int = 34 - bob
	var left_h: int = left_bottom - pants_top + 1
	var right_h: int = right_bottom - pants_top + 1
	_rect(img, 10, pants_top, 6, left_h, pants)
	_rect(img, 16, pants_top, 6, right_h, pants)
	_rect(img, 15, pants_top, 1, left_h, pants_shade)
	_rect(img, 21, pants_top, 1, right_h, pants_shade)

	var left_boot_y: int = 39 if frame == 3 else 41
	var right_boot_y: int = 39 if frame == 1 else 41
	_rect(img, 10, left_boot_y, 6, 5, boots)
	_rect(img, 16, right_boot_y, 6, 5, boots)
	_rect(img, 10, left_boot_y, 6, 1, boots_shade)
	_rect(img, 16, right_boot_y, 6, 1, boots_shade)

	if sword:
		_rect(img, 22, 26 - bob, 3, 1, gold)
		for y in range(27, 38):
			var x: int = 23 + int(floor(float(y - 27) * 2.0 / 10.0))
			_rect(img, x, y - bob, 2, 1, scabbard)
		_px(img, 23, 28 - bob, ribbon)
		_px(img, 23, 29 - bob, ribbon)
		_px(img, 23, 30 - bob, ribbon)


static func _draw_up(
	img: Image, palette: Dictionary, frame: int, bob: int, ponytail: bool, sword: bool
) -> void:
	var hair: Color = _color(palette, "hair")
	var hair_shade: Color = _color(palette, "hair_shade")
	var skin: Color = _color(palette, "skin")
	var skin_shade: Color = _color(palette, "skin_shade")
	var ribbon: Color = _color(palette, "ribbon")
	var top: Color = _color(palette, "top")
	var top_shade: Color = _color(palette, "top_shade")
	var shirt: Color = _color(palette, "shirt")
	var shirt_shade: Color = _color(palette, "shirt_shade")
	var sash: Color = _color(palette, "sash")
	var pants: Color = _color(palette, "pants")
	var pants_shade: Color = _color(palette, "pants_shade")
	var boots: Color = _color(palette, "boots")
	var boots_shade: Color = _color(palette, "boots_shade")
	var band: Color = _color(palette, "band")
	var scabbard: Color = _color(palette, "scabbard")
	var gold: Color = _color(palette, "gold")

	_rect(img, 14, 17 - bob, 4, 2, skin_shade)
	for y in range(3, 18):
		var span: Vector2i = _front_span(y)
		_rect(img, span.x, y - bob, span.y - span.x + 1, 1, hair)
	for y in range(15, 18):
		var span: Vector2i = _front_span(y)
		_rect(img, span.y - 1, y - bob, 2, 1, hair_shade)

	for y in range(19, 31):
		var span: Vector2i = _torso_span(y)
		_rect(img, span.x, y - bob, span.y - span.x + 1, 1, top)
	for y in range(19, 31):
		var span: Vector2i = _torso_span(y)
		var shade_x: int = maxi(span.x, 20)
		if shade_x <= span.y:
			_rect(img, shade_x, y - bob, span.y - shade_x + 1, 1, top_shade)
	_rect(img, 15, 19 - bob, 2, 12, top_shade)

	_rect(img, 10, 26 - bob, 12, 3, sash)
	_rect(img, 14, 27 - bob, 4, 2, sash)

	for y in range(29, 34):
		_rect(img, 9, y - bob, 14, 1, top)
		_rect(img, 21, y - bob, 2, 1, top_shade)
	_rect(img, 9, 34 - bob, 14, 1, top_shade)
	_rect(img, 15, 29 - bob, 2, 3, sash)

	if ponytail:
		_rect(img, 14, 8 - bob, 4, 12, hair)
		_rect(img, 15, 10 - bob, 2, 1, ribbon)
		_rect(img, 15, 20 - bob, 2, 1, hair_shade)

	_rect(img, 6, 20 - bob, 4, 9, shirt)
	_rect(img, 22, 20 - bob, 4, 9, shirt)
	_rect(img, 9, 20 - bob, 1, 9, shirt_shade)
	_rect(img, 25, 20 - bob, 1, 9, shirt_shade)
	_rect(img, 6, 28 - bob, 4, 1, band)
	_rect(img, 22, 28 - bob, 4, 1, band)

	var left_hand_dy: int = 0
	var right_hand_dy: int = 0
	if frame == 1:
		left_hand_dy = 1
		right_hand_dy = -1
	elif frame == 3:
		left_hand_dy = -1
		right_hand_dy = 1
	_rect(img, 7, 29 - bob + left_hand_dy, 2, 2, skin)
	_rect(img, 23, 29 - bob + right_hand_dy, 2, 2, skin)

	var left_bottom: int = 40
	var right_bottom: int = 40
	if frame == 1:
		right_bottom = 38
	elif frame == 3:
		left_bottom = 38
	var pants_top: int = 34 - bob
	var left_h: int = left_bottom - pants_top + 1
	var right_h: int = right_bottom - pants_top + 1
	_rect(img, 10, pants_top, 6, left_h, pants)
	_rect(img, 16, pants_top, 6, right_h, pants)
	_rect(img, 15, pants_top, 1, left_h, pants_shade)
	_rect(img, 21, pants_top, 1, right_h, pants_shade)

	var left_boot_y: int = 39 if frame == 3 else 41
	var right_boot_y: int = 39 if frame == 1 else 41
	_rect(img, 10, left_boot_y, 6, 5, boots)
	_rect(img, 16, right_boot_y, 6, 5, boots)
	_rect(img, 10, left_boot_y, 6, 1, boots_shade)
	_rect(img, 16, right_boot_y, 6, 1, boots_shade)

	if sword:
		_rect(img, 7, 26 - bob, 3, 1, gold)
		for y in range(27, 38):
			var x: int = 8 - int(floor(float(y - 27) * 2.0 / 10.0))
			_rect(img, x, y - bob, 2, 1, scabbard)
		_px(img, 8, 28 - bob, ribbon)
		_px(img, 8, 29 - bob, ribbon)
		_px(img, 8, 30 - bob, ribbon)


static func _draw_right(
	img: Image, palette: Dictionary, frame: int, bob: int, ponytail: bool, sword: bool
) -> void:
	var hair: Color = _color(palette, "hair")
	var skin: Color = _color(palette, "skin")
	var skin_shade: Color = _color(palette, "skin_shade")
	var ribbon: Color = _color(palette, "ribbon")
	var eye: Color = _color(palette, "eye")
	var mouth: Color = _color(palette, "mouth")
	var top: Color = _color(palette, "top")
	var shirt: Color = _color(palette, "shirt")
	var sash: Color = _color(palette, "sash")
	var pants: Color = _color(palette, "pants")
	var boots: Color = _color(palette, "boots")
	var boots_shade: Color = _color(palette, "boots_shade")
	var band: Color = _color(palette, "band")
	var scabbard: Color = _color(palette, "scabbard")
	var gold: Color = _color(palette, "gold")

	if ponytail:
		_rect(img, 3, 6 + bob, 7, 3, hair)
		_px(img, 2, 7 + bob, ribbon)
		_px(img, 2, 8 + bob, ribbon)
		_px(img, 4, 6 + bob, ribbon)
		_px(img, 5, 6 + bob, ribbon)

	for y in range(3, 18):
		var span: Vector2i = _side_span(y)
		_rect(img, span.x, y - bob, span.y - span.x + 1, 1, skin)
	for y in range(3, 18):
		var span: Vector2i = _side_span(y)
		var hair_right: int = mini(16, span.y)
		_rect(img, span.x, y - bob, hair_right - span.x + 1, 1, hair)
	for y in range(3, 9):
		var span: Vector2i = _side_span(y)
		_rect(img, span.x, y - bob, span.y - span.x + 1, 1, hair)
	_rect(img, 17, 9 - bob, 4, 1, hair)

	_rect(img, 19, 11 - bob, 2, 2, eye)
	_px(img, 20, 14 - bob, mouth)
	_rect(img, 14, 17 - bob, 3, 2, skin_shade)

	_rect(img, 12, 19 - bob, 9, 12, top)
	_rect(img, 12, 26 - bob, 9, 3, sash)
	_rect(img, 11, 29 - bob, 11, 6, top)

	var arm_dx: int = 0
	if frame == 1:
		arm_dx = 3
	elif frame == 3:
		arm_dx = -3
	_rect(img, 14 + arm_dx, 20 - bob, 4, 9, shirt)
	_rect(img, 14 + arm_dx, 28 - bob, 4, 1, band)
	_rect(img, 15 + arm_dx, 29 - bob, 2, 2, skin)

	var back_x: int = 0
	var front_x: int = 0
	var back_boot_x: int = 0
	var front_boot_x: int = 0
	var back_boot_y: int = 41
	var front_boot_y: int = 41
	if frame == 1:
		back_x = 9
		front_x = 17
		back_boot_x = 8
		front_boot_x = 17
		front_boot_y = 39
	elif frame == 3:
		back_x = 13
		front_x = 13
		back_boot_x = 12
		front_boot_x = 13
		back_boot_y = 39
	elif frame == 2 or frame == 4:
		back_x = 12
		front_x = 14
		back_boot_x = 11
		front_boot_x = 14
	else:
		back_x = 11
		front_x = 15
		back_boot_x = 10
		front_boot_x = 15

	var pants_top: int = 34 - bob
	var pants_h: int = 40 - pants_top + 1
	_rect(img, back_x, pants_top, 4, pants_h, pants)
	_rect(img, front_x, pants_top, 4, pants_h, pants)
	_rect(img, back_boot_x, back_boot_y, 6, 5, boots)
	_rect(img, front_boot_x, front_boot_y, 7, 5, boots)
	_rect(img, back_boot_x, back_boot_y, 6, 1, boots_shade)
	_rect(img, front_boot_x, front_boot_y, 7, 1, boots_shade)

	if sword:
		_rect(img, 12, 26 - bob, 3, 1, gold)
		for y in range(27, 36):
			var x: int = 13 - int(floor(float(y - 27) * 6.0 / 8.0))
			_rect(img, x, y - bob, 2, 1, scabbard)
		_px(img, 14, 28 - bob, ribbon)


static func _front_span(y: int) -> Vector2i:
	if y == 3:
		return Vector2i(11, 20)
	if y == 4:
		return Vector2i(9, 22)
	if y >= 5 and y <= 14:
		return Vector2i(8, 23)
	if y == 15:
		return Vector2i(9, 22)
	if y == 16:
		return Vector2i(10, 21)
	if y == 17:
		return Vector2i(12, 19)
	return Vector2i(-1, -1)


static func _side_span(y: int) -> Vector2i:
	if y == 3:
		return Vector2i(12, 20)
	if y == 4:
		return Vector2i(10, 21)
	if y >= 5 and y <= 14:
		return Vector2i(9, 22)
	if y == 15:
		return Vector2i(10, 21)
	if y == 16:
		return Vector2i(11, 20)
	if y == 17:
		return Vector2i(12, 18)
	return Vector2i(-1, -1)


static func _torso_span(y: int) -> Vector2i:
	if y == 19:
		return Vector2i(11, 20)
	if y >= 20 and y <= 30:
		return Vector2i(10, 21)
	return Vector2i(-1, -1)


static func _color(palette: Dictionary, key: String) -> Color:
	var value: Variant = palette.get(key, null)
	if typeof(value) == TYPE_COLOR:
		return value
	return Color(1.0, 0.0, 1.0, 1.0)


static func _px(img: Image, x: int, y: int, color: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	img.set_pixel(x, y, color)


static func _rect(img: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	for dy in range(h):
		for dx in range(w):
			_px(img, x + dx, y + dy, color)


static func _outline(img: Image, color: Color) -> void:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var targets: Array[Vector2i] = []
	for y in range(h):
		for x in range(w):
			if img.get_pixel(x, y).a > 0.0:
				continue
			if _is_opaque(img, x - 1, y) \
					or _is_opaque(img, x + 1, y) \
					or _is_opaque(img, x, y - 1) \
					or _is_opaque(img, x, y + 1):
				targets.append(Vector2i(x, y))
	var outline_color: Color = Color(color.r, color.g, color.b, 1.0)
	for target in targets:
		img.set_pixel(target.x, target.y, outline_color)


static func _is_opaque(img: Image, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return false
	return img.get_pixel(x, y).a > 0.0


static func _flip_h(img: Image) -> Image:
	var out: Image = Image.new()
	out.copy_from(img)
	out.flip_x()
	return out

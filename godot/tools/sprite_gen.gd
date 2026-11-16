extends RefCounted

const FRAME_W := 32
const FRAME_H := 48
const SHEET_COLS := 5
const SHEET_ROWS := 4

const HAIR_PONYTAIL_RIBBON := "ponytail_ribbon"
const HAIR_LONG_PONYTAIL := "long_ponytail"
const HAIR_TOPKNOT := "topknot"
const BUILD_STOCKY := "stocky"
const PROP_SWORD_HIP := "sword_hip"
const PROP_GOURD_HIP := "gourd_hip"
const PROP_BLADE_HIP := "blade_hip"
const PROP_BLADE_SHOULDER := "blade_shoulder"
const FEATURE_HEADBAND := "headband"
const FEATURE_BEARD := "beard"
const FEATURE_FUR_COLLAR := "fur_collar"
const FEATURE_APRON := "apron"
const FEATURE_TOWEL := "towel"
const FEATURE_SHOULDER_ARMOR := "shoulder_armor"
const FEATURE_ROBE_LONG := "robe_long"


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

	var style: Dictionary = {
		"ponytail": false,
		"long_ponytail": false,
		"topknot": false,
		"stocky": false,
		"sword": false,
		"gourd_hip": false,
		"blade_hip": false,
		"blade_shoulder": false,
		"headband": false,
		"beard": false,
		"fur_collar": false,
		"apron": false,
		"towel": false,
		"shoulder_armor": false,
		"robe_long": false,
	}
	var hair_style: String = str(def.get("hair_style", ""))
	if hair_style == HAIR_PONYTAIL_RIBBON:
		style["ponytail"] = true
	elif hair_style == HAIR_LONG_PONYTAIL:
		style["long_ponytail"] = true
	elif hair_style == HAIR_TOPKNOT:
		style["topknot"] = true
	elif hair_style != "":
		push_warning("sprite_gen: unsupported hair_style '%s', skipping" % hair_style)

	var build: String = str(def.get("build", ""))
	if build == BUILD_STOCKY:
		style["stocky"] = true
	elif build != "":
		push_warning("sprite_gen: unsupported build '%s', skipping" % build)

	var features_value: Variant = def.get("features", [])
	if typeof(features_value) == TYPE_ARRAY:
		var features: Array = features_value
		for feature in features:
			var feature_name: String = str(feature)
			match feature_name:
				FEATURE_HEADBAND:
					style["headband"] = true
				FEATURE_BEARD:
					style["beard"] = true
				FEATURE_FUR_COLLAR:
					style["fur_collar"] = true
				FEATURE_APRON:
					style["apron"] = true
				FEATURE_TOWEL:
					style["towel"] = true
				FEATURE_SHOULDER_ARMOR:
					style["shoulder_armor"] = true
				FEATURE_ROBE_LONG:
					style["robe_long"] = true
				"":
					pass
				_:
					push_warning("sprite_gen: unsupported feature '%s', skipping" % feature_name)

	var props_value: Variant = def.get("props", [])
	if typeof(props_value) == TYPE_ARRAY:
		var props: Array = props_value
		for prop in props:
			var prop_name: String = str(prop)
			match prop_name:
				PROP_SWORD_HIP:
					style["sword"] = true
				PROP_GOURD_HIP:
					style["gourd_hip"] = true
				PROP_BLADE_HIP:
					style["blade_hip"] = true
				PROP_BLADE_SHOULDER:
					style["blade_shoulder"] = true
				"":
					pass
				_:
					push_warning("sprite_gen: unsupported prop '%s', skipping" % prop_name)

	var bob: int = 1 if frame == 2 or frame == 4 else 0
	match direction:
		0:
			_draw_down(img, palette, frame, bob, style)
		1:
			_draw_up(img, palette, frame, bob, style)
		2:
			_draw_right(img, palette, frame, bob, style)
		_:
			_draw_right(img, palette, frame, bob, style)

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
	img: Image, palette: Dictionary, frame: int, bob: int, style: Dictionary
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

	var ponytail: bool = bool(style.get("ponytail", false))
	var long_ponytail: bool = bool(style.get("long_ponytail", false))
	var topknot: bool = bool(style.get("topknot", false))
	var stocky: bool = bool(style.get("stocky", false))
	var sword: bool = bool(style.get("sword", false))
	var robe_long: bool = bool(style.get("robe_long", false))

	if bool(style.get("blade_shoulder", false)) and _has_color(palette, "blade"):
		_draw_blade_shoulder(img, palette, 6, 5, 8, 21, 27, 3, 0)

	if ponytail or long_ponytail:
		_rect(img, 21, 3 - bob, 4, 7, hair)
		_px(img, 22, 4 - bob, ribbon)
		_px(img, 23, 4 - bob, ribbon)
		_px(img, 24, 5 - bob, ribbon)
		_px(img, 25, 6 - bob, ribbon)

	if long_ponytail:
		_rect(img, 6, 10 - bob, 2, 10, hair)
		_rect(img, 24, 10 - bob, 2, 10, hair)

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

	if topknot:
		_rect(img, 14, 2, 4, 2, hair)

	if bool(style.get("headband", false)) and _has_color(palette, "headband"):
		var headband: Color = _color(palette, "headband")
		_rect(img, 8, 7 - bob, 16, 2, headband)
		_px(img, 24, 8 - bob, headband)
		_px(img, 25, 9 - bob, headband)
		_px(img, 25, 10 - bob, headband)

	_rect(img, 12, 11 - bob, 2, 2, eye)
	_rect(img, 18, 11 - bob, 2, 2, eye)
	_rect(img, 15, 14 - bob, 2, 1, mouth)
	_px(img, 14, 13 - bob, mouth)
	_px(img, 17, 13 - bob, mouth)

	_rect(img, 14, 17 - bob, 4, 2, skin_shade)

	if bool(style.get("beard", false)) and _has_color(palette, "beard"):
		var beard: Color = _color(palette, "beard")
		_rect(img, 11, 15 - bob, 10, 2, beard)
		_px(img, 13, 14 - bob, beard)
		_px(img, 18, 14 - bob, beard)

	for y in range(19, 31):
		var span: Vector2i = _torso_span(y)
		if stocky:
			span = Vector2i(span.x - 1, span.y + 1)
		_rect(img, span.x, y - bob, span.y - span.x + 1, 1, top)
	for y in range(19, 31):
		var span: Vector2i = _torso_span(y)
		if stocky:
			span = Vector2i(span.x - 1, span.y + 1)
		var shade_x: int = maxi(span.x, 20)
		if shade_x <= span.y:
			_rect(img, shade_x, y - bob, span.y - shade_x + 1, 1, top_shade)
	_rect(img, 14, 19 - bob, 4, 1, shirt)
	_rect(img, 15, 20 - bob, 2, 1, shirt)
	_rect(img, 15, 21 - bob, 2, 1, shirt_shade)

	if bool(style.get("fur_collar", false)) and _has_color(palette, "fur"):
		_draw_fur_collar_front(img, palette, bob)

	var sash_x: int = 9 if stocky else 10
	var sash_w: int = 14 if stocky else 12
	_rect(img, sash_x, 26 - bob, sash_w, 3, sash)
	_rect(img, 19, 27 - bob, 3, 2, sash)

	var hem_x: int = 8 if stocky else 9
	var hem_w: int = 16 if stocky else 14
	for y in range(29, 34):
		_rect(img, hem_x, y - bob, hem_w, 1, top)
		_rect(img, hem_x + hem_w - 2, y - bob, 2, 1, top_shade)
	_rect(img, hem_x, 34 - bob, hem_w, 1, top_shade)
	# The hanging sash tail sits in front of the coat hem.
	_rect(img, 20, 29 - bob, 2, 3, sash)

	if bool(style.get("gourd_hip", false)) and _has_color(palette, "gourd"):
		_draw_gourd(img, palette, 8, bob)

	var arm_left_x: int = 5 if stocky else 6
	var arm_left_w: int = 5 if stocky else 4
	var arm_right_w: int = 5 if stocky else 4
	_rect(img, arm_left_x, 20 - bob, arm_left_w, 9, shirt)
	_rect(img, 22, 20 - bob, arm_right_w, 9, shirt)
	_rect(img, arm_left_x + arm_left_w - 1, 20 - bob, 1, 9, shirt_shade)
	_rect(img, 22 + arm_right_w - 1, 20 - bob, 1, 9, shirt_shade)
	_rect(img, arm_left_x, 28 - bob, arm_left_w, 1, band)
	_rect(img, 22, 28 - bob, arm_right_w, 1, band)

	if bool(style.get("shoulder_armor", false)) and _has_color(palette, "armor"):
		_draw_shoulder_armor_front(img, palette, bob)

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
	if not robe_long:
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

	if bool(style.get("apron", false)) and _has_color(palette, "apron"):
		_draw_apron_front(img, palette)

	if robe_long:
		_draw_robe_long_front(img, palette)

	if bool(style.get("towel", false)) and _has_color(palette, "towel"):
		var towel: Color = _color(palette, "towel")
		_rect(img, 6, 24 - bob, 3, 5, towel)
		if _has_color(palette, "towel_line"):
			_px(img, 7, 26 - bob, _color(palette, "towel_line"))

	if bool(style.get("blade_hip", false)):
		_draw_blade_hip_front(img, palette, bob)

	if sword:
		_rect(img, 22, 26 - bob, 3, 1, gold)
		for y in range(27, 38):
			var x: int = 23 + int(floor(float(y - 27) * 2.0 / 10.0))
			_rect(img, x, y - bob, 2, 1, scabbard)
		_px(img, 23, 28 - bob, ribbon)
		_px(img, 23, 29 - bob, ribbon)
		_px(img, 23, 30 - bob, ribbon)


static func _draw_up(
	img: Image, palette: Dictionary, frame: int, bob: int, style: Dictionary
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

	var ponytail: bool = bool(style.get("ponytail", false))
	var long_ponytail: bool = bool(style.get("long_ponytail", false))
	var topknot: bool = bool(style.get("topknot", false))
	var stocky: bool = bool(style.get("stocky", false))
	var sword: bool = bool(style.get("sword", false))
	var robe_long: bool = bool(style.get("robe_long", false))

	_rect(img, 14, 17 - bob, 4, 2, skin_shade)
	for y in range(3, 18):
		var span: Vector2i = _front_span(y)
		_rect(img, span.x, y - bob, span.y - span.x + 1, 1, hair)
	for y in range(15, 18):
		var span: Vector2i = _front_span(y)
		_rect(img, span.y - 1, y - bob, 2, 1, hair_shade)

	if topknot:
		_rect(img, 14, 2, 4, 2, hair)

	if bool(style.get("headband", false)) and _has_color(palette, "headband"):
		var headband: Color = _color(palette, "headband")
		_rect(img, 8, 7 - bob, 16, 2, headband)
		_px(img, 24, 8 - bob, headband)
		_px(img, 25, 9 - bob, headband)
		_px(img, 25, 10 - bob, headband)

	for y in range(19, 31):
		var span: Vector2i = _torso_span(y)
		if stocky:
			span = Vector2i(span.x - 1, span.y + 1)
		_rect(img, span.x, y - bob, span.y - span.x + 1, 1, top)
	for y in range(19, 31):
		var span: Vector2i = _torso_span(y)
		if stocky:
			span = Vector2i(span.x - 1, span.y + 1)
		var shade_x: int = maxi(span.x, 20)
		if shade_x <= span.y:
			_rect(img, shade_x, y - bob, span.y - shade_x + 1, 1, top_shade)
	_rect(img, 15, 19 - bob, 2, 12, top_shade)

	if bool(style.get("blade_shoulder", false)) and _has_color(palette, "blade"):
		_draw_blade_shoulder(img, palette, 24, 26, 23, 21, 4, 3, 0)

	if bool(style.get("fur_collar", false)) and _has_color(palette, "fur"):
		_draw_fur_collar_back(img, palette, bob)

	var sash_x: int = 9 if stocky else 10
	var sash_w: int = 14 if stocky else 12
	_rect(img, sash_x, 26 - bob, sash_w, 3, sash)
	_rect(img, 14, 27 - bob, 4, 2, sash)

	var hem_x: int = 8 if stocky else 9
	var hem_w: int = 16 if stocky else 14
	for y in range(29, 34):
		_rect(img, hem_x, y - bob, hem_w, 1, top)
		_rect(img, hem_x + hem_w - 2, y - bob, 2, 1, top_shade)
	_rect(img, hem_x, 34 - bob, hem_w, 1, top_shade)
	_rect(img, 15, 29 - bob, 2, 3, sash)

	if bool(style.get("gourd_hip", false)) and _has_color(palette, "gourd"):
		_draw_gourd(img, palette, 20, bob)

	if long_ponytail:
		_rect(img, 11, 8 - bob, 10, 22 + bob, hair)
		_rect(img, 15, 12 - bob, 2, 17 + bob, hair_shade)
		_rect(img, 14, 9 - bob, 4, 1, ribbon)

	if ponytail:
		_rect(img, 14, 8 - bob, 4, 12, hair)
		_rect(img, 15, 10 - bob, 2, 1, ribbon)
		_rect(img, 15, 20 - bob, 2, 1, hair_shade)

	var arm_left_x: int = 5 if stocky else 6
	var arm_left_w: int = 5 if stocky else 4
	var arm_right_w: int = 5 if stocky else 4
	_rect(img, arm_left_x, 20 - bob, arm_left_w, 9, shirt)
	_rect(img, 22, 20 - bob, arm_right_w, 9, shirt)
	_rect(img, arm_left_x + arm_left_w - 1, 20 - bob, 1, 9, shirt_shade)
	_rect(img, 22 + arm_right_w - 1, 20 - bob, 1, 9, shirt_shade)
	_rect(img, arm_left_x, 28 - bob, arm_left_w, 1, band)
	_rect(img, 22, 28 - bob, arm_right_w, 1, band)

	if bool(style.get("shoulder_armor", false)) and _has_color(palette, "armor"):
		_draw_shoulder_armor_front(img, palette, bob)

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
	if not robe_long:
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

	if bool(style.get("apron", false)) and _has_color(palette, "apron"):
		_draw_apron_back(img, palette)

	if robe_long:
		_draw_robe_long_front(img, palette)

	if bool(style.get("towel", false)) and _has_color(palette, "towel"):
		_rect(img, 23, 24 - bob, 3, 5, _color(palette, "towel"))

	if bool(style.get("blade_hip", false)):
		_draw_blade_hip_back(img, palette, bob)

	if sword:
		_rect(img, 7, 26 - bob, 3, 1, gold)
		for y in range(27, 38):
			var x: int = 8 - int(floor(float(y - 27) * 2.0 / 10.0))
			_rect(img, x, y - bob, 2, 1, scabbard)
		_px(img, 8, 28 - bob, ribbon)
		_px(img, 8, 29 - bob, ribbon)
		_px(img, 8, 30 - bob, ribbon)


static func _draw_right(
	img: Image, palette: Dictionary, frame: int, bob: int, style: Dictionary
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

	var ponytail: bool = bool(style.get("ponytail", false))
	var long_ponytail: bool = bool(style.get("long_ponytail", false))
	var topknot: bool = bool(style.get("topknot", false))
	var stocky: bool = bool(style.get("stocky", false))
	var sword: bool = bool(style.get("sword", false))
	var robe_long: bool = bool(style.get("robe_long", false))

	if bool(style.get("blade_shoulder", false)) and _has_color(palette, "blade"):
		_draw_blade_shoulder(img, palette, 17, 19, 16, 21, 4, 4, -bob)

	if ponytail:
		_rect(img, 3, 6 + bob, 7, 3, hair)
		_px(img, 2, 7 + bob, ribbon)
		_px(img, 2, 8 + bob, ribbon)
		_px(img, 4, 6 + bob, ribbon)
		_px(img, 5, 6 + bob, ribbon)

	if long_ponytail:
		_rect(img, 2, 6 + bob, 8, 3, hair)
		_rect(img, 3, 9 + bob, 3, 10, hair)
		_px(img, 4, 6 + bob, ribbon)
		_px(img, 5, 6 + bob, ribbon)
		_px(img, 2, 7 + bob, ribbon)

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

	if topknot:
		_rect(img, 13, 2, 4, 2, hair)

	if bool(style.get("headband", false)) and _has_color(palette, "headband"):
		var headband: Color = _color(palette, "headband")
		_rect(img, 9, 7 - bob, 13, 2, headband)
		_px(img, 7, 8 - bob, headband)
		_px(img, 6, 9 - bob, headband)
		_px(img, 5, 10 - bob, headband)

	_rect(img, 19, 11 - bob, 2, 2, eye)
	_px(img, 20, 14 - bob, mouth)
	_rect(img, 14, 17 - bob, 3, 2, skin_shade)

	if bool(style.get("beard", false)) and _has_color(palette, "beard"):
		var beard: Color = _color(palette, "beard")
		_rect(img, 14, 15 - bob, 7, 2, beard)
		_px(img, 19, 14 - bob, beard)

	var torso_x: int = 11 if stocky else 12
	var torso_w: int = 10 if stocky else 9
	var hem_x: int = 10 if stocky else 11
	var hem_w: int = 12 if stocky else 11
	_rect(img, torso_x, 19 - bob, torso_w, 12, top)

	if bool(style.get("fur_collar", false)) and _has_color(palette, "fur"):
		_draw_fur_collar_side(img, palette, bob)

	_rect(img, torso_x, 26 - bob, torso_w, 3, sash)
	_rect(img, hem_x, 29 - bob, hem_w, 6, top)

	if bool(style.get("gourd_hip", false)) and _has_color(palette, "gourd"):
		_draw_gourd(img, palette, 11, bob)

	var arm_dx: int = 0
	if frame == 1:
		arm_dx = 3
	elif frame == 3:
		arm_dx = -3
	_rect(img, 14 + arm_dx, 20 - bob, 4, 9, shirt)
	_rect(img, 14 + arm_dx, 28 - bob, 4, 1, band)
	_rect(img, 15 + arm_dx, 29 - bob, 2, 2, skin)

	if bool(style.get("shoulder_armor", false)) and _has_color(palette, "armor"):
		_draw_shoulder_armor_side(img, palette, bob)

	if bool(style.get("towel", false)) and _has_color(palette, "towel"):
		var towel: Color = _color(palette, "towel")
		_rect(img, 13, 24 - bob, 3, 5, towel)
		if _has_color(palette, "towel_line"):
			_px(img, 14, 26 - bob, _color(palette, "towel_line"))

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
	if not robe_long:
		_rect(img, back_x, pants_top, 4, pants_h, pants)
		_rect(img, front_x, pants_top, 4, pants_h, pants)
	_rect(img, back_boot_x, back_boot_y, 6, 5, boots)
	_rect(img, front_boot_x, front_boot_y, 7, 5, boots)
	_rect(img, back_boot_x, back_boot_y, 6, 1, boots_shade)
	_rect(img, front_boot_x, front_boot_y, 7, 1, boots_shade)

	if bool(style.get("apron", false)) and _has_color(palette, "apron"):
		_draw_apron_side(img, palette)

	if robe_long:
		_draw_robe_long_side(img, palette)

	if bool(style.get("blade_hip", false)):
		_draw_blade_hip_side(img, palette, bob)

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


static func _has_color(palette: Dictionary, key: String) -> bool:
	return typeof(palette.get(key, null)) == TYPE_COLOR


static func _draw_fur_collar_front(img: Image, palette: Dictionary, bob: int) -> void:
	var fur: Color = _color(palette, "fur")
	for y in range(18, 21):
		for x in range(7, 25):
			if y <= 19 and x >= 14 and x <= 17:
				continue
			_px(img, x, y - bob, fur)
	_rect(img, 7, 21 - bob, 3, 4, fur)
	_rect(img, 22, 21 - bob, 3, 4, fur)
	if _has_color(palette, "fur_light"):
		var fur_light: Color = _color(palette, "fur_light")
		_px(img, 8, 18 - bob, fur_light)
		_px(img, 11, 18 - bob, fur_light)
		_px(img, 20, 18 - bob, fur_light)
		_px(img, 23, 18 - bob, fur_light)


static func _draw_fur_collar_back(img: Image, palette: Dictionary, bob: int) -> void:
	var fur: Color = _color(palette, "fur")
	_rect(img, 7, 18 - bob, 18, 3, fur)
	_rect(img, 7, 21 - bob, 3, 4, fur)
	_rect(img, 22, 21 - bob, 3, 4, fur)
	if _has_color(palette, "fur_light"):
		var fur_light: Color = _color(palette, "fur_light")
		_px(img, 8, 18 - bob, fur_light)
		_px(img, 11, 18 - bob, fur_light)
		_px(img, 14, 18 - bob, fur_light)
		_px(img, 17, 18 - bob, fur_light)
		_px(img, 20, 18 - bob, fur_light)
		_px(img, 23, 18 - bob, fur_light)


static func _draw_fur_collar_side(img: Image, palette: Dictionary, bob: int) -> void:
	var fur: Color = _color(palette, "fur")
	_rect(img, 10, 18 - bob, 10, 4, fur)
	_rect(img, 9, 19 - bob, 3, 6, fur)
	if _has_color(palette, "fur_light"):
		var fur_light: Color = _color(palette, "fur_light")
		_px(img, 11, 18 - bob, fur_light)
		_px(img, 15, 18 - bob, fur_light)
		_px(img, 19, 18 - bob, fur_light)


static func _draw_shoulder_armor_front(img: Image, palette: Dictionary, bob: int) -> void:
	var armor: Color = _color(palette, "armor")
	_rect(img, 6, 18 - bob, 5, 3, armor)
	_rect(img, 21, 18 - bob, 5, 3, armor)
	if _has_color(palette, "armor_shade"):
		var armor_shade: Color = _color(palette, "armor_shade")
		_rect(img, 6, 20 - bob, 5, 1, armor_shade)
		_rect(img, 21, 20 - bob, 5, 1, armor_shade)


static func _draw_shoulder_armor_side(img: Image, palette: Dictionary, bob: int) -> void:
	var armor: Color = _color(palette, "armor")
	_rect(img, 12, 18 - bob, 6, 3, armor)


static func _draw_gourd(img: Image, palette: Dictionary, x: int, bob: int) -> void:
	var gourd: Color = _color(palette, "gourd")
	_rect(img, x, 29 - bob, 4, 5, gourd)
	if _has_color(palette, "gourd_shade"):
		_rect(img, x + 3, 29 - bob, 1, 5, _color(palette, "gourd_shade"))
	if _has_color(palette, "rope"):
		var rope: Color = _color(palette, "rope")
		_px(img, x + 1, 28 - bob, rope)
		_px(img, x + 2, 28 - bob, rope)


static func _draw_apron_front(img: Image, palette: Dictionary) -> void:
	var apron: Color = _color(palette, "apron")
	_rect(img, 11, 29, 10, 11, apron)
	_rect(img, 10, 28, 2, 1, apron)
	if _has_color(palette, "apron_shade"):
		var apron_shade: Color = _color(palette, "apron_shade")
		_rect(img, 20, 29, 1, 11, apron_shade)
		_rect(img, 11, 39, 10, 1, apron_shade)


static func _draw_apron_back(img: Image, palette: Dictionary) -> void:
	_rect(img, 10, 28, 12, 1, _color(palette, "apron"))


static func _draw_apron_side(img: Image, palette: Dictionary) -> void:
	_rect(img, 15, 29, 4, 11, _color(palette, "apron"))


static func _draw_robe_long_front(img: Image, palette: Dictionary) -> void:
	var top: Color = _color(palette, "top")
	var top_shade: Color = _color(palette, "top_shade")
	var shirt: Color = _color(palette, "shirt")
	var shirt_shade: Color = _color(palette, "shirt_shade")
	_rect(img, 8, 29, 8, 12, top)
	_rect(img, 16, 29, 8, 12, shirt)
	_rect(img, 15, 29, 1, 12, top_shade)
	_rect(img, 23, 29, 1, 12, shirt_shade)
	_rect(img, 8, 41, 16, 1, top_shade)


static func _draw_robe_long_side(img: Image, palette: Dictionary) -> void:
	var top: Color = _color(palette, "top")
	var top_shade: Color = _color(palette, "top_shade")
	var shirt: Color = _color(palette, "shirt")
	_rect(img, 10, 29, 12, 12, top)
	_rect(img, 21, 29, 1, 12, shirt)
	_rect(img, 10, 41, 12, 1, top_shade)


static func _draw_blade_hip_front(img: Image, palette: Dictionary, bob: int) -> void:
	var scabbard: Color = _color(palette, "scabbard")
	for y in range(27, 38):
		var x: int = 23 + int(floor(float(y - 27) * 2.0 / 10.0))
		_rect(img, x, y - bob, 3, 1, scabbard)
	if _has_color(palette, "rope"):
		var rope: Color = _color(palette, "rope")
		_px(img, 23, 28 - bob, rope)
		_px(img, 23, 30 - bob, rope)


static func _draw_blade_hip_back(img: Image, palette: Dictionary, bob: int) -> void:
	var scabbard: Color = _color(palette, "scabbard")
	for y in range(27, 38):
		var x: int = 8 - int(floor(float(y - 27) * 2.0 / 10.0))
		_rect(img, x, y - bob, 3, 1, scabbard)
	if _has_color(palette, "rope"):
		var rope: Color = _color(palette, "rope")
		_px(img, 8, 28 - bob, rope)
		_px(img, 8, 30 - bob, rope)


static func _draw_blade_hip_side(img: Image, palette: Dictionary, bob: int) -> void:
	var scabbard: Color = _color(palette, "scabbard")
	for y in range(27, 36):
		var x: int = 13 - int(floor(float(y - 27) * 6.0 / 8.0))
		_rect(img, x, y - bob, 3, 1, scabbard)
	if _has_color(palette, "rope"):
		var rope: Color = _color(palette, "rope")
		_px(img, 13, 28 - bob, rope)
		_px(img, 11, 30 - bob, rope)


static func _draw_blade_shoulder(
	img: Image, palette: Dictionary,
	handle_x: int, ring_x: int,
	start_x: int, start_y: int, end_x: int, end_y: int, y_off: int
) -> void:
	var scabbard: Color = _color(palette, "scabbard")
	var gold: Color = _color(palette, "gold")
	var blade: Color = _color(palette, "blade")
	var blade_light: Color = blade
	if _has_color(palette, "blade_light"):
		blade_light = _color(palette, "blade_light")
	_rect(img, handle_x, 22 + y_off, 2, 3, scabbard)
	_px(img, ring_x, 24 + y_off, gold)
	_blade_diagonal(img, start_x, start_y + y_off, end_x, end_y + y_off, blade, blade_light)


static func _blade_diagonal(
	img: Image, x0: int, y0: int, x1: int, y1: int, blade: Color, light: Color
) -> void:
	var steps: int = absi(x1 - x0)
	if steps == 0:
		return
	var dir: int = 1 if x1 > x0 else -1
	for i in range(steps + 1):
		var x: int = x0 + dir * i
		var y: int = int(round(float(y0) + float(y1 - y0) * float(i) / float(steps)))
		_px(img, x, y, light)
		_px(img, x, y + 1, blade)
		if i >= steps - 1:
			_px(img, x, y + 2, blade)

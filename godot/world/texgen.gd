extends RefCounted


static func noise(x: int, y: int, seed: int) -> float:
	var h: int = (x * 73856093) ^ (y * 19349663) ^ (seed * 83492791)
	h = h & 0xFFFFFFFF
	h = (h ^ (h >> 13)) & 0xFFFFFFFF
	h = (h * 1274126177) & 0xFFFFFFFF
	h = (h ^ (h >> 16)) & 0xFFFFFFFF
	return float(h & 0xFFFFFF) / 16777215.0


static func _blank(width: int, height: int) -> Image:
	var img: Image = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	return img


static func grass() -> Image:
	var img: Image = _blank(16, 16)
	var base := Color("#6f8f4a")
	var dark := Color("#5f7f3e")
	var light := Color("#82a257")
	var flower := Color("#e8d86a")
	for y in range(16):
		for x in range(16):
			var n: float = noise(x, y, 101)
			var c := base
			if n < 0.30:
				c = dark
			elif n < 0.52:
				c = light
			img.set_pixel(x, y, c)
	img.set_pixel(3, 4, flower)
	img.set_pixel(12, 9, flower)
	img.set_pixel(7, 13, flower)
	img.set_pixel(0, 0, dark)
	img.set_pixel(15, 15, light)
	img.set_pixel(5, 5, base)
	return img


static func stone_street() -> Image:
	var img: Image = _blank(16, 16)
	var base := Color("#8a8277")
	var gap := Color("#5e584f")
	var light := Color("#96907f")
	var dark := Color("#7a7368")
	for y in range(16):
		for x in range(16):
			var cx: int = int(floor(x / 5.0))
			var cy: int = int(floor(y / 4.0))
			var lx: int = x - cx * 5
			var ly: int = y - cy * 4
			var tone: float = noise(cx, cy, 202)
			var c := base
			if lx == 4 or ly == 3:
				c = gap
			elif tone < 0.30:
				c = dark
			elif tone < 0.55:
				c = light
			img.set_pixel(x, y, c)
	img.set_pixel(0, 0, light)
	img.set_pixel(1, 0, dark)
	img.set_pixel(2, 1, base)
	img.set_pixel(0, 3, gap)
	return img


static func step_stone() -> Image:
	var img: Image = _blank(16, 16)
	var base := Color("#9a9286")
	var top := Color("#b4ab9c")
	var bottom := Color("#6c655b")
	var dot := Color("#857d70")
	for y in range(16):
		for x in range(16):
			var c := base
			if y == 0:
				c = top
			elif y == 15:
				c = bottom
			elif noise(x, y, 303) < 0.22:
				c = dot
			img.set_pixel(x, y, c)
	img.set_pixel(5, 5, base)
	img.set_pixel(6, 5, dot)
	return img


static func wood_planks() -> Image:
	var img: Image = _blank(16, 16)
	var base := Color("#7a5232")
	var seam := Color("#4a3020")
	var grain := Color("#8a6240")
	var dark := Color("#664327")
	for y in range(16):
		for x in range(16):
			var c := base
			if x % 4 == 0:
				c = seam
			else:
				var n: float = noise(x, y, 404)
				if n > 0.76:
					c = grain
				elif n < 0.12:
					c = dark
			img.set_pixel(x, y, c)
	img.set_pixel(5, 2, grain)
	img.set_pixel(6, 9, dark)
	img.set_pixel(5, 5, base)
	return img


static func plaster() -> Image:
	var img: Image = _blank(16, 16)
	var base := Color("#d9c9a8")
	var stain1 := Color("#c7b58f")
	var stain2 := Color("#b8a57d")
	var stain3 := Color("#a89570")
	for y in range(16):
		for x in range(16):
			var n: float = noise(x, y, 505)
			var c := base
			if n < 0.10:
				c = stain1
			elif n < 0.18:
				c = stain2
			elif n > 0.94:
				c = stain3
			img.set_pixel(x, y, c)
	img.set_pixel(2, 2, stain1)
	img.set_pixel(6, 5, stain2)
	img.set_pixel(11, 12, stain3)
	img.set_pixel(5, 5, base)
	return img


static func roof_tiles() -> Image:
	var img: Image = _blank(16, 16)
	var base := Color("#5d636b")
	var seam := Color("#3d4248")
	var light := Color("#7a828b")
	var dark := Color("#4f545b")
	for y in range(16):
		var row: int = int(floor(y / 4.0))
		var ly: int = y - row * 4
		var offset: int = (row % 2) * 2
		for x in range(16):
			var lx: int = (x + offset) % 4
			var c := base
			if ly == 3 or lx == 0:
				c = seam
			elif ly == 0:
				c = light
			elif noise(x, y, 606) < 0.18:
				c = dark
			img.set_pixel(x, y, c)
	img.set_pixel(2, 1, dark)
	return img


static func water() -> Image:
	var img: Image = _blank(16, 16)
	var base := Color("#4f86a8")
	var ripple := Color("#7fb0c8")
	var deep := Color("#3e6f90")
	var deep2 := Color("#35617f")
	for y in range(16):
		for x in range(16):
			var n: float = noise(x, y, 707)
			var band: float = noise(x, int(floor(y / 2.0)), 708)
			var c := base
			if band > 0.72:
				c = ripple
			elif n < 0.16:
				c = deep
			elif n > 0.92:
				c = deep2
			img.set_pixel(x, y, c)
	img.set_pixel(1, 1, ripple)
	img.set_pixel(3, 6, deep)
	img.set_pixel(9, 12, deep2)
	img.set_pixel(5, 5, base)
	return img


static func door() -> Image:
	var img: Image = _blank(16, 32)
	var base := Color("#5a3a22")
	var dark := Color("#4a2e1a")
	var seam := Color("#33200f")
	var ring := Color("#b99a4b")
	var grain := Color("#6c4629")
	for y in range(32):
		for x in range(16):
			var c := base
			var n: float = noise(x, y, 808)
			if x == 8:
				c = seam
			elif n < 0.18:
				c = dark
			elif n > 0.82:
				c = grain
			img.set_pixel(x, y, c)
	var ring_points: Array[Vector2i] = [
		Vector2i(10, 17),
		Vector2i(11, 16),
		Vector2i(12, 17),
		Vector2i(10, 18),
		Vector2i(12, 18),
		Vector2i(10, 19),
		Vector2i(11, 20),
		Vector2i(12, 19),
	]
	for p in ring_points:
		img.set_pixel(p.x, p.y, ring)
	return img


static func window() -> Image:
	var img: Image = _blank(16, 16)
	var frame := Color("#4a3020")
	var bar := Color("#5c3d22")
	var glass := Color("#e8c878")
	var glow := Color("#f2dc96")
	for y in range(16):
		for x in range(16):
			var c := glass
			if x < 2 or x > 13 or y < 2 or y > 13:
				c = frame
			elif x == 7 or x == 8 or y == 7 or y == 8:
				c = bar
			elif (x + y) % 7 == 0:
				c = glow
			img.set_pixel(x, y, c)
	return img


static func awning_stripes() -> Image:
	var img: Image = _blank(16, 16)
	var red := Color("#a8453a")
	var red_dark := Color("#93392f")
	var cream := Color("#e6dcc6")
	var cream_dark := Color("#d6ccb6")
	for y in range(16):
		for x in range(16):
			var stripe: int = int(floor(x / 4.0)) % 2
			var shade: bool = (y % 8) == 7
			var c := cream
			if stripe == 0:
				c = red_dark if shade else red
			else:
				c = cream_dark if shade else cream
			img.set_pixel(x, y, c)
	return img


static func cloth(color: Color) -> Image:
	var img: Image = _blank(16, 16)
	var dark := color.darkened(0.14)
	var light := color.lightened(0.10)
	for y in range(16):
		for x in range(16):
			var n: float = noise(x, y, 909)
			var c := color
			if n < 0.22:
				c = dark
			elif n > 0.84:
				c = light
			img.set_pixel(x, y, c)
	return img


static func tree_sprite() -> Image:
	var img: Image = _blank(48, 64)
	var outline := Color("#2c4422")
	var trunk := Color("#5a3d26")
	var trunk_dark := Color("#3e2a1a")
	var light := Color("#7fa857")
	var mid := Color("#5f8a3f")
	var shade := Color("#46702f")
	for y in range(38, 63):
		for x in range(21, 27):
			img.set_pixel(x, y, trunk)
	for y in range(38, 63):
		for x in range(21, 23):
			img.set_pixel(x, y, trunk_dark)
	# roots
	for x in range(17, 31):
		img.set_pixel(x, 63, trunk_dark)
	for x in range(18, 24):
		img.set_pixel(x, 61, trunk)
	for x in range(26, 30):
		img.set_pixel(x, 61, trunk)
	var blobs: Array[Vector3] = [
		Vector3(24.0, 22.0, 13.0),
		Vector3(13.0, 30.0, 9.0),
		Vector3(35.0, 30.0, 9.0),
	]
	for y in range(64):
		for x in range(48):
			var best: float = 99.0
			for blob_value in blobs:
				var blob: Vector3 = blob_value
				var dx: float = float(x) + 0.5 - blob.x
				var dy: float = float(y) + 0.5 - blob.y
				var d: float = sqrt(dx * dx + dy * dy) / blob.z
				if d < best:
					best = d
			if best > 1.0:
				continue
			var c := outline
			if best <= 0.88:
				var t: float = (float(y) - 9.0) / 34.0
				if t < 0.35:
					c = light
				elif t < 0.62:
					c = mid
				else:
					c = shade
			img.set_pixel(x, y, c)
	return img


static func blob_shadow() -> Image:
	var img: Image = _blank(16, 8)
	for y in range(8):
		for x in range(16):
			var nx: float = (float(x) + 0.5 - 8.0) / 8.0
			var ny: float = (float(y) + 0.5 - 4.0) / 4.0
			var d: float = sqrt(nx * nx + ny * ny)
			var a: float = maxf(0.0, 1.0 - d)
			a = pow(a, 0.8) * 0.45
			img.set_pixel(x, y, Color(0.0, 0.0, 0.0, a))
	return img


static func mountain_layer(width: int, height: int, seed: int, color: Color) -> Image:
	var img: Image = _blank(width, height)
	var mid: float = float(height) * 0.55
	var amp: float = float(height) * 0.22
	for x in range(width):
		var t: float = float(x) / maxf(1.0, float(width))
		var ridge: float = mid
		ridge += sin(t * TAU * 1.5 + float(seed)) * amp
		ridge += sin(t * TAU * 4.0 + float(seed) * 2.0) * amp * 0.45
		ridge += (noise(x, seed, seed) - 0.5) * 3.0
		var top: int = int(round(ridge))
		top = clampi(top, 2, height - 2)
		for y in range(top, height):
			img.set_pixel(x, y, color)
	return img


static func make_texture(img: Image, repeat: bool) -> ImageTexture:
	var texture: ImageTexture = ImageTexture.create_from_image(img)
	texture.set_meta("repeat", repeat)
	return texture


static func make_material(tex: Texture2D, uv_scale: Vector2, unshaded := false, transparent := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	if tex != null:
		mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.texture_repeat = true
	mat.uv1_scale = Vector3(uv_scale.x, uv_scale.y, 1.0)
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.metallic_specular = 0.0
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if transparent:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.5
	return mat

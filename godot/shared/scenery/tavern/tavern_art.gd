extends RefCounted

# 酒馆美术资源：纹理缓存、程序材质、程序图与精灵摆放。每个酒馆实例持有一个。

const Texgen = preload("res://shared/scene/texgen.gd")
const AiAssets = preload("res://shared/resources/ai_assets.gd")
const SceneKit = preload("res://shared/scene/scene_kit.gd")

var _textures: Dictionary = {}


func get_tex(key: String) -> ImageTexture:
	if _textures.has(key):
		var cached: ImageTexture = _textures[key]
		return cached
	var img: Image
	match key:
		"plaster":
			img = Texgen.plaster()
		_:
			img = Texgen.wood_planks()
	var texture: ImageTexture = Texgen.make_texture(img, true)
	_textures[key] = texture
	return texture


# Dark wood texture from the AI pack, with the generated planks as a fallback.
func wood_material(uv_scale: Vector2) -> StandardMaterial3D:
	var tex: ImageTexture = AiAssets.load_texture("tex_dark_wood.png")
	if tex != null:
		return Texgen.make_material(tex, uv_scale)
	return Texgen.make_material(get_tex("wood_planks"), uv_scale)


# Floor boards from the AI pack, repeating once every four world units.
func floor_material(uv_scale: Vector2) -> StandardMaterial3D:
	var tex: ImageTexture = AiAssets.load_texture("tex_floor_wood.png")
	if tex != null:
		return Texgen.make_material(tex, uv_scale)
	return wood_material(uv_scale)


# Aged plaster from the AI pack, repeated roughly every 2.5 world units.
func plaster_material(uv_scale: Vector2) -> StandardMaterial3D:
	var tex: ImageTexture = AiAssets.load_texture("tex_aged_plaster.png")
	if tex != null:
		return Texgen.make_material(tex, uv_scale)
	return Texgen.make_material(get_tex("plaster"), uv_scale)


# Crisp pixel-art material for the generated rug and scroll images.
func image_material(img: Image) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.metallic_specular = 0.0
	return mat


func sprite_prop(
	parent: Node3D, file: String, height: float, fallback_size: Vector3, fallback_mat: Material
) -> void:
	var sprite := AiAssets.make_sprite(file, height, Vector3.ZERO, "")
	if sprite != null:
		parent.add_child(sprite)
		return
	SceneKit.add_box(parent, fallback_size, fallback_mat, Vector3(0.0, fallback_size.y * 0.5, 0.0))


# Places a sprite whose world width is fixed, deriving its height from the image.
func sprite_by_width(
	parent: Node3D, file: String, world_width: float, pos: Vector3, node_name: String
) -> Sprite3D:
	var texture: ImageTexture = AiAssets.load_texture(file)
	if texture == null or world_width <= 0.0:
		return null
	var size: Vector2 = texture.get_size()
	if size.x <= 0.0 or size.y <= 0.0:
		return null
	var sprite := AiAssets.make_sprite(
		file, world_width * size.y / size.x, pos, node_name
	)
	if sprite != null:
		parent.add_child(sprite)
	return sprite


func rug_image() -> Image:
	var img: Image = Image.create_empty(64, 36, false, Image.FORMAT_RGBA8)
	var base := Color("#7a2a2a")
	img.fill(base)
	var gold := Color("#a88438")
	var line := Color("#4a1414")
	for y in range(36):
		for x in range(64):
			if x < 2 or x >= 62 or y < 2 or y >= 34:
				img.set_pixel(x, y, gold)
			elif x == 2 or x == 61 or y == 2 or y == 33:
				img.set_pixel(x, y, line)
	var motif := Color("#c9a24a")
	for center_x in [20, 28, 36, 44]:
		for dy in range(-4, 5):
			var half_width: int = 4 - abs(dy)
			for dx in range(-half_width, half_width + 1):
				var px: int = int(center_x) + dx
				var py: int = 18 + dy
				if px >= 4 and px < 60 and py >= 4 and py < 32:
					img.set_pixel(px, py, motif)
	return img


func scroll_image() -> Image:
	var img: Image = Image.create_empty(32, 84, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.88, 0.82, 0.68))
	var far := Color("#6a6a64")
	var near := Color("#3a3a38")
	for x in range(2, 30):
		var t := float(x - 2) / 27.0
		var top := int(57.0 - 8.0 * sin(t * PI))
		for y in range(top, 73):
			img.set_pixel(x, y, far)
	for x in range(3, 29):
		var t := float(x - 3) / 25.0
		var top := int(64.0 - 13.0 * sin(t * PI))
		for y in range(top, 79):
			img.set_pixel(x, y, near)
	var seal := Color("#a8322a")
	for y in range(7, 12):
		for x in range(23, 28):
			img.set_pixel(x, y, seal)
	img.set_pixel(25, 9, Color(0.88, 0.82, 0.68))
	return img

extends RefCounted

# 小镇美术资源：纹理缓存、场景专用材质与标签美术。每个小镇实例持有一个。

const Texgen = preload("res://shared/scene/texgen.gd")
const AiAssets = preload("res://shared/resources/ai_assets.gd")

var _textures: Dictionary = {}


func get_tex(key: String) -> ImageTexture:
	if _textures.has(key):
		var cached: ImageTexture = _textures[key]
		return cached
	var img: Image
	match key:
		"grass":
			img = Texgen.grass()
		"stone_street":
			img = Texgen.stone_street()
		"step_stone":
			img = Texgen.step_stone()
		"wood_planks":
			img = Texgen.wood_planks()
		"plaster":
			img = Texgen.plaster()
		"roof_tiles":
			img = Texgen.roof_tiles()
		"water":
			img = Texgen.water()
		"door":
			img = Texgen.door()
		"window":
			img = Texgen.window()
		"awning_stripes":
			img = Texgen.awning_stripes()
		"cloth_red":
			img = Texgen.cloth(Color(0.75, 0.22, 0.18))
		"tree":
			img = Texgen.tree_sprite()
		"blob_shadow":
			img = Texgen.blob_shadow()
		_:
			img = Texgen.grass()
	var texture: ImageTexture = Texgen.make_texture(img, true)
	_textures[key] = texture
	return texture


# Uses the AI stone-wall texture when available; the passed tiling is in
# "one tile per world unit" terms, and the AI tile spans 2.5 world units.
func make_step_stone_material(tiling: Vector2) -> StandardMaterial3D:
	var tex: ImageTexture = AiAssets.load_texture("tex_stone_wall.png")
	if tex != null:
		return Texgen.make_material(tex, tiling / 2.5)
	return Texgen.make_material(get_tex("step_stone"), tiling)


# Same idea for street/step tops, with the AI cobblestone tile spanning 3 units.
func make_street_material(tiling: Vector2) -> StandardMaterial3D:
	var tex: ImageTexture = AiAssets.load_texture("tex_cobblestone.png")
	if tex != null:
		return Texgen.make_material(tex, tiling / 3.0)
	return Texgen.make_material(get_tex("stone_street"), tiling)


func make_label(text: String, pixel_size: float, font_size: int) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.pixel_size = pixel_size
	label.font_size = font_size
	label.modulate = Color("#f2e2b0")
	label.outline_modulate = Color(0.0, 0.0, 0.0)
	label.outline_size = 10
	label.no_depth_test = false
	label.double_sided = false
	return label

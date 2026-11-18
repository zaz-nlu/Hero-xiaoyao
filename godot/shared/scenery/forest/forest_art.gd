extends RefCounted

# 森林场景的材质工具：草地、道路、泥地与深色木材。
# 只依赖共享资源与渲染工具，不读取任何玩法状态。

const AiAssets = preload("res://shared/resources/ai_assets.gd")
const Texgen = preload("res://shared/scene/texgen.gd")
const SceneKit = preload("res://shared/scene/scene_kit.gd")


func grass_material(uv_scale: Vector2) -> StandardMaterial3D:
	var tex: ImageTexture = AiAssets.load_texture("tex_forest_floor.png")
	if tex == null:
		tex = AiAssets.load_texture("tex_grass.png")
	if tex == null:
		tex = Texgen.make_texture(Texgen.grass(), true)
	return Texgen.make_material(tex, uv_scale)


func path_material(uv_scale: Vector2) -> StandardMaterial3D:
	var tex: ImageTexture = AiAssets.load_texture("tex_forest_path.png")
	if tex == null:
		return dirt_material(uv_scale)
	return Texgen.make_material(tex, uv_scale)


func dirt_material(uv_scale: Vector2) -> StandardMaterial3D:
	var tex: ImageTexture = AiAssets.load_texture("tex_dirt.png")
	if tex == null:
		tex = Texgen.make_texture(Texgen.stone_street(), true)
	return Texgen.make_material(tex, uv_scale)


func dark_wood_material() -> StandardMaterial3D:
	var tex: ImageTexture = AiAssets.load_texture("tex_dark_wood.png")
	if tex != null:
		return Texgen.make_material(tex, Vector2(1.0, 1.0))
	return solid_material(Color("#4a3020"))


func solid_material(color: Color) -> StandardMaterial3D:
	return SceneKit.solid_material(color)

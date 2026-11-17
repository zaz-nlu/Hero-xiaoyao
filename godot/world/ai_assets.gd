extends RefCounted

# Loads the AI-painted art pack from res://assets/ai/game/.
# These PNGs are not imported by Godot, so they must be read from disk.

const BASE_DIR := "res://assets/ai/game/"

static var _textures: Dictionary = {}


static func load_texture(file: String) -> ImageTexture:
	if _textures.has(file):
		var cached: ImageTexture = _textures[file]
		return cached
	var image: Image = _read_image(BASE_DIR + file)
	if image == null:
		_textures[file] = null
		return null
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_textures[file] = texture
	return texture


static func make_sprite(
	file: String, world_height: float, pos: Vector3, name: String
) -> Sprite3D:
	var texture: ImageTexture = load_texture(file)
	if texture == null or world_height <= 0.0:
		return null
	var size: Vector2 = texture.get_size()
	if size.x <= 0.0 or size.y <= 0.0:
		return null
	var sprite := Sprite3D.new()
	if name != "":
		sprite.name = name
	sprite.texture = texture
	sprite.centered = true
	sprite.pixel_size = world_height / size.y
	sprite.offset = Vector2(0.0, size.y * 0.5)
	sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.double_sided = true
	sprite.shaded = true
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	sprite.position = pos
	return sprite


static func make_wall_quad(
	file: String, world_width: float, pos: Vector3, name: String
) -> MeshInstance3D:
	var texture: ImageTexture = load_texture(file)
	if texture == null or world_width <= 0.0:
		return null
	var size: Vector2 = texture.get_size()
	if size.x <= 0.0 or size.y <= 0.0:
		return null
	var height: float = world_width * size.y / size.x
	var quad := QuadMesh.new()
	quad.size = Vector2(world_width, height)
	var instance := MeshInstance3D.new()
	if name != "":
		instance.name = name
	instance.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = texture
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.metallic_specular = 0.0
	mat.emission_enabled = true
	mat.emission = Color.WHITE
	mat.emission_texture = texture
	mat.emission_energy_multiplier = 0.0
	instance.material_override = mat
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	instance.position = Vector3(pos.x, pos.y + height * 0.5, pos.z)
	return instance


static func _read_image(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var image: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null or image.is_empty():
		return null
	return image

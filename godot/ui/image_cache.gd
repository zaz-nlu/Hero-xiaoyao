extends RefCounted

static var _textures: Dictionary = {}


static func texture(path: String) -> Texture2D:
	if _textures.has(path):
		var cached: Texture2D = _textures[path]
		return cached
	var image: Image = Image.load_from_file(path)
	if image == null or image.is_empty():
		return null
	var created: ImageTexture = ImageTexture.create_from_image(image)
	_textures[path] = created
	return created

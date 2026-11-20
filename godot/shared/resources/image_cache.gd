extends RefCounted

static var _textures: Dictionary = {}


static func texture(path: String) -> Texture2D:
	if _textures.has(path):
		var cached: Texture2D = _textures[path]
		return cached
	var created: Texture2D = null
	if ResourceLoader.exists(path, "Texture2D"):
		created = ResourceLoader.load(path, "Texture2D") as Texture2D
	if created == null and FileAccess.file_exists(path):
		var source := Image.load_from_file(path)
		if source != null and not source.is_empty():
			created = ImageTexture.create_from_image(source)
	if created != null:
		_textures[path] = created
	return created


static func image(path: String) -> Image:
	if FileAccess.file_exists(path):
		return Image.load_from_file(path)
	var imported := texture(path)
	if imported == null:
		return null
	var source := imported.get_image()
	if source != null and source.is_compressed() and source.decompress() != OK:
		return null
	return source

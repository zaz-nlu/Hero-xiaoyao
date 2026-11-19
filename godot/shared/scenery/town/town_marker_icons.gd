extends RefCounted

# 头顶任务标记图标：把任务文字映射成徽章图。素材未导入，用 Image.load_from_file 读取。

const ICON_DIR := "res://assets/ui/world/"
const FILE_BY_TEXT := {
	"!": "quest_available.png",
	"?": "quest_ready.png",
	"…": "quest_active.png",
}

static var _textures: Dictionary = {}


# "!"→可接、"?"→可交付、"…"→进行中；其它文字返回 null。
static func texture_for(text: String) -> ImageTexture:
	if not FILE_BY_TEXT.has(text):
		return null
	if _textures.has(text):
		var cached: ImageTexture = _textures[text]
		return cached
	var path := ICON_DIR + str(FILE_BY_TEXT[text])
	if not FileAccess.file_exists(path):
		_textures[text] = null
		return null
	var image: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null or image.is_empty():
		_textures[text] = null
		return null
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_textures[text] = texture
	return texture

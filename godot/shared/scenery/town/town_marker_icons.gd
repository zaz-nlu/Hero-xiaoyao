extends RefCounted

# 头顶任务标记图标：把任务文字映射成徽章图。

const ImageCache = preload("res://shared/resources/image_cache.gd")
const ICON_DIR := "res://assets/ui/world/"
const FILE_BY_TEXT := {
	"!": "quest_available.png",
	"?": "quest_ready.png",
	"…": "quest_active.png",
}

# "!"→可接、"?"→可交付、"…"→进行中；其它文字返回 null。
static func texture_for(text: String) -> Texture2D:
	if not FILE_BY_TEXT.has(text):
		return null
	return ImageCache.texture(ICON_DIR + str(FILE_BY_TEXT[text]))

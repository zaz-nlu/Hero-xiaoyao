extends RefCounted

# 小镇字体：毛笔字标题和招牌。

const BRUSH_PATH := "res://assets/fonts/MaShanZheng-Regular.ttf"

static var _brush: Font = null
static var _brush_loaded: bool = false


static func brush() -> Font:
	if _brush_loaded:
		return _brush
	_brush_loaded = true
	if not FileAccess.file_exists(BRUSH_PATH):
		if ResourceLoader.exists(BRUSH_PATH, "Font"):
			_brush = ResourceLoader.load(BRUSH_PATH, "Font") as Font
		return _brush
	var font := FontFile.new()
	if font.load_dynamic_font(BRUSH_PATH) != OK:
		_brush = null
		return null
	_brush = font
	return _brush

extends RefCounted

# 小镇字体：毛笔字标题/招牌。素材未经过 Godot 导入，用 FontFile.load_dynamic_font
# 直接读原始文件，不要改成 load()/preload()。

const BRUSH_PATH := "res://assets/fonts/MaShanZheng-Regular.ttf"

static var _brush: Font = null
static var _brush_loaded: bool = false


static func brush() -> Font:
	if _brush_loaded:
		return _brush
	_brush_loaded = true
	if not FileAccess.file_exists(BRUSH_PATH):
		_brush = null
		return null
	var font := FontFile.new()
	if font.load_dynamic_font(BRUSH_PATH) != OK:
		_brush = null
		return null
	_brush = font
	return _brush

extends Sprite3D

# 一次性的精灵表特效：按 fps 逐帧播放一行，播完自毁。
# 供过场演出（酒馆前戏等）使用，不依赖战旗的特效系统。

const ImageCache = preload("res://shared/resources/image_cache.gd")

var _fps: float = 16.0
var _age: float = 0.0
var _count: int = 1
var _first: int = 0


# path: 精灵表（res:// 路径，按原始文件读取）；cols/rows: 表格行列数；row: 播放哪一行；
# height: 画面高度（米）；flip: 水平翻转。返回 null 表示素材缺失。
static func spawn(
	parent: Node3D, path: String, cols: int, rows: int, row: int,
	pos: Vector3, height: float, fps: float, tint: Color = Color.WHITE, flip: bool = false
) -> Node3D:
	var texture: Texture2D = ImageCache.texture(path)
	if texture == null or parent == null:
		return null
	var node := new()
	node.texture = texture
	node.hframes = maxi(1, cols)
	node.vframes = maxi(1, rows)
	node._count = maxi(1, cols)
	node._first = clampi(row, 0, maxi(0, rows - 1)) * maxi(1, cols)
	node.frame = node._first
	node._fps = maxf(1.0, fps)
	node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	node.shaded = false
	node.transparent = true
	node.no_depth_test = true
	node.double_sided = true
	node.flip_h = flip
	node.modulate = tint
	node.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cell_height := float(texture.get_height()) / float(maxi(1, rows))
	node.pixel_size = height / maxf(1.0, cell_height)
	node.position = pos
	parent.add_child(node)
	return node


func _process(delta: float) -> void:
	_age += delta
	var index := int(_age * _fps)
	if index >= _count:
		queue_free()
		return
	frame = _first + index

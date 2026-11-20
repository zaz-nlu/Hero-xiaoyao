extends RefCounted

# 帝王世纪：环境压暗。用一层半透明黑色 CanvasLayer 降低整体亮度（15%~25%），
# 不修改场景灯光与材质，关闭时整层释放。镜头相关表现由控制器的 camera_effect() 输出，
# 本模块不碰摄像机。

var _layer: CanvasLayer = null
var _rect: ColorRect = null
var _level: float = 0.0


func ensure(host: Node) -> void:
	if _layer != null and is_instance_valid(_layer):
		return
	if host == null or not host.is_inside_tree():
		return
	_layer = CanvasLayer.new()
	_layer.name = "EmperorDim"
	_layer.layer = 4
	_rect = ColorRect.new()
	_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_rect)
	host.add_child(_layer)


func set_level(host: Node, amount: float) -> void:
	_level = clampf(amount, 0.0, 0.9)
	if _level > 0.001:
		ensure(host)
	if _rect != null and is_instance_valid(_rect):
		_rect.color.a = _level


func level() -> float:
	return _level


func node_count() -> int:
	return 1 if _layer != null and is_instance_valid(_layer) else 0


func cleanup() -> void:
	if _layer != null and is_instance_valid(_layer):
		if _layer.get_parent() != null:
			_layer.get_parent().remove_child(_layer)
		_layer.free()
	_layer = null
	_rect = null
	_level = 0.0

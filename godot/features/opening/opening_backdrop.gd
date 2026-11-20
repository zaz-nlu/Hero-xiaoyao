extends Control

# 序幕背景：按 slide.backdrop 的 kind 分发。
# battlefield → opening_battlefield 的 3D 战场；art → 决战插画 + 暗角；black → 纯黑。
# palette 渐变保留为各自加载失败时的回退；外部仍可通过 set_backdrop_node() 注入节点。

const OpeningBattlefield = preload("res://features/opening/opening_battlefield.gd")
const DomainStage = preload("res://features/opening/opening_domain_stage.gd")
const AiAssets = preload("res://shared/resources/ai_assets.gd")

const PALETTE_TOP := {
	"ash": Color(0.26, 0.26, 0.28),
	"dawn": Color(0.86, 0.5, 0.26),
	"dusk": Color(0.34, 0.1, 0.16),
	"gold": Color(0.72, 0.56, 0.22),
}
const PALETTE_BOTTOM := {
	"ash": Color(0.06, 0.06, 0.07),
	"dawn": Color(0.16, 0.09, 0.12),
	"dusk": Color(0.08, 0.04, 0.12),
	"gold": Color(0.14, 0.09, 0.04),
}
const BLACK := Color(0.0, 0.0, 0.0)

var current_kind: String = "black"
var backdrop_node: Node = null

var _fill: TextureRect = null
var _gradient: Gradient = null
var _art_rect: TextureRect = null
var _art_elapsed: float = 0.0
var _art_seconds: float = 1.0
var _art_zoom_to: float = 1.1
var _art_zoom_value: float = 1.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fill = TextureRect.new()
	_fill.name = "Gradient"
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fill.stretch_mode = TextureRect.STRETCH_SCALE
	_fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fill)
	_gradient = Gradient.new()
	_gradient.offsets = PackedFloat32Array([0.0, 1.0])
	_gradient.colors = PackedColorArray([BLACK, BLACK])
	var texture := GradientTexture2D.new()
	texture.gradient = _gradient
	texture.width = 8
	texture.height = 8
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, 1.0)
	_fill.texture = texture


func apply(slide: Dictionary) -> void:
	var backdrop_value: Variant = slide.get("backdrop", {})
	var backdrop: Dictionary = {}
	if backdrop_value is Dictionary:
		backdrop = backdrop_value
	var kind := str(backdrop.get("kind", "black"))
	var palette := str(backdrop.get("palette", ""))
	var seconds := _seconds_of(slide)
	current_kind = kind
	_art_rect = null
	_art_zoom_value = 1.0
	if kind == "battlefield":
		var top: Color = PALETTE_TOP.get(palette, BLACK)
		var bottom: Color = PALETTE_BOTTOM.get(palette, BLACK)
		_set_colors(top, bottom)
		_build_battlefield(backdrop, seconds)
	elif kind == "art":
		_set_colors(BLACK, BLACK)
		_build_art(backdrop, seconds)
	elif kind == "domain":
		_set_colors(BLACK, BLACK)
		var stage := DomainStage.new()
		stage.name = "DomainStage"
		set_backdrop_node(stage)
		stage.build(backdrop, seconds)
	else:
		current_kind = "black"
		_set_colors(BLACK, BLACK)
		set_backdrop_node(null)


func advance(delta: float) -> void:
	var step := maxf(delta, 0.0)
	if backdrop_node != null and is_instance_valid(backdrop_node):
		if backdrop_node.has_method("advance"):
			backdrop_node.advance(step)
	if _art_rect != null and is_instance_valid(_art_rect):
		_art_elapsed += step
		_apply_art_zoom()


func art_zoom() -> float:
	return _art_zoom_value


func art_zoom_target() -> float:
	return _art_zoom_to


# 下一轮的 3D 战场从这里挂进来；传 null 收回占位渐变。
func set_backdrop_node(node: Node) -> void:
	if backdrop_node != null and is_instance_valid(backdrop_node):
		if backdrop_node.get_parent() == self:
			remove_child(backdrop_node)
		if is_inside_tree():
			backdrop_node.queue_free()
		else:
			backdrop_node.free()
	backdrop_node = node
	if node != null:
		add_child(node)
		if node is Control:
			(node as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _fill != null:
		_fill.visible = node == null


func _build_battlefield(backdrop: Dictionary, seconds: float) -> void:
	var field := OpeningBattlefield.new()
	field.name = "Battlefield"
	set_backdrop_node(field)
	field.build(backdrop, seconds)


func _build_art(backdrop: Dictionary, seconds: float) -> void:
	var texture: Texture2D = AiAssets.load_texture(str(backdrop.get("image", "")))
	if texture == null:
		set_backdrop_node(null)
		return
	var container := Control.new()
	container.name = "ArtBackground"
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rect := TextureRect.new()
	rect.name = "Art"
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.add_child(rect)
	container.add_child(_vignette())
	_art_rect = rect
	_art_seconds = maxf(seconds, 0.001)
	_art_elapsed = 0.0
	_art_zoom_to = _zoom_of(backdrop.get("zoom"))
	_art_zoom_value = 1.0
	set_backdrop_node(container)


# 径向暗角：让浅色插画的四边自然融入黑场。
func _vignette() -> TextureRect:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.0, 0.0, 0.0, 0.0),
		Color(0.0, 0.0, 0.0, 0.0),
		Color(0.0, 0.0, 0.0, 0.82),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = 256
	texture.height = 256
	var rect := TextureRect.new()
	rect.name = "Vignette"
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return rect


func _apply_art_zoom() -> void:
	var t := clampf(_art_elapsed / _art_seconds, 0.0, 1.0)
	var eased := t * t * (3.0 - 2.0 * t)
	_art_zoom_value = lerpf(1.0, _art_zoom_to, eased)
	_art_rect.pivot_offset = _art_rect.size * 0.5
	_art_rect.scale = Vector2(_art_zoom_value, _art_zoom_value)


func _seconds_of(slide: Dictionary) -> float:
	var value: Variant = slide.get("seconds", 0.0)
	if value is int or value is float:
		return maxf(float(value), 0.001)
	return 0.001


func _zoom_of(value: Variant) -> float:
	var zoom := 1.1
	if value is int or value is float:
		zoom = float(value)
	return zoom if zoom > 1.0 else 1.1


func _set_colors(top: Color, bottom: Color) -> void:
	if _gradient == null:
		return
	_gradient.colors = PackedColorArray([top, bottom])

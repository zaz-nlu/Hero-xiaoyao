extends Node3D

const ImageCache = preload("res://shared/resources/image_cache.gd")
const AssetPaths = preload("res://shared/resources/asset_paths.gd")
const Texgen = preload("res://shared/scene/texgen.gd")

const WALK_INTERVAL := 0.125

var facing: String = "down"
var moving: bool = false
var walk_col: int = 1
var _t: float = 0.0
var sprite: Sprite3D = null


func setup(sprite_id: String) -> void:
	if sprite != null:
		return
	sprite = Sprite3D.new()
	sprite.name = "Sprite"
	sprite.texture = ImageCache.texture(AssetPaths.sprite_path(sprite_id))
	sprite.hframes = 5
	sprite.vframes = 4
	sprite.pixel_size = 1.0 / 16.0
	sprite.offset = Vector2(0, 24)
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.shaded = true
	sprite.double_sided = true
	add_child(sprite)
	apply_frame()

	var shadow := MeshInstance3D.new()
	shadow.name = "BlobShadow"
	var quad := QuadMesh.new()
	quad.size = Vector2(1.6, 0.8)
	shadow.mesh = quad
	var shadow_tex: ImageTexture = Texgen.make_texture(Texgen.blob_shadow(), false)
	var shadow_mat: StandardMaterial3D = Texgen.make_material(shadow_tex, Vector2.ONE, true, true)
	shadow_mat.alpha_scissor_threshold = 0.05
	shadow.material_override = shadow_mat
	shadow.position = Vector3(0.0, 0.03, 0.0)
	shadow.rotation.x = -PI / 2.0
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shadow)


func set_facing(f: String) -> void:
	facing = f
	apply_frame()


func set_moving(m: bool) -> void:
	if m and not moving:
		walk_col = 1
		_t = 0.0
	moving = m
	apply_frame()


func advance(delta: float) -> void:
	if not moving:
		return
	_t += delta
	while _t >= WALK_INTERVAL:
		_t -= WALK_INTERVAL
		walk_col += 1
		if walk_col > 4:
			walk_col = 1
	apply_frame()


func current_frame_index() -> int:
	var row: int = 0
	match facing:
		"up":
			row = 1
		"right":
			row = 2
		"left":
			row = 3
		_:
			row = 0
	var col: int = walk_col if moving else 0
	return row * 5 + col


func apply_frame() -> void:
	if sprite == null:
		return
	sprite.frame = current_frame_index()


# 躺倒：节点绕 Z 轴旋转时，精灵不能再做“绕 Y 轴朝向相机”的公告板，否则永远是站着的。
# 躺倒期间改成固定朝向（相机从 +Z 看）并隐藏脚下的圆形阴影，起身后恢复。
func _sync_lying() -> void:
	if sprite == null:
		return
	var lying := absf(rotation.z) > 0.01
	sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED if lying else BaseMaterial3D.BILLBOARD_FIXED_Y
	var shadow: Node = get_node_or_null("BlobShadow")
	if shadow is Node3D:
		(shadow as Node3D).visible = not lying


func _process(delta: float) -> void:
	_sync_lying()
	advance(delta)

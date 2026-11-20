extends RefCounted

# 帝王世纪演出的图形工具：素材读取（原始文件读取，缓存）、程序化贴图（细圆环/斩线/光点）、
# 以及 QuadMesh 特效节点的创建与对象池。所有特效节点都是 MeshInstance3D + QuadMesh，
# 材质为不受光的叠加混合，贴图透明度已由 tools/prepare_emperor_century_vfx.py 抠好。

const ImageCache = preload("res://shared/resources/image_cache.gd")

const DIR := "res://assets/vfx/emperor_century/"
const GOLD := Color(1.0, 0.82, 0.42)

static var _tex: Dictionary = {}
static var _procedural: Dictionary = {}

var _free: Array = []
var _live: int = 0


# ---------------------------------------------------------------- 素材

static func texture(file: String) -> Texture2D:
	if _tex.has(file):
		return _tex[file]
	var loaded: Texture2D = ImageCache.texture(DIR + file + ".png")
	_tex[file] = loaded
	return loaded


static func role_files(config, role: String) -> Array:
	var raw: Variant = config.roles.get(role, [])
	if raw is String:
		return [str(raw)]
	return raw if raw is Array else []


static func role_texture(config, role: String, index: int = 0) -> Texture2D:
	var files := role_files(config, role)
	if files.is_empty():
		return null
	return texture(str(files[clampi(index, 0, files.size() - 1)]))


# ---------------------------------------------------------------- 程序化贴图

# 细金环（真圆，贴地后随战场透视自然变成椭圆）。
static func ring_texture() -> Texture2D:
	if _procedural.has("ring"):
		return _procedural["ring"]
	var size := 256
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var c := float(size) * 0.5
	for y in range(size):
		for x in range(size):
			var r := Vector2(float(x) + 0.5 - c, float(y) + 0.5 - c).length() / c
			var core := 1.0 - clampf(absf(r - 0.96) / 0.012, 0.0, 1.0)
			var glow := (1.0 - clampf(absf(r - 0.96) / 0.06, 0.0, 1.0)) * 0.35
			image.set_pixel(x, y, Color(1.0, 0.9, 0.6, clampf(core + glow, 0.0, 1.0)))
	_procedural["ring"] = ImageTexture.create_from_image(image)
	return _procedural["ring"]


# 水平细线：中间一条亮线，两端渐隐。
static func line_texture() -> Texture2D:
	if _procedural.has("line"):
		return _procedural["line"]
	var width := 128
	var height := 16
	var image := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	for y in range(height):
		for x in range(width):
			var u := float(x) / float(width - 1)
			var v := absf((float(y) + 0.5) / float(height) - 0.5) * 2.0
			var along := clampf(minf(u, 1.0 - u) / 0.18, 0.0, 1.0)
			var core := pow(1.0 - v, 2.2)
			image.set_pixel(x, y, Color(1.0, 0.9, 0.62, clampf(core * along, 0.0, 1.0)))
	_procedural["line"] = ImageTexture.create_from_image(image)
	return _procedural["line"]


# 小光点（暗金色颗粒）。
static func dot_texture() -> Texture2D:
	if _procedural.has("dot"):
		return _procedural["dot"]
	var size := 32
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var c := float(size) * 0.5
	for y in range(size):
		for x in range(size):
			var d := Vector2(float(x) + 0.5 - c, float(y) + 0.5 - c).length() / c
			image.set_pixel(x, y, Color(1.0, 0.85, 0.5, pow(clampf(1.0 - d, 0.0, 1.0), 2.0)))
	_procedural["dot"] = ImageTexture.create_from_image(image)
	return _procedural["dot"]


# ---------------------------------------------------------------- 节点与对象池

# kind: "billboard"（朝向相机）/ "flat"（贴地）/ "ribbon"（手动朝向相机的细条）。
func acquire(parent: Node3D, kind: String, additive: bool = true) -> MeshInstance3D:
	var node: MeshInstance3D = null
	while not _free.is_empty() and node == null:
		var candidate: MeshInstance3D = _free.pop_back()
		if is_instance_valid(candidate):
			node = candidate
	if node == null:
		node = MeshInstance3D.new()
		node.mesh = QuadMesh.new()
		node.material_override = StandardMaterial3D.new()
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material: StandardMaterial3D = node.material_override
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED if kind == "billboard" \
		else BaseMaterial3D.BILLBOARD_DISABLED
	material.albedo_color = Color.WHITE
	node.rotation = Vector3.ZERO
	node.scale = Vector3.ONE
	if kind == "flat":
		node.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	node.set_meta("kind", kind)
	node.visible = true
	if node.get_parent() != parent:
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		parent.add_child(node)
	_live += 1
	return node


func release(node: MeshInstance3D) -> void:
	if node == null or not is_instance_valid(node):
		return
	node.visible = false
	_live = maxi(0, _live - 1)
	_free.append(node)


func live_count() -> int:
	return _live


func pooled_count() -> int:
	return _free.size()


func clear() -> void:
	for node in _free:
		if is_instance_valid(node):
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.free()
	_free.clear()
	_live = 0


# 设置贴图与尺寸（米）与颜色；贴图为空时节点隐藏。
static func setup(node: MeshInstance3D, tex: Texture2D, size: Vector2, tint: Color = Color.WHITE) -> void:
	var material: StandardMaterial3D = node.material_override
	material.albedo_texture = tex
	material.albedo_color = tint
	(node.mesh as QuadMesh).size = size
	node.visible = tex != null


static func set_alpha(node: MeshInstance3D, alpha: float) -> void:
	var material: StandardMaterial3D = node.material_override
	var color: Color = material.albedo_color
	color.a = clampf(alpha, 0.0, 1.0)
	material.albedo_color = color


static func set_tint(node: MeshInstance3D, tint: Color, alpha: float) -> void:
	var material: StandardMaterial3D = node.material_override
	material.albedo_color = Color(tint.r, tint.g, tint.b, clampf(alpha, 0.0, 1.0))

extends Node3D

# 战旗 3D 地块层：按 grid 生成有厚度的立体格子、顶面贴图、侧面与地形道具，
# 并维护每格顶面高亮。只读 grid 数据，不修改战斗规则。

const AiAssets = preload("res://shared/resources/ai_assets.gd")
const ImageCache = preload("res://shared/resources/image_cache.gd")
const SceneKit = preload("res://shared/scene/scene_kit.gd")
const TacticsTheme = preload("res://features/tactics/tactics_theme.gd")

const HIGHLIGHT_PATH := "res://assets/vfx/tile_highlights.png"
const ATLAS_COLS := 3
const ATLAS_ROWS := 2
const PROPS_NODE := "Props"
const DEFAULT_PROP_SCALE := 1.0
const ACCENT_SCALE := 0.9
const ACCENT_FORWARD := 0.4
const HIGHLIGHT_MOVE := Vector2i(0, 0)
const HIGHLIGHT_ATTACK := Vector2i(1, 0)
const HIGHLIGHT_CORNERS := Vector2i(2, 0)
const HIGHLIGHT_WHITE := Vector2i(2, 1)
const TOP_INSET := 0.03
const CHECKER_LIGHT := 1.0
const CHECKER_DARK := 0.9
const MOVE_TINT := Color(0.58, 0.84, 1.0, 0.6)
const ATTACK_TINT := Color(1.0, 0.88, 0.88, 0.6)
const AFFECTED_TINT := Color(1.0, 0.72, 0.30, 0.6)
const GOLD_TINT := Color(1.0, 0.84, 0.34, 0.75)
const HOVER_TINT := Color(1.0, 1.0, 1.0, 0.7)

# 图集用品红作未抠底色，shader 里直接丢弃，避免高亮块泛紫。
const HIGHLIGHT_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	if (c.r > 0.7 && c.b > 0.7 && c.g < 0.3) {
		discard;
	}
	ALBEDO = c.rgb * tint.rgb;
	ALPHA = c.a * tint.a;
}
"""

static var _materials: Dictionary = {}
static var _atlas: Texture2D = null
static var _regions: Dictionary = {}
static var _highlight_materials: Dictionary = {}

var grid: Variant = null
var cell_size: float = TacticsTheme.CELL_SIZE
var level_height: float = TacticsTheme.LEVEL_HEIGHT

var _cells: Dictionary = {}
var _props: Dictionary = {}
var _props_root: Node3D = null
var _highlights: Dictionary = {}
var _hover: Vector2i = Vector2i(-1, -1)
var _last_overlays: Dictionary = {}


func build(p_grid, p_theme: Dictionary) -> void:
	_clear()
	grid = p_grid
	cell_size = float(p_theme.get("cell_size", TacticsTheme.CELL_SIZE))
	level_height = float(p_theme.get("level_height", TacticsTheme.LEVEL_HEIGHT))
	if grid == null:
		return
	_props_root = Node3D.new()
	_props_root.name = PROPS_NODE
	add_child(_props_root)
	for y in range(int(grid.height)):
		for x in range(int(grid.width)):
			_build_cell(Vector2i(x, y), p_theme)


func cell_count() -> int:
	if grid == null:
		return 0
	return int(grid.width) * int(grid.height)


func tile_node(cell: Vector2i):
	return _cells.get(cell, null)


func prop_node(cell: Vector2i):
	return _props.get(cell, null)


func props_root():
	return _props_root


func highlight_node(cell: Vector2i):
	return _highlights.get(cell, null)


# 格子顶面中心的本地世界坐标（含高度）。
func cell_center(cell: Vector2i) -> Vector3:
	var origin := _board_origin()
	return Vector3(
		origin.x + float(cell.x) * cell_size,
		top_y(cell),
		origin.z + float(cell.y) * cell_size)


func top_y(cell: Vector2i) -> float:
	if grid == null or not grid.in_bounds(cell):
		return 0.0
	var level := float(int(grid.height_at(cell))) * level_height
	var terrain := str(grid.terrain_at(cell))
	if terrain == "water":
		return level - 0.12
	if terrain == "wall":
		return level + 2.0 * level_height
	return level


func cell_from_world(pos: Vector3) -> Vector2i:
	if grid == null:
		return Vector2i(-1, -1)
	var origin := _board_origin()
	var x := int(floor((pos.x - origin.x + cell_size * 0.5) / cell_size))
	var y := int(floor((pos.z - origin.z + cell_size * 0.5) / cell_size))
	if x < 0 or y < 0 or x >= int(grid.width) or y >= int(grid.height):
		return Vector2i(-1, -1)
	return Vector2i(x, y)


func set_hover(cell: Vector2i) -> void:
	if _hover == cell:
		return
	_hover = cell
	_apply_highlights()


func set_highlights(overlays: Dictionary) -> void:
	_last_overlays = overlays.duplicate()
	_apply_highlights()


func _apply_highlights() -> void:
	var states: Dictionary = {}
	var affected: Dictionary = {}
	var active = _last_overlays.get("active", null)
	if active is Vector2i and active.x >= 0:
		states[active] = HIGHLIGHT_CORNERS
	for raw in _list(_last_overlays.get("move", [])):
		if raw is Vector2i:
			states[raw] = HIGHLIGHT_MOVE
	for raw in _list(_last_overlays.get("attack", [])):
		if raw is Vector2i:
			states[raw] = HIGHLIGHT_ATTACK
	for raw in _list(_last_overlays.get("affected", [])):
		if raw is Vector2i:
			states[raw] = HIGHLIGHT_CORNERS
			affected[raw] = true
	var selected = _last_overlays.get("selected", null)
	if selected is Vector2i and selected.x >= 0:
		states[selected] = HIGHLIGHT_WHITE
	if _hover.x >= 0:
		states[_hover] = HIGHLIGHT_WHITE
	for cell in _highlights.keys():
		var node: Sprite3D = _highlights[cell]
		if node == null or not is_instance_valid(node):
			continue
		if states.has(cell):
			var region: Vector2i = states[cell]
			node.texture = _highlight_texture(region)
			node.material_override = _highlight_material(
				region, _highlight_tint(region, affected.has(cell), cell, selected))
			node.visible = true
		else:
			node.visible = false


func _highlight_tint(
	region: Vector2i, is_affected: bool, cell: Vector2i, selected: Variant
) -> Color:
	if is_affected:
		return AFFECTED_TINT
	if region == HIGHLIGHT_MOVE:
		return MOVE_TINT
	if region == HIGHLIGHT_ATTACK:
		return ATTACK_TINT
	if region == HIGHLIGHT_CORNERS:
		return GOLD_TINT
	if selected is Vector2i and selected == cell:
		return GOLD_TINT
	return HOVER_TINT


func _build_cell(cell: Vector2i, theme: Dictionary) -> void:
	var holder := Node3D.new()
	holder.name = "Tile_%d_%d" % [cell.x, cell.y]
	holder.position = _cell_origin(cell)
	add_child(holder)
	_cells[cell] = holder

	var terrain := str(grid.terrain_at(cell))
	var top := top_y(cell)
	var top_file := _file_for(theme, "top", terrain)
	var side_file := _file_for(theme, "side", terrain)
	var side_tint := Color.WHITE
	if terrain == "wall":
		# 墙体统一用深色木料，避免实心浅色方块。
		side_file = str(theme.get("wall_side", side_file))
		top_file = str(theme.get("wall_top", top_file))
		side_tint = theme.get("wall_side_tint", Color.WHITE)
	var side_mat: StandardMaterial3D = _material(side_file, 1.0, side_tint)
	if terrain == "water":
		side_mat = _material(side_file, 0.7, Color(0.55, 0.75, 0.95))
		var column_h := maxf(0.3, top + 0.35)
		SceneKit.add_box(
			holder, Vector3(cell_size * 0.985, column_h, cell_size * 0.985),
			side_mat, Vector3(0.0, top - column_h * 0.5, 0.0), "Column")
	else:
		var column_h := maxf(0.35, top + 0.35)
		SceneKit.add_box(
			holder, Vector3(cell_size * 0.985, column_h, cell_size * 0.985),
			side_mat, Vector3(0.0, top - column_h * 0.5, 0.0), "Column")

	var top_mat: StandardMaterial3D = _material(
		top_file, 1.0, _top_tint(cell, terrain, theme))
	if terrain == "water":
		top_mat = _material(top_file, 0.72, Color(0.55, 0.75, 0.95))
	var quad := QuadMesh.new()
	quad.size = Vector2(cell_size - TOP_INSET, cell_size - TOP_INSET)
	var surface := MeshInstance3D.new()
	surface.name = "Top"
	surface.mesh = quad
	surface.material_override = top_mat
	surface.rotation.x = -PI / 2.0
	surface.position = Vector3(0.0, top + 0.01, 0.0)
	holder.add_child(surface)

	_build_cell_props(cell, terrain, top, theme)

	var highlight := Sprite3D.new()
	highlight.name = "Highlight"
	highlight.texture = _highlight_texture(HIGHLIGHT_WHITE)
	highlight.material_override = _highlight_material(HIGHLIGHT_WHITE, HOVER_TINT)
	highlight.pixel_size = cell_size / 512.0
	highlight.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	highlight.shaded = false
	highlight.no_depth_test = false
	highlight.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	highlight.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	highlight.rotation.x = -PI / 2.0
	highlight.position = Vector3(0.0, top + 0.035, 0.0)
	highlight.visible = false
	holder.add_child(highlight)
	_highlights[cell] = highlight


# 场景道具集中挂在 Props 下，节点名带格子坐标，缺素材时跳过。
func _build_cell_props(
	cell: Vector2i, terrain: String, top: float, theme: Dictionary
) -> void:
	var props_table: Dictionary = theme.get("props", {})
	var prop_key := terrain
	if terrain == "wall":
		var is_back := bool(theme.get("back_wall_row", false)) and cell.y == 0
		prop_key = "wall_back" if is_back else "wall_front"
	var files: Array = props_table.get(prop_key, [])
	if files.is_empty():
		return
	var index := absi(cell.x * 7 + cell.y * 13) % files.size()
	var file := str(files[index])
	var height := TacticsTheme.prop_height(file) * _prop_scale(theme, terrain)
	var sprite = _add_prop(
		cell, file, height, top, "Prop_%d_%d" % [cell.x, cell.y])
	if sprite != null:
		_props[cell] = sprite
	if prop_key != "wall_back":
		return
	var accents: Array = props_table.get("wall_back_accent", [])
	if accents.is_empty() or cell.x % 2 == 0:
		return
	var accent := str(accents[(cell.x / 2) % accents.size()])
	_add_prop(cell, accent, TacticsTheme.prop_height(accent) * ACCENT_SCALE,
		top + 0.02, "Accent_%d_%d" % [cell.x, cell.y],
		Vector3(0.0, 0.0, ACCENT_FORWARD))


func _add_prop(cell: Vector2i, file: String, world_height: float, top: float,
		node_name: String, offset: Vector3 = Vector3.ZERO):
	if _props_root == null or file == "":
		return null
	var pos := _cell_origin(cell) + Vector3(0.0, top, 0.0) + offset
	var sprite = AiAssets.make_sprite(file, world_height, pos, node_name)
	if sprite == null:
		return null
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_props_root.add_child(sprite)
	return sprite


func _prop_scale(theme: Dictionary, terrain: String) -> float:
	var table: Variant = theme.get("prop_scale", {})
	if table is Dictionary:
		return float(table.get(terrain, DEFAULT_PROP_SCALE))
	return DEFAULT_PROP_SCALE


func _board_origin() -> Vector3:
	if grid == null:
		return Vector3.ZERO
	return Vector3(
		-float(grid.width) * cell_size * 0.5 + cell_size * 0.5, 0.0,
		-float(grid.height) * cell_size * 0.5 + cell_size * 0.5)


func _cell_origin(cell: Vector2i) -> Vector3:
	var origin := _board_origin()
	return Vector3(
		origin.x + float(cell.x) * cell_size, 0.0,
		origin.z + float(cell.y) * cell_size)


func _file_for(theme: Dictionary, group: String, terrain: String) -> String:
	var table: Dictionary = theme.get(group, {})
	var file := str(table.get(terrain, table.get("floor", "")))
	if file == "":
		return "tex_grass.png"
	return file


# 地板顶面做轻微棋盘格明暗交替，墙体用主题里的深色顶面，其余地形保持原色。
func _top_tint(cell: Vector2i, terrain: String, theme: Dictionary) -> Color:
	if terrain == "wall":
		return theme.get("wall_top_tint", Color.WHITE)
	if terrain != "floor":
		return Color.WHITE
	var tone := CHECKER_LIGHT if (cell.x + cell.y) % 2 == 0 else CHECKER_DARK
	return Color(tone, tone, tone)


func _list(raw: Variant) -> Array:
	return raw if raw is Array else []


func _clear() -> void:
	for child in get_children():
		remove_child(child)
		if is_inside_tree():
			child.queue_free()
		else:
			child.free()
	_cells.clear()
	_props.clear()
	_props_root = null
	_highlights.clear()
	_hover = Vector2i(-1, -1)
	_last_overlays = {}


static func _highlight_texture(region_cell: Vector2i) -> Texture2D:
	var key := "%d_%d" % [region_cell.x, region_cell.y]
	if _regions.has(key):
		return _regions[key]
	if _atlas == null:
		_atlas = ImageCache.texture(HIGHLIGHT_PATH)
	var atlas := AtlasTexture.new()
	atlas.atlas = _atlas
	if _atlas != null:
		var cell_w := float(_atlas.get_width()) / float(ATLAS_COLS)
		var cell_h := float(_atlas.get_height()) / float(ATLAS_ROWS)
		atlas.region = Rect2(
			float(region_cell.x) * cell_w, float(region_cell.y) * cell_h,
			cell_w, cell_h)
	_regions[key] = atlas
	return atlas


static func _highlight_material(
	region_cell: Vector2i, tint: Color
) -> ShaderMaterial:
	var key := "%d_%d|%s" % [region_cell.x, region_cell.y, tint]
	if _highlight_materials.has(key):
		return _highlight_materials[key]
	var shader := Shader.new()
	shader.code = HIGHLIGHT_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("albedo_tex", _highlight_texture(region_cell))
	mat.set_shader_parameter("tint", tint)
	_highlight_materials[key] = mat
	return mat


static func _material(
	file: String, alpha: float = 1.0, tint: Color = Color.WHITE
) -> StandardMaterial3D:
	var key := "%s|%.2f|%s" % [file, alpha, tint]
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	var texture: Texture2D = AiAssets.load_texture(file)
	if texture != null:
		mat.albedo_texture = texture
	mat.albedo_color = Color(tint.r, tint.g, tint.b, alpha)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.metallic_specular = 0.0
	if alpha < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_materials[key] = mat
	return mat

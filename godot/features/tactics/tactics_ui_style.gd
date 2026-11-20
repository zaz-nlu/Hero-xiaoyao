extends RefCounted

# 战旗 UI 的统一样式表：颜色常量、StyleBox 工厂、单位头像裁剪与武学图标读取。
# 底部技能栏 / 行动条 / 单位卡 / 日志 / 反制菜单都从这里取样式。
#
# 贴图可替换：res://assets/ui/tactics/ 下存在约定文件时用九宫格 StyleBoxTexture，
# 尺寸与九宫格边距读同目录的 layout.json；缺文件时回退 StyleBoxFlat
# （深褐木色底、金色细边、圆角 6、轻微阴影）。

const ImageCache = preload("res://shared/resources/image_cache.gd")
const AssetPaths = preload("res://shared/resources/asset_paths.gd")

# 目录拆成两段，避免静态检查把尚不存在的素材目录当成缺失资源。
const TEXTURE_DIR := "res://"
const TEXTURE_SUBDIR := "assets/ui/tactics/"
const LAYOUT_FILE := "layout.json"
# 九宫格内容边距 = 贴图边距 + 这层留白。
const CONTENT_PAD := 3.0
const ICON_DIR := "res://assets/icons/"
const TEXTURE_FILES := {
	"panel_frame": "panel_frame.png",
	"panel_filled": "panel_frame_wood_filled.png",
	"turn_card": "turn_card.png",
	"turn_card_active": "turn_card_active.png",
	"skill_button": "skill_button.png",
	"skill_button_selected": "skill_button_selected.png",
	"skill_button_disabled": "skill_button_disabled.png",
	"unit_card": "unit_card.png",
	"bar_hp": "bar_hp.png",
	"bar_hp_bg": "bar_hp_bg.png",
	"bar_toughness": "bar_toughness.png",
	"pip_toughness": "pip_toughness.png",
	"pip_toughness_empty": "pip_toughness_empty.png",
	"pip_jianyi": "pip_jianyi.png",
	"pip_jianyi_empty": "pip_jianyi_empty.png",
	"energy_neili": "energy_neili.png",
	"energy_ziqi": "energy_ziqi.png",
	"energy_xianqi": "energy_xianqi.png",
	"form_thrust": "form_thrust.png",
	"form_chop": "form_chop.png",
	"form_sweep": "form_sweep.png",
	"form_point": "form_point.png",
	"weak_neili": "weak_neili.png",
	"weak_ziqi": "weak_ziqi.png",
	"weak_xianqi": "weak_xianqi.png",
	"release": "release.png",
}

const BG_WOOD := Color(0.11, 0.075, 0.05, 0.94)
const BG_WOOD_LIGHT := Color(0.17, 0.115, 0.075, 0.97)
const BG_WOOD_DARK := Color(0.065, 0.048, 0.034, 0.96)
const GOLD := Color(0.78, 0.65, 0.35)
const GOLD_BRIGHT := Color(1.0, 0.88, 0.52)
const GOLD_DIM := Color(0.48, 0.39, 0.22)
const TEXT := Color(0.95, 0.92, 0.85)
const MUTED := Color(0.69, 0.64, 0.56)
const HP_RED := Color(0.78, 0.2, 0.2)
const HP_RED_DARK := Color(0.3, 0.07, 0.07, 0.9)
const TOUGH_GOLD := Color(0.95, 0.8, 0.35)
const TOUGH_OFF := Color(0.26, 0.23, 0.2, 0.9)
const JIANYI_PURPLE := Color(0.68, 0.48, 0.95)
const REACTION_CYAN := Color(0.38, 0.78, 0.86)
const PLAYER_BG := Color(0.11, 0.18, 0.34, 0.96)
const PLAYER_BORDER := Color(0.76, 0.64, 0.32)
const ENEMY_BG := Color(0.3, 0.09, 0.09, 0.96)
const ENEMY_BORDER := Color(0.52, 0.16, 0.14)
const TURN_NAME_PLAYER := Color(0.74, 0.82, 0.95)
const TURN_NAME_ENEMY := Color(0.95, 0.7, 0.66)
const PLAYER_AVATAR_BG := Color(0.16, 0.22, 0.34, 0.96)
const ENEMY_AVATAR_BG := Color(0.34, 0.12, 0.12, 0.96)
const LOG_SIDE := Color(1.0, 0.85, 0.42)
const LOG_REACTION := Color(0.42, 0.86, 0.92)
const LOG_KILL := Color(0.95, 0.32, 0.28)
const RADIUS := 6

static var _textures: Dictionary = {}
static var _styles: Dictionary = {}
static var _portraits: Dictionary = {}
static var _icons: Dictionary = {}
static var _texture_dir: String = TEXTURE_DIR + TEXTURE_SUBDIR
static var _layout_entries: Dictionary = {}
static var _layout_ready := false


# ---- 贴图与回退 -----------------------------------------------------------

# 测试与降级用：切到另一个素材目录会清空贴图 / 样式 / 布局缓存。
static func set_texture_dir(dir: String) -> void:
	_texture_dir = (TEXTURE_DIR + TEXTURE_SUBDIR) if dir == "" else dir
	_textures.clear()
	_styles.clear()
	_layout_entries.clear()
	_layout_ready = false


static func reset_texture_dir() -> void:
	set_texture_dir("")


static func texture_dir() -> String:
	return _texture_dir


static func _image_texture(path: String) -> Texture2D:
	return ImageCache.texture(path)


static func _load_layout() -> void:
	if _layout_ready:
		return
	_layout_ready = true
	var path := _texture_dir + LAYOUT_FILE
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		var entries: Dictionary = parsed
		_layout_entries = entries


# layout.json 中某个贴图的 {size, margins}；缺省返回空字典。
static func layout_for(key: String) -> Dictionary:
	_load_layout()
	var file := str(TEXTURE_FILES.get(key, ""))
	if file == "":
		file = key if key.ends_with(".png") else key + ".png"
	var entry: Dictionary = _layout_entries.get(file, {})
	return entry


static func layout_size(key: String) -> Vector2:
	var size: Variant = layout_for(key).get("size", [])
	if size is Array and size.size() >= 2:
		return Vector2(float(size[0]), float(size[1]))
	var texture := _texture_for(key)
	return texture.get_size() if texture != null else Vector2.ZERO


static func _layout_margin(key: String, side: String, fallback: float) -> float:
	var margins: Variant = layout_for(key).get("margins", {})
	if margins is Dictionary:
		return float(margins.get(side, fallback))
	return fallback


static func _texture_for(key: String) -> Texture2D:
	if _textures.has(key):
		var cached: Texture2D = _textures[key]
		return cached
	var file := str(TEXTURE_FILES.get(key, ""))
	var texture: Texture2D = null
	if file != "":
		texture = _image_texture(_texture_dir + file)
	_textures[key] = texture
	return texture


static func texture_for(key: String) -> Texture2D:
	return _texture_for(key)


# 九宫格贴图；边距读 layout.json，缺省取图片宽高的 1/4。
# 缺图时返回 null，由调用方回退 StyleBoxFlat。
static func _textured_style(key: String) -> StyleBoxTexture:
	if _styles.has("tex|" + key):
		var cached: StyleBoxTexture = _styles["tex|" + key]
		return cached
	var texture := _texture_for(key)
	if texture == null:
		return null
	var style := StyleBoxTexture.new()
	style.texture = texture
	var size := texture.get_size()
	var left := _layout_margin(key, "left", size.x * 0.25)
	var right := _layout_margin(key, "right", size.x * 0.25)
	var top := _layout_margin(key, "top", size.y * 0.25)
	var bottom := _layout_margin(key, "bottom", size.y * 0.25)
	style.texture_margin_left = left
	style.texture_margin_right = right
	style.texture_margin_top = top
	style.texture_margin_bottom = bottom
	style.content_margin_left = left + CONTENT_PAD
	style.content_margin_right = right + CONTENT_PAD
	style.content_margin_top = top + CONTENT_PAD
	style.content_margin_bottom = bottom + CONTENT_PAD
	_styles["tex|" + key] = style
	return style


static func _flat(
	bg: Color, border: Color, width: int = 1, radius: int = RADIUS
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.38)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0.0, 2.0)
	return style


# ---- 面板与卡片 -----------------------------------------------------------

# 实心木底的面板（反制菜单、结果层等需要盖住背景的浮层用它，字才看得清）。
static func panel_filled_style() -> StyleBox:
	var textured := _textured_style("panel_filled")
	if textured != null:
		return textured
	var style := _flat(BG_WOOD_DARK, GOLD, 1, RADIUS)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


static func panel_style() -> StyleBox:
	var textured := _textured_style("panel_frame")
	if textured != null:
		return textured
	var style := _flat(BG_WOOD, GOLD, 1, RADIUS)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


# 顶部行动条背后的半透明深色横带。
static func turn_band_style() -> StyleBox:
	var style := _flat(Color(0.045, 0.035, 0.03, 0.72), Color(0.78, 0.65, 0.35, 0.3), 0, 0)
	style.border_width_bottom = 1
	style.shadow_size = 0
	return style


static func turn_card_style(side: String, current: bool) -> StyleBox:
	var textured := _textured_style("turn_card_active" if current else "turn_card")
	if textured != null:
		return textured
	var bg := PLAYER_BG if side == "player" else ENEMY_BG
	var border := PLAYER_BORDER if side == "player" else ENEMY_BORDER
	if current:
		border = GOLD_BRIGHT
	var style := _flat(bg, border, 3 if current else 1, RADIUS)
	if current:
		style.shadow_color = Color(1.0, 0.84, 0.4, 0.5)
		style.shadow_size = 10
	return style


static func turn_name_color(side: String, current: bool) -> Color:
	if current:
		return GOLD_BRIGHT
	return TURN_NAME_PLAYER if side == "player" else TURN_NAME_ENEMY


static func avatar_bg(side: String) -> Color:
	return PLAYER_AVATAR_BG if side == "player" else ENEMY_AVATAR_BG


static func unit_card_style() -> StyleBox:
	var textured := _textured_style("unit_card")
	if textured != null:
		return textured
	var style := _flat(BG_WOOD, GOLD, 1, RADIUS)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


# ---- 按钮 / 角标 / 提示 ---------------------------------------------------

static func button_style(state: String = "normal", selected: bool = false) -> StyleBox:
	var textured: StyleBoxTexture = null
	if state == "normal":
		textured = _textured_style(
			"skill_button_selected" if selected else "skill_button")
	elif state == "hover" or state == "pressed":
		textured = _textured_style("skill_button")
	elif state == "disabled":
		textured = _textured_style("skill_button_disabled")
	if textured != null:
		return textured
	if state == "normal" and selected:
		return _flat(BG_WOOD_LIGHT, GOLD_BRIGHT, 3, RADIUS)
	if state == "normal":
		return _flat(BG_WOOD, GOLD, 1, RADIUS)
	match state:
		"hover":
			return _flat(BG_WOOD_LIGHT, GOLD_BRIGHT, 2, RADIUS)
		"pressed":
			return _flat(Color(0.23, 0.16, 0.1, 0.98), GOLD_BRIGHT, 2, RADIUS)
		"disabled":
			var muted := _flat(
				Color(0.09, 0.085, 0.075, 0.82),
				Color(0.35, 0.3, 0.22, 0.75), 1, RADIUS)
			muted.shadow_size = 0
			return muted
		_:
			return _flat(BG_WOOD, GOLD, 1, RADIUS)


# 能量切换的小标签：选中金色描边，未选中暗金细边。
static func energy_style(selected: bool) -> StyleBoxFlat:
	var style := _flat(
		Color(0.06, 0.05, 0.04, 0.9),
		GOLD_BRIGHT if selected else GOLD_DIM,
		2 if selected else 1, 4)
	style.content_margin_left = 5.0
	style.content_margin_right = 6.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	style.shadow_size = 0
	return style


static func badge_style(border: Color = GOLD) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.02, 0.03, 0.95)
	style.border_color = Color(border.r, border.g, border.b, 0.85)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 2.0
	style.content_margin_right = 2.0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	return style


static func tooltip_style() -> StyleBox:
	var style := _flat(BG_WOOD_DARK, GOLD, 1, RADIUS)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	style.shadow_size = 6
	return style


static func bar_bg_style() -> StyleBox:
	var textured := _textured_style("bar_hp_bg")
	if textured != null:
		return textured
	var style := _flat(
		Color(0.02, 0.02, 0.025, 0.85), Color(0.78, 0.65, 0.35, 0.35), 1, 3)
	style.shadow_size = 0
	return style


static func bar_fill_style(kind: String = "hp") -> StyleBox:
	var key := "bar_toughness" if kind == "toughness" else "bar_hp"
	var textured := _textured_style(key)
	if textured != null:
		return textured
	var color: Color = TOUGH_GOLD if kind == "toughness" else HP_RED
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(3)
	return style


static func configure_label(label: Label, font_size: int, color: Color) -> void:
	if label == null:
		return
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE


# ---- 素材：单位头像与武学图标 --------------------------------------------

# 玩家固定用主角立绘；敌人用 def.sprite，最后退回单位 id。
static func unit_sprite_id(unit) -> String:
	if unit == null:
		return ""
	if str(unit.side) == "player":
		return str(unit.sprite_id) if str(unit.sprite_id) != "" else "ren_xiaoyao"
	if unit.unit != null and unit.unit.def != null:
		var sprite := str(unit.unit.def.sprite)
		if sprite != "":
			return sprite
	var fallback := str(unit.unit.id) if unit.unit != null else ""
	return fallback if fallback != "" else "bandit"


# 单位卡片用的立绘（assets/portraits/<id>.png 的上半身）；没有立绘时退回精灵正面。
static func card_portrait_texture(unit, aspect: float = 1.2) -> Texture2D:
	var id := unit_sprite_id(unit)
	var key := "card_%s_%.2f" % [id, aspect]
	if _portraits.has(key):
		var cached: Texture2D = _portraits[key]
		return cached
	var art: Texture2D = ImageCache.texture(AssetPaths.PORTRAITS + id + ".png")
	var out: Texture2D = null
	if art != null and art.get_width() > 0:
		var crop := AtlasTexture.new()
		crop.atlas = art
		crop.region = Rect2(0.0, 0.0, art.get_width(), minf(art.get_height(), art.get_width() * aspect))
		out = crop
	else:
		out = portrait_texture(unit)
	_portraits[key] = out
	return out


# 立绘图集为 5×4，正面站立是第 0 行第 0 帧，用 AtlasTexture 裁出。
static func portrait_texture(unit) -> Texture2D:
	var sprite_id := unit_sprite_id(unit)
	if sprite_id == "":
		return null
	if _portraits.has(sprite_id):
		var cached: Texture2D = _portraits[sprite_id]
		return cached
	var atlas: Texture2D = ImageCache.texture(AssetPaths.sprite_path(sprite_id))
	var portrait: Texture2D = null
	if atlas != null and atlas.get_width() > 0 and atlas.get_height() > 0:
		var crop := AtlasTexture.new()
		crop.atlas = atlas
		crop.region = Rect2(
			0.0, 0.0,
			atlas.get_width() / 5.0, atlas.get_height() / 4.0)
		portrait = crop
	_portraits[sprite_id] = portrait
	return portrait


# 取不到头像时用名字生成稳定的色块颜色。
static func name_color(name: String) -> Color:
	var seed_value := absi(name.hash())
	var hue := float(seed_value % 360) / 360.0
	return Color.from_hsv(hue, 0.42, 0.52)


# 武学图标：res://assets/icons/icon_martial_<id>.png，直接读原始 PNG 并缓存。
static func martial_icon(martial_id: String) -> Texture2D:
	if martial_id == "":
		return null
	if _icons.has(martial_id):
		var cached: Texture2D = _icons[martial_id]
		return cached
	var texture := _image_texture(ICON_DIR + "icon_martial_" + martial_id + ".png")
	_icons[martial_id] = texture
	return texture


# 招式形态图标（thrust/chop/sweep/point）：缺素材返回 null，由调用方回退文字。
static func form_icon(form: String) -> Texture2D:
	if form == "":
		return null
	return _texture_for("form_" + form)


# 韧性 / 剑意点：filled=false 取 _empty 版本。
static func pip_texture(kind: String, filled: bool) -> Texture2D:
	return _texture_for("pip_" + kind + ("" if filled else "_empty"))


static func energy_icon(color: String) -> Texture2D:
	return _texture_for("energy_" + color)


static func release_icon() -> Texture2D:
	return _texture_for("release")

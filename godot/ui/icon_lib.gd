extends RefCounted

# 统一的界面图标入口：武学、物品、属性。
# 图标来自 res://assets/ai/game/（透明 PNG），缺失时返回 null，由调用方回退。

const AiAssets = preload("res://world/ai_assets.gd")

const ICON_DIR := "icon_"
const ITEM_FILES := {
	"plain_sword": "icon_item_iron_sword.png",
	"herb": "icon_item_herbs.png",
	"cloth_robe": "icon_item_cloth_robe.png",
	"jade_pendant": "icon_item_jade_pendant.png",
	"iron_ore": "icon_item_iron_key.png",
	"old_box": "icon_item_old_scroll.png",
	"jade_hairpin": "icon_item_jade_pendant.png",
	"ginseng": "icon_item_herbs.png",
	"healing_pills": "icon_item_healing_pills.png",
}

static var _martial_cache: Dictionary = {}
static var _item_cache: Dictionary = {}
static var _stat_cache: Dictionary = {}


static func martial_icon(id: String) -> Texture2D:
	if id == "":
		return null
	if _martial_cache.has(id):
		var cached: Texture2D = _martial_cache[id]
		return cached
	var texture: Texture2D = AiAssets.load_texture(ICON_DIR + "martial_" + id + ".png")
	_martial_cache[id] = texture
	return texture


static func item_icon(id: String) -> Texture2D:
	if id == "":
		return null
	if _item_cache.has(id):
		var cached: Texture2D = _item_cache[id]
		return cached
	var file: String = str(ITEM_FILES.get(id, ""))
	if file == "":
		file = ICON_DIR + "item_" + id + ".png"
	var texture: Texture2D = AiAssets.load_texture(file)
	_item_cache[id] = texture
	return texture


static func stat_icon(stat: String) -> Texture2D:
	if stat == "":
		return null
	if _stat_cache.has(stat):
		var cached: Texture2D = _stat_cache[stat]
		return cached
	var texture: Texture2D = AiAssets.load_texture(ICON_DIR + "stat_" + stat + ".png")
	_stat_cache[stat] = texture
	return texture

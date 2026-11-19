extends RefCounted

# 战旗 3D 舞台的主题表：按地图 meta.backdrop 返回地形贴图、道具、光照与外壳参数。
# 纯数据，不创建节点；地块/演员/特效的构建逻辑在各 stage_* 脚本里。

const CELL_SIZE := 2.4
const LEVEL_HEIGHT := 0.7

# 道具 sprite 的世界高度（米）。未登记的文件使用 DEFAULT_PROP_HEIGHT。
const DEFAULT_PROP_HEIGHT := 1.2
const PROP_HEIGHTS := {
	"prop_crates.png": 1.5,
	"prop_barrel.png": 1.5,
	"prop_jars.png": 1.0,
	"prop_baskets.png": 1.0,
	"prop_boulder.png": 1.3,
	"prop_rocks.png": 0.9,
	"prop_stump.png": 0.8,
	"prop_log.png": 0.7,
	"prop_shrub.png": 1.1,
	"prop_fern.png": 0.8,
	"prop_grass.png": 0.6,
	"prop_willow.png": 5.0,
	"prop_bamboo.png": 3.4,
	"tree_camphor.png": 5.4,
	"tree_pine.png": 4.6,
	"tavern_square_table.png": 1.2,
	"tavern_round_table.png": 1.1,
	"tavern_long_bench.png": 0.8,
	"tavern_small_stool.png": 0.7,
	"tavern_bar_counter.png": 1.6,
}


static func cell_size() -> float:
	return CELL_SIZE


static func level_height() -> float:
	return LEVEL_HEIGHT


static func prop_height(file: String) -> float:
	return float(PROP_HEIGHTS.get(file, DEFAULT_PROP_HEIGHT))


static func for_backdrop(backdrop: String) -> Dictionary:
	if backdrop == "forest":
		return _forest()
	return _tavern()


static func _tavern() -> Dictionary:
	return {
		"id": "tavern",
		"top": {
			"floor": "tex_floor_wood.png",
			"water": "tex_water.png",
			"wall": "tex_stone_wall.png",
			"obstacle": "tex_floor_wood.png",
			"furniture": "tex_floor_wood.png",
			"bush": "tex_grass.png",
		},
		"side": {
			"floor": "tex_dark_wood.png",
			"water": "tex_cobblestone.png",
			"wall": "tex_dark_wood.png",
			"obstacle": "tex_dark_wood.png",
			"furniture": "tex_dark_wood.png",
			"bush": "tex_dirt.png",
		},
		"props": {
			"obstacle": ["prop_crates.png", "prop_barrel.png", "prop_boulder.png"],
			"furniture": [
				"tavern_square_table.png", "tavern_round_table.png",
				"tavern_long_bench.png",
			],
			"bush": [],
			# 顶行墙面做成连续吧台与酒架，间隔摆罐子/篮子。
			"wall_back": ["tavern_bar_counter.png", "tavern_wine_shelf.png"],
			"wall_back_accent": ["prop_jars.png", "prop_baskets.png"],
			# 底行墙垛上叠放木桶/木箱。
			"wall_front": ["prop_barrel.png", "prop_crates.png"],
		},
		"prop_scale": {"obstacle": 1.15, "furniture": 1.4},
		"back_wall_row": true,
		"wall_side": "tex_dark_wood.png",
		"wall_top": "tex_dark_wood.png",
		"wall_side_tint": Color(0.52, 0.40, 0.30),
		"wall_top_tint": Color(0.36, 0.28, 0.22),
		"ambient_color": Color(0.56, 0.46, 0.36),
		"ambient_energy": 0.9,
		"sun_color": Color(1.0, 0.82, 0.58),
		"sun_energy": 1.7,
		"sun_rotation": Vector3(-42.0, -30.0, 0.0),
		"bg_color": Color(0.09, 0.06, 0.045),
		"fog_color": Color(0.10, 0.075, 0.055),
		"fog_density": 0.0035,
		"glow_intensity": 0.45,
		"glow_bloom": 0.1,
		"shell": "tavern",
		"shell_wall": "tex_aged_plaster.png",
		"shell_beam": "tex_dark_wood.png",
		"wall_height": 6.4,
		"side_wall_height": 1.2,
		"wall_tint": Color(0.62, 0.54, 0.46),
		"beam_tint": Color(0.58, 0.48, 0.40),
		"ground_tint": Color(0.52, 0.42, 0.34),
		"border_tint": Color(0.40, 0.30, 0.24),
	}


static func _forest() -> Dictionary:
	return {
		"id": "forest",
		"top": {
			"floor": "tex_forest_floor.png",
			"water": "tex_water.png",
			"wall": "tex_stone_wall.png",
			"obstacle": "tex_forest_floor.png",
			"furniture": "tex_floor_wood.png",
			"bush": "tex_grass.png",
		},
		"side": {
			"floor": "tex_dirt.png",
			"water": "tex_dirt.png",
			"wall": "tex_stone_wall.png",
			"obstacle": "tex_forest_floor.png",
			"furniture": "tex_dirt.png",
			"bush": "tex_dirt.png",
		},
		"props": {
			# 树与巨石交替：树高在 PROP_HEIGHTS 的 4.6~5.4 米，再乘下面 1.1 的缩放。
			"obstacle": [
				"prop_willow.png", "tree_camphor.png", "tree_pine.png",
				"prop_boulder.png",
			],
			"furniture": ["prop_log.png", "prop_stump.png"],
			"bush": ["prop_shrub.png", "prop_fern.png"],
			"wall_back": [],
			"wall_back_accent": [],
			"wall_front": [],
		},
		"prop_scale": {"obstacle": 1.1, "furniture": 1.4},
		"back_wall_row": false,
		"wall_side": "tex_dark_wood.png",
		"wall_top": "tex_dark_wood.png",
		"wall_side_tint": Color(0.52, 0.40, 0.30),
		"wall_top_tint": Color(0.36, 0.28, 0.22),
		"ambient_color": Color(0.50, 0.58, 0.45),
		"ambient_energy": 1.0,
		"sun_color": Color(1.0, 0.96, 0.78),
		"sun_energy": 1.8,
		"sun_rotation": Vector3(-44.0, -24.0, 0.0),
		"bg_color": Color(0.05, 0.09, 0.06),
		"fog_color": Color(0.07, 0.12, 0.09),
		"fog_density": 0.006,
		"glow_intensity": 0.30,
		"glow_bloom": 0.06,
		"shell": "forest",
		"shell_wall": "tex_stone_wall.png",
		"shell_beam": "tex_dark_wood.png",
		"wall_height": 3.0,
		"side_wall_height": 1.2,
		"wall_tint": Color(0.66, 0.66, 0.58),
		"beam_tint": Color(0.58, 0.50, 0.42),
		"ground_tint": Color(0.62, 0.58, 0.46),
		"border_tint": Color(0.42, 0.38, 0.30),
	}

extends RefCounted

# 布局运行时的环境搭建：天空、光照、相机夹取与边界林。
# 旧地图没有 environment 时使用与 layout_walk 原实现完全相同的默认天空/光照；
# 边界林复用 TownBorder 的环带，只在地图外铺背景树，不参与碰撞。

const LayoutEnvironment = preload("res://core/layouts/layout_environment.gd")
const LayoutGrid = preload("res://core/layouts/layout_grid.gd")
const LayoutTerrain = preload("res://core/layouts/layout_terrain.gd")
const TownBorder = preload("res://shared/scenery/town/town_border.gd")

const SUN_ROTATION := Vector3(-48.0, -38.0, 0.0)
const SUN_SHADOW_DISTANCE := 90.0
const SUN_SHADOW_BIAS := 0.05

const SKY_PRESETS := {
	"default": {
		"top": Color("#7fa6d8"), "horizon": Color("#f2d9b0"),
		"ground_horizon": Color("#f2d9b0"), "ground_bottom": Color("#c8b898"),
	},
	"clear": {
		"top": Color("#6ba4dc"), "horizon": Color("#d9ecf7"),
		"ground_horizon": Color("#d9ecf7"), "ground_bottom": Color("#b8cdd8"),
	},
	"dusk": {
		"top": Color("#5b5f9a"), "horizon": Color("#f0a06a"),
		"ground_horizon": Color("#d9855a"), "ground_bottom": Color("#7a5050"),
	},
	"night": {
		"top": Color("#0c1730"), "horizon": Color("#263a5e"),
		"ground_horizon": Color("#1c2a44"), "ground_bottom": Color("#0a1120"),
	},
}

const LIGHTING_PRESETS := {
	"default": {
		"sun": Color("#ffd9a8"), "energy": 0.72,
		"ambient": Color("#8e9bb8"), "ambient_energy": 0.36,
		"fog": Color("#e8d8c0"), "fog_density": 0.0008,
	},
	"warm": {
		"sun": Color("#ffc58a"), "energy": 0.95,
		"ambient": Color("#a08a72"), "ambient_energy": 0.34,
		"fog": Color("#f0dcc0"), "fog_density": 0.0009,
	},
	"cool": {
		"sun": Color("#d8e8ff"), "energy": 0.70,
		"ambient": Color("#7d90b0"), "ambient_energy": 0.34,
		"fog": Color("#d8e4f0"), "fog_density": 0.0008,
	},
	"night": {
		"sun": Color("#9fb6e8"), "energy": 0.22,
		"ambient": Color("#3a4a70"), "ambient_energy": 0.22,
		"fog": Color("#25324c"), "fog_density": 0.0012,
	},
}


# 天空与光照分开选择；返回节点便于测试检查预设是否生效。
static func build_lighting(parent: Node3D, document: Dictionary) -> Dictionary:
	var sky_id := LayoutEnvironment.sky_id(document)
	var lighting_id := LayoutEnvironment.lighting_id(document)
	var sky_preset: Dictionary = SKY_PRESETS.get(sky_id, SKY_PRESETS["default"])
	var light_preset: Dictionary = LIGHTING_PRESETS.get(
		lighting_id, LIGHTING_PRESETS["default"]
	)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = SUN_ROTATION
	sun.light_color = light_preset["sun"]
	sun.light_energy = float(light_preset["energy"])
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = SUN_SHADOW_DISTANCE
	sun.shadow_bias = SUN_SHADOW_BIAS
	parent.add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = sky_preset["top"]
	sky_material.sky_horizon_color = sky_preset["horizon"]
	sky_material.ground_horizon_color = sky_preset["ground_horizon"]
	sky_material.ground_bottom_color = sky_preset["ground_bottom"]
	sky.sky_material = sky_material
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = light_preset["ambient"]
	env.ambient_light_energy = float(light_preset["ambient_energy"])
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = light_preset["fog"]
	env.fog_density = float(light_preset["fog_density"])
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	parent.add_child(world_env)
	return {"sun": sun, "world_environment": world_env}


static func camera_clamp(document: Dictionary) -> Rect2:
	return LayoutEnvironment.camera_clamp(document)


# 只在 environment.border 有效且 sides 非空时建林；树根跟随地形高度。
static func build_border(
	parent: Node3D, document: Dictionary, terrain: Dictionary
) -> Node3D:
	var border := LayoutEnvironment.border_options(document)
	if border.is_empty():
		return null
	var bounds := LayoutGrid.world_bounds(document)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return null
	var data := {
		"bounds": {
			"x0": bounds.position.x,
			"z0": bounds.position.y,
			"x1": bounds.end.x,
			"z1": bounds.end.y,
		},
		"border": border,
	}
	var height_at := func(point: Vector2) -> float:
		return LayoutTerrain.height_at(terrain, point)
	TownBorder.new().build(parent, data, height_at)
	return parent.get_node_or_null("Border") as Node3D

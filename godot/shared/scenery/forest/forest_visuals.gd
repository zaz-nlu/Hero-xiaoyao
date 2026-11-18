extends RefCounted

# 森林远景、主灯、环境雾/辉光与暗角。只读布局里的灯光配置。

const AiAssets = preload("res://shared/resources/ai_assets.gd")
const SceneKit = preload("res://shared/scene/scene_kit.gd")
const Texgen = preload("res://shared/scene/texgen.gd")
const ForestLayout = preload("res://shared/resources/forest_layout.gd")

const VIGNETTE_SHADER := """
shader_type canvas_item;

uniform float vignette_strength = 0.45;

void fragment() {
	vec2 uv = SCREEN_UV - vec2(0.5);
	float d = length(uv);
	float v = smoothstep(0.32, 0.85, d);
	COLOR = vec4(0.0, 0.0, 0.0, v * vignette_strength);
}
"""

var sun: DirectionalLight3D = null
var world_env: WorldEnvironment = null


func build(parent: Node3D, layout: ForestLayout) -> void:
	_build_backdrop(parent)
	_build_lighting(parent, layout.data)


func _build_backdrop(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Backdrop"
	parent.add_child(root)
	var mountain_tex: ImageTexture = AiAssets.load_texture("bg_mountains.png")
	if mountain_tex != null:
		var quad := QuadMesh.new()
		quad.size = Vector2(240.0, 60.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = mountain_tex
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		mat.roughness = 1.0
		mat.metallic = 0.0
		mat.metallic_specular = 0.0
		mat.set("disable_fog", true)
		var backdrop := SceneKit.add_mesh(
			root, quad, mat, Vector3(0.0, 19.0, -27.0), "MountainBackdrop"
		)
		backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return
	var layers: Array[Dictionary] = [
		{"z": -46.0, "seed": 31, "color": Color("#6f7f9a")},
		{"z": -60.0, "seed": 32, "color": Color("#8e9bb2")},
	]
	for i in range(layers.size()):
		var layer: Dictionary = layers[i]
		var img: Image = Texgen.mountain_layer(
			256, 64, int(layer["seed"]), layer["color"]
		)
		var tex: ImageTexture = Texgen.make_texture(img, false)
		var mat: StandardMaterial3D = Texgen.make_material(tex, Vector2.ONE, true, true)
		var quad := QuadMesh.new()
		quad.size = Vector2(220.0, 40.0)
		SceneKit.add_mesh(root, quad, mat, Vector3(0.0, 17.0, float(layer["z"])))


func _build_lighting(parent: Node3D, data: Dictionary) -> void:
	var lights: Dictionary = {}
	var lights_value: Variant = data.get("lights", null)
	if lights_value is Dictionary:
		lights = lights_value

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	var rotation_value: Variant = lights.get("sun_rotation", [-48.0, -38.0, 0.0])
	if rotation_value is Array:
		var rotation: Array = rotation_value
		if rotation.size() >= 3:
			sun.rotation_degrees = Vector3(
				float(rotation[0]), float(rotation[1]), float(rotation[2])
			)
		else:
			sun.rotation_degrees = Vector3(-48.0, -38.0, 0.0)
	else:
		sun.rotation_degrees = Vector3(-48.0, -38.0, 0.0)
	sun.light_color = Color(str(lights.get("sun_color", "#eef0c0")))
	sun.light_energy = float(lights.get("sun_energy", 1.1))
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	sun.shadow_bias = 0.05
	parent.add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(str(lights.get("sky_top", "#7fa6d8")))
	sky_mat.sky_horizon_color = Color(str(lights.get("sky_horizon", "#f2d9b0")))
	sky_mat.ground_horizon_color = Color(str(lights.get("sky_horizon", "#f2d9b0")))
	sky_mat.ground_bottom_color = Color("#c8b898")
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(str(lights.get("ambient_color", "#6b7f66")))
	env.ambient_light_energy = float(lights.get("ambient_energy", 0.7))
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color(str(lights.get("fog_color", "#b8c9a8")))
	env.fog_density = float(lights.get("fog_density", 0.006))
	world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	parent.add_child(world_env)

	SceneKit.build_vignette(parent, VIGNETTE_SHADER)

extends RefCounted

# 小镇地面、河流桥面、台阶平台、远景、光照与暗角。
# 显式接收父节点/数据/美术对象，静态几何不持有 controller。

const SceneKit = preload("res://shared/scene/scene_kit.gd")
const Texgen = preload("res://shared/scene/texgen.gd")
const AiAssets = preload("res://shared/resources/ai_assets.gd")
const GameState = preload("res://core/game_state.gd")
const TownData = preload("res://shared/resources/town_data.gd")
const TownArt = preload("res://shared/scenery/town/town_art.gd")
const TownPhaseController = preload("res://shared/scenery/town/town_phase_controller.gd")
const TownTerracesBuild = preload("res://shared/scenery/town/town_terraces_build.gd")
const TownBorder = preload("res://shared/scenery/town/town_border.gd")

const GROUND_TEXTURES := {
	"flagstone": "tex_flagstone_large.png",
	"flagstone_wet": "tex_flagstone_wet.png",
	"mud": "tex_riverbank_mud.png",
	"pier": "tex_wood_pier.png",
}

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
var mountain_backdrop: MeshInstance3D = null
var water_material: StandardMaterial3D = null


func build_ground(parent: Node3D, data: Dictionary, art: TownArt) -> void:
	var root := Node3D.new()
	root.name = "Ground"
	parent.add_child(root)
	# A huge dull-grass plane under the town so the far-away camera never sees the void.
	var fill := MeshInstance3D.new()
	fill.name = "GroundFill"
	var fill_mesh := PlaneMesh.new()
	fill_mesh.size = Vector2(600.0, 70.0)
	fill.mesh = fill_mesh
	var fill_mat := StandardMaterial3D.new()
	fill_mat.albedo_color = Color("#65722c")
	fill_mat.roughness = 1.0
	fill.material_override = fill_mat
	fill.position = Vector3(12.0, -0.05, 6.0)
	root.add_child(fill)
	var grounds: Array = data.get("ground", [])
	for i in range(grounds.size()):
		var ground_value: Variant = grounds[i]
		if typeof(ground_value) != TYPE_DICTIONARY:
			continue
		var ground: Dictionary = ground_value
		var ground_type := str(ground.get("type", "grass"))
		var rect_value: Variant = ground.get("rect", [])
		if typeof(rect_value) != TYPE_ARRAY:
			continue
		var rect: Array = rect_value
		if rect.size() < 4:
			continue
		var x0 := float(rect[0])
		var z0 := float(rect[1])
		var x1 := float(rect[2])
		var z1 := float(rect[3])
		var width := x1 - x0
		var depth := z1 - z0
		if width <= 0.0 or depth <= 0.0:
			continue
		var y := 0.0
		var tex: ImageTexture
		var uv_scale := Vector2(width, depth)
		var node_name := "Ground_%d" % i
		match ground_type:
			"stone":
				y = 0.01
				tex = AiAssets.load_texture("tex_cobblestone.png")
				if tex != null:
					uv_scale = Vector2(width / 3.0, depth / 3.0)
				else:
					tex = art.get_tex("stone_street")
			"water":
				y = 0.02
				tex = AiAssets.load_texture("tex_water.png")
				if tex != null:
					uv_scale = Vector2(width / 6.0, depth / 6.0)
				else:
					tex = art.get_tex("water")
				node_name = "WaterSurface"
			"flagstone", "flagstone_wet", "mud", "pier":
				y = 0.03 if ground_type == "pier" else 0.01
				tex = AiAssets.load_texture(
					str(GROUND_TEXTURES.get(ground_type, "tex_flagstone_large.png"))
				)
				uv_scale = Vector2(width / 4.0, depth / 4.0)
				if tex == null:
					tex = art.get_tex("stone_street")
			_:
				y = 0.0
				tex = AiAssets.load_texture("tex_grass.png")
				if tex != null:
					uv_scale = Vector2(width / 4.0, depth / 4.0)
				else:
					tex = art.get_tex("grass")
		var plane := PlaneMesh.new()
		plane.size = Vector2(width, depth)
		var mat: StandardMaterial3D = Texgen.make_material(tex, uv_scale)
		if ground_type == "water":
			water_material = mat
		SceneKit.add_mesh(
			root, plane, mat, Vector3((x0 + x1) * 0.5, y, (z0 + z1) * 0.5), node_name
		)
	_build_bridges(root, data, art)
	TownBorder.new().build(root, data)


func _build_bridges(parent: Node3D, data: Dictionary, art: TownArt) -> void:
	var wood_mat: StandardMaterial3D = Texgen.make_material(
		art.get_tex("wood_planks"), Vector2(1.0, 1.0)
	)
	var bridges: Array = data.get("bridges", [])
	for i in range(bridges.size()):
		var bridge_value: Variant = bridges[i]
		if typeof(bridge_value) != TYPE_DICTIONARY:
			continue
		var bridge: Dictionary = bridge_value
		if not TownData._has_numbers(bridge, ["x0", "x1", "z0", "z1"]):
			continue
		var x0 := float(bridge["x0"])
		var x1 := float(bridge["x1"])
		var z0 := float(bridge["z0"])
		var z1 := float(bridge["z1"])
		var width := x1 - x0
		var depth := z1 - z0
		var bridge_root := Node3D.new()
		bridge_root.name = "Bridge%d" % i
		parent.add_child(bridge_root)
		SceneKit.add_box(
			bridge_root,
			Vector3(width, 0.3, depth),
			wood_mat,
			Vector3((x0 + x1) * 0.5, 0.1, (z0 + z1) * 0.5)
		)
		for side in range(2):
			var rail_x := x0 + 0.08
			if side == 1:
				rail_x = x1 - 0.08
			var z := z0
			while z <= z1 + 0.001:
				SceneKit.add_box(
					bridge_root,
					Vector3(0.15, 0.9, 0.15),
					wood_mat,
					Vector3(rail_x, 0.7, z)
				)
				z += 1.0
			SceneKit.add_box(
				bridge_root,
				Vector3(0.1, 0.08, depth),
				wood_mat,
				Vector3(rail_x, 0.75, (z0 + z1) * 0.5)
			)
			SceneKit.add_box(
				bridge_root,
				Vector3(0.1, 0.08, depth),
				wood_mat,
				Vector3(rail_x, 1.05, (z0 + z1) * 0.5)
			)


func build_stairs(parent: Node3D, data: Dictionary, art: TownArt) -> void:
	var root := Node3D.new()
	root.name = "Stairs"
	parent.add_child(root)
	var stairs_value: Variant = data.get("stairs", null)
	if typeof(stairs_value) == TYPE_DICTIONARY:
		var stairs: Dictionary = stairs_value
		var x0 := float(stairs.get("x0", 0.0))
		var x1 := float(stairs.get("x1", 0.0))
		var z_start := float(stairs.get("z_start", 0.0))
		var z_end := float(stairs.get("z_end", 0.0))
		var steps: int = int(ceil(absf(z_start - z_end)))
		var step_mat: StandardMaterial3D = art.make_step_stone_material(Vector2(1.0, 1.0))
		for i in range(steps):
			var height := 0.5 * float(i + 1)
			var z_center := z_start - float(i) - 0.5
			SceneKit.add_box(
				root,
				Vector3(x1 - x0, height, 1.0),
				step_mat,
				Vector3((x0 + x1) * 0.5, height * 0.5, z_center)
			)
		var wall_mat: StandardMaterial3D = art.make_step_stone_material(Vector2(1.0, 1.0))
		var wall_len := absf(z_start - z_end)
		var wall_z := (z_start + z_end) * 0.5
		SceneKit.add_box(
			root, Vector3(0.3, 1.0, wall_len), wall_mat, Vector3(x0 - 0.25, 0.5, wall_z)
		)
		SceneKit.add_box(
			root, Vector3(0.3, 1.0, wall_len), wall_mat, Vector3(x1 + 0.25, 0.5, wall_z)
		)

	var platform_value: Variant = data.get("platform", null)
	if typeof(platform_value) == TYPE_DICTIONARY:
		var platform: Dictionary = platform_value
		var rect_value: Variant = platform.get("rect", [])
		if typeof(rect_value) == TYPE_ARRAY:
			var rect: Array = rect_value
			if rect.size() >= 4:
				var px0 := float(rect[0])
				var pz0 := float(rect[1])
				var px1 := float(rect[2])
				var pz1 := float(rect[3])
				var py := float(platform.get("y", 7.0))
				var side_mat: StandardMaterial3D = art.make_step_stone_material(
					Vector2(1.0, 1.0)
				)
				SceneKit.add_box(
					root,
					Vector3(px1 - px0, py, pz1 - pz0),
					side_mat,
					Vector3((px0 + px1) * 0.5, py * 0.5, (pz0 + pz1) * 0.5)
				)
				var top_mat: StandardMaterial3D = art.make_street_material(
					Vector2(px1 - px0, pz1 - pz0)
				)
				SceneKit.add_box(
					root,
					Vector3(px1 - px0, 0.06, pz1 - pz0),
					top_mat,
					Vector3((px0 + px1) * 0.5, py + 0.03, (pz0 + pz1) * 0.5)
				)

	var terrace_builder := TownTerracesBuild.new()
	terrace_builder.build(parent, data)

	var gate_value: Variant = data.get("gate", null)
	if typeof(gate_value) == TYPE_DICTIONARY:
		var gate: Dictionary = gate_value
		var gx := float(gate.get("x", 0.0))
		var gz := float(gate.get("z", 0.0))
		var gy := float(gate.get("y", 0.0))
		var label_text := str(gate.get("label", ""))
		var post_mat: StandardMaterial3D = SceneKit.solid_material(Color("#7a3a2a"))
		SceneKit.add_box(root, Vector3(0.8, 5.0, 0.8), post_mat, Vector3(gx - 2.5, gy + 2.5, gz))
		SceneKit.add_box(root, Vector3(0.8, 5.0, 0.8), post_mat, Vector3(gx + 2.5, gy + 2.5, gz))
		var beam_mat: StandardMaterial3D = SceneKit.solid_material(Color("#6a3224"))
		SceneKit.add_box(root, Vector3(6.0, 0.6, 0.8), beam_mat, Vector3(gx, gy + 5.3, gz))
		var roof_mat: StandardMaterial3D = Texgen.make_material(
			art.get_tex("roof_tiles"), Vector2(7.0, 1.4)
		)
		var front := SceneKit.add_box(
			root, Vector3(7.0, 0.15, 1.4), roof_mat, Vector3(gx, gy + 5.95, gz + 0.55)
		)
		front.rotation.x = -deg_to_rad(25.0)
		var back := SceneKit.add_box(
			root, Vector3(7.0, 0.15, 1.4), roof_mat, Vector3(gx, gy + 5.95, gz - 0.55)
		)
		back.rotation.x = deg_to_rad(25.0)
		if label_text != "":
			var label := art.make_label(label_text, 0.02, 96)
			label.position = Vector3(gx, gy + 4.8, gz + 0.45)
			root.add_child(label)


func build_backdrop(parent: Node3D) -> void:
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
			root, quad, mat, Vector3(12.0, 19.0, -29.6), "MountainBackdrop"
		)
		backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mountain_backdrop = backdrop
		return
	var layers: Array[Dictionary] = [
		{"z": -46.0, "seed": 31, "color": Color("#6f7f9a")},
		{"z": -60.0, "seed": 32, "color": Color("#8e9bb2")},
		{"z": -76.0, "seed": 33, "color": Color("#b4bdcc")},
	]
	for i in range(layers.size()):
		var layer: Dictionary = layers[i]
		var seed_value := int(layer["seed"])
		var color_value: Color = layer["color"]
		var img: Image = Texgen.mountain_layer(256, 64, seed_value, color_value)
		var tex: ImageTexture = Texgen.make_texture(img, false)
		var mat: StandardMaterial3D = Texgen.make_material(tex, Vector2.ONE, true, true)
		var quad := QuadMesh.new()
		quad.size = Vector2(220.0, 40.0)
		SceneKit.add_mesh(root, quad, mat, Vector3(0.0, 17.0, float(layer["z"])))


func build_lighting(parent: Node3D) -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48.0, -38.0, 0.0)
	sun.light_color = Color("#ffd9a8")
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	sun.shadow_bias = 0.05
	parent.add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#7fa6d8")
	sky_mat.sky_horizon_color = Color("#f2d9b0")
	sky_mat.ground_horizon_color = Color("#f2d9b0")
	sky_mat.ground_bottom_color = Color("#c8b898")
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#8e9bb8")
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color("#e8d8c0")
	env.fog_density = 0.0008
	world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	parent.add_child(world_env)

	var phase_controller := TownPhaseController.new()
	phase_controller.name = "TownPhaseController"
	parent.add_child(phase_controller)
	phase_controller.setup(sun, env, mountain_backdrop, parent)
	phase_controller.apply_phase(GameState.town_phase, false)

	SceneKit.build_vignette(parent, VIGNETTE_SHADER)


func advance(delta: float) -> void:
	if water_material != null:
		water_material.uv1_offset.x += 0.05 * delta

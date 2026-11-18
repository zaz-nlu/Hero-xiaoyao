extends RefCounted

# 酒馆氛围构建：光柱、尘埃、灯笼、主灯光与暗角。

const SceneKit = preload("res://shared/scene/scene_kit.gd")
const Layout = preload("res://shared/scenery/tavern/tavern_layout.gd")

const VIGNETTE_SHADER := """
shader_type canvas_item;

uniform float vignette_strength = 0.55;

void fragment() {
	vec2 uv = SCREEN_UV - vec2(0.5);
	float d = length(uv);
	float v = smoothstep(0.32, 0.85, d);
	COLOR = vec4(0.0, 0.0, 0.0, v * vignette_strength);
}
"""


static func build_light_shafts(parent: Node3D, room: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "LightShafts"
	parent.add_child(root)
	var z_back := Layout.room_float(room, "z_back", -12.0)
	var gradient: ImageTexture = shaft_gradient()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.92, 0.75, 0.12)
	mat.albedo_texture = gradient
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	var mesh: ArrayMesh = shaft_mesh(1.6, 1.8, 3.05, 4.0)
	var window_xs: Array[float] = [3.5, 11.0, 18.5]
	for i in range(window_xs.size()):
		var shaft := SceneKit.add_mesh(
			root,
			mesh,
			mat,
			Vector3(window_xs[i], 3.1, z_back + 0.1),
			"LightShaft_%d" % (i + 1)
		)
		shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


static func build_dust(parent: Node3D) -> CPUParticles3D:
	var dust := CPUParticles3D.new()
	dust.name = "Dust"
	dust.position = Vector3(11.0, 1.6, -9.9)
	dust.amount = 60
	dust.lifetime = 6.0
	dust.preprocess = 6.0
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(8.4, 1.5, 2.0)
	dust.direction = Vector3(0.0, 1.0, 0.0)
	dust.spread = 20.0
	dust.gravity = Vector3.ZERO
	dust.initial_velocity_min = 0.05
	dust.initial_velocity_max = 0.12
	dust.scale_amount_min = 0.8
	dust.scale_amount_max = 1.2
	dust.color = Color(1.0, 0.95, 0.85, 0.55)
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.95, 0.85, 0.55)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.disable_receive_shadows = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.04, 0.04)
	quad.material = mat
	dust.mesh = quad
	parent.add_child(dust)
	return dust


static func build_lanterns(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "Lanterns"
	parent.add_child(root)
	var positions: Array[Vector3] = [
		Vector3(4.5, 4.6, -2.0),
		Vector3(17.5, 4.6, -2.0),
		Vector3(11.0, 4.4, -6.5),
		Vector3(11.0, 4.4, 1.5),
	]
	for i in range(positions.size()):
		build_lantern(root, positions[i], i + 1)
	return root


static func build_lantern(parent: Node3D, pos: Vector3, index: int) -> Node3D:
	var node := Node3D.new()
	node.name = "Lantern_%d" % index
	node.position = pos
	parent.add_child(node)

	var lamp_mat: StandardMaterial3D = SceneKit.emissive_material(Color(1.0, 0.45, 0.2), 2.0)
	var mesh := SphereMesh.new()
	mesh.radius = 0.275
	mesh.height = 0.7
	var lamp := SceneKit.add_mesh(node, mesh, lamp_mat, Vector3.ZERO)
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var dark_mat: StandardMaterial3D = SceneKit.solid_material(Color("#2e1e12"))
	var rope_height: float = 5.95 - (pos.y + 0.35)
	SceneKit.add_box(
		node,
		Vector3(0.03, rope_height, 0.03),
		dark_mat,
		Vector3(0.0, 0.35 + rope_height * 0.5, 0.0),
		"Rope"
	)
	SceneKit.add_mesh(node, lantern_disc(0.12, 0.04), dark_mat, Vector3(0.0, 0.37, 0.0))
	SceneKit.add_mesh(node, lantern_disc(0.12, 0.04), dark_mat, Vector3(0.0, -0.37, 0.0))
	SceneKit.add_box(
		node,
		Vector3(0.05, 0.14, 0.05),
		SceneKit.solid_material(Color("#b03028")),
		Vector3(0.0, -0.46, 0.0),
		"Tassel"
	)

	var light := SceneKit.add_omni_light(
		node, Vector3.ZERO, Color(1.0, 0.62, 0.32), 7.5, 1.6
	)
	light.shadow_enabled = true
	return node


static func build_lighting(parent: Node3D, data: Dictionary) -> Dictionary:
	var sun := DirectionalLight3D.new()
	sun.name = "FillLight"
	sun.rotation_degrees = Vector3(-52.0, -25.0, 0.0)
	sun.light_color = Color("#ffd2a0")
	sun.light_energy = 0.35
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	sun.shadow_bias = 0.05
	parent.add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#17100c")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#3a3038")
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 0.9
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	parent.add_child(world_env)

	# Small warm pool above the bar counter.
	SceneKit.add_omni_light(
		parent, Vector3(5.5, 3.2, -9.8), Color(1.0, 0.7, 0.45), 5.0, 1.0
	)

	var lights: Array = data.get("lights", [])
	for i in range(lights.size()):
		var light_value: Variant = lights[i]
		if not (light_value is Dictionary):
			continue
		var light_data: Dictionary = light_value
		var pos_value: Variant = light_data.get("pos", [])
		if not (pos_value is Array) or (pos_value as Array).size() < 3:
			continue
		var pos: Array = pos_value
		var color := Color(str(light_data.get("color", "#ffb066")))
		var range_m := float(light_data.get("range", 9.0))
		var energy := float(light_data.get("energy", 1.2))
		SceneKit.add_omni_light(
			parent, Vector3(float(pos[0]), float(pos[1]), float(pos[2])), color, range_m, energy
		)

	SceneKit.build_vignette(parent, VIGNETTE_SHADER)
	return {"sun": sun, "world_env": world_env}


static func shaft_gradient() -> ImageTexture:
	var img: Image = Image.create_empty(4, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		var alpha: float = lerpf(0.18, 0.0, float(y) / 63.0)
		for x in range(4):
			img.set_pixel(x, y, Color(1.0, 0.95, 0.85, alpha))
	return ImageTexture.create_from_image(img)


static func shaft_mesh(
	top_width: float, bottom_width: float, drop: float, forward: float
) -> ArrayMesh:
	var verts := PackedVector3Array([
		Vector3(-top_width * 0.5, 0.0, 0.0),
		Vector3(top_width * 0.5, 0.0, 0.0),
		Vector3(bottom_width * 0.5, -drop, forward),
		Vector3(-bottom_width * 0.5, -drop, forward),
	])
	var uvs := PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(1.0, 0.0),
		Vector2(1.0, 1.0),
		Vector2(0.0, 1.0),
	])
	var normals := PackedVector3Array([
		Vector3(0.0, 0.6, 0.8),
		Vector3(0.0, 0.6, 0.8),
		Vector3(0.0, 0.6, 0.8),
		Vector3(0.0, 0.6, 0.8),
	])
	var indices := PackedInt32Array([0, 1, 2, 0, 2, 3])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func lantern_disc(radius: float, height: float) -> CylinderMesh:
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = height
	return disc

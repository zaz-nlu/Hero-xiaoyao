extends RefCounted

# 场景通用构建工具：小镇、酒馆、森林共用的网格、材质、灯光和暗角搭建逻辑。


static func add_mesh(
	parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, node_name: String = ""
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	if node_name != "":
		instance.name = node_name
	instance.mesh = mesh
	if mat != null:
		instance.material_override = mat
	instance.position = pos
	parent.add_child(instance)
	return instance


static func add_box(
	parent: Node3D, size: Vector3, mat: Material, pos: Vector3, node_name: String = ""
) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	return add_mesh(parent, box, mat, pos, node_name)


static func add_quad(
	parent: Node3D, size: Vector2, mat: Material, pos: Vector3, node_name: String = ""
) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = size
	return add_mesh(parent, quad, mat, pos, node_name)


static func solid_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.metallic_specular = 0.0
	return mat


static func emissive_material(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.metallic_specular = 0.0
	return mat


static func add_omni_light(
	parent: Node3D, pos: Vector3, color: Color, range_m: float, energy: float
) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.omni_range = range_m
	light.light_energy = energy
	light.shadow_enabled = false
	parent.add_child(light)
	return light


static func build_vignette(host: Node, shader_code: String) -> void:
	var layer := CanvasLayer.new()
	layer.name = "Vignette"
	host.add_child(layer)
	var rect := ColorRect.new()
	rect.name = "VignetteRect"
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	rect.offset_left = 0.0
	rect.offset_top = 0.0
	rect.offset_right = 0.0
	rect.offset_bottom = 0.0
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = shader_code
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = shader
	rect.material = shader_mat
	layer.add_child(rect)

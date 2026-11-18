extends RefCounted

# 森林地面：草皮填充、数据驱动的地块，以及道路/泥地的材质与旋转。
# 只依赖场景工具、美术资源与森林空间数据。

const AiAssets = preload("res://shared/resources/ai_assets.gd")
const SceneKit = preload("res://shared/scene/scene_kit.gd")
const Texgen = preload("res://shared/scene/texgen.gd")
const ForestLayout = preload("res://shared/resources/forest_layout.gd")
const ForestArt = preload("res://shared/scenery/forest/forest_art.gd")


func build(parent: Node3D, layout: ForestLayout, art: ForestArt) -> void:
	var root := Node3D.new()
	root.name = "Ground"
	parent.add_child(root)
	# A dull meadow plane under everything so the camera never sees the void.
	var fill := MeshInstance3D.new()
	fill.name = "GroundFill"
	var fill_mesh := PlaneMesh.new()
	fill_mesh.size = Vector2(160.0, 160.0)
	fill.mesh = fill_mesh
	var fill_mat: StandardMaterial3D = art.solid_material(Color("#4a5a30"))
	var fill_tex: ImageTexture = AiAssets.load_texture("tex_forest_floor.png")
	if fill_tex == null:
		fill_tex = AiAssets.load_texture("tex_grass.png")
	if fill_tex != null:
		fill_mat = Texgen.make_material(fill_tex, Vector2(40.0, 40.0))
		fill_mat.albedo_color = Color(0.8, 0.85, 0.75)
	fill.material_override = fill_mat
	fill.position = Vector3(0.0, -0.05, 0.0)
	root.add_child(fill)

	var grounds: Array = layout.data.get("ground", [])
	var dirt_index := 0
	for i in range(grounds.size()):
		var ground_value: Variant = grounds[i]
		if not (ground_value is Dictionary):
			continue
		var ground: Dictionary = ground_value
		var rect: Rect2 = layout.rect_from_array(ground.get("rect", []))
		if rect.size == Vector2.ZERO:
			continue
		var kind := str(ground.get("type", "grass"))
		var y := 0.0
		var center: Vector2 = rect.get_center()
		var plane := PlaneMesh.new()
		if kind == "dirt":
			# Nudge overlapping road rectangles apart so their seams do not z-fight.
			y = 0.01 + 0.001 * float(dirt_index)
			dirt_index += 1
			var path_tex: ImageTexture = AiAssets.load_texture("tex_forest_path.png")
			var horizontal := rect.size.x > rect.size.y
			var road_width := rect.size.y if horizontal else rect.size.x
			var road_length := rect.size.x if horizontal else rect.size.y
			if path_tex != null:
				# The path art runs vertically. Horizontal stretches rotate the mesh
				# 90 degrees so the painted path follows the road.
				if horizontal:
					plane.size = Vector2(road_width, road_length)
				else:
					plane.size = rect.size
				var mat := art.path_material(Vector2(1.0, road_length / 3.0))
				var path_node := SceneKit.add_mesh(
					root, plane, mat, Vector3(center.x, y, center.y), "Ground_%d" % i
				)
				if horizontal:
					path_node.rotation.y = PI * 0.5
			else:
				plane.size = rect.size
				var fallback := art.dirt_material(
					Vector2(rect.size.x / 3.0, rect.size.y / 3.0)
				)
				SceneKit.add_mesh(
					root, plane, fallback, Vector3(center.x, y, center.y), "Ground_%d" % i
				)
		else:
			plane.size = rect.size
			var mat := art.grass_material(Vector2(rect.size.x / 4.0, rect.size.y / 4.0))
			SceneKit.add_mesh(root, plane, mat, Vector3(center.x, y, center.y), "Ground_%d" % i)
